// Engine render bridge, Android native half (lane B1, docs/05 §4.3).
//
// - Hands the JavaVM to FFmpeg inside libmpv (MediaCodec needs it).
// - Turns Flutter SurfaceProducer surfaces into the JNI global references
//   mpv expects in `wid`.
// - Attaches and detaches mpv's video output synchronously from the
//   platform thread, so mpv never draws into a surface Flutter released.
//
// libmpv is resolved at runtime with dlopen; the plugin builds and runs
// without it (the engine then reports libraryMissing).
//
// Licence: AGPL-3.0-or-later or the Mediahro commercial licence.

#include <android/log.h>
#include <dlfcn.h>
#include <jni.h>

#include <cstdint>
#include <cstdio>

namespace {

JavaVM *g_vm = nullptr;

using set_java_vm_fn = int (*)(void *, void *);
using set_property_string_fn = int (*)(void *, const char *, const char *);

void *Libmpv() {
  static void *handle = dlopen("libmpv.so", RTLD_NOW | RTLD_GLOBAL);
  return handle;
}

int SetProperty(jlong mpv, const char *name, const char *value) {
  void *lib = Libmpv();
  if (lib == nullptr || mpv == 0) return -1;
  static auto fn = reinterpret_cast<set_property_string_fn>(
      dlsym(lib, "mpv_set_property_string"));
  if (fn == nullptr) return -1;
  int rc = fn(reinterpret_cast<void *>(mpv), name, value);
  if (rc < 0) {
    __android_log_print(ANDROID_LOG_WARN, "mediahro_engine",
                        "mpv set %s=%s failed: %d", name, value, rc);
  }
  return rc;
}

}  // namespace

extern "C" JNIEXPORT jint JNI_OnLoad(JavaVM *vm, void * /*reserved*/) {
  g_vm = vm;
  if (void *lib = Libmpv()) {
    auto set_vm =
        reinterpret_cast<set_java_vm_fn>(dlsym(lib, "av_jni_set_java_vm"));
    if (set_vm != nullptr) set_vm(vm, nullptr);
  }
  return JNI_VERSION_1_6;
}

extern "C" JNIEXPORT jboolean JNICALL
Java_com_mediahro_mediahro_1engine_NativeBridge_libmpvLoaded(JNIEnv *, jclass) {
  return Libmpv() != nullptr ? JNI_TRUE : JNI_FALSE;
}

extern "C" JNIEXPORT jlong JNICALL
Java_com_mediahro_mediahro_1engine_NativeBridge_newGlobalRef(JNIEnv *env, jclass,
                                                             jobject surface) {
  return reinterpret_cast<jlong>(env->NewGlobalRef(surface));
}

extern "C" JNIEXPORT void JNICALL
Java_com_mediahro_mediahro_1engine_NativeBridge_deleteGlobalRef(JNIEnv *env, jclass,
                                                                jlong ref) {
  if (ref != 0) env->DeleteGlobalRef(reinterpret_cast<jobject>(ref));
}

// Points mpv at [surfaceRef] (a global ref) of [width]x[height] pixels and
// (re)creates the GPU video output on it. Synchronous.
extern "C" JNIEXPORT jint JNICALL
Java_com_mediahro_mediahro_1engine_NativeBridge_attach(JNIEnv *, jclass, jlong mpv,
                                                       jlong surfaceRef, jint width,
                                                       jint height) {
  char size[32];
  snprintf(size, sizeof(size), "%dx%d", width, height);
  char wid[32];
  snprintf(wid, sizeof(wid), "%lld", static_cast<long long>(surfaceRef));
  SetProperty(mpv, "android-surface-size", size);
  int rc = SetProperty(mpv, "wid", wid);
  if (rc < 0) return rc;
  return SetProperty(mpv, "vo", "gpu-next");
}

// Stops drawing into the current surface. Synchronous: returns after mpv
// released it, so the caller may free the surface.
extern "C" JNIEXPORT jint JNICALL
Java_com_mediahro_mediahro_1engine_NativeBridge_detach(JNIEnv *, jclass, jlong mpv) {
  SetProperty(mpv, "vo", "null");
  return SetProperty(mpv, "wid", "0");
}

extern "C" JNIEXPORT jint JNICALL
Java_com_mediahro_mediahro_1engine_NativeBridge_resize(JNIEnv *, jclass, jlong mpv,
                                                       jint width, jint height) {
  char size[32];
  snprintf(size, sizeof(size), "%dx%d", width, height);
  return SetProperty(mpv, "android-surface-size", size);
}
