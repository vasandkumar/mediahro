// ignore_for_file: type=lint, unused_field

// Written by hand to match what `package:ffigen` generates from
// ffigen/avif.yaml (headers: .deps-cache/<platform>/include/avif, libavif
// 1.4 with dav1d, from mediahro-deps). This PC has no libclang. The structs
// (avifDecoder, avifImage, avifRGBImage) are read at the offsets documented
// in avif_codec.dart.
// Regenerate: (cd packages/mediahro_ffi && dart run ffigen --config ffigen/avif.yaml)
import 'dart:ffi' as ffi;

/// Opaque `avifDecoder` (fields are read at fixed offsets).
final class AvifDecoder extends ffi.Opaque {}

/// Opaque `avifImage`.
final class AvifImage extends ffi.Opaque {}

abstract final class AvifResult {
  static const int ok = 0;
}

abstract final class AvifRgbFormat {
  static const int rgb = 0;
  static const int rgba = 1;
}

/// Bindings to libavif (BSD-2-Clause) with the dav1d decoder.
class AvifBindings {
  final ffi.Pointer<T> Function<T extends ffi.NativeType>(String symbolName)
  _lookup;

  AvifBindings(ffi.DynamicLibrary dynamicLibrary)
    : _lookup = dynamicLibrary.lookup;

  AvifBindings.fromLookup(
    ffi.Pointer<T> Function<T extends ffi.NativeType>(String symbolName) lookup,
  ) : _lookup = lookup;

  late final avifVersion =
      _lookup<ffi.NativeFunction<ffi.Pointer<ffi.Char> Function()>>(
        'avifVersion',
      ).asFunction<ffi.Pointer<ffi.Char> Function()>();

  late final avifResultToString =
      _lookup<ffi.NativeFunction<ffi.Pointer<ffi.Char> Function(ffi.Int32)>>(
        'avifResultToString',
      ).asFunction<ffi.Pointer<ffi.Char> Function(int)>();

  late final avifDecoderCreate =
      _lookup<ffi.NativeFunction<ffi.Pointer<AvifDecoder> Function()>>(
        'avifDecoderCreate',
      ).asFunction<ffi.Pointer<AvifDecoder> Function()>();

  late final avifDecoderDestroy =
      _lookup<ffi.NativeFunction<ffi.Void Function(ffi.Pointer<AvifDecoder>)>>(
        'avifDecoderDestroy',
      ).asFunction<void Function(ffi.Pointer<AvifDecoder>)>();

  late final avifDecoderSetIOMemory =
      _lookup<
            ffi.NativeFunction<
              ffi.Int32 Function(
                ffi.Pointer<AvifDecoder>,
                ffi.Pointer<ffi.Uint8>,
                ffi.Size,
              )
            >
          >('avifDecoderSetIOMemory')
          .asFunction<
            int Function(ffi.Pointer<AvifDecoder>, ffi.Pointer<ffi.Uint8>, int)
          >();

  late final avifDecoderParse =
      _lookup<ffi.NativeFunction<ffi.Int32 Function(ffi.Pointer<AvifDecoder>)>>(
        'avifDecoderParse',
      ).asFunction<int Function(ffi.Pointer<AvifDecoder>)>();

  late final avifDecoderNextImage =
      _lookup<ffi.NativeFunction<ffi.Int32 Function(ffi.Pointer<AvifDecoder>)>>(
        'avifDecoderNextImage',
      ).asFunction<int Function(ffi.Pointer<AvifDecoder>)>();

  late final avifDecoderNthImage =
      _lookup<
            ffi.NativeFunction<
              ffi.Int32 Function(ffi.Pointer<AvifDecoder>, ffi.Uint32)
            >
          >('avifDecoderNthImage')
          .asFunction<int Function(ffi.Pointer<AvifDecoder>, int)>();

  /// `(avifRGBImage*, const avifImage*)`; the struct is a 64-byte buffer.
  late final avifRGBImageSetDefaults =
      _lookup<
            ffi.NativeFunction<
              ffi.Void Function(ffi.Pointer<ffi.Void>, ffi.Pointer<AvifImage>)
            >
          >('avifRGBImageSetDefaults')
          .asFunction<
            void Function(ffi.Pointer<ffi.Void>, ffi.Pointer<AvifImage>)
          >();

  late final avifRGBImageAllocatePixels =
      _lookup<ffi.NativeFunction<ffi.Int32 Function(ffi.Pointer<ffi.Void>)>>(
        'avifRGBImageAllocatePixels',
      ).asFunction<int Function(ffi.Pointer<ffi.Void>)>();

  late final avifRGBImageFreePixels =
      _lookup<ffi.NativeFunction<ffi.Void Function(ffi.Pointer<ffi.Void>)>>(
        'avifRGBImageFreePixels',
      ).asFunction<void Function(ffi.Pointer<ffi.Void>)>();

  late final avifImageYUVToRGB =
      _lookup<
            ffi.NativeFunction<
              ffi.Int32 Function(ffi.Pointer<AvifImage>, ffi.Pointer<ffi.Void>)
            >
          >('avifImageYUVToRGB')
          .asFunction<
            int Function(ffi.Pointer<AvifImage>, ffi.Pointer<ffi.Void>)
          >();
}
