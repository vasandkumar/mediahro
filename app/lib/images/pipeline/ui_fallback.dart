import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:mediahro/images/image_pipeline.dart';
import 'package:mediahro/images/pipeline/pixel_codec.dart';

/// Decoding through Flutter's own codecs (`dart:ui`): the last resort when
/// neither the OS facade nor libvips can read an image (HEIC without a
/// platform decoder, BMP/ICO, libvips missing in a build). Runs on the engine's
/// decode threads, but the call itself is on the UI isolate, so it is only
/// used for thumbnails and single-image decodes, one at a time.
abstract interface class UiImageFallback {
  /// Image size without decoding the pixels.
  Future<(int width, int height)> size(Uint8List bytes);

  /// Decodes with the longest edge reduced to [maxEdge] when given.
  Future<PixelFrame> decode(Uint8List bytes, {int? maxEdge});

  /// PNG bytes of [frame] (the cache format when libvips cannot write WebP).
  Future<Uint8List> encodePng(PixelFrame frame);
}

final class DartUiFallback implements UiImageFallback {
  const DartUiFallback();

  @override
  Future<(int, int)> size(Uint8List bytes) async {
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    try {
      final d = await ui.ImageDescriptor.encoded(buffer);
      try {
        return (d.width, d.height);
      } finally {
        d.dispose();
      }
    } finally {
      buffer.dispose();
    }
  }

  @override
  Future<PixelFrame> decode(Uint8List bytes, {int? maxEdge}) async {
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    ui.ImageDescriptor? d;
    ui.Codec? codec;
    ui.Image? image;
    try {
      d = await ui.ImageDescriptor.encoded(buffer);
      final w = d.width;
      final h = d.height;
      int? tw;
      int? th;
      if (maxEdge != null && (w > maxEdge || h > maxEdge)) {
        if (w >= h) {
          tw = maxEdge;
          th = (h * maxEdge / w).round().clamp(1, maxEdge);
        } else {
          th = maxEdge;
          tw = (w * maxEdge / h).round().clamp(1, maxEdge);
        }
      }
      codec = await d.instantiateCodec(targetWidth: tw, targetHeight: th);
      final frame = await codec.getNextFrame();
      image = frame.image;
      final data = await image.toByteData();
      if (data == null) {
        throw const CodecUnsupported('dart:ui returned no pixels');
      }
      return PixelFrame(
        width: image.width,
        height: image.height,
        rgba: data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        sourceWidth: w,
        sourceHeight: h,
      );
    } on Exception catch (e) {
      throw CodecUnsupported('dart:ui cannot decode this image: $e');
    } finally {
      image?.dispose();
      codec?.dispose();
      d?.dispose();
      buffer.dispose();
    }
  }

  @override
  Future<Uint8List> encodePng(PixelFrame frame) async {
    final buffer = await ui.ImmutableBuffer.fromUint8List(frame.rgba);
    final d = ui.ImageDescriptor.raw(
      buffer,
      width: frame.width,
      height: frame.height,
      pixelFormat: ui.PixelFormat.rgba8888,
    );
    final codec = await d.instantiateCodec();
    final image = (await codec.getNextFrame()).image;
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) throw const CodecUnsupported('PNG encoding failed');
      return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    } finally {
      image.dispose();
      codec.dispose();
      d.dispose();
      buffer.dispose();
    }
  }
}

/// Maps a [PixelFrame] from the facade or a codec to the pipeline's
/// `DecodedImage`.
DecodedImage toDecoded(
  PixelFrame f, {
  ImageDynamicRange range = ImageDynamicRange.sdr,
}) => DecodedImage(
  width: f.width,
  height: f.height,
  pixels: f.rgba,
  range: range,
);
