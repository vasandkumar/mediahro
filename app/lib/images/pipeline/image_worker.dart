import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:mediahro/images/image_format.dart';
import 'package:mediahro/images/image_pipeline.dart';
import 'package:mediahro/images/metadata/metadata_codec.dart';
import 'package:mediahro/images/pipeline/native_pixel_codecs.dart';
import 'package:mediahro/images/pipeline/pixel_codec.dart';
import 'package:mediahro/images/pipeline/vips_pixel_codec.dart';
import 'package:mediahro/images/pipeline/worker_pool.dart';
import 'package:mediahro_ffi/mediahro_ffi.dart'
    show AvifException, NativeLibraryUnavailable;

/// No codec on this device can do the job (library missing, format not
/// covered); the pipeline falls back to the OS decoders.
final class ImageBackendUnavailable implements Exception {
  const ImageBackendUnavailable(this.message);

  final String message;

  @override
  String toString() => 'ImageBackendUnavailable: $message';
}

// ---------------------------------------------------------------------------
// Wire types: everything below crosses the isolate boundary.
// ---------------------------------------------------------------------------

final class WireInput {
  WireInput.bytes(Uint8List bytes)
    : data = TransferableTypedData.fromList([bytes]),
      path = null;

  const WireInput.file(String this.path) : data = null;

  final TransferableTypedData? data;
  final String? path;

  ImageInput open() => path != null
      ? ImageInput.file(path!)
      : ImageInput.bytes(data!.materialize().asUint8List());
}

sealed class ImageJob {
  const ImageJob();
}

final class HeaderJob extends ImageJob {
  const HeaderJob(this.input, this.format);

  final WireInput input;
  final ImageFormat format;
}

final class ThumbJob extends ImageJob {
  const ThumbJob(this.input, this.format, this.edge, this.encode, this.quality);

  final WireInput input;
  final ImageFormat format;
  final int edge;
  final EncodeFormat encode;
  final int quality;
}

final class DecodeJob extends ImageJob {
  const DecodeJob(this.input, this.format, this.region, this.scale, this.frame);

  final WireInput input;
  final ImageFormat format;
  final ImageRegion? region;
  final double scale;
  final int frame;
}

final class EncodeJob extends ImageJob {
  EncodeJob(this.width, this.height, Uint8List rgba, this.format, this.quality)
    : pixels = TransferableTypedData.fromList([rgba]);

  final int width;
  final int height;
  final TransferableTypedData pixels;
  final EncodeFormat format;
  final int quality;
}

final class MetadataJob extends ImageJob {
  MetadataJob(Uint8List bytes, this.extension)
    : bytes = TransferableTypedData.fromList([bytes]);

  final TransferableTypedData bytes;
  final String? extension;
}

final class WriteMetadataJob extends ImageJob {
  WriteMetadataJob(
    Uint8List bytes,
    this.edit,
    this.extension,
    this.existingSidecar,
  ) : bytes = TransferableTypedData.fromList([bytes]);

  final TransferableTypedData bytes;
  final ImageMetadataEdit edit;
  final String? extension;
  final String? existingSidecar;
}

final class StripJob extends ImageJob {
  StripJob(Uint8List bytes, this.extension)
    : bytes = TransferableTypedData.fromList([bytes]);

  final TransferableTypedData bytes;
  final String? extension;
}

sealed class ImageReply {
  const ImageReply();
}

final class HeaderReply extends ImageReply {
  const HeaderReply(this.header);

  final PixelHeader header;
}

final class FrameReply extends ImageReply {
  FrameReply(PixelFrame f)
    : width = f.width,
      height = f.height,
      sourceWidth = f.sourceWidth,
      sourceHeight = f.sourceHeight,
      rgba = TransferableTypedData.fromList([f.rgba]);

  final int width;
  final int height;
  final int sourceWidth;
  final int sourceHeight;
  final TransferableTypedData rgba;

