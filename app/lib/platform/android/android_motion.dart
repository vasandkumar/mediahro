import 'package:mediahro/platform/android/gen/motion_api.pigeon.dart'
    hide attitude;
import 'package:mediahro/platform/android/gen/motion_api.pigeon.dart'
    as native
    show attitude;
import 'package:mediahro/platform/motion.dart';

/// [MotionFacade] on Android (IMG-001, ADR-042): `TYPE_GAME_ROTATION_VECTOR`
/// at game rate, with no magnetometer (so no absolute heading) and no
/// permission (`MotionModule.kt`). The sensor runs only while [attitude] is
/// listened to. Yaw is relative to the heading at the start of the stream.
final class AndroidMotion implements MotionFacade {
  AndroidMotion({
    MotionHostApi? api,
    Stream<MotionAttitudeMsg> Function()? events,
  }) : _api = api ?? MotionHostApi(),
       _events = events ?? native.attitude;

  final MotionHostApi _api;
  final Stream<MotionAttitudeMsg> Function() _events;

  @override
  Stream<MotionAttitude> get attitude =>
      _events().map((m) => MotionAttitude(yaw: m.yaw, pitch: m.pitch));

  @override
  Future<bool> get available => _api.available();
}
