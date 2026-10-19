import 'dart:ffi' as ffi;
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:mediahro_ffi/src/native/native_library.dart';
import 'package:mediahro_ffi/src/native/posix.dart';
import 'package:mediahro_ffi/src/nfs/nfs_bindings.dart';
import 'package:mediahro_ffi/src/vfs/isolate_file_system.dart';
import 'package:mediahro_ffi/src/vfs/virtual_file.dart';

/// NFS mount options (NET-002).
final class NfsOptions {
  const NfsOptions({
    required this.server,
    required this.export,
    this.version = 3,
    this.uid,
    this.gid,
    this.timeout = const Duration(seconds: 15),
  });

  final String server;

  /// Exported path, e.g. `/volume1/media`.
  final String export;

  /// 3 or 4.
  final int version;
  final int? uid;
  final int? gid;
  final Duration timeout;
}

// ftype3 (RFC 1813) as reported by readdirplus; S_IFDIR as fallback.
const int _nf3Dir = 2;
const int _sIfMt = 0xF000;
const int _sIfDir = 0x4000;

/// `struct exportnode` from libnfs-raw-mount.h (three pointers).
final class _ExportNode extends ffi.Struct {
  external ffi.Pointer<Utf8> exDir;
  external ffi.Pointer<ffi.Void> exGroups;
  external ffi.Pointer<_ExportNode> exNext;
}

/// Blocking libnfs client; runs on its worker isolate only.
final class NfsSyncFileSystem implements SyncFileSystem {
  NfsSyncFileSystem(this.options, {NfsBindings? bindings})
    : _b = bindings ?? NfsBindings(NativeLibraries.open(NativeLibrary.nfs)) {
    _ctx = _b.nfs_init_context();
    if (_ctx == ffi.nullptr) {
      throw VirtualFileException(
        VirtualFileError.io,
        _uri(''),
        'nfs_init_context failed',
      );
    }
    _b
      ..nfs_set_timeout(_ctx, options.timeout.inMilliseconds)
      ..nfs_set_version(_ctx, options.version);
    if (options.uid != null) _b.nfs_set_uid(_ctx, options.uid!);
    if (options.gid != null) _b.nfs_set_gid(_ctx, options.gid!);
    using((a) {
      final rc = _b.nfs_mount(
        _ctx,
        options.server.toNativeUtf8(allocator: a).cast(),
        options.export.toNativeUtf8(allocator: a).cast(),
      );
      if (rc < 0) {
        final e = _error();
        _b.nfs_destroy_context(_ctx);
        throw VirtualFileException(_map(rc, connect: true), _uri(''), e);
      }
    });
    _readMax = _b.nfs_get_readmax(_ctx).clamp(32 * 1024, 4 << 20);
    _writeMax = _b.nfs_get_writemax(_ctx).clamp(32 * 1024, 4 << 20);
  }

  final NfsOptions options;
  final NfsBindings _b;
  late final ffi.Pointer<nfs_context> _ctx;
  late final int _readMax;
  late final int _writeMax;
  final _handles = <int, (ffi.Pointer<nfsfh>, int?)>{};
  int _next = 1;

  Uri _uri(String path) => Uri(
    scheme: 'nfs',
    host: options.server,
    pathSegments: [
      ...options.export.split('/').where((s) => s.isNotEmpty),
      ...path.split('/').where((s) => s.isNotEmpty),
    ],
  );

  /// libnfs paths are relative to the export and start with `/`.
  static String _p(String path) => '/$path';

  String _error() {
    final p = _b.nfs_get_error(_ctx);
    return p == ffi.nullptr ? '' : p.cast<Utf8>().toDartString();
  }

