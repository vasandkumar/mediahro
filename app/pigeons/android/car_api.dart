// Pigeon messages for MediaBrowseFacade (Android Auto, MUS-013) and
// AlarmFacade (MUS-011) on Android (lane C4a).
//
//   dart run pigeon --input pigeons/android/car_api.dart   (from app/)
//
// Pigeon's schema is positional; named bool parameters do not map to Kotlin.
// ignore_for_file: avoid_positional_boolean_parameters

import 'package:pigeon/pigeon.dart';

@ConfigurePigeon(
  PigeonOptions(
    dartOut: 'lib/platform/android/gen/car_api.pigeon.dart',
    kotlinOut:
        'android/app/src/main/kotlin/com/mediahro/mediahro/pigeon/CarApi.g.kt',
    kotlinOptions: KotlinOptions(
      // Shares FlutterError and the event-channel classes of StorageApi.g.kt.
      package: 'com.mediahro.mediahro.pigeon',
      includeErrorClass: false,
    ),
    dartPackageName: 'mediahro',
  ),
)
class MediaBrowseNodeMsg {
  MediaBrowseNodeMsg(
    this.id,
    this.title,
    this.subtitle,
    this.artworkUri,
    this.playable,
    this.browsable,
  );
  String id;
  String title;
  String? subtitle;
  String? artworkUri;
  bool playable;
  bool browsable;
}

class ScheduledAlarmMsg {
  ScheduledAlarmMsg(this.id, this.atMs, this.label);
  String id;

  /// Wall-clock time of the next firing, epoch milliseconds.
  int atMs;
  String label;
}

class AlarmFiredMsg {
  AlarmFiredMsg(this.id);
  String id;
}

@HostApi()
abstract class MediaBrowseHostApi {
  /// Dart has a provider; car and voice requests can be answered.
  void registered();

  void notifyChildrenChanged(String nodeId);
}

/// Native asks Dart (the registered MediaBrowseProvider).
@FlutterApi()
abstract class MediaBrowseFlutterApi {
  @async
  List<MediaBrowseNodeMsg> children(String nodeId, int page);

  @async
  List<MediaBrowseNodeMsg> search(String query);

  @async
  void play(String nodeId);
}

@HostApi()
abstract class AlarmHostApi {
  bool isSupported();

  @async
  void schedule(ScheduledAlarmMsg alarm);

  void cancel(String id);
}

@EventChannelApi(
  kotlinOptions: KotlinEventChannelOptions(includeSharedClasses: false),
)
abstract class AlarmEventsApi {
  AlarmFiredMsg alarmsFired();
}
