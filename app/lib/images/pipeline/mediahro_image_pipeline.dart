import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show Rect;

import 'package:mediahro/images/image_format.dart';
import 'package:mediahro/images/image_pipeline.dart';
import 'package:mediahro/images/metadata/metadata_codec.dart';
import 'package:mediahro/images/pipeline/image_io.dart';
import 'package:mediahro/images/pipeline/image_worker.dart';
import 'package:mediahro/images/pipeline/pixel_codec.dart';
import 'package:mediahro/images/pipeline/thumbnail_cache.dart';
import 'package:mediahro/images/pipeline/ui_fallback.dart';
import 'package:mediahro/images/pipeline/worker_pool.dart';
import 'package:mediahro/images/raw_preview.dart';
import 'package:mediahro/platform/imaging.dart';
import 'package:mediahro/platform/platform_facades.dart'
    show PlatformCapabilityUnavailable;
import 'package:mediahro_ffi/mediahro_ffi.dart';

/// Where a metadata write ended up.
final class MetadataWriteOutcome {
  const MetadataWriteOutcome.file() : sidecar = null;
  const MetadataWriteOutcome.sidecar(Uri this.sidecar);

  /// The XMP sidecar written next to a RAW (or any file the container
  /// cannot carry the change in); null when the file itself was rewritten.
  final Uri? sidecar;
}

/// The image engine (docs/05 §5): OS decoders first (through
/// `ImagingFacade`), then libvips in the isolate pool, then Flutter's own
/// codecs. All pixel and metadata work runs off the UI isolate.
final class MediahroImagePipeline implements ImagePipeline {
  MediahroImagePipeline({
    required this.worker,
    required this.cache,
    required this.io,
    this.imaging,
    this.fallback = const DartUiFallback(),
    this.maxBufferBytes = 192 << 20,
  });

  final ImageWorkerClient worker;
  final ThumbnailCache cache;
  final ImageIo io;
  final ImagingFacade? imaging;
  final UiImageFallback fallback;

  /// Largest file read into memory for a decode that cannot stream from disk
  /// (remote sources, content URIs).
  final int maxBufferBytes;

  /// Head read for sniffing and metadata directories.
  static const int _head = 4 << 20;

  final Map<String, Future<File>> _inflight = {};
  Future<ImagingSupport>? _support;

  Future<ImagingSupport> _imagingSupport() => _support ??= () async {
    final im = imaging;
    if (im == null) return const ImagingSupport();
    try {
      return await im.support();
    } on PlatformCapabilityUnavailable {
      return const ImagingSupport();
    } on Exception {
      return const ImagingSupport();
    }
  }();

  // ---- reading -------------------------------------------------------

  static String? extensionOf(Uri uri) {
    final name = uri.pathSegments.isEmpty ? '' : uri.pathSegments.last;
    final dot = name.lastIndexOf('.');
    return dot < 0 ? null : name.substring(dot + 1).toLowerCase();
  }

  Future<Uint8List> _range(VirtualFile f, int offset, int length) async {
    final b = BytesBuilder(copy: false);
    var at = offset;
    final end = offset + length;
    while (at < end) {
      final chunk = await f.read(at, math.min(4 << 20, end - at));
      if (chunk.isEmpty) break;
      b.add(chunk);
      at += chunk.length;
    }
    return b.takeBytes();
  }

  Future<int> _length(ImageSource src) async {
    final n = await src.file.length();
    if (n == null) {
      throw VirtualFileException(
        VirtualFileError.unsupported,
        src.uri,
        'unknown length',
      );
    }
    return n;
  }

  Future<Uint8List> _readAll(ImageSource src, {int? max}) async {
    final n = await _length(src);
    if (n > (max ?? maxBufferBytes)) {
      throw ImageBackendUnavailable('file too large to buffer ($n bytes)');
    }
    return await _range(src.file, 0, n);
  }

  /// Format from the first bytes and the file extension.
  Future<ImageFormat> formatOf(ImageSource src) async {
    final n = await _length(src);
    final head = await _range(src.file, 0, math.min(n, 1024));
    return sniffImageFormat(head, extension: extensionOf(src.uri));
  }

