// Pigeon messages for ManagedConfigFacade and KioskFacade on Android
// (lane C4a, B2B-001, B2B-002): RestrictionsManager and lock task mode.
//
//   dart run pigeon --input pigeons/android/enterprise_api.dart   (from app/)
//
// Pigeon's schema is positional; named bool parameters do not map to Kotlin.
// ignore_for_file: avoid_positional_boolean_parameters

import 'package:pigeon/pigeon.dart';

@ConfigurePigeon(
  PigeonOptions(
    dartOut: 'lib/platform/android/gen/enterprise_api.pigeon.dart',
    kotlinOut: 'android/app/src/main/kotlin/com/mediahro/mediahro/pigeon/EnterpriseApi.g.kt',
    kotlinOptions: KotlinOptions(
      // Shares FlutterError and the event-channel classes of StorageApi.g.kt.
      package: 'com.mediahro.mediahro.pigeon',
      includeErrorClass: false,
    ),
    dartPackageName: 'mediahro',
  ),
)
enum ManagedKindMsg { string, boolean, integer, list }

/// One managed restriction; only the field of its [kind] is set.
class ManagedEntryMsg {
  ManagedEntryMsg(
    this.key,
    this.kind,
    this.stringValue,
    this.boolValue,
    this.intValue,
    this.listValue,
  );
  String key;
  ManagedKindMsg kind;
  String? stringValue;
  bool? boolValue;
  int? intValue;
  List<String>? listValue;
}

class ManagedSnapshotMsg {
  ManagedSnapshotMsg(this.entries);
  List<ManagedEntryMsg> entries;
}

@HostApi()
abstract class ManagedConfigHostApi {
  ManagedSnapshotMsg read();
}

@HostApi()
abstract class KioskHostApi {
  bool isSupported();
  bool isActive();

  /// Starts lock task mode (screen pinning unless the app is a lock-task
  /// package of the device owner), hides the system bars and starts the
  /// crash watchdog.
  void enter();
  void exit();

  /// Launches the app after boot (enterprise build only; `unsupported` elsewhere).
  void setStartOnBoot(bool enabled);
}

@EventChannelApi(
  kotlinOptions: KotlinEventChannelOptions(includeSharedClasses: false),
)
abstract class EnterpriseEventsApi {
  ManagedSnapshotMsg managedChanges();
  bool kioskStates();
}
