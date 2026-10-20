import 'package:mediahro/platform/android/gen/car_api.pigeon.dart';
import 'package:mediahro/platform/car_and_alarms.dart';

/// [MediaBrowseFacade] on Android (MUS-013): Android Auto and the Assistant
/// browse, search and play through the Media3 library session, which asks
/// the registered [MediaBrowseProvider] (`BrowseCallback.kt`).
final class AndroidMediaBrowse implements MediaBrowseFacade {
  AndroidMediaBrowse({MediaBrowseHostApi? api})
    : _api = api ?? MediaBrowseHostApi();

  final MediaBrowseHostApi _api;

  @override
  Future<void> register(MediaBrowseProvider provider) async {
    MediaBrowseFlutterApi.setUp(_ProviderAdapter(provider));
    await _api.registered();
  }

  @override
  Future<void> notifyChildrenChanged(String nodeId) =>
      _api.notifyChildrenChanged(nodeId);
}

final class _ProviderAdapter implements MediaBrowseFlutterApi {
  _ProviderAdapter(this.provider);

  final MediaBrowseProvider provider;

  @override
  Future<List<MediaBrowseNodeMsg>> children(String nodeId, int page) async =>
      (await provider.children(nodeId, page: page)).map(_msg).toList();

  @override
  Future<List<MediaBrowseNodeMsg>> search(String query) async =>
      (await provider.search(query)).map(_msg).toList();

  @override
  Future<void> play(String nodeId) => provider.play(nodeId);

  static MediaBrowseNodeMsg _msg(MediaBrowseNode n) => MediaBrowseNodeMsg(
    id: n.id,
    title: n.title,
    subtitle: n.subtitle,
    artworkUri: n.artworkUri?.toString(),
    playable: n.playable,
    browsable: n.browsable,
  );
}

/// [AlarmFacade] on Android (MUS-011): `AlarmManager.setAlarmClock`; a
/// fired alarm reaches [fired] directly while the app runs, or through the
/// alarm notification that opens it (`AlarmModule.kt`). Alarms do not
/// survive a reboot: schedule them again when the player starts.
final class AndroidAlarms implements AlarmFacade {
  AndroidAlarms({AlarmHostApi? api, Stream<AlarmFiredMsg> Function()? events})
    : _api = api ?? AlarmHostApi(),
      _events = events ?? alarmsFired;

  final AlarmHostApi _api;
  final Stream<AlarmFiredMsg> Function() _events;

  @override
  Future<bool> isSupported() => _api.isSupported();

  @override
  Future<void> schedule(ScheduledAlarm alarm) => _api.schedule(
    ScheduledAlarmMsg(
      id: alarm.id,
      atMs: alarm.at.millisecondsSinceEpoch,
      label: alarm.label,
    ),
  );

  @override
  Future<void> cancel(String id) => _api.cancel(id);

  @override
  late final Stream<String> fired = _events().map((e) => e.id);
}
