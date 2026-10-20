// ignore_for_file: type=lint, unused_field

// Written by hand to match what `package:ffigen` generates from
// ffigen/jxl.yaml (headers: .deps-cache/<platform>/include/jxl, libjxl from
// mediahro-deps). This PC has no libclang. Structs the decoder fills
// (JxlBasicInfo, JxlPixelFormat) are plain byte buffers read at the offsets
// documented in jxl_codec.dart, which a contract test checks on device.
// Regenerate: (cd packages/mediahro_ffi && dart run ffigen --config ffigen/jxl.yaml)
import 'dart:ffi' as ffi;

/// Opaque `JxlDecoder`.
final class JxlDecoder extends ffi.Opaque {}

/// Opaque `JxlEncoder`.
final class JxlEncoder extends ffi.Opaque {}

abstract final class JxlDecoderStatus {
  static const int success = 0;
  static const int error = 1;
  static const int needMoreInput = 2;
  static const int needImageOutBuffer = 5;
  static const int basicInfo = 0x40;
  static const int colorEncoding = 0x100;
  static const int frame = 0x400;
  static const int fullImage = 0x1000;
}

abstract final class JxlDataType {
  static const int float = 0;
  static const int uint8 = 2;
  static const int uint16 = 3;
  static const int float16 = 5;
}

/// Bindings to libjxl (BSD-3-Clause).
class JxlBindings {
  final ffi.Pointer<T> Function<T extends ffi.NativeType>(String symbolName)
  _lookup;

  JxlBindings(ffi.DynamicLibrary dynamicLibrary)
    : _lookup = dynamicLibrary.lookup;

  JxlBindings.fromLookup(
    ffi.Pointer<T> Function<T extends ffi.NativeType>(String symbolName) lookup,
  ) : _lookup = lookup;

  late final JxlDecoderCreate =
      _lookup<
            ffi.NativeFunction<
              ffi.Pointer<JxlDecoder> Function(ffi.Pointer<ffi.Void>)
            >
          >('JxlDecoderCreate')
          .asFunction<
            ffi.Pointer<JxlDecoder> Function(ffi.Pointer<ffi.Void>)
          >();

  late final JxlDecoderDestroy =
      _lookup<ffi.NativeFunction<ffi.Void Function(ffi.Pointer<JxlDecoder>)>>(
        'JxlDecoderDestroy',
      ).asFunction<void Function(ffi.Pointer<JxlDecoder>)>();

  late final JxlDecoderSubscribeEvents =
      _lookup<
            ffi.NativeFunction<
              ffi.Int32 Function(ffi.Pointer<JxlDecoder>, ffi.Int)
            >
          >('JxlDecoderSubscribeEvents')
          .asFunction<int Function(ffi.Pointer<JxlDecoder>, int)>();

  late final JxlDecoderSetInput =
      _lookup<
            ffi.NativeFunction<
              ffi.Int32 Function(
                ffi.Pointer<JxlDecoder>,
                ffi.Pointer<ffi.Uint8>,
                ffi.Size,
              )
            >
          >('JxlDecoderSetInput')
          .asFunction<
            int Function(ffi.Pointer<JxlDecoder>, ffi.Pointer<ffi.Uint8>, int)
          >();

  late final JxlDecoderCloseInput =
      _lookup<ffi.NativeFunction<ffi.Void Function(ffi.Pointer<JxlDecoder>)>>(
        'JxlDecoderCloseInput',
      ).asFunction<void Function(ffi.Pointer<JxlDecoder>)>();

  late final JxlDecoderProcessInput =
      _lookup<ffi.NativeFunction<ffi.Int32 Function(ffi.Pointer<JxlDecoder>)>>(
        'JxlDecoderProcessInput',
      ).asFunction<int Function(ffi.Pointer<JxlDecoder>)>();

  late final JxlDecoderSkipFrames =
      _lookup<
            ffi.NativeFunction<
              ffi.Void Function(ffi.Pointer<JxlDecoder>, ffi.Size)
            >
          >('JxlDecoderSkipFrames')
          .asFunction<void Function(ffi.Pointer<JxlDecoder>, int)>();

  late final JxlDecoderSetUnpremultiplyAlpha =
      _lookup<
            ffi.NativeFunction<
              ffi.Int32 Function(ffi.Pointer<JxlDecoder>, ffi.Int)
            >
          >('JxlDecoderSetUnpremultiplyAlpha')
          .asFunction<int Function(ffi.Pointer<JxlDecoder>, int)>();

