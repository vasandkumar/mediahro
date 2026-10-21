// Pigeon messages for BackgroundWorkFacade on Android (lane C4a, POD-002, ADR-049):
// WorkManager periodic work that wakes the app and hands the task id to Dart.
//
//   dart run pigeon --input pigeons/android/background_api.dart   (from app/)
// Pigeon's schema is positional; named bool parameters do not map to Kotlin.
// ignore_for_file: avoid_positional_boolean_parameters

import 'package:pigeon/pigeon.dart';

@ConfigurePigeon(
  PigeonOptions(
    dartOut: 'lib/platform/android/gen/background_api.pigeon.dart',
    kotlinOut: 'android/app/src/main/kotlin/com/mediahro/mediahro/pigeon/BackgroundApi.g.kt',
    kotlinOptions: KotlinOptions(
      // Shares FlutterError and the event-channel classes of StorageApi.g.kt.
      package: 'com.mediahro.mediahro.pigeon',
      includeErrorClass: false,
    ),
    dartPackageName: 'mediahro',
  ),
)
@HostApi()
abstract class BackgroundWorkHostApi {
  /// Unique periodic work named by [id]; scheduling it again updates it.
  /// [intervalMs] below 15 minutes is raised to 15 minutes.
  void schedulePeriodic(
    String id,
    int intervalMs,
    bool requiresNetwork,
    bool unmeteredOnly,
    bool requiresCharging,
  );

  void cancel(String id);

  /// Ends the run of [id] that the OS is waiting on.
  void complete(String id, bool success);

  bool available();
}

@EventChannelApi(
  kotlinOptions: KotlinEventChannelOptions(includeSharedClasses: false),
)
abstract class BackgroundEventsApi {
  /// The id of a task the OS woke the app for.
  String runs();
}
