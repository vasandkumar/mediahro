import 'dart:math' as math;
import 'dart:ui' show Offset, Size;

import 'package:mediahro/images/metadata/pano_meta.dart';
import 'package:meta/meta.dart';

/// The maths of the 360° look-around (IMG-001): where a picture sits on the
/// sphere, what a camera looking in some direction sees, and how touches and
/// the phone's own motion move that camera. The shader and the mesh fallback
/// in `pano_painter.dart` do exactly this arithmetic, so what is tested here
/// is what is drawn.
///
/// Angles are radians. Longitude 0 is the middle of the whole sphere and
/// grows to the right; latitude 0 is the horizon and grows upward.
const double _pi = math.pi;
const double _twoPi = 2 * math.pi;

double degToRad(double d) => d * _pi / 180;
double radToDeg(double r) => r * 180 / _pi;

/// Wraps [a] into (-π, π].
double wrapAngle(double a) {
  var r = a % _twoPi;
  if (r > _pi) r -= _twoPi;
  if (r <= -_pi) r += _twoPi;
  return r;
}

/// Where the picture sits on the sphere. A whole sphere covers 360° by 180°;
/// a cropped panorama covers a window of it and has nothing outside.
@immutable
final class PanoGeometry {
  const PanoGeometry({
    required this.lonMin,
    required this.lonSpan,
    required this.latMax,
    required this.latSpan,
  });

  /// From the photo's GPano numbers. Without the whole sphere's size the
  /// picture is taken to be the whole sphere; without a crop, the crop is the
  /// whole sphere.
  factory PanoGeometry.from(PanoramaMeta? meta) {
    final fw = meta?.fullWidth;
    final fh = meta?.fullHeight;
    if (meta == null || fw == null || fh == null || fw <= 0 || fh <= 0) {
      return whole;
    }
    final cw = meta.croppedWidth ?? fw;
    final ch = meta.croppedHeight ?? fh;
    final left = meta.croppedLeft ?? 0;
    final top = meta.croppedTop ?? 0;
    if (cw <= 0 || ch <= 0 || left < 0 || top < 0) return whole;
    // The sphere's own pixels are not the decoded picture's: only the
    // fractions matter.
    final lonMin = (left / fw - 0.5) * _twoPi;
    final lonSpan = math.min<double>(cw / fw, 1) * _twoPi;
    final latMax = (0.5 - top / fh) * _pi;
    final latSpan = math.min<double>(ch / fh, 1) * _pi;
    return PanoGeometry(
      lonMin: lonMin,
      lonSpan: lonSpan,
      latMax: latMax,
      latSpan: latSpan,
    );
  }

  static const PanoGeometry whole = PanoGeometry(
    lonMin: -_pi,
    lonSpan: _twoPi,
    latMax: _pi / 2,
    latSpan: _pi,
  );

  final double lonMin;
  final double lonSpan;
  final double latMax;
  final double latSpan;

  double get lonMax => lonMin + lonSpan;
  double get latMin => latMax - latSpan;
  double get lonCentre => lonMin + lonSpan / 2;
  double get latCentre => latMax - latSpan / 2;

  /// The picture goes all the way round: its left edge meets its right.
  bool get wrapsAround => lonSpan >= _twoPi - 1e-6;

  /// The texture coordinate (0 to 1 on both axes) of a direction. Outside the
  /// picture of a cropped panorama the values fall outside 0 to 1.
  Offset uv(double lon, double lat) {
    var l = lon;
    if (wrapsAround) {
      l = lonMin + (lon - lonMin) % _twoPi;
    } else {
      // The nearest copy of the longitude to the picture's middle.
      l = lonCentre + wrapAngle(lon - lonCentre);
    }
    return Offset((l - lonMin) / lonSpan, (latMax - lat) / latSpan);
  }

  /// True when the direction is inside the picture.
  bool covers(double lon, double lat) {
    final p = uv(lon, lat);
    return p.dx >= 0 && p.dx <= 1 && p.dy >= 0 && p.dy <= 1;
  }

