// Pigeon messages for AccessibilityPrefsFacade and GamepadFacade on Android
// (lane C4a, SYS-008, SYS-009, ADR-038).
//
//   dart run pigeon --input pigeons/android/input_api.dart   (from app/)
//
// Pigeon's schema is positional; named bool parameters do not map to Kotlin.
// ignore_for_file: avoid_positional_boolean_parameters

import 'package:pigeon/pigeon.dart';

@ConfigurePigeon(
  PigeonOptions(
    dartOut: 'lib/platform/android/gen/input_api.pigeon.dart',
    kotlinOut: 'android/app/src/main/kotlin/com/mediahro/mediahro/pigeon/InputApi.g.kt',
    kotlinOptions: KotlinOptions(
      // Shares FlutterError and the event-channel classes of StorageApi.g.kt.
      package: 'com.mediahro.mediahro.pigeon',
      includeErrorClass: false,
    ),
    dartPackageName: 'mediahro',
  ),
)
enum GamepadAxisMsg {
  leftX,
  leftY,
  rightX,
  rightY,
  leftTrigger,
  rightTrigger,
  hatX,
  hatY,
}

class GamepadInfoMsg {
  GamepadInfoMsg(this.id, this.name, this.vendorId, this.productId);
  int id;
  String name;
  int? vendorId;
  int? productId;
}

class GamepadChangeMsg {
  GamepadChangeMsg(this.added, this.gamepad);
  bool added;
  GamepadInfoMsg gamepad;
}

class GamepadAxisEventMsg {
  GamepadAxisEventMsg(this.deviceId, this.axis, this.value);
  int deviceId;
  GamepadAxisMsg axis;
  double value;
}

@HostApi()
abstract class AccessibilityPrefsHostApi {
  bool audioDescriptionRequested();
}

@HostApi()
abstract class GamepadHostApi {
  List<GamepadInfoMsg> connected();
}

@EventChannelApi(
  kotlinOptions: KotlinEventChannelOptions(includeSharedClasses: false),
)
abstract class InputEventsApi {
  bool audioDescriptionChanges();
  GamepadChangeMsg gamepadConnections();
  GamepadAxisEventMsg gamepadAxes();
}
