import 'dart:typed_data';

import 'package:mediahro/images/image_format.dart';
import 'package:mediahro/images/image_pipeline.dart';
import 'package:meta/meta.dart';

/// Where a codec reads from: memory or a local file (streamed, so 100 MP+
/// images never sit in Dart memory).
@immutable
sealed class ImageInput {
  const ImageInput();

  const factory ImageInput.bytes(Uint8List bytes) = BytesInput;
  const factory ImageInput.file(String path) = FileInput;
}

final class BytesInput extends ImageInput {
  const BytesInput(this.bytes);

  final Uint8List bytes;
}

final class FileInput extends ImageInput {
  const FileInput(this.path);

  final String path;
}

/// Decoded pixels plus the size of the image they came from (thumbnails
/// and scaled decodes are smaller than their source).
@immutable
final class PixelFrame {
  const PixelFrame({
    required this.width,
    required this.height,
    required this.rgba,
    int? sourceWidth,
    int? sourceHeight,
  }) : sourceWidth = sourceWidth ?? width,
       sourceHeight = sourceHeight ?? height;

  final int width;
  final int height;

  /// RGBA8888, straight alpha, no row padding.
  final Uint8List rgba;
  final int sourceWidth;
  final int sourceHeight;
}

/// The facts a decoder reads from the header.
@immutable
final class PixelHeader {
  const PixelHeader({
    required this.width,
    required this.height,
    this.frames = 1,
    this.hasAlpha = false,
  });

  final int width;
  final int height;
  final int frames;
  final bool hasAlpha;
}

/// A blocking decoder/encoder that runs on a worker isolate. Implementations
/// wrap one native library (libvips, libjxl, LibRaw) and throw
/// [CodecUnsupported] for input they cannot read so the next one is tried.
abstract interface class PixelCodec {
  /// Short name for diagnostics (`vips`, `jxl`).
  String get name;

  /// Whether this codec reads [format].
  bool canRead(ImageFormat format);

  PixelHeader header(ImageInput input, ImageFormat format);

  /// A thumbnail of the longest edge [edge], orientation applied.
  PixelFrame thumbnail(ImageInput input, int edge, ImageFormat format);

  /// [region] in source pixels; the result is scaled by [scale].
  PixelFrame decode(
    ImageInput input,
    ImageFormat format, {
    ImageRegion? region,
    double scale = 1,
    int frame = 0,
  });

  /// Encodes [image]; [format] is one of the formats [canWrite] accepts.
  Uint8List encode(PixelFrame image, EncodeFormat format, int quality);

  bool canWrite(EncodeFormat format);
}

/// This codec cannot read or write the input; try another backend.
final class CodecUnsupported implements Exception {
  const CodecUnsupported(this.message);

  final String message;

  @override
  String toString() => 'CodecUnsupported: $message';
}

/// Tries each codec in order (OS first is handled above this level).
final class CompositePixelCodec implements PixelCodec {
  CompositePixelCodec(this.codecs);

  final List<PixelCodec> codecs;

  @override
  String get name => codecs.map((c) => c.name).join('+');

  @override
  bool canRead(ImageFormat format) => codecs.any((c) => c.canRead(format));

  @override
  bool canWrite(EncodeFormat format) => codecs.any((c) => c.canWrite(format));

  T _first<T>(
    ImageFormat format,
    T Function(PixelCodec c) body, {
    bool Function(PixelCodec c)? applies,
  }) {
    CodecUnsupported? last;
    for (final c in codecs) {
      if (applies != null ? !applies(c) : !c.canRead(format)) continue;
      try {
        return body(c);
      } on CodecUnsupported catch (e) {
        last = e;
      }
    }
    throw last ?? CodecUnsupported('no codec reads ${format.shortName}');
  }

  @override
  PixelHeader header(ImageInput input, ImageFormat format) =>
      _first(format, (c) => c.header(input, format));

  @override
  PixelFrame thumbnail(ImageInput input, int edge, ImageFormat format) =>
      _first(format, (c) => c.thumbnail(input, edge, format));

  @override
  PixelFrame decode(
    ImageInput input,
    ImageFormat format, {
    ImageRegion? region,
    double scale = 1,
    int frame = 0,
  }) => _first(
    format,
    (c) => c.decode(input, format, region: region, scale: scale, frame: frame),
  );

  @override
  Uint8List encode(PixelFrame image, EncodeFormat format, int quality) =>
      _first(
        ImageFormat.unknown,
        (c) => c.encode(image, format, quality),
        applies: (c) => c.canWrite(format),
      );
}