  @override
  List<VirtualEntry> list(String path) => using((a) {
    final out = a<ffi.Pointer<nfsdir>>();
    final rc = _b.nfs_opendir(
      _ctx,
      _p(path).toNativeUtf8(allocator: a).cast(),
      out,
    );
    if (rc < 0) throw VirtualFileException(_map(rc), _uri(path), _error());
    final dir = out.value;
    final entries = <VirtualEntry>[];
    try {
      while (true) {
        final ent = _b.nfs_readdir(_ctx, dir);
        if (ent == ffi.nullptr) break;
        final name = ent.ref.name.cast<Utf8>().toDartString();
        if (name == '.' || name == '..') continue;
        final isDir =
            ent.ref.type == _nf3Dir || (ent.ref.mode & _sIfMt) == _sIfDir;
        final child = path.isEmpty ? name : '$path/$name';
        final u = _uri(child);
        entries.add(
          VirtualEntry(
            uri: isDir ? u.replace(pathSegments: [...u.pathSegments, '']) : u,
            name: name,
            isDirectory: isDir,
            size: isDir ? null : ent.ref.size,
            modified: DateTime.fromMillisecondsSinceEpoch(
              ent.ref.mtime.tv_sec * 1000,
              isUtc: true,
            ),
          ),
        );
      }
    } finally {
      _b.nfs_closedir(_ctx, dir);
    }
    return entries;
  });

  @override
  VirtualEntry stat(String path) => using((a) {
    final st = a<nfs_stat_64>();
    final rc = _b.nfs_stat64(
      _ctx,
      _p(path).toNativeUtf8(allocator: a).cast(),
      st,
    );
    if (rc < 0) throw VirtualFileException(_map(rc), _uri(path), _error());
    final isDir = (st.ref.nfs_mode & _sIfMt) == _sIfDir;
    return VirtualEntry(
      uri: _uri(path),
      name: path.split('/').last,
      isDirectory: isDir,
      size: isDir ? null : st.ref.nfs_size,
      modified: DateTime.fromMillisecondsSinceEpoch(
        st.ref.nfs_mtime * 1000,
        isUtc: true,
      ),
    );
  });

  @override
  int open(String path, {bool write = false, bool create = false}) => using((
    a,
  ) {
    final out = a<ffi.Pointer<nfsfh>>();
    final p = _p(path).toNativeUtf8(allocator: a).cast<ffi.Char>();
    final flags = PosixOpenFlags.current;
    final rc = write && create
        ? _b.nfs_creat(_ctx, p, 0x1A4 /* 0644 */, out)
        : _b.nfs_open(_ctx, p, write ? flags.writeOnly : flags.readOnly, out);
    if (rc < 0) throw VirtualFileException(_map(rc), _uri(path), _error());
    int? size;
    if (!write) {
      final st = a<nfs_stat_64>();
      if (_b.nfs_fstat64(_ctx, out.value, st) >= 0) size = st.ref.nfs_size;
    }
    final id = _next++;
    _handles[id] = (out.value, size);
    return id;
  });

  @override
  int? length(int handle) => _handles[handle]?.$2;

  @override
  Uint8List read(int handle, int offset, int length) {
    final (fh, size) = _fh(handle);
    var want = length;
    if (size != null) {
      if (offset >= size) return Uint8List(0);
      if (offset + want > size) want = size - offset;
    }
    final out = Uint8List(want);
    final buf = calloc<ffi.Uint8>(_readMax);
    try {
      var got = 0;
      while (got < want) {
        final n = (want - got).clamp(0, _readMax);
        final rc = _b.nfs_pread(_ctx, fh, buf.cast(), n, offset + got);
        if (rc < 0) throw VirtualFileException(_map(rc), _uri(''), _error());
        if (rc == 0) break;
        out.setRange(got, got + rc, buf.asTypedList(rc));
        got += rc;
      }
      return got == want ? out : Uint8List.sublistView(out, 0, got);
    } finally {
      calloc.free(buf);
    }
  }

  @override
  void write(int handle, int offset, List<int> bytes) {
    final (fh, _) = _fh(handle);
    final buf = calloc<ffi.Uint8>(_writeMax);
    try {
      var done = 0;
      while (done < bytes.length) {
        final n = (bytes.length - done).clamp(0, _writeMax);
        buf.asTypedList(n).setRange(0, n, bytes, done);
        final rc = _b.nfs_pwrite(_ctx, fh, buf.cast(), n, offset + done);
        if (rc < 0) throw VirtualFileException(_map(rc), _uri(''), _error());
        done += rc;
      }
    } finally {
      calloc.free(buf);
    }
  }

