/// FFI declarations for the engine shim (`src/shim/mediahro_engine_shim.c`),
/// compiled per platform by the package's build hook (`hook/build.dart`).
@DefaultAsset('package:mediahro_engine/src/mpv/native_shim.dart')
library;

import 'dart:ffi';

import 'package:ffi/ffi.dart';

/// `mh_request` (public prefix; field order is the C ABI).
final class MhRequest extends Struct {
  @Int32()
  external int op;
  @Int32()
  external int seekable;
  @Int64()
  external int stream;
  @Int64()
  external int offset;
  @Int64()
  external int length;
  external Pointer<Uint8> buffer;
  external Pointer<Utf8> uri;
  @Int64()
  external int result;
}

abstract final class MhOp {
  static const open = 1;
  static const read = 2;
  static const close = 3;
}

typedef MhPostNative = Void Function(Pointer<MhRequest>);

/// Opaque `mh_vfs`.
final class MhVfs extends Opaque;

@Native<Pointer<MhVfs> Function(Pointer<NativeFunction<MhPostNative>>)>(
  symbol: 'mh_vfs_create',
)
external Pointer<MhVfs> mhVfsCreate(Pointer<NativeFunction<MhPostNative>> post);

@Native<Void Function(Pointer<MhVfs>)>(symbol: 'mh_vfs_shutdown')
external void mhVfsShutdown(Pointer<MhVfs> vfs);

@Native<Void Function(Pointer<MhVfs>)>(symbol: 'mh_vfs_release')
external void mhVfsRelease(Pointer<MhVfs> vfs);

@Native<Void Function(Pointer<MhRequest>)>(symbol: 'mh_request_complete')
external void mhRequestComplete(Pointer<MhRequest> req);

@Native<Void Function(Pointer<MhRequest>, Pointer<Uint8>, Int64)>(
  symbol: 'mh_request_fill',
  isLeaf: true,
)
external void mhRequestFill(Pointer<MhRequest> req, Pointer<Uint8> data, int n);

@Native<Int32 Function()>(symbol: 'mh_request_size')
external int mhRequestSize();

/// `mpv_stream_cb_open_ro_fn` implemented by the shim.
typedef MpvStreamOpenNative = Int Function(
  Pointer<Void>,
  Pointer<Char>,
  Pointer<Void>,
);

@Native<MpvStreamOpenNative>(symbol: 'mh_stream_open')
external int mhStreamOpen(
  Pointer<Void> userData,
  Pointer<Char> uri,
  Pointer<Void> info,
);
