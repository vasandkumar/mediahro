import 'dart:math' as math;
import 'dart:ui' show Offset, Rect, Size;

import 'package:meta/meta.dart';

/// How the picture sits in the viewport when not zoomed.
enum FitMode { fit, fill }

/// Zoom and pan state of one picture (IMG-004). [scale] is screen pixels
/// per source pixel (1.0 = 1:1, the value the readout shows), [centre] is
/// the source-pixel point at the middle of the viewport.
@immutable
final class ZoomState {
  const ZoomState(this.scale, this.centre);

  final double scale;
  final Offset centre;

  @override
  bool operator ==(Object other) =>
      other is ZoomState && other.scale == scale && other.centre == centre;

  @override
  int get hashCode => Object.hash(scale, centre);

  @override
  String toString() => 'ZoomState($scale, $centre)';
}

/// Geometry of an image of [image] source pixels shown in [viewport] logical
/// pixels at [devicePixelRatio].
@immutable
final class ZoomGeometry {
  const ZoomGeometry({
    required this.image,
    required this.viewport,
    this.devicePixelRatio = 1,
    this.mode = FitMode.fit,
    this.maxPixelRatio = 8,
  });

  final Size image;
  final Size viewport;
  final double devicePixelRatio;
  final FitMode mode;

  /// Largest zoom, in device pixels per source pixel (beyond 1:1: IMG-004).
  final double maxPixelRatio;

  /// Scale at which the whole picture fits (or fills) the viewport.
  double get fitScale {
    if (image.isEmpty || viewport.isEmpty) return 1;
    final sx = viewport.width / image.width;
    final sy = viewport.height / image.height;
    return mode == FitMode.fit ? math.min(sx, sy) : math.max(sx, sy);
  }

  /// Scale of one device pixel per source pixel.
  double get oneToOne => 1 / devicePixelRatio;

  double get minScale => math.min(fitScale, oneToOne);

  double get maxScale =>
      math.max(fitScale * 4, maxPixelRatio / devicePixelRatio);

  ZoomState get initial => ZoomState(fitScale, centreOfImage);

  Offset get centreOfImage => Offset(image.width / 2, image.height / 2);

  /// Source-pixel rectangle visible at [s].
  Rect visibleRect(ZoomState s) => Rect.fromCenter(
    center: s.centre,
    width: viewport.width / s.scale,
    height: viewport.height / s.scale,
  );

  /// Keeps the picture covering the viewport (or centred when smaller).
  ZoomState clamp(ZoomState s) {
    final scale = s.scale.clamp(minScale, maxScale);
    final halfW = viewport.width / scale / 2;
    final halfH = viewport.height / scale / 2;
    double axis(double c, double half, double size) {
      // Picture smaller than the viewport on this axis: centred.
      if (half * 2 >= size) return size / 2;
      return c.clamp(half, size - half);
    }

    return ZoomState(
      scale,
      Offset(
        axis(s.centre.dx, halfW, image.width),
        axis(s.centre.dy, halfH, image.height),
      ),
    );
  }

  /// Zooms by [factor] keeping the source point under [focal] (viewport
  /// coordinates) fixed: pinch and scroll-wheel zoom.
  ZoomState zoomAt(ZoomState s, double factor, Offset focal) {
    final scale = (s.scale * factor).clamp(minScale, maxScale);
    final fromCentre = focal - Offset(viewport.width / 2, viewport.height / 2);
    // The source point under the focal stays put.
    final under = s.centre + fromCentre / s.scale;
    return clamp(ZoomState(scale, under - fromCentre / scale));
  }

  /// Pans by [delta] viewport pixels (a drag to the right moves the picture
  /// right, so the visible area moves left).
  ZoomState pan(ZoomState s, Offset delta) =>
      clamp(ZoomState(s.scale, s.centre - delta / s.scale));

  /// Whether the picture is at (or below) the fit zoom, where horizontal
  /// swipes belong to the page view.
  bool isAtFit(ZoomState s) => s.scale <= fitScale * 1.02;

  /// The next stop of the double-tap cycle (fit → 1:1 or 2× → 4× → fit),
  /// centred on the tapped source point.
  ZoomState nextStop(ZoomState s, Offset focal) {
    final fit = fitScale;
    final one = oneToOne;
    final stops = <double>[
      fit,
      if (one > fit * 1.05) one else fit * 2,
      math.max(one, fit) * 4,
    ]..sort();
    var target = stops.first;
    for (final stop in stops) {
      if (s.scale < stop * 0.98) {
        target = stop;
        break;
      }
      target = stops.first;
    }
    if (target <= fit * 1.02) return initial;
    return zoomAt(s, target / s.scale, focal);
  }

  /// The readout: percent of 1:1 (physical pixels), so 100 % is one source
  /// pixel per device pixel.
  int percent(ZoomState s) => (s.scale * devicePixelRatio * 100).round();
}
