import 'dart:io';
import 'dart:typed_data';

import 'package:mediahro/images/image_format.dart';
import 'package:mediahro/images/image_pipeline.dart';
import 'package:mediahro/images/pipeline/pixel_codec.dart';
import 'package:mediahro/images/pipeline/pixel_ops.dart';
import 'package:mediahro/images/pipeline/small_decoders.dart';
import 'package:mediahro_ffi/mediahro_ffi.dart';

/// The whole file as bytes (these libraries decode from memory).
Uint8List _bytes(ImageInput input) => switch (input) {
  BytesInput(:final bytes) => bytes,
  FileInput(:final path) => File(path).readAsBytesSync(),
};

/// JPEG XL through libjxl (IMG-001 decode, IMG-010 encode). It produces whole
/// frames, so regions and thumbnails are cut from the decoded frame.
final class JxlPixelCodec implements PixelCodec {
  JxlPixelCodec([JxlCodec? jxl]) : _jxl = jxl ?? JxlCodec.open();

  final JxlCodec _jxl;

  @override
  String get name => 'jxl';

  @override
  bool canRead(ImageFormat format) => format == ImageFormat.jxl;

  @override
  bool canWrite(EncodeFormat format) => format == EncodeFormat.jxl;

  T _guard<T>(T Function() body) {
    try {
      return body();
    } on JxlException catch (e) {
      throw CodecUnsupported(e.message);
    }
  }

  @override
  PixelHeader header(ImageInput input, ImageFormat format) => _guard(() {
    final h = _jxl.header(_bytes(input));
    return PixelHeader(
      width: h.width,
      height: h.height,
      // The frame count of an animation needs a full scan; 2 means "animated".
      frames: h.animated ? 2 : 1,
      hasAlpha: h.hasAlpha,
    );
  });

  PixelFrame _frame(ImageInput input, int frame) => _guard(() {
    final img = _jxl.decode(_bytes(input), frame: frame);
    return PixelFrame(width: img.width, height: img.height, rgba: img.rgba);
  });

  @override
  PixelFrame thumbnail(ImageInput input, int edge, ImageFormat format) {
    final f = _frame(input, 0);
    final t = downscaleToEdge(f, edge);
    return PixelFrame(
      width: t.width,
      height: t.height,
      rgba: t.rgba,
      sourceWidth: f.width,
      sourceHeight: f.height,
    );
  }

  @override
  PixelFrame decode(
    ImageInput input,
    ImageFormat format, {
    ImageRegion? region,
    double scale = 1,
    int frame = 0,
  }) => regionAndScale(_frame(input, frame), region, scale);

  @override
  Uint8List encode(PixelFrame image, EncodeFormat format, int quality) {
    if (format != EncodeFormat.jxl) {
      throw CodecUnsupported('jxl codec cannot write $format');
    }
    return _guard(
      () =>
          _jxl.encode(image.rgba, image.width, image.height, quality: quality),
    );
  }
}

/// AVIF stills and sequences through libavif and dav1d (IMG-001). Encoding
/// waits for the AV1 encoder in mediahro-deps (B4a).
final class AvifPixelCodec implements PixelCodec {
  AvifPixelCodec([AvifCodec? avif]) : _avif = avif ?? AvifCodec.open();

  final AvifCodec _avif;

  @override
  String get name => 'avif';

  @override
  bool canRead(ImageFormat format) => format == ImageFormat.avif;

  @override
  bool canWrite(EncodeFormat format) => false;

  T _guard<T>(T Function() body) {
    try {
      return body();
    } on AvifException catch (e) {
      throw CodecUnsupported(e.message);
    }
  }

  @override
  PixelHeader header(ImageInput input, ImageFormat format) => _guard(() {
    final h = _avif.header(_bytes(input));
    return PixelHeader(width: h.width, height: h.height, frames: h.frames);
  });

  PixelFrame _frame(ImageInput input, int frame) => _guard(() {
    final f = _avif.decode(_bytes(input), frame: frame);
    return PixelFrame(width: f.width, height: f.height, rgba: f.rgba);
  });

  @override
  PixelFrame thumbnail(ImageInput input, int edge, ImageFormat format) {
    final f = _frame(input, 0);
    final t = downscaleToEdge(f, edge);
    return PixelFrame(
      width: t.width,
      height: t.height,
      rgba: t.rgba,
      sourceWidth: f.width,
      sourceHeight: f.height,
    );
  }

  @override
  PixelFrame decode(
    ImageInput input,
    ImageFormat format, {
    ImageRegion? region,
    double scale = 1,
    int frame = 0,
  }) => regionAndScale(_frame(input, frame), region, scale);

