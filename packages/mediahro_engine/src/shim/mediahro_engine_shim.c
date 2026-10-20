// Mediahro engine shim (lane B1): synchronous mpv stream callbacks served by
// an asynchronous Dart VirtualFile (VID-006, docs/05 §9).
//
// mpv calls the stream_cb functions on its demuxer thread and expects data
// synchronously. Each call becomes a request posted to Dart through a
// NativeCallable.listener; the calling thread waits on a condition variable
// until Dart fills the request and calls mh_request_complete, the stream is
// cancelled (mpv cancel_fn), or the VFS shuts down.
//
// Licence: AGPL-3.0-or-later or the Mediahro commercial licence.

#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#if defined(_WIN32)
#include <windows.h>
#define MH_EXPORT __declspec(dllexport)
typedef SRWLOCK mh_mutex;
typedef CONDITION_VARIABLE mh_cond;
static void mh_mutex_init(mh_mutex *m) { InitializeSRWLock(m); }
static void mh_mutex_destroy(mh_mutex *m) { (void)m; }
static void mh_lock(mh_mutex *m) { AcquireSRWLockExclusive(m); }
static void mh_unlock(mh_mutex *m) { ReleaseSRWLockExclusive(m); }
static void mh_cond_init(mh_cond *c) { InitializeConditionVariable(c); }
static void mh_cond_destroy(mh_cond *c) { (void)c; }
static void mh_cond_broadcast(mh_cond *c) { WakeAllConditionVariable(c); }
// Returns 0 on timeout.
static int mh_cond_wait_ms(mh_cond *c, mh_mutex *m, uint32_t ms) {
  return SleepConditionVariableSRW(c, m, ms, 0) ? 1 : 0;
}
#else
#include <errno.h>
#include <pthread.h>
#include <sys/time.h>
#include <time.h>
#define MH_EXPORT __attribute__((visibility("default"))) __attribute__((used))
typedef pthread_mutex_t mh_mutex;
typedef pthread_cond_t mh_cond;
static void mh_mutex_init(mh_mutex *m) { pthread_mutex_init(m, NULL); }
static void mh_mutex_destroy(mh_mutex *m) { pthread_mutex_destroy(m); }
static void mh_lock(mh_mutex *m) { pthread_mutex_lock(m); }
static void mh_unlock(mh_mutex *m) { pthread_mutex_unlock(m); }
static void mh_cond_init(mh_cond *c) { pthread_cond_init(c, NULL); }
static void mh_cond_destroy(mh_cond *c) { pthread_cond_destroy(c); }
static void mh_cond_broadcast(mh_cond *c) { pthread_cond_broadcast(c); }
static int mh_cond_wait_ms(mh_cond *c, mh_mutex *m, uint32_t ms) {
  struct timeval now;
  gettimeofday(&now, NULL);
  struct timespec ts;
  uint64_t ns = (uint64_t)now.tv_usec * 1000u + (uint64_t)(ms % 1000u) * 1000000u;
  ts.tv_sec = now.tv_sec + ms / 1000u + (time_t)(ns / 1000000000u);
  ts.tv_nsec = (long)(ns % 1000000000u);
  return pthread_cond_timedwait(c, m, &ts) == ETIMEDOUT ? 0 : 1;
}
#endif

// mpv/stream_cb.h (ISC), mirrored so the shim builds without mpv headers.
typedef int64_t (*mpv_stream_cb_read_fn)(void *cookie, char *buf, uint64_t nbytes);
typedef int64_t (*mpv_stream_cb_seek_fn)(void *cookie, int64_t offset);
typedef int64_t (*mpv_stream_cb_size_fn)(void *cookie);
typedef void (*mpv_stream_cb_close_fn)(void *cookie);
typedef void (*mpv_stream_cb_cancel_fn)(void *cookie);
typedef struct mpv_stream_cb_info {
  void *cookie;
  mpv_stream_cb_read_fn read_fn;
  mpv_stream_cb_seek_fn seek_fn;
  mpv_stream_cb_size_fn size_fn;
  mpv_stream_cb_close_fn close_fn;
  mpv_stream_cb_cancel_fn cancel_fn;
} mpv_stream_cb_info;

#define MPV_ERROR_LOADING_FAILED (-13)
#define MPV_ERROR_UNSUPPORTED (-18)
#define MPV_ERROR_GENERIC (-20)

enum { MH_OP_OPEN = 1, MH_OP_READ = 2, MH_OP_CLOSE = 3 };

// Shared with Dart (lib/src/mpv/native_shim.dart). Field order is ABI.
typedef struct mh_request {
  int32_t op;
  int32_t seekable;   // out (open)
  int64_t stream;     // in (read/close), out (open)
  int64_t offset;     // in (read)
  int64_t length;     // in (read), out (open: size or -1)
  char *buffer;       // in (read)
  char *uri;          // in (open)
  int64_t result;     // out: bytes, 0 = EOF, < 0 = mpv error
  // Private below.
  int32_t done;
  int32_t abandoned;  // the waiter gave up; buffer must not be touched
  int32_t refs;
  struct mh_vfs *vfs;
  struct mh_request *next_inflight;
} mh_request;

