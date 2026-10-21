import 'dart:async';
import 'dart:ui' as ui;

import 'package:mediahro/features/photos/viewer/tile_plan.dart';
import 'package:mediahro/features/photos/viewer/viewer_surface.dart';
import 'package:mediahro/images/image_format.dart';
import 'package:mediahro/images/image_pipeline.dart';
import 'package:mediahro/images/pipeline/mediahro_image_pipeline.dart';

/// An animated GIF, WebP or APNG, played by the engine's codec.
final class ImageAnimation {
  ImageAnimation(this.codec);

  final ui.Codec codec;

  int get frameCount => codec.frameCount;

  /// The next frame and how long to show it; the caller disposes the image.
  Future<(ui.Image, Duration)> next() async {
    final f = await codec.getNextFrame();
    final d = f.duration;
    return (
      f.image,
      d == Duration.zero ? const Duration(milliseconds: 100) : d,
    );
  }

  void dispose() => codec.dispose();
}

/// What the viewer needs to show one image: a base picture, its full size,
/// and a loader for full-resolution tiles when the image is too big for one
/// texture (IMG-004).
final class ViewerImage {
  ViewerImage({
    required this.base,
    required this.fullSize,
    required this.info,
    this.tileLoader,
    this.previewOnly = false,
    this.onDispose,
    this.develop,
    this.animation,
  });

  final ui.Image base;

  /// Source pixels after orientation.
  final ui.Size fullSize;
  final ImageInfo info;
  final TileLoader? tileLoader;

  /// A RAW shown from its embedded preview.
  final bool previewOnly;

  /// A RAW shown from its preview can be developed in the background; the
  /// result replaces this image (null when nothing better is available).
  final Future<ViewerImage?> Function()? develop;

  /// Set for animated images: [base] is the first frame.
  final ImageAnimation? animation;

  /// Closes the file the tile loader reads from.
  final Future<void> Function()? onDispose;

  void dispose() {
    base.dispose();
    animation?.dispose();
    final close = onDispose;
    if (close != null) unawaited(close());
  }
}

/// RGBA pixels as a `dart:ui` image.
Future<ui.Image> uiImageFrom(DecodedImage d) {
  final c = Completer<ui.Image>();
  ui.decodeImageFromPixels(
    d.pixels,
    d.width,
    d.height,
    ui.PixelFormat.rgba8888,
    c.complete,
  );
  return c.future;
}

/// Opens [src] for the viewer ([page] of a multi-page TIFF): size from the header, a base picture at the
/// plan's scale, and a tile loader above 12 MP. A RAW shows its largest
/// embedded preview.
Future<ViewerImage> loadViewerImage(
  MediahroImagePipeline pipeline,
  ImageSource src, {
  int page = 0,
  Future<void> Function()? onDispose,
}) async {
  final info = await pipeline.info(src);
  final format = await pipeline.formatOf(src);
  if (format == ImageFormat.raw) {
    final d = await pipeline.decode(src);
    return ViewerImage(
      base: await uiImageFrom(d),
      fullSize: ui.Size(d.width.toDouble(), d.height.toDouble()),
      info: info,
      previewOnly: true,
      onDispose: onDispose,
      develop: () async {
        try {
          final full = await pipeline.developRaw(src);
          return ViewerImage(
            base: await uiImageFrom(full),
            fullSize: ui.Size(full.width.toDouble(), full.height.toDouble()),
            info: info,
          );
        } on Object {
          // LibRaw missing or the file too big: the preview stays.
          return null;
        }
      },
    );
  }
  if (info.frames > 1 &&
      (info.format == 'gif' || info.format == 'webp' || info.format == 'png')) {
    final animated = await _animated(pipeline, src, info, onDispose);
    if (animated != null) return animated;
  }
  final plan = ViewerPlan.forSize(info.width, info.height);
  final base = await pipeline.decode(src, scale: plan.baseScale, frame: page);
  final image = await uiImageFrom(base);
  // The header's size is authoritative for tiles; if a decoder returned a
  // different orientation the base wins so nothing is drawn off-grid.
  var size = ui.Size(info.width.toDouble(), info.height.toDouble());
  if (!plan.tiled || (base.width / plan.baseScale - size.width).abs() > 4) {
    size = ui.Size(
      (base.width / plan.baseScale).roundToDouble(),
      (base.height / plan.baseScale).roundToDouble(),
    );
  }
  TileLoader? loader;
  if (plan.tiled) {
    final full = size;
    loader = (key) async {
      final r = key.sourceRect(full);
      final scale = 1 / (1 << key.level);
      try {
        final d = await pipeline.decode(
          src,
          region: ImageRegion(
            r.left.round(),
            r.top.round(),
            r.width.round(),
            r.height.round(),
          ),
          scale: scale,
          frame: page,
        );
        return await uiImageFrom(d);
      } on Object {
        // A tile that fails leaves the base picture showing there.
        return null;
      }
    };
  }
  return ViewerImage(
    base: image,
    fullSize: size,
    info: info,
    tileLoader: loader,
    onDispose: onDispose,
  );
}

/// The animation through `dart:ui`'s codec (frames are decoded on demand by
/// the engine); null when it cannot be opened, so the still path runs.
Future<ViewerImage?> _animated(
  MediahroImagePipeline pipeline,
  ImageSource src,
  ImageInfo info,
  Future<void> Function()? onDispose,
) async {
  try {
    final bytes = await pipeline.readAll(src, max: 64 << 20);
    final codec = await ui.instantiateImageCodec(bytes);
    final animation = ImageAnimation(codec);
    final (first, _) = await animation.next();
    return ViewerImage(
      base: first,
      fullSize: ui.Size(first.width.toDouble(), first.height.toDouble()),
      info: info,
      animation: animation,
      onDispose: onDispose,
    );
  } on Object {
    return null;
  }
}
