import 'dart:typed_data';
import 'dart:ui' show Rect;

import 'package:mediahro/images/image_format.dart';
import 'package:mediahro/images/image_pipeline.dart';
import 'package:mediahro/images/pipeline/image_io.dart';
import 'package:mediahro/images/pipeline/image_worker.dart';
import 'package:mediahro/images/pipeline/pixel_codec.dart';
import 'package:mediahro/images/pipeline/pixel_ops.dart';
import 'package:mediahro/images/pipeline/ui_fallback.dart';
import 'package:mediahro/images/pipeline/worker_pool.dart';
import 'package:mediahro/platform/imaging.dart';
import 'package:mediahro_ffi/mediahro_ffi.dart';

import 'fixtures.dart';

/// A tiny image format for pipeline tests: `[w, h, ...rgba]` with w, h < 256.
Uint8List fakeImage(int w, int h, {int seed = 0}) {
  final b = Uint8List(2 + w * h * 4)
    ..[0] = w
    ..[1] = h;
  for (var i = 0; i < w * h; i++) {
    b[2 + i * 4] = (i + seed) & 0xFF;
    b[3 + i * 4] = 100;
    b[4 + i * 4] = 50;
    b[5 + i * 4] = 255;
  }
  return b;
}

/// Reads [fakeImage] bytes. JPEG-looking input (a RAW preview) yields a
/// frame whose width is the input length mod 200, so tests can tell which
/// bytes the pipeline handed over.
final class FakeCodec implements PixelCodec {
  @override
  String get name => 'fake';

  @override
  bool canRead(ImageFormat format) => true;

  @override
  bool canWrite(EncodeFormat format) =>
      format == EncodeFormat.jpeg ||
      format == EncodeFormat.png ||
      format == EncodeFormat.webp ||
      format == EncodeFormat.jxl;

  Uint8List _bytes(ImageInput input) => switch (input) {
    BytesInput(:final bytes) => bytes,
    FileInput() => throw const CodecUnsupported('fake codec reads buffers'),
  };

  PixelFrame _frame(Uint8List b, ImageFormat format) {
    if (format == ImageFormat.raw) {
      // A whole RAW file: "developed" to a tiny frame.
      return PixelFrame(width: 3, height: 2, rgba: Uint8List(24));
    }
    if (b.length > 2 && b[0] == 0xFF && b[1] == 0xD8) {
      final w = b.length % 200 + 1;
      return PixelFrame(width: w, height: 1, rgba: Uint8List(w * 4));
    }
    final w = b[0];
    final h = b[1];
    return PixelFrame(
      width: w,
      height: h,
      rgba: Uint8List.sublistView(b, 2, 2 + w * h * 4),
    );
  }

  @override
  PixelHeader header(ImageInput input, ImageFormat format) {
    final f = _frame(_bytes(input), format);
    return PixelHeader(width: f.width, height: f.height);
  }

  @override
  PixelFrame thumbnail(ImageInput input, int edge, ImageFormat format) {
    final f = _frame(_bytes(input), format);
    return PixelFrame(
      width: f.width,
      height: f.height,
      rgba: f.rgba,
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
  }) {
    final f = _frame(_bytes(input), format);
    return region == null ? f : cropFrame(f, region, 1);
  }

  @override
  Uint8List encode(PixelFrame image, EncodeFormat format, int quality) =>
      switch (format) {
        EncodeFormat.jpeg => sampleJpeg(),
        _ => Uint8List.fromList([
          0xEE,
          image.width,
          image.height,
          ...image.rgba,
        ]),
      };
}

/// Worker factory using [FakeCodec]; top level so it crosses isolates.
WorkerHandler fakeWorker() =>
    imageJobHandler(CompositePixelCodec([FakeCodec()]));

/// A worker with no codecs: every pixel job is "unsupported".
WorkerHandler emptyWorker() => imageJobHandler(CompositePixelCodec([]));

final class MemoryFile implements VirtualFile {
  MemoryFile(this.uri, this.data);

  @override
  final Uri uri;
  Uint8List data;
  int reads = 0;

  @override
  Future<int?> length() async => data.length;

  @override
  Future<Uint8List> read(int offset, int length) async {
    reads++;
    final end = (offset + length).clamp(0, data.length);
    return Uint8List.sublistView(data, offset.clamp(0, data.length), end);
  }

  @override
  bool get isSeekable => true;

  @override
  Future<void> close() async {}
}

/// In-memory [ImageIo]; `file:` URIs report no local path so the pipeline
/// reads buffers.
final class MemoryIo implements ImageIo {
  final Map<Uri, Uint8List> files = {};
  final List<Uri> writes = [];

  MemoryFile add(String path, Uint8List data) {
    final uri = Uri.parse('smb://nas/photos/$path');
    files[uri] = data;
    return MemoryFile(uri, data);
  }

  @override
  String? localPath(Uri uri) => null;

  @override
  Future<VirtualFile> open(Uri uri) async {
    final d = files[uri];
    if (d == null) throw VirtualFileException(VirtualFileError.notFound, uri);
    return MemoryFile(uri, d);
  }

  @override
  Future<void> replace(Uri uri, Uint8List bytes) async {
    files[uri] = bytes;
    writes.add(uri);
  }

  @override
  Future<void> create(Uri uri, Uint8List bytes) async {
    if (files.containsKey(uri)) {
      throw VirtualFileException(VirtualFileError.alreadyExists, uri);
    }
    await replace(uri, bytes);
  }

  @override
  Future<bool> exists(Uri uri) async => files.containsKey(uri);

  @override
  Future<void> delete(Uri uri) async {
    files.remove(uri);
  }
}

/// Fallback standing in for dart:ui in plain unit tests.
final class FakeUiFallback implements UiImageFallback {
  int decodes = 0;

  @override
  Future<(int, int)> size(Uint8List bytes) async => (bytes[0], bytes[1]);

  @override
  Future<PixelFrame> decode(Uint8List bytes, {int? maxEdge}) async {
    decodes++;
    return PixelFrame(
      width: bytes[0],
      height: bytes[1],
      rgba: Uint8List.sublistView(bytes, 2, 2 + bytes[0] * bytes[1] * 4),
    );
  }

  @override
  Future<Uint8List> encodePng(PixelFrame frame) async =>
      Uint8List.fromList([0x89, 0x50, frame.width, frame.height]);
}

/// An [ImagingFacade] with only the calls the pipeline makes.
final class FakeImaging implements ImagingFacade {
  FakeImaging({
    this.thumb,
    this.supported = const ImagingSupport(),
    this.decoded,
  });

  PlatformImage? thumb;
  ImagingSupport supported;
  PlatformImage? decoded;
  int thumbCalls = 0;
  int decodeCalls = 0;

  @override
  Future<ImagingSupport> support() async => supported;

  @override
  Future<PlatformImage?> thumbnail(Uri uri, int size) async {
    thumbCalls++;
    return thumb;
  }

  @override
  Future<PlatformImage> decode(
    Uri uri, {
    int? maxEdge,
    Rect? region,
    int frame = 0,
    bool keepHdr = false,
  }) async {
    decodeCalls++;
    return decoded!;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
