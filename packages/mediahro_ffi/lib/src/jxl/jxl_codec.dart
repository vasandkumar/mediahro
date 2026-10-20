import 'dart:ffi' as ffi;
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:mediahro_ffi/src/jxl/jxl_bindings.dart';
import 'package:mediahro_ffi/src/native/native_library.dart';
import 'package:meta/meta.dart';

/// libjxl could not decode the data; [message] says where it stopped.
final class JxlException implements Exception {
  const JxlException(this.message);

  final String message;

  @override
  String toString() => 'JxlException: $message';
}

/// What the JPEG XL header says.
@immutable
final class JxlHeader {
  const JxlHeader({
    required this.width,
    required this.height,
    required this.hasAlpha,
    required this.animated,
    required this.bitsPerSample,
    required this.intensityTarget,
    required this.orientation,
  });

  /// Size after the stored orientation is applied (the decoder rotates).
  final int width;
  final int height;
  final bool hasAlpha;
  final bool animated;
  final int bitsPerSample;

  /// Peak luminance in nits the image was mastered for (255 for SDR).
  final double intensityTarget;

  /// 1–8 (EXIF numbering).
  final int orientation;

  /// More than 8 bits and a bright target: an HDR image (IMG-002).
  bool get isHdr => intensityTarget > 300;
}

/// A decoded frame: RGBA8888 in sRGB, straight alpha.
@immutable
final class JxlImage {
  const JxlImage(this.header, this.width, this.height, this.rgba);

  final JxlHeader header;
  final int width;
  final int height;
  final Uint8List rgba;
}

/// JPEG XL decoding on top of libjxl's streaming decoder (IMG-001). Blocking;
/// use on a worker isolate.
///
/// Struct layouts read here (64-bit and 32-bit alike, every field 4 bytes):
/// `JxlBasicInfo` { have_container 0, xsize 4, ysize 8, bits_per_sample 12,
/// exponent_bits 16, intensity_target 20 (float), …, have_animation 44,
/// orientation 48, num_color_channels 52, num_extra_channels 56,
/// alpha_bits 60 }; `JxlPixelFormat` { num_channels 0, data_type 4,
/// endianness 8, align 16 (size_t) }.
final class JxlCodec {
  JxlCodec._(this._j);

  factory JxlCodec.open({JxlBindings? bindings}) => _instance ??= JxlCodec._(
    bindings ?? JxlBindings(NativeLibraries.open(NativeLibrary.jxl)),
  );

  static JxlCodec? _instance;

  final JxlBindings _j;

  static const int _infoSize = 256;
  static const int _formatSize = 24;

  JxlHeader _readInfo(ffi.Pointer<ffi.Void> info) {
    final u = info.cast<ffi.Uint32>();
    final f = info.cast<ffi.Float>();
    var w = u[1];
    var h = u[2];
    final orientation = u[12].clamp(1, 8);
    // The decoder applies the orientation to the pixels by default.
    if (orientation >= 5) {
      final t = w;
      w = h;
      h = t;
    }
    return JxlHeader(
      width: w,
      height: h,
      hasAlpha: u[15] > 0,
      animated: u[11] != 0,
      bitsPerSample: u[3],
      intensityTarget: f[5],
      orientation: orientation,
    );
  }

  /// Runs [body] with a decoder subscribed to [events] over [bytes]; `next`
  /// processes input until the next event.
  T _run<T>(
    Uint8List bytes,
    int events,
    T Function(ffi.Pointer<JxlDecoder> dec, int Function() next) body,
  ) {
    final data = malloc<ffi.Uint8>(bytes.isEmpty ? 1 : bytes.length);
    final dec = _j.JxlDecoderCreate(ffi.nullptr);
    if (dec == ffi.nullptr) {
      malloc.free(data);
      throw const JxlException('cannot create a decoder');
    }
    try {
      data.asTypedList(bytes.length).setAll(0, bytes);
      if (_j.JxlDecoderSubscribeEvents(dec, events) !=
          JxlDecoderStatus.success) {
        throw const JxlException('cannot subscribe to decoder events');
      }
      if (_j.JxlDecoderSetInput(dec, data, bytes.length) !=
          JxlDecoderStatus.success) {
        throw const JxlException('cannot set the input');
      }
      _j.JxlDecoderCloseInput(dec);
      return body(dec, () => _j.JxlDecoderProcessInput(dec));
    } finally {
      _j.JxlDecoderDestroy(dec);
      malloc.free(data);
    }
  }

