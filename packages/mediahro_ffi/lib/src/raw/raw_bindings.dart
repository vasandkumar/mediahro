// ignore_for_file: type=lint, unused_field

// Written by hand to match what `package:ffigen` generates from
// ffigen/raw.yaml (headers: .deps-cache/<platform>/include/libraw, LibRaw
// from mediahro-deps, CDDL-1.0). This PC has no libclang.
// `libraw_processed_image_t` is read at fixed offsets (raw_codec.dart).
// Regenerate: (cd packages/mediahro_ffi && dart run ffigen --config ffigen/raw.yaml)
import 'dart:ffi' as ffi;

/// Opaque `libraw_data_t`.
final class LibRawData extends ffi.Opaque {}

abstract final class LibRawImageFormat {
  static const int jpeg = 1;
  static const int bitmap = 2;
}

/// Bindings to LibRaw.
class LibRawBindings {
  final ffi.Pointer<T> Function<T extends ffi.NativeType>(String symbolName)
  _lookup;

  LibRawBindings(ffi.DynamicLibrary dynamicLibrary)
    : _lookup = dynamicLibrary.lookup;

  LibRawBindings.fromLookup(
    ffi.Pointer<T> Function<T extends ffi.NativeType>(String symbolName) lookup,
  ) : _lookup = lookup;

  late final libraw_init =
      _lookup<
            ffi.NativeFunction<
              ffi.Pointer<LibRawData> Function(ffi.UnsignedInt)
            >
          >('libraw_init')
          .asFunction<ffi.Pointer<LibRawData> Function(int)>();

  late final libraw_close =
      _lookup<ffi.NativeFunction<ffi.Void Function(ffi.Pointer<LibRawData>)>>(
        'libraw_close',
      ).asFunction<void Function(ffi.Pointer<LibRawData>)>();

  late final libraw_strerror =
      _lookup<ffi.NativeFunction<ffi.Pointer<ffi.Char> Function(ffi.Int)>>(
        'libraw_strerror',
      ).asFunction<ffi.Pointer<ffi.Char> Function(int)>();

  late final libraw_open_buffer =
      _lookup<
            ffi.NativeFunction<
              ffi.Int Function(
                ffi.Pointer<LibRawData>,
                ffi.Pointer<ffi.Void>,
                ffi.Size,
              )
            >
          >('libraw_open_buffer')
          .asFunction<
            int Function(ffi.Pointer<LibRawData>, ffi.Pointer<ffi.Void>, int)
          >();

  late final libraw_open_file =
      _lookup<
            ffi.NativeFunction<
              ffi.Int Function(ffi.Pointer<LibRawData>, ffi.Pointer<ffi.Char>)
            >
          >('libraw_open_file')
          .asFunction<
            int Function(ffi.Pointer<LibRawData>, ffi.Pointer<ffi.Char>)
          >();

  late final libraw_unpack =
      _lookup<ffi.NativeFunction<ffi.Int Function(ffi.Pointer<LibRawData>)>>(
        'libraw_unpack',
      ).asFunction<int Function(ffi.Pointer<LibRawData>)>();

  late final libraw_unpack_thumb =
      _lookup<ffi.NativeFunction<ffi.Int Function(ffi.Pointer<LibRawData>)>>(
        'libraw_unpack_thumb',
      ).asFunction<int Function(ffi.Pointer<LibRawData>)>();

  late final libraw_dcraw_process =
      _lookup<ffi.NativeFunction<ffi.Int Function(ffi.Pointer<LibRawData>)>>(
        'libraw_dcraw_process',
      ).asFunction<int Function(ffi.Pointer<LibRawData>)>();

  /// Returns a `libraw_processed_image_t*` (free with [libraw_dcraw_clear_mem]).
  late final libraw_dcraw_make_mem_image =
      _lookup<
            ffi.NativeFunction<
              ffi.Pointer<ffi.Void> Function(
                ffi.Pointer<LibRawData>,
                ffi.Pointer<ffi.Int>,
              )
            >
          >('libraw_dcraw_make_mem_image')
          .asFunction<
            ffi.Pointer<ffi.Void> Function(
              ffi.Pointer<LibRawData>,
              ffi.Pointer<ffi.Int>,
            )
          >();

  late final libraw_dcraw_make_mem_thumb =
      _lookup<
            ffi.NativeFunction<
              ffi.Pointer<ffi.Void> Function(
                ffi.Pointer<LibRawData>,
                ffi.Pointer<ffi.Int>,
              )
            >
          >('libraw_dcraw_make_mem_thumb')
          .asFunction<
            ffi.Pointer<ffi.Void> Function(
              ffi.Pointer<LibRawData>,
              ffi.Pointer<ffi.Int>,
            )
          >();

  late final libraw_dcraw_clear_mem =
      _lookup<ffi.NativeFunction<ffi.Void Function(ffi.Pointer<ffi.Void>)>>(
        'libraw_dcraw_clear_mem',
      ).asFunction<void Function(ffi.Pointer<ffi.Void>)>();

  late final libraw_get_iwidth =
      _lookup<ffi.NativeFunction<ffi.Int Function(ffi.Pointer<LibRawData>)>>(
        'libraw_get_iwidth',
      ).asFunction<int Function(ffi.Pointer<LibRawData>)>();

  late final libraw_get_iheight =
      _lookup<ffi.NativeFunction<ffi.Int Function(ffi.Pointer<LibRawData>)>>(
        'libraw_get_iheight',
      ).asFunction<int Function(ffi.Pointer<LibRawData>)>();

  late final libraw_set_output_bps =
      _lookup<
            ffi.NativeFunction<
              ffi.Void Function(ffi.Pointer<LibRawData>, ffi.Int)
            >
          >('libraw_set_output_bps')
          .asFunction<void Function(ffi.Pointer<LibRawData>, int)>();

  late final libraw_set_output_color =
      _lookup<
            ffi.NativeFunction<
              ffi.Void Function(ffi.Pointer<LibRawData>, ffi.Int)
            >
          >('libraw_set_output_color')
          .asFunction<void Function(ffi.Pointer<LibRawData>, int)>();

  late final libraw_set_demosaic =
      _lookup<
            ffi.NativeFunction<
              ffi.Void Function(ffi.Pointer<LibRawData>, ffi.Int)
            >
          >('libraw_set_demosaic')
          .asFunction<void Function(ffi.Pointer<LibRawData>, int)>();
}
