import 'dart:async';
import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:mediahro_engine/src/mpv/mpv_client.dart';
import 'package:mediahro_engine/src/mpv/mpv_node.dart';
import 'package:mediahro_engine/src/mpv/native_shim.dart';
import 'package:mediahro_ffi/mediahro_ffi.dart';

/// Exposes [VirtualFile]s to mpv as the `mhvf://` stream protocol through
/// `mpv_stream_cb_add_ro` (VID-006, docs/05 §9), so SMB/NFS/WebDAV/FTP/SFTP,
/// archive entries and server downloads are seekable in the engine.
///
/// mpv's demuxer thread blocks in the native shim while this object serves
/// each request asynchronously on the owning isolate.
final class MpvStreamProtocol {
  MpvStreamProtocol._(this._vfs, this._callable);

  static const scheme = 'mhvf';

  final Pointer<MhVfs> _vfs;
  final NativeCallable<MhPostNative> _callable;
  final _files = <int, VirtualFile>{};
  final _streams = <int, VirtualFile>{};
  final _sizes = <VirtualFile, int?>{};
  var _nextFile = 1;
  var _nextStream = 1;
  var _shutdown = false;
  var _disposed = false;

  /// Registers the protocol on [client]'s core. Returns null when the shim
  /// is not in this build; `VirtualFileSource`s then fail with
  /// `sourceUnavailable` instead of crashing.
  static MpvStreamProtocol? register(MpvClient client) {
    late final MpvStreamProtocol protocol;
    final NativeCallable<MhPostNative> callable;
    final Pointer<MhVfs> vfs;
    try {
      callable = NativeCallable<MhPostNative>.listener(
        (Pointer<MhRequest> req) => protocol._onRequest(req),
      );
      vfs = mhVfsCreate(callable.nativeFunction);
      // A missing shim is reported by the FFI resolver as ArgumentError.
      // ignore: avoid_catching_errors
    } on ArgumentError {
      return null;
    }
    protocol = MpvStreamProtocol._(vfs, callable);
    final rc = using(
      (arena) => client.library.bindings.mpv_stream_cb_add_ro(
        client.handle,
        scheme.toNativeUtf8(allocator: arena).cast(),
        vfs.cast(),
        Native.addressOf<NativeFunction<MpvStreamOpenNative>>(mhStreamOpen)
            .cast(),
      ),
    );
    if (rc < 0) {
      mhVfsRelease(vfs);
      callable.close();
      return null;
    }
    return protocol;
  }

  /// URL that opens [file] in the core.
  String urlFor(VirtualFile file) {
    final id = _nextFile++;
    _files[id] = file;
    return '$scheme://$id';
  }

  /// Forgets [file] after the engine moved on (the caller owns closing it).
  void forget(VirtualFile file) {
    _files.removeWhere((_, f) => identical(f, file));
    _sizes.remove(file);
  }

  /// Files the core can still open by URL (finished items drop out).
  int get registeredCount => _files.length;

  void _onRequest(Pointer<MhRequest> req) {
    unawaited(_serve(req));
  }

  Future<void> _serve(Pointer<MhRequest> req) async {
    final r = req.ref;
    switch (r.op) {
      case MhOp.open:
        final uri = r.uri.toDartString();
        final id = int.tryParse(uri.substring(scheme.length + 3));
        final file = id == null ? null : _files[id];
        if (file == null || _shutdown) {
          r.result = MpvError.loadingFailed;
          mhRequestComplete(req);
          return;
        }
        try {
          final size = _sizes.containsKey(file)
              ? _sizes[file]
              : (_sizes[file] = await file.length());
          final stream = _nextStream++;
          _streams[stream] = file;
          r
            ..length = size ?? -1
            ..seekable = file.isSeekable && size != null ? 1 : 0
            ..result = stream;
        } on VirtualFileException {
          r.result = MpvError.loadingFailed;
        }
        mhRequestComplete(req);
      case MhOp.read:
        final file = _streams[r.stream];
        if (file == null || _shutdown) {
          r.result = -1;
          mhRequestComplete(req);
          return;
        }
        try {
          final bytes = await file.read(r.offset, r.length);
          _fill(req, bytes);
        } on VirtualFileException {
          r.result = -1;
          mhRequestComplete(req);
        }
      case MhOp.close:
        _streams.remove(r.stream);
        mhRequestComplete(req);
    }
  }

  void _fill(Pointer<MhRequest> req, Uint8List bytes) {
    mhRequestFill(req, bytes.address, bytes.length);
  }

  /// Fails pending and future reads so the core can be destroyed without
  /// waiting on this isolate. Call before `mpv_terminate_destroy`.
  void shutdown() {
    if (_shutdown) return;
    _shutdown = true;
    mhVfsShutdown(_vfs);
  }

  /// Releases native resources. Call after the core is destroyed.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    shutdown();
    mhVfsRelease(_vfs);
    _callable.close();
    _files.clear();
    _streams.clear();
  }
}