  /// The header only.
  JxlHeader header(Uint8List bytes) =>
      _run(bytes, JxlDecoderStatus.basicInfo, (dec, next) {
        final info = malloc<ffi.Uint8>(_infoSize);
        try {
          while (true) {
            final s = next();
            if (s == JxlDecoderStatus.basicInfo) {
              if (_j.JxlDecoderGetBasicInfo(dec, info.cast()) !=
                  JxlDecoderStatus.success) {
                throw const JxlException('no basic info');
              }
              return _readInfo(info.cast());
            }
            throw JxlException(
              s == JxlDecoderStatus.needMoreInput
                  ? 'truncated file'
                  : 'not a JPEG XL file',
            );
          }
        } finally {
          malloc.free(info);
        }
      });

  /// Decodes frame [frame] (0 for stills) to sRGB RGBA8888.
  JxlImage decode(Uint8List bytes, {int frame = 0}) => _run(
    bytes,
    JxlDecoderStatus.basicInfo |
        JxlDecoderStatus.colorEncoding |
        JxlDecoderStatus.fullImage,
    (dec, next) {
      final info = malloc<ffi.Uint8>(_infoSize);
      final format = malloc<ffi.Uint8>(_formatSize);
      final enc = malloc<ffi.Uint8>(_infoSize);
      ffi.Pointer<ffi.Uint8>? out;
      var outSize = 0;
      JxlHeader? header;
      try {
        format.asTypedList(_formatSize).fillRange(0, _formatSize, 0);
        format.cast<ffi.Uint32>()[0] = 4; // RGBA
        format.cast<ffi.Uint32>()[1] = JxlDataType.uint8;
        _j.JxlDecoderSetUnpremultiplyAlpha(dec, 1);
        if (frame > 0) _j.JxlDecoderSkipFrames(dec, frame);
        while (true) {
          final s = next();
          switch (s) {
            case JxlDecoderStatus.basicInfo:
              if (_j.JxlDecoderGetBasicInfo(dec, info.cast()) !=
                  JxlDecoderStatus.success) {
                throw const JxlException('no basic info');
              }
              header = _readInfo(info.cast());
            case JxlDecoderStatus.colorEncoding:
              // Ask for sRGB so wide-gamut and HDR images arrive tone-mapped
              // for SDR; images libjxl cannot convert keep their own colours.
              _j.JxlColorEncodingSetToSRGB(enc.cast(), 0);
              _j.JxlDecoderSetOutputColorProfile(
                dec,
                enc.cast(),
                ffi.nullptr,
                0,
              );
            case JxlDecoderStatus.needImageOutBuffer:
              final size = malloc<ffi.Size>();
              try {
                if (_j.JxlDecoderImageOutBufferSize(dec, format.cast(), size) !=
                    JxlDecoderStatus.success) {
                  throw const JxlException('no output size');
                }
                outSize = size.value;
              } finally {
                malloc.free(size);
              }
              out = malloc<ffi.Uint8>(outSize);
              if (_j.JxlDecoderSetImageOutBuffer(
                    dec,
                    format.cast(),
                    out.cast(),
                    outSize,
                  ) !=
                  JxlDecoderStatus.success) {
                throw const JxlException('cannot set the output buffer');
              }
            case JxlDecoderStatus.fullImage || JxlDecoderStatus.success:
              final h = header;
              final o = out;
              if (h == null || o == null) {
                throw const JxlException('no image in this file');
              }
              var w = h.width;
              var ht = h.height;
              if (w * ht * 4 != outSize) {
                // Orientation was kept in the pixels: undo the swap.
                final t = w;
                w = ht;
                ht = t;
              }
              if (w * ht * 4 != outSize) {
                throw const JxlException('unexpected output size');
              }
              return JxlImage(
                h,
                w,
                ht,
                Uint8List.fromList(o.asTypedList(outSize)),
              );
            case JxlDecoderStatus.needMoreInput:
              throw const JxlException('truncated file');
            default:
              throw const JxlException('decoder error');
          }
        }
      } finally {
        malloc
          ..free(info)
          ..free(format)
          ..free(enc);
        if (out != null) malloc.free(out);
      }
    },
  );