  // ---- thumbnails ----------------------------------------------------

  /// The cached thumbnail file for [src] at [edge] px, generating it on the
  /// worker pool at [priority]. The file is WebP (PNG when only Flutter's
  /// codecs could read the image). Safe to call for many items at once;
  /// concurrent calls for the same rendition share one job.
  Future<File> thumbnailFile(
    ImageSource src,
    int edge, {
    ThumbnailPriority priority = ThumbnailPriority.visible,
    Object? group,
    void Function(JobHandle)? onQueued,
  }) async {
    final length = await _length(src);
    final key = ThumbnailCache.keyFor(
      uri: src.uri,
      edge: edge,
      mtime: src.mtime,
      size: length,
      orientation: src.orientationHint ?? 1,
    );
    final hit = await cache.lookup(key);
    if (hit != null) return hit;
    return await (_inflight[key] ??=
        _generate(
          src,
          key,
          edge,
          length,
          priority,
          group,
          onQueued,
        ).whenComplete(() {
          // A block body: returning remove()'s value would make this future
          // wait on itself.
          unawaited(_inflight.remove(key));
        }));
  }

  Future<File> _generate(
    ImageSource src,
    String key,
    int edge,
    int length,
    ThumbnailPriority priority,
    Object? group,
    void Function(JobHandle)? onQueued,
  ) async {
    final head = await _range(src.file, 0, math.min(length, 1024));
    final ext = extensionOf(src.uri);
    final format = sniffImageFormat(head, extension: ext);

    // 1. The OS thumbnail cache / decoder.
    final os = await _osThumbnail(src.uri, edge);
    if (os != null) {
      try {
        final webp = await worker.encode(
          os,
          EncodeFormat.webp,
          quality: 80,
          priority: priority.index,
        );
        return await cache.store(key, webp);
      } on ImageBackendUnavailable {
        return await cache.store(key, await fallback.encodePng(os), ext: 'png');
      }
    }

    // 2. libvips on the worker pool.
    try {
      final (input, workerFormat) = await _workerInput(
        src,
        format,
        length,
        edge,
      );
      final t = await worker.thumbnail(
        input,
        workerFormat,
        edge,
        priority: priority.index,
        group: group,
        onQueued: onQueued,
      );
      return await cache.store(key, t.bytes);
    } on ImageBackendUnavailable {
      // A RAW is never handed to Flutter's codecs (no preview, no image).
      if (format == ImageFormat.raw) rethrow;
    }

    // 3. Flutter's codecs, one image at a time.
    final bytes = await _readAll(src);
    final frame = await fallback.decode(bytes, maxEdge: edge);
    return await cache.store(key, await fallback.encodePng(frame), ext: 'png');
  }

  Future<PixelFrame?> _osThumbnail(Uri uri, int edge) async {
    final im = imaging;
    if (im == null) return null;
    try {
      final p = await im.thumbnail(uri, edge);
      if (p == null || p.f16) return null;
      return PixelFrame(width: p.width, height: p.height, rgba: p.pixels);
    } on PlatformCapabilityUnavailable {
      return null;
    } on Exception {
      return null;
    }
  }

  /// What to hand the worker for [src]: a local path to stream, the bytes
  /// of a RAW's embedded preview, or the whole file in memory.
  Future<(WireInput, ImageFormat)> _workerInput(
    ImageSource src,
    ImageFormat format,
    int length,
    int edge, {
    bool largestPreview = false,
  }) async {
    if (format == ImageFormat.raw) {
      final head = await _range(src.file, 0, math.min(length, _head));
      final previews = findRawPreviews(head, length);
      final p = largestPreview
          ? (previews.isEmpty ? null : previews.last)
          : previewForThumbnail(previews, edge);
      if (p == null) {
        throw const ImageBackendUnavailable('RAW without an embedded preview');
      }
      final jpeg = await _range(src.file, p.offset, p.length);
      return (WireInput.bytes(jpeg), ImageFormat.jpeg);
    }
    final path = io.localPath(src.uri);
    if (path != null) return (WireInput.file(path), format);
    return (WireInput.bytes(await _readAll(src)), format);
  }