typedef void (*mh_post_fn)(mh_request *req);

typedef struct mh_vfs {
  mh_post_fn post;
  mh_mutex lock;
  mh_cond cond;
  int32_t shutdown;
  int32_t streams;    // open streams (keeps the vfs alive)
  int32_t released;   // Dart released its reference
  mh_request *inflight;
} mh_vfs;

typedef struct mh_stream {
  mh_vfs *vfs;
  int64_t id;
  int64_t pos;
  int64_t size;
  int32_t cancelled;
} mh_stream;

static const uint32_t kOpenTimeoutMs = 30000;
// Network sources may stall during a Wi-Fi drop; mpv's cache keeps playing
// and cancel_fn interrupts the wait on stop or seek (VID-006).
static const uint32_t kReadTimeoutMs = 60000;

static void vfs_maybe_free(mh_vfs *vfs) {
  // Called with the lock held; unlocks.
  int free_it = vfs->released && vfs->streams == 0 && vfs->inflight == NULL;
  mh_unlock(&vfs->lock);
  if (free_it) {
    mh_cond_destroy(&vfs->cond);
    mh_mutex_destroy(&vfs->lock);
    free(vfs);
  }
}

static void request_unref_locked(mh_request *req) {
  if (--req->refs > 0) return;
  mh_vfs *vfs = req->vfs;
  mh_request **p = &vfs->inflight;
  while (*p && *p != req) p = &(*p)->next_inflight;
  if (*p) *p = req->next_inflight;
  free(req->uri);
  free(req);
}

// Posts [req] to Dart and waits. Returns req->result, or [fallback] on
// timeout, cancellation or shutdown. Consumes the caller's reference.
static int64_t request_run(mh_vfs *vfs, mh_request *req, uint32_t timeout_ms,
                           const int32_t *cancelled, int64_t fallback) {
  mh_lock(&vfs->lock);
  if (vfs->shutdown) {
    request_unref_locked(req);
    request_unref_locked(req);
    mh_unlock(&vfs->lock);
    return fallback;
  }
  req->next_inflight = vfs->inflight;
  vfs->inflight = req;
  mh_unlock(&vfs->lock);
  vfs->post(req);
  mh_lock(&vfs->lock);
  int64_t result = fallback;
  uint32_t waited = 0;
  while (!req->done && !vfs->shutdown && !(cancelled && *cancelled)) {
    if (waited >= timeout_ms) break;
    if (!mh_cond_wait_ms(&vfs->cond, &vfs->lock, 250)) waited += 250;
  }
  if (req->done) {
    result = req->result;
  } else {
    req->abandoned = 1;
  }
  request_unref_locked(req);
  mh_unlock(&vfs->lock);
  return result;
}

static mh_request *request_new(mh_vfs *vfs, int32_t op) {
  mh_request *req = (mh_request *)calloc(1, sizeof(mh_request));
  if (!req) return NULL;
  req->op = op;
  req->vfs = vfs;
  req->refs = 2;  // waiter + Dart (mh_request_complete)
  return req;
}

// Completes a read with [n] bytes from [data] (Dart passes a typed list in a
// leaf call). The copy happens under the lock and only while mpv's thread
// still waits, so an abandoned buffer is never written.
MH_EXPORT void mh_request_fill(mh_request *req, const uint8_t *data, int64_t n) {
  mh_vfs *vfs = req->vfs;
  mh_lock(&vfs->lock);
  if (!req->abandoned) {
    if (n > req->length) n = req->length;
    if (n > 0) memcpy(req->buffer, data, (size_t)n);
    req->result = n;
  }
  req->done = 1;
  request_unref_locked(req);
  mh_cond_broadcast(&vfs->cond);
  mh_unlock(&vfs->lock);
}

// Called by Dart when it has set the result fields of [req] (open, close,
// failed read). Safe after the waiter gave up.
MH_EXPORT void mh_request_complete(mh_request *req) {
  mh_vfs *vfs = req->vfs;
  mh_lock(&vfs->lock);
  req->done = 1;
  request_unref_locked(req);
  mh_cond_broadcast(&vfs->cond);
  mh_unlock(&vfs->lock);
}

static int64_t stream_read(void *cookie, char *buf, uint64_t nbytes) {
  mh_stream *s = (mh_stream *)cookie;
  if (s->cancelled) return -1;
  if (s->size >= 0 && s->pos >= s->size) return 0;
  mh_request *req = request_new(s->vfs, MH_OP_READ);
  if (!req) return -1;
  req->stream = s->id;
  req->offset = s->pos;
  req->length = (int64_t)nbytes;
  req->buffer = buf;
  int64_t n = request_run(s->vfs, req, kReadTimeoutMs, &s->cancelled, -1);
  if (n > 0) s->pos += n;
  return n < 0 ? -1 : n;
}