  /// Encodes RGBA8888 as a JPEG XL codestream (IMG-010). [quality] 1–100
  /// (about JPEG's scale; 100 or [lossless] is mathematically lossless);
  /// [effort] 1–9, lower is faster. Alpha is kept only if some pixel is not
  /// opaque.
  Uint8List encode(
    Uint8List rgba,
    int width,
    int height, {
    int quality = 90,
    bool lossless = false,
    int effort = 5,
  }) {
    if (rgba.length != width * height * 4) {
      throw const JxlException('pixel buffer does not match the size');
    }
    var hasAlpha = false;
    for (var i = 3; i < rgba.length; i += 4) {
      if (rgba[i] != 255) {
        hasAlpha = true;
        break;
      }
    }
    final channels = hasAlpha ? 4 : 3;
    final enc = _j.JxlEncoderCreate(ffi.nullptr);
    if (enc == ffi.nullptr) {
      throw const JxlException('cannot create an encoder');
    }
    final info = malloc<ffi.Uint8>(_infoSize);
    final colour = malloc<ffi.Uint8>(_infoSize);
    final extra = malloc<ffi.Uint8>(_infoSize);
    final format = malloc<ffi.Uint8>(_formatSize);
    final pixels = malloc<ffi.Uint8>(width * height * channels);
    var cap = 1 << 16;
    var out = malloc<ffi.Uint8>(cap);
    final next = malloc<ffi.Pointer<ffi.Uint8>>();
    final avail = malloc<ffi.Size>();
    try {
      final lossy = !lossless && quality < 100;
      _j.JxlEncoderInitBasicInfo(info.cast());
      final u = info.cast<ffi.Uint32>();
      u[1] = width;
      u[2] = height;
      u[3] = 8; // bits per sample
      u[4] = 0; // exponent bits
      u[9] = lossy ? 0 : 1; // uses_original_profile (required for lossless)
      u[13] = 3; // colour channels
      u[14] = hasAlpha ? 1 : 0; // extra channels
      u[15] = hasAlpha ? 8 : 0; // alpha bits
      _ok(_j.JxlEncoderSetBasicInfo(enc, info.cast()), 'basic info');
      if (hasAlpha) {
        _j.JxlEncoderInitExtraChannelInfo(0, extra.cast()); // alpha
        _ok(_j.JxlEncoderSetExtraChannelInfo(enc, 0, extra.cast()), 'alpha');
      }
      _j.JxlColorEncodingSetToSRGB(colour.cast(), 0);
      _ok(_j.JxlEncoderSetColorEncoding(enc, colour.cast()), 'colour');
      final settings = _j.JxlEncoderFrameSettingsCreate(enc, ffi.nullptr);
      _ok(
        _j.JxlEncoderFrameSettingsSetOption(settings, 0, effort.clamp(1, 9)),
        'effort',
      );
      if (lossy) {
        _ok(
          _j.JxlEncoderSetFrameDistance(
            settings,
            _j.JxlEncoderDistanceFromQuality(quality.toDouble()),
          ),
          'distance',
        );
      } else {
        _ok(_j.JxlEncoderSetFrameLossless(settings, 1), 'lossless');
      }
      format.asTypedList(_formatSize).fillRange(0, _formatSize, 0);
      format.cast<ffi.Uint32>()[0] = channels;
      format.cast<ffi.Uint32>()[1] = JxlDataType.uint8;
      if (hasAlpha) {
        pixels.asTypedList(rgba.length).setAll(0, rgba);
      } else {
        final p = pixels.asTypedList(width * height * 3);
        for (var i = 0, j = 0; i < rgba.length; i += 4, j += 3) {
          p[j] = rgba[i];
          p[j + 1] = rgba[i + 1];
          p[j + 2] = rgba[i + 2];
        }
      }
      _ok(
        _j.JxlEncoderAddImageFrame(
          settings,
          format.cast(),
          pixels.cast(),
          width * height * channels,
        ),
        'frame',
      );
      _j.JxlEncoderCloseInput(enc);
      next.value = out;
      avail.value = cap;
      while (true) {
        final s = _j.JxlEncoderProcessOutput(enc, next, avail);
        if (s == 0) break; // success
        if (s != 2) throw const JxlException('encoder error');
        final used = next.value.address - out.address;
        final bigger = malloc<ffi.Uint8>(cap * 2);
        bigger.asTypedList(used).setAll(0, out.asTypedList(used));
        malloc.free(out);
        out = bigger;
        cap *= 2;
        next.value = out + used;
        avail.value = cap - used;
      }
      return Uint8List.fromList(
        out.asTypedList(next.value.address - out.address),
      );
    } finally {
      _j.JxlEncoderDestroy(enc);
      malloc
        ..free(info)
        ..free(colour)
        ..free(extra)
        ..free(format)
        ..free(pixels)
        ..free(out)
        ..free(next)
        ..free(avail);
    }
  }

  void _ok(int status, String what) {
    if (status != JxlDecoderStatus.success) {
      throw JxlException('encoder: $what failed ($status)');
    }
  }
}