  /// `JxlDecoderGetBasicInfo(dec, JxlBasicInfo*)`: the buffer is at least 204 bytes.
  late final JxlDecoderGetBasicInfo =
      _lookup<
            ffi.NativeFunction<
              ffi.Int32 Function(ffi.Pointer<JxlDecoder>, ffi.Pointer<ffi.Void>)
            >
          >('JxlDecoderGetBasicInfo')
          .asFunction<
            int Function(ffi.Pointer<JxlDecoder>, ffi.Pointer<ffi.Void>)
          >();

  /// `(dec, const JxlPixelFormat*, size_t* size)`.
  late final JxlDecoderImageOutBufferSize =
      _lookup<
            ffi.NativeFunction<
              ffi.Int32 Function(
                ffi.Pointer<JxlDecoder>,
                ffi.Pointer<ffi.Void>,
                ffi.Pointer<ffi.Size>,
              )
            >
          >('JxlDecoderImageOutBufferSize')
          .asFunction<
            int Function(
              ffi.Pointer<JxlDecoder>,
              ffi.Pointer<ffi.Void>,
              ffi.Pointer<ffi.Size>,
            )
          >();

  /// `(dec, const JxlPixelFormat*, void* buffer, size_t size)`.
  late final JxlDecoderSetImageOutBuffer =
      _lookup<
            ffi.NativeFunction<
              ffi.Int32 Function(
                ffi.Pointer<JxlDecoder>,
                ffi.Pointer<ffi.Void>,
                ffi.Pointer<ffi.Void>,
                ffi.Size,
              )
            >
          >('JxlDecoderSetImageOutBuffer')
          .asFunction<
            int Function(
              ffi.Pointer<JxlDecoder>,
              ffi.Pointer<ffi.Void>,
              ffi.Pointer<ffi.Void>,
              int,
            )
          >();

  /// `(dec, const JxlColorEncoding*, const void* icc, size_t icc_size)`.
  late final JxlDecoderSetOutputColorProfile =
      _lookup<
            ffi.NativeFunction<
              ffi.Int32 Function(
                ffi.Pointer<JxlDecoder>,
                ffi.Pointer<ffi.Void>,
                ffi.Pointer<ffi.Void>,
                ffi.Size,
              )
            >
          >('JxlDecoderSetOutputColorProfile')
          .asFunction<
            int Function(
              ffi.Pointer<JxlDecoder>,
              ffi.Pointer<ffi.Void>,
              ffi.Pointer<ffi.Void>,
              int,
            )
          >();

  /// `JxlColorEncodingSetToSRGB(JxlColorEncoding*, JXL_BOOL is_gray)`.
  late final JxlColorEncodingSetToSRGB =
      _lookup<
            ffi.NativeFunction<
              ffi.Void Function(ffi.Pointer<ffi.Void>, ffi.Int)
            >
          >('JxlColorEncodingSetToSRGB')
          .asFunction<void Function(ffi.Pointer<ffi.Void>, int)>();

  // ---- encoder ----

  late final JxlEncoderCreate =
      _lookup<
            ffi.NativeFunction<
              ffi.Pointer<JxlEncoder> Function(ffi.Pointer<ffi.Void>)
            >
          >('JxlEncoderCreate')
          .asFunction<
            ffi.Pointer<JxlEncoder> Function(ffi.Pointer<ffi.Void>)
          >();

  late final JxlEncoderDestroy =
      _lookup<ffi.NativeFunction<ffi.Void Function(ffi.Pointer<JxlEncoder>)>>(
        'JxlEncoderDestroy',
      ).asFunction<void Function(ffi.Pointer<JxlEncoder>)>();

  /// `JxlEncoderInitBasicInfo(JxlBasicInfo*)`: the buffer is at least 204 bytes.
  late final JxlEncoderInitBasicInfo =
      _lookup<ffi.NativeFunction<ffi.Void Function(ffi.Pointer<ffi.Void>)>>(
        'JxlEncoderInitBasicInfo',
      ).asFunction<void Function(ffi.Pointer<ffi.Void>)>();

  late final JxlEncoderSetBasicInfo =
      _lookup<
            ffi.NativeFunction<
              ffi.Int32 Function(ffi.Pointer<JxlEncoder>, ffi.Pointer<ffi.Void>)
            >
          >('JxlEncoderSetBasicInfo')
          .asFunction<
            int Function(ffi.Pointer<JxlEncoder>, ffi.Pointer<ffi.Void>)
          >();

