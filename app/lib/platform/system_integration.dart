import 'package:mediahro/platform/media_session.dart';
import 'package:meta/meta.dart';

/// App-level OS integration: files handed to the app (CORE-003 open-with,
/// SYS-004 share targets, CORE-004 drops), windows (CORE-010) and the signed
/// self-updater for direct builds (CORE-012).
abstract interface class SystemIntegrationFacade {
  /// Files/URLs from open-with, share sheet, Services, "Send to", drops.
  Stream<List<Uri>> get openRequests;

  /// OS "default apps" page or per-OS guidance.
  Future<void> showDefaultAppGuidance();
  Future<void> setAlwaysOnTop({required bool enabled});
  Future<WindowFrame?> windowFrame();
  Future<void> setWindowFrame(WindowFrame frame);

  /// Signed-appcast update check; only when `Capabilities.selfUpdater`.
  Future<UpdateInfo?> checkForUpdate();
}

@immutable
final class WindowFrame {
  const WindowFrame(this.x, this.y, this.width, this.height);
  final double x;
  final double y;
  final double width;
  final double height;
}

@immutable
final class UpdateInfo {
  const UpdateInfo({required this.version, required this.releaseNotes});
  final String version;
  final String releaseNotes;
}

/// Shortcuts and intents (SYS-003): App Intents / Siri (I M), App Actions /
/// Assistant (A), jump lists (W).
abstract interface class IntentsFacade {
  Stream<AppIntent> get incoming;
  Future<void> publishShortcuts(List<AppShortcut> shortcuts);
}

enum AppIntentKind { resumeLast, playPlaylist, openMode, search }

@immutable
final class AppIntent {
  const AppIntent(this.kind, {this.argument});
  final AppIntentKind kind;
  final String? argument;
}

@immutable
final class AppShortcut {
  const AppShortcut({
    required this.id,
    required this.title,
    required this.intent,
  });
  final String id;
  final String title;
  final AppIntent intent;
}

/// Widgets and quick controls (MUS-012): home-screen widgets (A), WidgetKit
/// and Live Activities (I), menu-bar extra (M), taskbar thumbnail toolbar (W).
abstract interface class HomeWidgetsFacade {
  Future<void> update(NowPlaying? item, {required bool playing});
}
