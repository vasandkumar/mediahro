import 'dart:math' as math;
import 'dart:ui' show Offset;

import 'package:flutter/foundation.dart';
import 'package:mediahro/features/photos/pano/pano_math.dart';
import 'package:mediahro/images/metadata/pano_meta.dart';

/// The camera of one 360° picture (IMG-001): where it looks, how it is moved
/// by touch, keys, buttons and the phone's own motion, and where it starts.
final class PanoController extends ChangeNotifier {
  PanoController({PanoramaMeta? meta, double aspect = 4 / 3})
    : geometry = PanoGeometry.from(meta),
      _meta = meta {
    _camera = PanoCamera(geometry, aspect: aspect);
    _view = _camera.initial(meta);
  }

  final PanoGeometry geometry;
  final PanoramaMeta? _meta;
  late PanoCamera _camera;
  late PanoView _view;
  final MotionFollower _follower = MotionFollower();

  PanoCamera get camera => _camera;
  PanoView get view => _view;

  /// True while the camera follows the phone's motion.
  bool get motionOn => _follower.following;

  /// The viewport's shape. Called while drawing, so it does not notify; the
  /// view is brought inside the picture's limits for the new shape.
  void setAspect(double aspect) {
    if (aspect == _camera.aspect || aspect <= 0) return;
    _camera = PanoCamera(geometry, aspect: aspect);
    _view = _camera.clamp(_view);
  }

  void _set(PanoView v, {bool byHand = true}) {
    final next = _camera.clamp(v);
    if (next == _view) return;
    _view = next;
    if (byHand && _follower.following) _follower.rebase(_view);
    notifyListeners();
  }

  /// A finger moved by [delta] over a viewport [viewportHeight] tall.
  void drag(Offset delta, double viewportHeight) =>
      _set(_camera.dragged(_view, delta, viewportHeight));

  /// Turns the camera by [yaw] (right) and [pitch] (up) radians.
  void turn({double yaw = 0, double pitch = 0}) =>
      _set(_view.copyWith(yaw: _view.yaw + yaw, pitch: _view.pitch + pitch));

  /// A pinch of [scale] (above 1 zooms in).
  void zoom(double scale) => _set(_camera.zoomed(_view, scale));

  /// One step in or out of the picture.
  void zoomStep({required bool zoomIn}) => zoom(zoomIn ? 1.25 : 0.8);

  /// One step in a direction: a sixth of the field of view.
  void step({int right = 0, int up = 0}) {
    final s = _view.fov / 6;
    turn(yaw: right * s * _camera.aspect.clamp(0.5, 2), pitch: up * s);
  }

  /// Back to the view the photo opens at.
  void reset() => _set(_camera.initial(_meta));

  /// The camera coasts: [velocity] in radians per second (yaw, pitch).
  /// Returns the speeds left after [dt] seconds.
  (double, double) coastBy((double, double) velocity, double dt) {
    final (vy, vp) = velocity;
    if (vy == 0 && vp == 0) return (0, 0);
    turn(yaw: vy * dt, pitch: vp * dt);
    return (coast(vy, dt), coast(vp, dt));
  }

  /// Starts following the phone's aim from the present view.
  void startMotion() {
    _follower.start(_view);
    notifyListeners();
  }

  void stopMotion() {
    _follower.stop();
    notifyListeners();
  }

  /// A reading of the phone's aim; ignored unless following.
  void onAttitude(PanoAttitude a) {
    final v = _follower.update(a, _camera);
    if (v == null || v == _view) return;
    _view = v;
    notifyListeners();
  }

  /// Heading in whole degrees (0 to 359 round from the sphere's left edge)
  /// and tilt (positive up), for the screen reader.
  (int, int) get facing {
    final heading = ((_view.yaw / (2 * math.pi) + 0.5) * 360) % 360;
    return (heading.round() % 360, radToDeg(_view.pitch).round());
  }
}
