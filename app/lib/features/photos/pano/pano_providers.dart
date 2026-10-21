import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mediahro/features/photos/pano/pano_math.dart';
import 'package:mediahro/features/photos/pano/pano_painter.dart';
import 'package:mediahro/features/photos/photos_providers.dart';
import 'package:mediahro/features/photos/timeline/timeline_model.dart';
import 'package:mediahro/features/photos/viewer/viewer_image.dart';
import 'package:mediahro/images/metadata/pano_meta.dart';
import 'package:mediahro/platform/motion.dart';
import 'package:mediahro/platform/platform_facades.dart' show motionProvider;

/// Where the phone points, as the platform reports it (IMG-001, ADR-042).
/// Where the phone has no sensor the look-around works by touch, keys and
/// buttons only.
abstract interface class PanoMotionSource {
  /// Readings of the aim of the back of the phone, a few dozen a second while
  /// someone listens, none otherwise.
  Stream<PanoAttitude> get attitude;

  /// Whether the phone has a usable sensor.
  Future<bool> get available;
}

/// The platform's [MotionFacade] as the look-around's source.
final class MotionFacadeSource implements PanoMotionSource {
  const MotionFacadeSource(this._motion);

  final MotionFacade _motion;

  @override
  Stream<PanoAttitude> get attitude =>
      _motion.attitude.map((a) => PanoAttitude(yaw: a.yaw, pitch: a.pitch));

  @override
  Future<bool> get available => _motion.available;
}

/// The look-around's motion source: the platform's motion facade.
final panoMotionProvider = Provider<PanoMotionSource?>(
  (ref) => MotionFacadeSource(ref.watch(motionProvider)),
);

/// A 360° picture ready to draw.
final class PanoImage {
  PanoImage({required this.image, required this.meta, this.onDispose});

  final ui.Image image;
  final PanoramaMeta? meta;
  final Future<void> Function()? onDispose;

  void dispose() {
    image.dispose();
    final close = onDispose;
    if (close != null) unawaited(close());
  }
}

/// Opens one photo for the look-around; tests replace it.
typedef PanoImageLoader = Future<PanoImage> Function(PhotoEntry entry);

/// Longest edge of the texture: what every phone GPU takes.
const int panoTextureEdge = 8192;

final panoImageLoaderProvider = Provider<PanoImageLoader>((ref) {
  final files = ref.watch(photoFilesProvider);
  final pipeline = ref.watch(imagePipelineProvider);
  return (entry) async {
    final src = await files.open(entry);
    try {
      final info = await pipeline.info(src);
      final scale = math.min<double>(
        1,
        panoTextureEdge / math.max(info.width, info.height),
      );
      final decoded = await pipeline.decode(src, scale: scale);
      return PanoImage(
        image: await uiImageFrom(decoded),
        meta: info.panorama,
        onDispose: src.file.close,
      );
    } on Object {
      await src.file.close();
      rethrow;
    }
  };
});

/// The shader, loaded once; null when this build does not have it.
final panoProgramProvider = FutureProvider<ui.FragmentProgram?>(
  (ref) => loadPanoProgram(),
);