  @override
  void close(int handle) {
    final h = _handles.remove(handle);
    if (h != null) _b.nfs_close(_ctx, h.$1);
  }

  @override
  void mkdir(String path) => _op(path, _b.nfs_mkdir);

  @override
  void rmdir(String path) => _op(path, _b.nfs_rmdir);

  @override
  void unlink(String path) => _op(path, _b.nfs_unlink);

  @override
  void rename(String from, String to) => using((a) {
    final rc = _b.nfs_rename(
      _ctx,
      _p(from).toNativeUtf8(allocator: a).cast(),
      _p(to).toNativeUtf8(allocator: a).cast(),
    );
    if (rc < 0) throw VirtualFileException(_map(rc), _uri(from), _error());
  });

  @override
  void dispose() {
    for (final h in _handles.values) {
      _b.nfs_close(_ctx, h.$1);
    }
    _handles.clear();
    _b
      ..nfs_umount(_ctx)
      ..nfs_destroy_context(_ctx);
  }

  void _op(
    String path,
    int Function(ffi.Pointer<nfs_context>, ffi.Pointer<ffi.Char>) f,
  ) => using((a) {
    final rc = f(_ctx, _p(path).toNativeUtf8(allocator: a).cast());
    if (rc < 0) throw VirtualFileException(_map(rc), _uri(path), _error());
  });

  (ffi.Pointer<nfsfh>, int?) _fh(int handle) =>
      _handles[handle] ??
      (throw VirtualFileException(VirtualFileError.closed, _uri('')));

  static VirtualFileError _map(int rc, {bool connect = false}) {
    final e = PosixErrno.current;
    final errno = -rc;
    if (errno == e.noent) return VirtualFileError.notFound;
    if (errno == e.acces || errno == e.perm) {
      return VirtualFileError.permissionDenied;
    }
    if (errno == e.exist || errno == e.notempty) {
      return VirtualFileError.alreadyExists;
    }
    if (errno == e.nospc) return VirtualFileError.noSpace;
    if (errno == e.timedout) return VirtualFileError.timeout;
    if (errno == e.connrefused ||
        errno == e.hostunreach ||
        errno == e.netunreach) {
      return VirtualFileError.unreachable;
    }
    return connect ? VirtualFileError.unreachable : VirtualFileError.io;
  }
}

/// Exports of [server] (mount protocol), for the "discovered mounts" list.
/// Blocking: call on a worker isolate.
List<String> nfsExports(String server, {NfsBindings? bindings}) {
  final b = bindings ?? NfsBindings(NativeLibraries.open(NativeLibrary.nfs));
  return using((a) {
    final list = b.mount_getexports(server.toNativeUtf8(allocator: a).cast());
    if (list == ffi.nullptr) return const <String>[];
    final out = <String>[];
    try {
      var n = list.cast<_ExportNode>();
      while (n != ffi.nullptr) {
        out.add(n.ref.exDir.toDartString());
        n = n.ref.exNext;
      }
    } finally {
      b.mount_free_export_list(list);
    }
    return out;
  });
}

/// NFS servers answering a portmapper broadcast on the LAN. Blocking.
List<String> nfsFindLocalServers({NfsBindings? bindings}) {
  final b = bindings ?? NfsBindings(NativeLibraries.open(NativeLibrary.nfs));
  final list = b.nfs_find_local_servers();
  if (list == ffi.nullptr) return const [];
  final out = <String>[];
  try {
    var n = list;
    while (n != ffi.nullptr) {
      out.add(n.ref.addr.cast<Utf8>().toDartString());
      n = n.ref.next;
    }
  } finally {
    b.free_nfs_srvr_list(list);
  }
  return out;
}

/// `nfs://server/export/path` (export given separately: NFS paths are not
/// self-describing).
IsolateFileSystem nfsFileSystem(Uri root, NfsOptions options) =>
    IsolateFileSystem(
      root: root,
      schemes: const {'nfs'},
      debugName: 'mediahro-nfs:${options.server}',
      factory: () => NfsSyncFileSystem(options),
    );