  /// `JxlEncoderInitExtraChannelInfo(JxlExtraChannelType type, JxlExtraChannelInfo*)`.
  late final JxlEncoderInitExtraChannelInfo =
      _lookup<
            ffi.NativeFunction<
              ffi.Void Function(ffi.Int32, ffi.Pointer<ffi.Void>)
            >
          >('JxlEncoderInitExtraChannelInfo')
          .asFunction<void Function(int, ffi.Pointer<ffi.Void>)>();

  late final JxlEncoderSetExtraChannelInfo =
      _lookup<
            ffi.NativeFunction<
              ffi.Int32 Function(
                ffi.Pointer<JxlEncoder>,
                ffi.Size,
                ffi.Pointer<ffi.Void>,
              )
            >
          >('JxlEncoderSetExtraChannelInfo')
          .asFunction<
            int Function(ffi.Pointer<JxlEncoder>, int, ffi.Pointer<ffi.Void>)
          >();

  late final JxlEncoderSetColorEncoding =
      _lookup<
            ffi.NativeFunction<
              ffi.Int32 Function(ffi.Pointer<JxlEncoder>, ffi.Pointer<ffi.Void>)
            >
          >('JxlEncoderSetColorEncoding')
          .asFunction<
            int Function(ffi.Pointer<JxlEncoder>, ffi.Pointer<ffi.Void>)
          >();

  late final JxlEncoderFrameSettingsCreate =
      _lookup<
            ffi.NativeFunction<
              ffi.Pointer<ffi.Void> Function(
                ffi.Pointer<JxlEncoder>,
                ffi.Pointer<ffi.Void>,
              )
            >
          >('JxlEncoderFrameSettingsCreate')
          .asFunction<
            ffi.Pointer<ffi.Void> Function(
              ffi.Pointer<JxlEncoder>,
              ffi.Pointer<ffi.Void>,
            )
          >();

  late final JxlEncoderSetFrameLossless =
      _lookup<
            ffi.NativeFunction<
              ffi.Int32 Function(ffi.Pointer<ffi.Void>, ffi.Int)
            >
          >('JxlEncoderSetFrameLossless')
          .asFunction<int Function(ffi.Pointer<ffi.Void>, int)>();

  late final JxlEncoderSetFrameDistance =
      _lookup<
            ffi.NativeFunction<
              ffi.Int32 Function(ffi.Pointer<ffi.Void>, ffi.Float)
            >
          >('JxlEncoderSetFrameDistance')
          .asFunction<int Function(ffi.Pointer<ffi.Void>, double)>();

  late final JxlEncoderDistanceFromQuality =
      _lookup<ffi.NativeFunction<ffi.Float Function(ffi.Float)>>(
        'JxlEncoderDistanceFromQuality',
      ).asFunction<double Function(double)>();

  late final JxlEncoderFrameSettingsSetOption =
      _lookup<
            ffi.NativeFunction<
              ffi.Int32 Function(ffi.Pointer<ffi.Void>, ffi.Int32, ffi.Int64)
            >
          >('JxlEncoderFrameSettingsSetOption')
          .asFunction<int Function(ffi.Pointer<ffi.Void>, int, int)>();

  /// `(const JxlEncoderFrameSettings*, const JxlPixelFormat*, const void*, size_t)`.
  late final JxlEncoderAddImageFrame =
      _lookup<
            ffi.NativeFunction<
              ffi.Int32 Function(
                ffi.Pointer<ffi.Void>,
                ffi.Pointer<ffi.Void>,
                ffi.Pointer<ffi.Void>,
                ffi.Size,
              )
            >
          >('JxlEncoderAddImageFrame')
          .asFunction<
            int Function(
              ffi.Pointer<ffi.Void>,
              ffi.Pointer<ffi.Void>,
              ffi.Pointer<ffi.Void>,
              int,
            )
          >();

  late final JxlEncoderCloseInput =
      _lookup<ffi.NativeFunction<ffi.Void Function(ffi.Pointer<JxlEncoder>)>>(
        'JxlEncoderCloseInput',
      ).asFunction<void Function(ffi.Pointer<JxlEncoder>)>();

  /// `(enc, uint8_t** next_out, size_t* avail_out)`.
  late final JxlEncoderProcessOutput =
      _lookup<
            ffi.NativeFunction<
              ffi.Int32 Function(
                ffi.Pointer<JxlEncoder>,
                ffi.Pointer<ffi.Pointer<ffi.Uint8>>,
                ffi.Pointer<ffi.Size>,
              )
            >
          >('JxlEncoderProcessOutput')
          .asFunction<
            int Function(
              ffi.Pointer<JxlEncoder>,
              ffi.Pointer<ffi.Pointer<ffi.Uint8>>,
              ffi.Pointer<ffi.Size>,
            )
          >();
}
