// Pigeon messages for MotionFacade on Android (lane C4a, IMG-001 360 look-around,
// ADR-042): SensorManager TYPE_GAME_ROTATION_VECTOR.
//
//   dart run pigeon --input pigeons/android/motion_api.dart   (from app/)

import 'package:pigeon/pigeon.dart';

@ConfigurePigeon(
  PigeonOptions(
    dartOut: 'lib/platform/android/gen/motion_api.pigeon.dart',
    kotlinOut: 'android/app/src/main/kotlin/com/mediahro/mediahro/pigeon/MotionApi.g.kt',
    kotlinOptions: KotlinOptions(
      // Shares FlutterError and the event-channel classes of StorageApi.g.kt.
      package: 'com.mediahro.mediahro.pigeon',
      includeErrorClass: false,
    ),
    dartPackageName: 'mediahro',
  ),
)
/// Radians; yaw is to the right of the heading at the start of the stream,
/// pitch above the horizon.
class MotionAttitudeMsg {
  MotionAttitudeMsg(this.yaw, this.pitch);
  double yaw;
  double pitch;
}

@HostApi()
abstract class MotionHostApi {
  /// The device has a game rotation vector sensor.
  bool available();
}

@EventChannelApi(
  kotlinOptions: KotlinEventChannelOptions(includeSharedClasses: false),
)
abstract class MotionEventsApi {
  /// Registers the sensor when listened to, unregisters on cancel.
  MotionAttitudeMsg attitude();
}