  @override
  bool operator ==(Object other) =>
      other is PanoGeometry &&
      other.lonMin == lonMin &&
      other.lonSpan == lonSpan &&
      other.latMax == latMax &&
      other.latSpan == latSpan;

  @override
  int get hashCode => Object.hash(lonMin, lonSpan, latMax, latSpan);
}

/// Where the camera looks: [yaw] right and [pitch] up from the middle of the
/// whole sphere, with a vertical field of view [fov].
@immutable
final class PanoView {
  const PanoView({required this.yaw, required this.pitch, required this.fov});

  final double yaw;
  final double pitch;
  final double fov;

  PanoView copyWith({double? yaw, double? pitch, double? fov}) => PanoView(
    yaw: yaw ?? this.yaw,
    pitch: pitch ?? this.pitch,
    fov: fov ?? this.fov,
  );

  @override
  bool operator ==(Object other) =>
      other is PanoView &&
      other.yaw == yaw &&
      other.pitch == pitch &&
      other.fov == fov;

  @override
  int get hashCode => Object.hash(yaw, pitch, fov);

  @override
  String toString() =>
      'PanoView(yaw ${radToDeg(yaw).toStringAsFixed(1)}°, '
      'pitch ${radToDeg(pitch).toStringAsFixed(1)}°, '
      'fov ${radToDeg(fov).toStringAsFixed(1)}°)';
}

/// The limits and conventions of one camera over one picture.
@immutable
final class PanoCamera {
  const PanoCamera(
    this.geometry, {
    this.aspect = 1,
    this.minFov = 0.3490658503988659, // 20°
    this.maxFov = 1.7453292519943295, // 100°
  });

  final PanoGeometry geometry;

  /// Viewport width over height.
  final double aspect;
  final double minFov;
  final double maxFov;

  /// Horizontal field of view for a vertical one.
  double horizontalFov(double fov) => 2 * math.atan(math.tan(fov / 2) * aspect);

  /// The widest vertical field of view that stays inside the picture (never
  /// above [maxFov]; a whole sphere has no limit but [maxFov]).
  double get widestFov {
    final g = geometry;
    var widest = maxFov;
    if (g.latSpan < _pi - 1e-6) widest = math.min(widest, g.latSpan);
    if (!g.wrapsAround) {
      final h = math.min(g.lonSpan, math.pi - 1e-3);
      widest = math.min(widest, 2 * math.atan(math.tan(h / 2) / aspect));
    }
    return math.max(widest, 1e-3);
  }

  /// The view moved back inside what the picture covers, and wrapped.
  PanoView clamp(PanoView v) {
    final g = geometry;
    final widest = widestFov;
    final fov = v.fov.clamp(math.min(minFov, widest), widest).toDouble();
    final hHalf = horizontalFov(fov) / 2;
    var pitch = v.pitch;
    final pMax = g.latMax - fov / 2;
    final pMin = g.latMin + fov / 2;
    pitch = pMax < pMin ? g.latCentre : pitch.clamp(pMin, pMax);
    var yaw = v.yaw;
    if (g.wrapsAround) {
      yaw = wrapAngle(yaw);
    } else {
      final yMin = g.lonMin + hHalf;
      final yMax = g.lonMax - hHalf;
      yaw = yMax < yMin ? g.lonCentre : yaw.clamp(yMin, yMax);
    }
    return PanoView(yaw: yaw, pitch: pitch, fov: fov);
  }

  /// The view a photo opens at: the one its GPano says, else the middle of
  /// the picture, at 75° of vertical field of view when that fits.
  PanoView initial(PanoramaMeta? meta) {
    final g = geometry;
    var yaw = g.lonCentre;
    var pitch = g.latCentre;
    var fov = degToRad(75);
    final heading = meta?.initialHeading;
    if (heading != null) yaw = (heading / 360 - 0.5) * _twoPi;
    if (meta?.initialPitch != null) pitch = degToRad(meta!.initialPitch!);
    final hfov = meta?.initialFov;
    if (hfov != null && hfov > 1 && hfov < 179) {
      fov = 2 * math.atan(math.tan(degToRad(hfov) / 2) / aspect);
    }
    return clamp(PanoView(yaw: yaw, pitch: pitch, fov: fov));
  }