static int64_t stream_seek(void *cookie, int64_t offset) {
  mh_stream *s = (mh_stream *)cookie;
  if (offset < 0 || (s->size >= 0 && offset > s->size)) return MPV_ERROR_GENERIC;
  s->pos = offset;
  return offset;
}

static int64_t stream_size(void *cookie) {
  mh_stream *s = (mh_stream *)cookie;
  return s->size >= 0 ? s->size : MPV_ERROR_UNSUPPORTED;
}

static void stream_cancel(void *cookie) {
  mh_stream *s = (mh_stream *)cookie;
  mh_lock(&s->vfs->lock);
  s->cancelled = 1;
  mh_cond_broadcast(&s->vfs->cond);
  mh_unlock(&s->vfs->lock);
}

static void stream_close(void *cookie) {
  mh_stream *s = (mh_stream *)cookie;
  mh_vfs *vfs = s->vfs;
  mh_lock(&vfs->lock);
  int shutdown = vfs->shutdown;
  mh_unlock(&vfs->lock);
  if (!shutdown) {
    mh_request *req = request_new(vfs, MH_OP_CLOSE);
    if (req) {
      req->stream = s->id;
      // Fire and forget: Dart completes it without anyone waiting.
      mh_lock(&vfs->lock);
      req->refs = 1;
      req->next_inflight = vfs->inflight;
      vfs->inflight = req;
      mh_unlock(&vfs->lock);
      vfs->post(req);
    }
  }
  free(s);
  mh_lock(&vfs->lock);
  vfs->streams--;
  vfs_maybe_free(vfs);
}

// mpv_stream_cb_open_ro_fn: registered with mpv_stream_cb_add_ro.
MH_EXPORT int mh_stream_open(void *user_data, char *uri,
                             mpv_stream_cb_info *info) {
  mh_vfs *vfs = (mh_vfs *)user_data;
  mh_request *req = request_new(vfs, MH_OP_OPEN);
  if (!req) return MPV_ERROR_LOADING_FAILED;
  size_t len = strlen(uri);
  req->uri = (char *)malloc(len + 1);
  if (!req->uri) {
    free(req);
    return MPV_ERROR_LOADING_FAILED;
  }
  memcpy(req->uri, uri, len + 1);
  req->length = -1;
  // Keep size/seekable readable after request_run releases the request.
  mh_lock(&vfs->lock);
  req->refs++;
  mh_unlock(&vfs->lock);
  int64_t id = request_run(vfs, req, kOpenTimeoutMs, NULL, MPV_ERROR_LOADING_FAILED);
  int64_t size = req->length;
  int32_t seekable = req->seekable;
  mh_lock(&vfs->lock);
  request_unref_locked(req);
  mh_unlock(&vfs->lock);
  if (id < 0) return (int)(id < -1 ? id : MPV_ERROR_LOADING_FAILED);
  mh_stream *s = (mh_stream *)calloc(1, sizeof(mh_stream));
  if (!s) return MPV_ERROR_LOADING_FAILED;
  s->vfs = vfs;
  s->id = id;
  s->size = size;
  mh_lock(&vfs->lock);
  vfs->streams++;
  mh_unlock(&vfs->lock);
  info->cookie = s;
  info->read_fn = stream_read;
  info->seek_fn = seekable ? stream_seek : NULL;
  info->size_fn = stream_size;
  info->close_fn = stream_close;
  info->cancel_fn = stream_cancel;
  return 0;
}

MH_EXPORT mh_vfs *mh_vfs_create(mh_post_fn post) {
  mh_vfs *vfs = (mh_vfs *)calloc(1, sizeof(mh_vfs));
  if (!vfs) return NULL;
  vfs->post = post;
  mh_mutex_init(&vfs->lock);
  mh_cond_init(&vfs->cond);
  return vfs;
}

// Fails every pending and future request so mpv threads never wait on Dart
// while the core is being destroyed. Call before mpv_terminate_destroy.
MH_EXPORT void mh_vfs_shutdown(mh_vfs *vfs) {
  mh_lock(&vfs->lock);
  vfs->shutdown = 1;
  mh_cond_broadcast(&vfs->cond);
  mh_unlock(&vfs->lock);
}

// Drops Dart's reference; the vfs is freed once no stream uses it.
MH_EXPORT void mh_vfs_release(mh_vfs *vfs) {
  mh_lock(&vfs->lock);
  vfs->shutdown = 1;
  vfs->released = 1;
  mh_cond_broadcast(&vfs->cond);
  vfs_maybe_free(vfs);
}

MH_EXPORT int32_t mh_request_size(void) { return (int32_t)sizeof(mh_request); }
