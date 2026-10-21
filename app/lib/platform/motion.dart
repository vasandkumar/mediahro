import 'package:meta/meta.dart';

/// Device attitude for the 360° look-around (IMG-001, ADR-042). Android reads
/// `SensorManager` `TYPE_GAME_ROTATION_VECTOR` (no magnetometer, no
/// permission, no absolute heading, so nothing that reveals location), iOS
/// `CMMotionManager.deviceMotion` with `xArbitraryZVertical`, macOS has no
/// sensor, Windows uses `OrientationSensor` / `Inclinometer` where present.
abstract interface class MotionFacade {
  /// Where the back of the device points, at about game rate. The sensor runs
  /// only while the stream is listened to and stops when the listener cancels.
  /// The start heading is arbitrary: consumers use differences.
  Stream<MotionAttitude> get attitude;

  /// Whether this device has a usable sensor.
  Future<bool> get available;
}

/// The aim of the camera axis (out of the back of the device), with the
/// screen rotation applied.
@immutable
final class MotionAttitude {
  const MotionAttitude({required this.yaw, required this.pitch});

  /// Radians to the right of the heading at the start of the stream.
  final double yaw;

  /// Radians above the horizon; negative looks down.
  final double pitch;

  @override
  bool operator ==(Object other) =>
      other is MotionAttitude && other.yaw == yaw && other.pitch == pitch;

  @override
  int get hashCode => Object.hash(yaw, pitch);

  @override
  String toString() => 'MotionAttitude(yaw: $yaw, pitch: $pitch)';
}

/// Default for platforms and tests with no native implementation (ADR-042):
/// no sensor and no readings; the look-around works by touch and keys.
final class UnsupportedMotion implements MotionFacade {
  const UnsupportedMotion();

  @override
  Future<bool> get available async => false;

  @override
  Stream<MotionAttitude> get attitude => const Stream<MotionAttitude>.empty();
}