  PixelFrame take() => PixelFrame(
    width: width,
    height: height,
    rgba: rgba.materialize().asUint8List(),
    sourceWidth: sourceWidth,
    sourceHeight: sourceHeight,
  );
}

final class EncodedReply extends ImageReply {
  EncodedReply(
    Uint8List bytes,
    this.width,
    this.height,
    this.sourceWidth,
    this.sourceHeight,
  ) : bytes = TransferableTypedData.fromList([bytes]);

  final TransferableTypedData bytes;
  final int width;
  final int height;
  final int sourceWidth;
  final int sourceHeight;
}

final class BytesReply extends ImageReply {
  BytesReply(Uint8List? bytes)
    : bytes = bytes == null ? null : TransferableTypedData.fromList([bytes]);

  final TransferableTypedData? bytes;
}

final class MetadataReply extends ImageReply {
  const MetadataReply(this.parsed);

  final ParsedMetadata parsed;
}

final class WriteMetadataReply extends ImageReply {
  const WriteMetadataReply(this.result);

  final MetadataWriteResult result;
}

final class UnsupportedReply extends ImageReply {
  const UnsupportedReply(this.message);

  final String message;
}

// ---------------------------------------------------------------------------
// Worker side
// ---------------------------------------------------------------------------

/// Handles [ImageJob]s with [codec]. Runs inside a worker isolate.
FutureOr<Object?> Function(Object?) imageJobHandler(PixelCodec codec) =>
    (request) {
      final job = request! as ImageJob;
      try {
        return _handle(codec, job);
        // NativeLibraryUnavailable and CodecUnsupported both mean "try
        // something else", not "crash the worker".
      } on NativeLibraryUnavailable catch (e) {
        return UnsupportedReply('${e.library.baseName} is not available');
      } on CodecUnsupported catch (e) {
        return UnsupportedReply(e.message);
      }
    };

ImageReply _handle(PixelCodec codec, ImageJob job) => switch (job) {
  HeaderJob() => HeaderReply(codec.header(job.input.open(), job.format)),
  ThumbJob() => _thumb(codec, job),
  DecodeJob() => FrameReply(
    codec.decode(
      job.input.open(),
      job.format,
      region: job.region,
      scale: job.scale,
      frame: job.frame,
    ),
  ),
  EncodeJob() => BytesReply(
    codec.encode(
      PixelFrame(
        width: job.width,
        height: job.height,
        rgba: job.pixels.materialize().asUint8List(),
      ),
      job.format,
      job.quality,
    ),
  ),
  MetadataJob() => MetadataReply(
    parseMetadata(
      job.bytes.materialize().asUint8List(),
      extension: job.extension,
    ),
  ),
  WriteMetadataJob() => WriteMetadataReply(
    writeMetadata(
      job.bytes.materialize().asUint8List(),
      job.edit,
      extension: job.extension,
      existingSidecar: job.existingSidecar,
    ),
  ),
  StripJob() => BytesReply(
    stripMetadata(
      job.bytes.materialize().asUint8List(),
      extension: job.extension,
    ),
  ),
};

ImageReply _thumb(PixelCodec codec, ThumbJob job) {
  final frame = codec.thumbnail(job.input.open(), job.edge, job.format);
  return EncodedReply(
    codec.encode(frame, job.encode, job.quality),
    frame.width,
    frame.height,
    frame.sourceWidth,
    frame.sourceHeight,
  );
}

/// The worker factory the app uses: libvips when it loads. Top-level so the
/// pool can hand it to a new isolate.
WorkerHandler defaultImageWorker() {
  final codecs = <PixelCodec>[];
  PixelCodec? vips;
  // Each library is optional: a missing one leaves its formats to the next
  // backend, and metadata jobs still work.
  try {
    vips = VipsPixelCodec();
    codecs.add(vips);
  } on NativeLibraryUnavailable {
    // libvips missing.
  }
  try {
    codecs.add(JxlPixelCodec());
  } on NativeLibraryUnavailable {
    // libjxl missing.
  }
  try {
    codecs.add(AvifPixelCodec());
  } on NativeLibraryUnavailable {
    // libavif missing.
  } on AvifException {
    // An unsupported libavif major version.
  }
  try {
    codecs.add(RawPixelCodec(jpeg: vips));
  } on NativeLibraryUnavailable {
    // LibRaw missing.
  }
  codecs.add(const SmallFormatsPixelCodec());
  return imageJobHandler(CompositePixelCodec(codecs));
}