  /// The longitude and latitude seen through the viewport point [p] (in
  /// [viewport] logical pixels) by [view].
  (double, double) direction(Offset p, Size viewport, PanoView view) {
    final t = math.tan(view.fov / 2);
    final nx = (p.dx / viewport.width - 0.5) * 2 * t * aspect;
    final ny = (0.5 - p.dy / viewport.height) * 2 * t;
    final sp = math.sin(view.pitch);
    final cp = math.cos(view.pitch);
    final dx = nx;
    final dy = ny * cp + sp;
    final dz = cp - ny * sp;
    final lon = view.yaw + math.atan2(dx, dz);
    final lat = math.asin(dy / math.sqrt(dx * dx + dy * dy + dz * dz));
    return (lon, lat);
  }

  /// The texture coordinate drawn at the viewport point [p].
  Offset uvAt(Offset p, Size viewport, PanoView view) {
    final (lon, lat) = direction(p, viewport, view);
    return geometry.uv(lon, lat);
  }

  /// The view after a finger moved by [delta] logical pixels over a viewport
  /// [viewportHeight] tall: the picture follows the finger, so the camera
  /// turns the other way.
  PanoView dragged(PanoView v, Offset delta, double viewportHeight) {
    if (viewportHeight <= 0) return v;
    final perPixel = v.fov / viewportHeight;
    return clamp(
      v.copyWith(
        yaw: v.yaw - delta.dx * perPixel,
        pitch: v.pitch + delta.dy * perPixel,
      ),
    );
  }

  /// The view after a pinch of [scale] (above 1 zooms in).
  PanoView zoomed(PanoView v, double scale) {
    if (scale <= 0) return v;
    return clamp(v.copyWith(fov: v.fov / scale));
  }
}

/// Coasting after a flick: the speed (radians per second) after [dt] seconds,
/// halving about every 0.35 s. Zero once it is too slow to see.
double coast(double speed, double dt) {
  final s = speed * math.pow(0.5, dt / 0.35);
  return s.abs() < degToRad(0.5) ? 0 : s;
}

/// The phone's own aim, as the platform reports it: [yaw] is the compass-like
/// turn of the back of the phone (right is positive) and [pitch] is how far
/// that axis points above the horizon.
@immutable
final class PanoAttitude {
  const PanoAttitude({required this.yaw, required this.pitch});

  final double yaw;
  final double pitch;
}

/// Turns the phone's aim into a camera: the view the person had when motion
/// was switched on stays where it is, and from then on the camera moves with
/// the phone. Small tremors are smoothed away.
final class MotionFollower {
  MotionFollower({this.smoothing = 0.2});

  /// How much of the way to the target each reading goes (0 to 1).
  final double smoothing;

  PanoAttitude? _origin;
  PanoView? _base;
  PanoView? _shown;

  /// Starts following from [view] (the phone's present aim is zero).
  void start(PanoView view) {
    _origin = null;
    _base = view;
    _shown = view;
  }

  void stop() {
    _origin = null;
    _base = null;
    _shown = null;
  }

  bool get following => _base != null;

  /// The view for a new reading, kept inside [camera]'s limits; null when
  /// not following.
  PanoView? update(PanoAttitude a, PanoCamera camera) {
    final base = _base;
    if (base == null) return null;
    final origin = _origin ??= a;
    final target = camera.clamp(
      PanoView(
        yaw: base.yaw + wrapAngle(a.yaw - origin.yaw),
        pitch: base.pitch + (a.pitch - origin.pitch),
        fov: base.fov,
      ),
    );
    final from = _shown ?? target;
    final next = camera.clamp(
      PanoView(
        yaw: from.yaw + wrapAngle(target.yaw - from.yaw) * smoothing,
        pitch: from.pitch + (target.pitch - from.pitch) * smoothing,
        fov: target.fov,
      ),
    );
    _shown = next;
    return next;
  }

  /// Takes up a change the person made by hand (a drag or a zoom) while
  /// following: the phone's present aim becomes the new zero.
  void rebase(PanoView view) {
    _origin = null;
    _base = view;
    _shown = view;
  }
}