  /// Cancels the queued jobs of [group] (a tile that scrolled away).
  void cancelGroup(Object group) =>
      worker.pool.cancelWhere((h) => h.group == group);

  /// Moves the queued jobs of [group] to [priority].
  void reprioritise(Object group, ThumbnailPriority priority) =>
      worker.pool.reprioritise(group, priority.index);

  // ---- ImagePipeline -------------------------------------------------

  @override
  Future<DecodedImage> thumbnail(
    ImageSource src,
    int size, {
    ThumbnailPriority priority = ThumbnailPriority.visible,
  }) async {
    final file = await thumbnailFile(src, size, priority: priority);
    final bytes = await file.readAsBytes();
    try {
      return toDecoded(
        await worker.decode(
          WireInput.bytes(bytes),
          file.path.endsWith('.png') ? ImageFormat.png : ImageFormat.webp,
          priority: priority.index,
        ),
      );
    } on ImageBackendUnavailable {
      return toDecoded(await fallback.decode(bytes));
    }
  }

  @override
  Future<DecodedImage> decode(
    ImageSource src, {
    ImageRegion? region,
    double scale = 1,
    int frame = 0,
  }) async {
    final length = await _length(src);
    final format = await formatOf(src);
    final support = await _imagingSupport();

    // 1. OS decoders for what they list (HEIC, AVIF, JXL where present).
    if (support.decodable.contains(format.shortName) && frame == 0) {
      final os = await _osDecode(src, region, scale);
      if (os != null) return toDecoded(os);
    }

    // 2. libvips.
    try {
      final (input, wf) = await _workerInput(
        src,
        format,
        length,
        2048,
        largestPreview: true,
      );
      return toDecoded(
        await worker.decode(
          input,
          wf,
          region: region,
          scale: scale,
          frame: frame,
        ),
      );
    } on ImageBackendUnavailable {
      // Fall through.
    }

    // 3. Flutter's codecs.
    final bytes = await _readAll(src);
    final (w, h) = await fallback.size(bytes);
    final maxEdge = scale >= 1 ? null : (math.max(w, h) * scale).round();
    var f = await fallback.decode(bytes, maxEdge: maxEdge);
    if (region != null) f = cropFrame(f, region, f.width / w);
    return toDecoded(f);
  }

  Future<PixelFrame?> _osDecode(
    ImageSource src,
    ImageRegion? region,
    double scale,
  ) async {
    final im = imaging;
    if (im == null) return null;
    try {
      final info = await this.info(src);
      final maxEdge = scale >= 1
          ? null
          : (math.max(info.width, info.height) * scale).round();
      final p = await im.decode(
        src.uri,
        maxEdge: maxEdge,
        region: region == null
            ? null
            : Rect.fromLTWH(
                region.left.toDouble(),
                region.top.toDouble(),
                region.width.toDouble(),
                region.height.toDouble(),
              ),
      );
      if (p.f16) return null;
      return PixelFrame(width: p.width, height: p.height, rgba: p.pixels);
    } on PlatformCapabilityUnavailable {
      return null;
    } on Exception {
      return null;
    }
  }

  @override
  Future<ImageInfo> info(ImageSource src) async {
    final length = await _length(src);
    final head = await _range(src.file, 0, math.min(length, _head));
    final ext = extensionOf(src.uri);
    final parsed = parseMetadata(head, extension: ext);
    final format = parsed.blocks.format;
    var w = parsed.blocks.width;
    var h = parsed.blocks.height;
    var frames = 1;
    var pages = 1;
    if (w == 0 ||
        h == 0 ||
        format == ImageFormat.gif ||
        format == ImageFormat.tiff) {
      try {
        final (input, wf) = await _workerInput(src, format, length, 256);
        final ph = await worker.header(input, wf);
        w = ph.width;
        h = ph.height;
        if (format == ImageFormat.tiff) {
          pages = ph.frames;
        } else {
          frames = ph.frames;
        }
      } on ImageBackendUnavailable {
        if (w == 0 || h == 0) {
          final (fw, fh) = await fallback.size(await _readAll(src));
          w = fw;
          h = fh;
        }
      }
    } else if (parsed.blocks.animated) {
      frames = 2;
    }
    if (parsed.orientation >= 5) {
      final t = w;
      w = h;
      h = t;
    }
    return ImageInfo(
      width: w,
      height: h,
      format: format == ImageFormat.raw ? (ext ?? 'raw') : format.shortName,
      frames: frames,
      pages: pages,
      range: parsed.hasGainMap
          ? ImageDynamicRange.hdrGainMap
          : ImageDynamicRange.sdr,
      isLivePhoto: parsed.livePhotoId != null,
      isMotionPhoto: parsed.motionVideoLength != null,
      isPanorama: parsed.isPanorama,
    );
  }

