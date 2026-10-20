import 'package:mediahro/platform/android/gen/system_api.pigeon.dart' as pigeon;
import 'package:mediahro/platform/system_integration.dart';

/// [SystemIntegrationFacade] on Android (CORE-003, SYS-004): files and links
/// from "Open with" and the share sheet, held from a cold start until
/// [openRequests] is listened to (`SystemModules.kt`). Window members do
/// nothing on Android (the system manages windows, CORE-010 is desktop),
/// and updates come from the store or F-Droid, so [checkForUpdate] is null.
final class AndroidSystemIntegration implements SystemIntegrationFacade {
  AndroidSystemIntegration({
    pigeon.SystemHostApi? api,
    Stream<pigeon.OpenRequestMsg> Function()? events,
  }) : _api = api ?? pigeon.SystemHostApi(),
       _events = events ?? pigeon.openRequests;

  final pigeon.SystemHostApi _api;
  final Stream<pigeon.OpenRequestMsg> Function() _events;

  @override
  late final Stream<List<Uri>> openRequests = _events().map(
    (m) => m.uris.map(Uri.parse).toList(),
  );

  @override
  Future<void> showDefaultAppGuidance() => _api.showDefaultAppGuidance();

  @override
  Future<void> setAlwaysOnTop({required bool enabled}) async {}

  @override
  Future<WindowFrame?> windowFrame() async => null;

  @override
  Future<void> setWindowFrame(WindowFrame frame) async {}

  @override
  Future<UpdateInfo?> checkForUpdate() async => null;
}

/// [IntentsFacade] on Android (SYS-003): launcher shortcuts (also suggested
/// to the Assistant) and the App Actions in `res/xml/shortcuts.xml`
/// ("open music in Mediahro", "search for … in Mediahro", "Resume").
final class AndroidIntents implements IntentsFacade {
  AndroidIntents({
    pigeon.IntentsHostApi? api,
    Stream<pigeon.AppIntentMsg> Function()? events,
  }) : _api = api ?? pigeon.IntentsHostApi(),
       _events = events ?? pigeon.appIntents;

  final pigeon.IntentsHostApi _api;
  final Stream<pigeon.AppIntentMsg> Function() _events;

  @override
  late final Stream<AppIntent> incoming = _events().map(
    (m) => AppIntent(AppIntentKind.values[m.kind.index], argument: m.argument),
  );

  @override
  Future<void> publishShortcuts(List<AppShortcut> shortcuts) =>
      _api.publishShortcuts([
        for (final s in shortcuts)
          pigeon.AppShortcutMsg(
            id: s.id,
            title: s.title,
            kind: pigeon.AppIntentKindMsg.values[s.intent.kind.index],
            argument: s.intent.argument,
          ),
      ]);
}
