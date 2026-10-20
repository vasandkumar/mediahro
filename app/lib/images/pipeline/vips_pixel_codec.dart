import 'dart:typed_data';

import 'package:mediahro/images/image_format.dart';
import 'package:mediahro/images/image_pipeline.dart';
import 'package:mediahro/images/pipeline/pixel_codec.dart';
import 'package:mediahro_ffi/mediahro_ffi.dart';

/// libvips as a [PixelCodec]: JPEG, PNG, WebP, TIFF, GIF, EXR and Radiance
/// HDR with shrink-on-load (docs/05 §5). Formats libvips lacks in
/// `mediahro-deps` (HEIF, JXL, PSD, RAW) are other codecs' job.
final class VipsPixelCodec implements PixelCodec {
  VipsPixelCodec([VipsCodec? vips]) : _vips = vips ?? VipsCodec.open();

  final VipsCodec _vips;

  @override
  String get name => 'vips';

  @override
  bool canRead(ImageFormat format) =>
      format.vipsDecodable ||
      format == ImageFormat.unknown ||
      format == ImageFormat.pnm;

  @override
  bool canWrite(EncodeFormat format) => switch (format) {
    EncodeFormat.jpeg || EncodeFormat.png || EncodeFormat.webp => true,
    EncodeFormat.avif || EncodeFormat.jxl || EncodeFormat.heic => false,
  };

  VipsInput _in(ImageInput input) => switch (input) {
    BytesInput(:final bytes) => VipsInput.bytes(bytes),
    FileInput(:final path) => VipsInput.file(path),
  };

  T _guard<T>(T Function() body) {
    try {
      return body();
    } on VipsException catch (e) {
      throw CodecUnsupported(e.message);
    }
  }

  @override
  PixelHeader header(ImageInput input, ImageFormat format) => _guard(() {
    final h = _vips.header(_in(input));
    return PixelHeader(
      width: h.width,
      height: h.pageHeight > 0 && h.pages > 1 ? h.pageHeight : h.height,
      frames: h.pages,
      hasAlpha: h.hasAlpha,
    );
  });

  @override
  PixelFrame thumbnail(ImageInput input, int edge, ImageFormat format) =>
      _guard(() {
        final h = _vips.header(_in(input));
        final t = _vips.thumbnail(_in(input), edge);
        return PixelFrame(
          width: t.width,
          height: t.height,
          rgba: t.rgba,
          sourceWidth: h.width,
          sourceHeight: h.pageHeight > 0 && h.pages > 1
              ? h.pageHeight
              : h.height,
        );
      });

  @override
  PixelFrame decode(
    ImageInput input,
    ImageFormat format, {
    ImageRegion? region,
    double scale = 1,
    int frame = 0,
  }) => _guard(() {
    final p = _vips.decode(
      _in(input),
      region: region == null
          ? null
          : (
              left: region.left,
              top: region.top,
              width: region.width,
              height: region.height,
            ),
      scale: scale,
      page: frame,
    );
    return PixelFrame(width: p.width, height: p.height, rgba: p.rgba);
  });

  @override
  Uint8List encode(PixelFrame image, EncodeFormat format, int quality) {
    final f = switch (format) {
      EncodeFormat.jpeg => VipsSaveFormat.jpeg,
      EncodeFormat.png => VipsSaveFormat.png,
      EncodeFormat.webp => VipsSaveFormat.webp,
      EncodeFormat.avif ||
      EncodeFormat.jxl ||
      EncodeFormat.heic => throw CodecUnsupported('vips cannot write $format'),
    };
    return _guard(
      () => _vips.encode(
        VipsPixels(image.width, image.height, image.rgba),
        f,
        quality: quality,
      ),
    );
  }
}