  Future<Uint8List> _forMetadata(ImageSource src) async {
    final length = await _length(src);
    return await _range(src.file, 0, math.min(length, 64 << 20));
  }

  @override
  Future<ImageMetadata> metadata(ImageSource src) async {
    final bytes = await _forMetadata(src);
    return (await worker.metadata(
      bytes,
      extension: extensionOf(src.uri),
    )).metadata;
  }

  /// The parsed metadata with orientation and the flags the viewer needs.
  Future<ParsedMetadata> parsedMetadata(ImageSource src) async {
    final bytes = await _forMetadata(src);
    return await worker.metadata(bytes, extension: extensionOf(src.uri));
  }

  /// Sidecar location for [uri]: the same name with `.xmp` (Lightroom and
  /// darktable read `IMG_1.xmp`; darktable also `IMG_1.CR2.xmp`).
  static Uri sidecarUri(Uri uri) {
    final segs = [...uri.pathSegments];
    final name = segs.removeLast();
    final dot = name.lastIndexOf('.');
    segs.add('${dot < 0 ? name : name.substring(0, dot)}.xmp');
    return uri.replace(pathSegments: segs);
  }

  @override
  Future<void> writeMetadata(ImageSource src, ImageMetadataEdit edit) async {
    await applyMetadataEdit(src, edit);
  }

  /// Like [writeMetadata] but says where the edit went.
  Future<MetadataWriteOutcome> applyMetadataEdit(
    ImageSource src,
    ImageMetadataEdit edit,
  ) async {
    final length = await _length(src);
    final sidecar = sidecarUri(src.uri);
    final existing = await _readText(sidecar);
    // Beyond 256 MiB the file is never rewritten in memory: sidecar only.
    final bytes = length > 256 << 20
        ? Uint8List(0)
        : await _range(src.file, 0, length);
    final result = await worker.writeMetadata(
      bytes,
      edit,
      extension: extensionOf(src.uri),
      existingSidecar: existing,
    );
    final file = result.file;
    if (file != null) {
      await io.replace(src.uri, file);
      return const MetadataWriteOutcome.file();
    }
    await io.replace(sidecar, Uint8List.fromList(utf8.encode(result.sidecar!)));
    return MetadataWriteOutcome.sidecar(sidecar);
  }

  Future<String?> _readText(Uri uri) async {
    try {
      if (!await io.exists(uri)) return null;
      final f = await io.open(uri);
      try {
        final n = await f.length() ?? 0;
        if (n > 4 << 20) return null;
        return utf8.decode(await _range(f, 0, n), allowMalformed: true);
      } finally {
        await f.close();
      }
    } on VirtualFileException {
      return null;
    }
  }