// ---------------------------------------------------------------------------
// Client side
// ---------------------------------------------------------------------------

/// Typed access to the image worker pool.
final class ImageWorkerClient {
  ImageWorkerClient(this.pool);

  factory ImageWorkerClient.create({int? size}) => ImageWorkerClient(
    IsolateWorkerPool(size: size ?? 2, factory: defaultImageWorker),
  );

  final IsolateWorkerPool pool;

  Future<T> _run<T extends ImageReply>(
    ImageJob job, {
    int priority = 0,
    Object? group,
    void Function(JobHandle)? onQueued,
  }) async {
    final reply = await pool.submit<ImageReply>(
      job,
      priority: priority,
      group: group,
      onQueued: onQueued,
    );
    if (reply is UnsupportedReply) {
      throw ImageBackendUnavailable(reply.message);
    }
    return reply as T;
  }

  Future<PixelHeader> header(
    WireInput input,
    ImageFormat format, {
    int priority = 1,
  }) async => (await _run<HeaderReply>(
    HeaderJob(input, format),
    priority: priority,
  )).header;

  /// A thumbnail already encoded as [encode]; the caller stores it.
  Future<
    ({
      Uint8List bytes,
      int width,
      int height,
      int sourceWidth,
      int sourceHeight,
    })
  >
  thumbnail(
    WireInput input,
    ImageFormat format,
    int edge, {
    EncodeFormat encode = EncodeFormat.webp,
    int quality = 80,
    int priority = 0,
    Object? group,
    void Function(JobHandle)? onQueued,
  }) async {
    final r = await _run<EncodedReply>(
      ThumbJob(input, format, edge, encode, quality),
      priority: priority,
      group: group,
      onQueued: onQueued,
    );
    return (
      bytes: r.bytes.materialize().asUint8List(),
      width: r.width,
      height: r.height,
      sourceWidth: r.sourceWidth,
      sourceHeight: r.sourceHeight,
    );
  }

  Future<PixelFrame> decode(
    WireInput input,
    ImageFormat format, {
    ImageRegion? region,
    double scale = 1,
    int frame = 0,
    int priority = 3,
    Object? group,
  }) async => (await _run<FrameReply>(
    DecodeJob(input, format, region, scale, frame),
    priority: priority,
    group: group,
  )).take();

  Future<Uint8List> encode(
    PixelFrame image,
    EncodeFormat format, {
    int quality = 90,
    int priority = 1,
  }) async {
    final r = await _run<BytesReply>(
      EncodeJob(image.width, image.height, image.rgba, format, quality),
      priority: priority,
    );
    return r.bytes!.materialize().asUint8List();
  }

  Future<ParsedMetadata> metadata(
    Uint8List bytes, {
    String? extension,
    int priority = 3,
  }) async => (await _run<MetadataReply>(
    MetadataJob(bytes, extension),
    priority: priority,
  )).parsed;

  Future<MetadataWriteResult> writeMetadata(
    Uint8List bytes,
    ImageMetadataEdit edit, {
    String? extension,
    String? existingSidecar,
  }) async => (await _run<WriteMetadataReply>(
    WriteMetadataJob(bytes, edit, extension, existingSidecar),
    priority: 3,
  )).result;

  Future<Uint8List?> strip(Uint8List bytes, {String? extension}) async {
    final r = await _run<BytesReply>(StripJob(bytes, extension), priority: 3);
    return r.bytes?.materialize().asUint8List();
  }

  Future<void> dispose() => pool.dispose();
}
