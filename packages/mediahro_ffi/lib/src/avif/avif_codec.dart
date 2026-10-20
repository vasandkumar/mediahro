import 'dart:ffi' as ffi;
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:mediahro_ffi/src/avif/avif_bindings.dart';
import 'package:mediahro_ffi/src/native/native_library.dart';
import 'package:meta/meta.dart';

/// libavif could not decode the data.
final class AvifException implements Exception {
  const AvifException(this.message);

  final String message;

  @override
  String toString() => 'AvifException: $message';
}

/// What an AVIF's container says before any pixel is decoded.
@immutable
final class AvifHeader {
  const AvifHeader({
    required this.width,
    required this.height,
    required this.frames,
  });

  final int width;
  final int height;

  /// Images in the sequence (1 for a still).
  final int frames;
}

/// A decoded frame: RGBA8888, straight alpha.
@immutable
final class AvifFrame {
  const AvifFrame(this.header, this.width, this.height, this.rgba);

  final AvifHeader header;
  final int width;
  final int height;
  final Uint8List rgba;
}

/// AVIF decoding through libavif and dav1d (IMG-001). Blocking; use on a
/// worker isolate.
///
/// Fixed offsets for libavif 1.x (checked against the pinned headers; the
/// codec refuses other major versions):
/// `avifDecoder` { …, image 48 (pointer), imageIndex 56, imageCount 60 };
/// `avifImage` { width 0, height 4, depth 8 };
/// `avifRGBImage` { width 0, height 4, depth 8, format 12, …, pixels 48
/// (pointer), rowBytes 56 } in a 64-byte buffer.
final class AvifCodec {
  AvifCodec._(this._a);

  factory AvifCodec.open({AvifBindings? bindings}) {
    final existing = _instance;
    if (existing != null) return existing;
    final a =
        bindings ?? AvifBindings(NativeLibraries.open(NativeLibrary.avif));
    final version = a.avifVersion().cast<Utf8>().toDartString();
    if (!version.startsWith('1.')) {
      throw AvifException('unsupported libavif $version');
    }
    return _instance = AvifCodec._(a);
  }

  static AvifCodec? _instance;

  final AvifBindings _a;

  static const int _rgbSize = 64;
  static const int _imageField = 6; // 48 / 8
  static const int _imageCountField = 15; // 60 / 4

  void _check(int result, String what) {
    if (result != AvifResult.ok) {
      throw AvifException(
        '$what: ${_a.avifResultToString(result).cast<Utf8>().toDartString()}',
      );
    }
  }

  T _open<T>(
    Uint8List bytes,
    T Function(ffi.Pointer<AvifDecoder> dec, int frames) body,
  ) {
    final data = malloc<ffi.Uint8>(bytes.isEmpty ? 1 : bytes.length);
    final dec = _a.avifDecoderCreate();
    if (dec == ffi.nullptr) {
      malloc.free(data);
      throw const AvifException('cannot create a decoder');
    }
    try {
      data.asTypedList(bytes.length).setAll(0, bytes);
      _check(_a.avifDecoderSetIOMemory(dec, data, bytes.length), 'input');
      _check(_a.avifDecoderParse(dec), 'parse');
      final frames = dec.cast<ffi.Int32>()[_imageCountField];
      return body(dec, frames < 1 ? 1 : frames);
    } finally {
      _a.avifDecoderDestroy(dec);
      malloc.free(data);
    }
  }

  ffi.Pointer<AvifImage> _image(ffi.Pointer<AvifDecoder> dec) =>
      dec.cast<ffi.Pointer<AvifImage>>()[_imageField];

  AvifHeader _header(ffi.Pointer<AvifDecoder> dec, int frames) {
    final img = _image(dec);
    if (img == ffi.nullptr) throw const AvifException('no image in this file');
    final u = img.cast<ffi.Uint32>();
    return AvifHeader(width: u[0], height: u[1], frames: frames);
  }

  AvifHeader header(Uint8List bytes) => _open(bytes, _header);

  /// Decodes frame [frame] (0 for stills) to RGBA8888.
  AvifFrame decode(Uint8List bytes, {int frame = 0}) =>
      _open(bytes, (dec, frames) {
        if (frame < 0 || frame >= frames) {
          throw AvifException('frame $frame of $frames');
        }
        _check(_a.avifDecoderNthImage(dec, frame), 'decode');
        final header = _header(dec, frames);
        final img = _image(dec);
        final rgb = calloc<ffi.Uint8>(_rgbSize);
        try {
          _a.avifRGBImageSetDefaults(rgb.cast(), img);
          final u = rgb.cast<ffi.Uint32>();
          u[2] = 8; // depth
          u[3] = AvifRgbFormat.rgba;
          _check(_a.avifRGBImageAllocatePixels(rgb.cast()), 'allocate');
          try {
            _check(_a.avifImageYUVToRGB(img, rgb.cast()), 'convert');
            final w = u[0];
            final h = u[1];
            final rowBytes = u[14]; // offset 56
            final pixels = rgb.cast<ffi.Pointer<ffi.Uint8>>()[6]; // offset 48
            final out = Uint8List(w * h * 4);
            for (var y = 0; y < h; y++) {
              out.setRange(
                y * w * 4,
                (y + 1) * w * 4,
                (pixels + y * rowBytes).asTypedList(w * 4),
              );
            }
            return AvifFrame(header, w, h, out);
          } finally {
            _a.avifRGBImageFreePixels(rgb.cast());
          }
        } finally {
          calloc.free(rgb);
        }
      });
}