  @override
  Uint8List encode(PixelFrame image, EncodeFormat format, int quality) =>
      throw const CodecUnsupported('AVIF encoding is not in this build');
}

/// Camera RAW through LibRaw (IMG-001): development to sRGB, and the
/// embedded preview for files whose previews are not in TIFF directories
/// (Canon CR3). The preview is JPEG, which [jpeg] decodes.
final class RawPixelCodec implements PixelCodec {
  RawPixelCodec({RawCodec? raw, this.jpeg}) : _raw = raw ?? RawCodec.open();

  final RawCodec _raw;

  /// Decodes the JPEG previews LibRaw hands back.
  final PixelCodec? jpeg;

  @override
  String get name => 'raw';

  @override
  bool canRead(ImageFormat format) => format == ImageFormat.raw;

  @override
  bool canWrite(EncodeFormat format) => false;

  T _guard<T>(T Function() body) {
    try {
      return body();
    } on RawException catch (e) {
      throw CodecUnsupported(e.message);
    }
  }

  @override
  PixelHeader header(ImageInput input, ImageFormat format) => _guard(() {
    final s = _raw.size(_bytes(input));
    return PixelHeader(width: s.width, height: s.height);
  });

  @override
  PixelFrame thumbnail(ImageInput input, int edge, ImageFormat format) {
    final bytes = _bytes(input);
    final t = _guard(() => _raw.thumbnail(bytes));
    final decoder = jpeg;
    final PixelFrame frame;
    final img = t.image;
    if (img != null) {
      frame = PixelFrame(width: img.width, height: img.height, rgba: img.rgba);
    } else if (t.jpeg != null && decoder != null) {
      return decoder.thumbnail(
        ImageInput.bytes(t.jpeg!),
        edge,
        ImageFormat.jpeg,
      );
    } else {
      throw const CodecUnsupported('no preview in this RAW');
    }
    final small = downscaleToEdge(frame, edge);
    return PixelFrame(
      width: small.width,
      height: small.height,
      rgba: small.rgba,
      sourceWidth: frame.width,
      sourceHeight: frame.height,
    );
  }

  @override
  PixelFrame decode(
    ImageInput input,
    ImageFormat format, {
    ImageRegion? region,
    double scale = 1,
    int frame = 0,
  }) {
    final img = _guard(() => _raw.develop(_bytes(input)));
    return regionAndScale(
      PixelFrame(width: img.width, height: img.height, rgba: img.rgba),
      region,
      scale,
    );
  }

  @override
  Uint8List encode(PixelFrame image, EncodeFormat format, int quality) =>
      throw const CodecUnsupported('RAW is read-only');
}

/// QOI, TGA, PNM, PSD and DDS in plain Dart (IMG-001); always available.
final class SmallFormatsPixelCodec implements PixelCodec {
  const SmallFormatsPixelCodec();

  static const Set<ImageFormat> formats = {
    ImageFormat.qoi,
    ImageFormat.tga,
    ImageFormat.pnm,
    ImageFormat.psd,
    ImageFormat.dds,
  };

  @override
  String get name => 'small';

  @override
  bool canRead(ImageFormat format) => formats.contains(format);

  @override
  bool canWrite(EncodeFormat format) => false;

  PixelFrame _decode(ImageInput input, ImageFormat format) {
    final b = _bytes(input);
    return switch (format) {
      ImageFormat.qoi => decodeQoi(b),
      ImageFormat.tga => decodeTga(b),
      ImageFormat.pnm => decodePnm(b),
      ImageFormat.psd => decodePsd(b),
      ImageFormat.dds => decodeDds(b),
      _ => throw CodecUnsupported('small decoders do not read $format'),
    };
  }

  @override
  PixelHeader header(ImageInput input, ImageFormat format) {
    final f = _decode(input, format);
    return PixelHeader(width: f.width, height: f.height);
  }

  @override
  PixelFrame thumbnail(ImageInput input, int edge, ImageFormat format) {
    final f = _decode(input, format);
    final t = downscaleToEdge(f, edge);
    return PixelFrame(
      width: t.width,
      height: t.height,
      rgba: t.rgba,
      sourceWidth: f.width,
      sourceHeight: f.height,
    );
  }

  @override
  PixelFrame decode(
    ImageInput input,
    ImageFormat format, {
    ImageRegion? region,
    double scale = 1,
    int frame = 0,
  }) => regionAndScale(_decode(input, format), region, scale);

  @override
  Uint8List encode(PixelFrame image, EncodeFormat format, int quality) =>
      throw const CodecUnsupported('these formats are read-only');
}