  @override
  Future<Uint8List> encode(DecodedImage image, EncodeOptions options) async {
    var frame = PixelFrame(
      width: image.width,
      height: image.height,
      rgba: image.pixels,
    );
    final edge = options.maxEdge;
    if (edge != null) frame = downscaleToEdge(frame, edge);
    switch (options.format) {
      case EncodeFormat.jpeg || EncodeFormat.png || EncodeFormat.webp:
        try {
          return await worker.encode(
            frame,
            options.format,
            quality: options.quality,
          );
        } on ImageBackendUnavailable catch (e) {
          if (options.format == EncodeFormat.png) {
            return await fallback.encodePng(frame);
          }
          throw UnsupportedError(e.message);
        }
      case EncodeFormat.heic || EncodeFormat.avif:
        final im = imaging;
        final name = options.format.name;
        final support = await _imagingSupport();
        if (im == null || !support.encodable.contains(name)) {
          throw UnsupportedError(
            'This device cannot encode ${name.toUpperCase()}.',
          );
        }
        return await im.encode(
          PlatformImage(
            width: frame.width,
            height: frame.height,
            pixels: frame.rgba,
          ),
          name,
          quality: options.quality,
        );
      case EncodeFormat.jxl:
        throw UnsupportedError('JPEG XL encoding is not available yet.');
    }
  }

  @override
  Future<void> export(
    ImageSource src,
    List<EditOp> ops,
    Uri destination,
    EncodeOptions options,
  ) async {
    if (ops.isNotEmpty) {
      throw UnsupportedError('Edit operations are applied by the editor.');
    }
    final decoded = await decode(src);
    var out = await encode(decoded, options);
    if (!options.stripMetadata) {
      final meta = await _forMetadata(src);
      final parsed = parseMetadata(meta, extension: extensionOf(src.uri));
      out = transplantMetadata(
        out,
        parsed.blocks,
        outputExtension: options.format.name,
      );
    }
    await io.replace(destination, out);
  }

  @override
  void cancelBelow(ThumbnailPriority priority) =>
      worker.pool.cancelBelow(priority.index);

  Future<void> dispose() async {
    await worker.dispose();
    await cache.dispose();
  }
}

/// Crops [f] to [region] given in source pixels and [scale] (frame size over
/// source size).
PixelFrame cropFrame(PixelFrame f, ImageRegion region, double scale) {
  final left = (region.left * scale).round().clamp(0, f.width - 1);
  final top = (region.top * scale).round().clamp(0, f.height - 1);
  final w = (region.width * scale).round().clamp(1, f.width - left);
  final h = (region.height * scale).round().clamp(1, f.height - top);
  final out = Uint8List(w * h * 4);
  for (var y = 0; y < h; y++) {
    final from = ((top + y) * f.width + left) * 4;
    out.setRange(y * w * 4, (y + 1) * w * 4, f.rgba, from);
  }
  return PixelFrame(
    width: w,
    height: h,
    rgba: out,
    sourceWidth: f.sourceWidth,
    sourceHeight: f.sourceHeight,
  );
}

/// Box-filter downscale so the longest edge is at most [edge].
PixelFrame downscaleToEdge(PixelFrame f, int edge) {
  final longest = math.max(f.width, f.height);
  if (longest <= edge) return f;
  final s = edge / longest;
  final w = math.max(1, (f.width * s).round());
  final h = math.max(1, (f.height * s).round());
  final out = Uint8List(w * h * 4);
  for (var y = 0; y < h; y++) {
    final y0 = (y * f.height) ~/ h;
    final y1 = math.max(y0 + 1, ((y + 1) * f.height) ~/ h);
    for (var x = 0; x < w; x++) {
      final x0 = (x * f.width) ~/ w;
      final x1 = math.max(x0 + 1, ((x + 1) * f.width) ~/ w);
      var r = 0;
      var g = 0;
      var b = 0;
      var a = 0;
      var n = 0;
      for (var yy = y0; yy < y1; yy++) {
        for (var xx = x0; xx < x1; xx++) {
          final i = (yy * f.width + xx) * 4;
          final al = f.rgba[i + 3];
          r += f.rgba[i] * al;
          g += f.rgba[i + 1] * al;
          b += f.rgba[i + 2] * al;
          a += al;
          n++;
        }
      }
      final o = (y * w + x) * 4;
      if (a > 0) {
        out[o] = r ~/ a;
        out[o + 1] = g ~/ a;
        out[o + 2] = b ~/ a;
      }
      out[o + 3] = a ~/ n;
    }
  }
  return PixelFrame(
    width: w,
    height: h,
    rgba: out,
    sourceWidth: f.sourceWidth,
    sourceHeight: f.sourceHeight,
  );
}
