// Pigeon messages for PowerStatusFacade on Android (lane C4a, ADR-033,
// VID-038/039 step-down).
//
//   dart run pigeon --input pigeons/android/power_api.dart   (from app/)
//
// Pigeon's schema is positional; named bool parameters do not map to Kotlin.
// ignore_for_file: avoid_positional_boolean_parameters

import 'package:pigeon/pigeon.dart';

@ConfigurePigeon(
  PigeonOptions(
    dartOut: 'lib/platform/android/gen/power_api.pigeon.dart',
    kotlinOut: 'android/app/src/main/kotlin/com/mediahro/mediahro/pigeon/PowerApi.g.kt',
    kotlinOptions: KotlinOptions(
      // Shares FlutterError and the event-channel classes of StorageApi.g.kt.
      package: 'com.mediahro.mediahro.pigeon',
      includeErrorClass: false,
    ),
    dartPackageName: 'mediahro',
  ),
)
enum ThermalLevelMsg { nominal, fair, serious, critical }

class PowerStatusMsg {
  PowerStatusMsg(this.thermal, this.batterySaver);
  ThermalLevelMsg thermal;
  bool batterySaver;
}

@HostApi()
abstract class PowerStatusHostApi {
  PowerStatusMsg current();
}

@EventChannelApi(
  kotlinOptions: KotlinEventChannelOptions(includeSharedClasses: false),
)
abstract class PowerEventsApi {
  PowerStatusMsg powerStatusChanges();
}
