import 'package:meta/meta.dart';

/// Browse tree for car and voice surfaces (MUS-013): Android Auto through
/// the Media3 `MediaLibraryService` (A) and CarPlay templates (I). The app
/// registers one [MediaBrowseProvider]; native code calls back into it.
abstract interface class MediaBrowseFacade {
  Future<void> register(MediaBrowseProvider provider);

  /// Tells the car UI that [nodeId]'s children changed.
  Future<void> notifyChildrenChanged(String nodeId);
}

/// Implemented in Dart (C2); the root id is `MediaBrowseNode.rootId`.
abstract interface class MediaBrowseProvider {
  Future<List<MediaBrowseNode>> children(String nodeId, {int page = 0});

  /// Voice and car search ("play … by …").
  Future<List<MediaBrowseNode>> search(String query);

  /// Starts playback of a playable node (or of a browsable node's contents).
  Future<void> play(String nodeId);
}

@immutable
final class MediaBrowseNode {
  const MediaBrowseNode({
    required this.id,
    required this.title,
    required this.playable,
    required this.browsable,
    this.subtitle,
    this.artworkUri,
  });

  static const rootId = 'root';

  final String id;
  final String title;
  final String? subtitle;
  final Uri? artworkUri;
  final bool playable;
  final bool browsable;
}

/// Wake-up alarms that start music (MUS-011): AlarmManager
/// `setAlarmClock` (A), AlarmKit where available or a time-sensitive
/// notification (I), Task Scheduler wake timers / notifications (M W).
abstract interface class AlarmFacade {
  Future<bool> isSupported();

  /// Schedules `alarm`, replacing any alarm with the same id.
  Future<void> schedule(ScheduledAlarm alarm);

  Future<void> cancel(String id);

  /// Fires when an alarm goes off while the app can run (or on launch from
  /// the alarm).
  Stream<String> get fired;
}

@immutable
final class ScheduledAlarm {
  const ScheduledAlarm({
    required this.id,
    required this.at,
    required this.label,
    this.repeatWeekdays = const {},
  });

  final String id;

  /// Local wall-clock time of the next firing.
  final DateTime at;
  final String label;

  /// ISO weekdays (1 = Monday) to repeat on; empty for one-off.
  final Set<int> repeatWeekdays;
}
