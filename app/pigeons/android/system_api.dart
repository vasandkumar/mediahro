// Pigeon messages for SystemIntegrationFacade and IntentsFacade on Android
// (lane C4a, CORE-003 open-with, SYS-004 share targets, SYS-003 shortcuts
// and App Actions).
//
//   dart run pigeon --input pigeons/android/system_api.dart   (from app/)

import 'package:pigeon/pigeon.dart';

@ConfigurePigeon(
  PigeonOptions(
    dartOut: 'lib/platform/android/gen/system_api.pigeon.dart',
    kotlinOut: 'android/app/src/main/kotlin/com/mediahro/mediahro/pigeon/SystemApi.g.kt',
    kotlinOptions: KotlinOptions(
      // Shares FlutterError and the event-channel classes of StorageApi.g.kt.
      package: 'com.mediahro.mediahro.pigeon',
      includeErrorClass: false,
    ),
    dartPackageName: 'mediahro',
  ),
)
enum AppIntentKindMsg { resumeLast, playPlaylist, openMode, search }

class OpenRequestMsg {
  OpenRequestMsg(this.uris);
  List<String> uris;
}

class AppIntentMsg {
  AppIntentMsg(this.kind, this.argument);
  AppIntentKindMsg kind;
  String? argument;
}

class AppShortcutMsg {
  AppShortcutMsg(this.id, this.title, this.kind, this.argument);
  String id;
  String title;
  AppIntentKindMsg kind;
  String? argument;
}

@HostApi()
abstract class SystemHostApi {
  /// Settings › Apps › Mediahro › Open by default (or the app's details).
  void showDefaultAppGuidance();
}

@HostApi()
abstract class IntentsHostApi {
  void publishShortcuts(List<AppShortcutMsg> shortcuts);
}

@EventChannelApi(
  kotlinOptions: KotlinEventChannelOptions(includeSharedClasses: false),
)
abstract class SystemEventsApi {
  OpenRequestMsg openRequests();
  AppIntentMsg appIntents();
}
