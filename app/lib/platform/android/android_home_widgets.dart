import 'package:mediahro/platform/android/gen/widget_api.pigeon.dart';
import 'package:mediahro/platform/media_session.dart';
import 'package:mediahro/platform/system_integration.dart';

/// [HomeWidgetsFacade] on Android (MUS-012): the now-playing home-screen
/// and lock-screen widget with artwork and previous / play-pause / next
/// (`NowPlayingWidget.kt`). Its buttons arrive as [RemoteCommand]s on
/// `MediaSessionFacade.commands` while the app runs.
final class AndroidHomeWidgets implements HomeWidgetsFacade {
  AndroidHomeWidgets({HomeWidgetsHostApi? api})
    : _api = api ?? HomeWidgetsHostApi();

  final HomeWidgetsHostApi _api;

  @override
  Future<void> update(NowPlaying? item, {required bool playing}) => _api.update(
    item == null
        ? null
        : WidgetStateMsg(
            title: item.title,
            artist: item.artist,
            artwork: item.artwork,
            playing: playing,
          ),
  );
}
