import 'dart:async';
import 'dart:ui' as ui;

import 'package:mediahro/features/photos/viewer/tile_plan.dart';
import 'package:mediahro/features/photos/viewer/viewer_surface.dart';
import 'package:mediahro/images/image_format.dart';
import 'package:mediahro/images/image_pipeline.dart';
import 'package:mediahro/images/pipeline/mediahro_image_pipeline.dart';

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
  });

  final ui.Image base;

  /// Source pixels after orientation.
  final ui.Size fullSize;
  final ImageInfo info;
  final TileLoader? tileLoader;

  /// A RAW shown from its embedded preview.
  final bool previewOnly;

  void dispose() => base.dispose();
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

/// Opens [src] for the viewer: size from the header, a base picture at the
/// plan's scale, and a tile loader above 12 MP. A RAW shows its largest
/// embedded preview.
Future<ViewerImage> loadViewerImage(
  MediahroImagePipeline pipeline,
  ImageSource src,
) async {
  final info = await pipeline.info(src);
  final format = await pipeline.formatOf(src);
  if (format == ImageFormat.raw) {
    final d = await pipeline.decode(src);
    return ViewerImage(
      base: await uiImageFrom(d),
      fullSize: ui.Size(d.width.toDouble(), d.height.toDouble()),
      info: info,
      previewOnly: true,
    );
  }
  final plan = ViewerPlan.forSize(info.width, info.height);
  final base = await pipeline.decode(src, scale: plan.baseScale);
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
  );
}
