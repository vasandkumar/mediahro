import 'dart:async';
import 'dart:math' as math;

import 'package:drift/drift.dart';
import 'package:mediahro/core/db/library_database.dart';
import 'package:mediahro/features/music/library/music_library.dart';
import 'package:mediahro/features/music/player/music_player.dart';
import 'package:mediahro/features/music/player/music_prefs.dart';
import 'package:mediahro/platform/platform_facades.dart';
import 'package:mediahro_engine/mediahro_engine.dart';
import 'package:meta/meta.dart';

/// A wake-up alarm that plays music (MUS-011): at [hour]:[minute] local
/// time, on [weekdays] (ISO, 1 = Monday; empty = once), playing
/// [playlistId] (or the current queue when null), fading in over [fadeIn].
@immutable
final class WakeAlarm {
  const WakeAlarm({
    required this.id,
    required this.hour,
    required this.minute,
    this.weekdays = const {},
    this.playlistId,
    this.label = '',
    this.enabled = true,
    this.shuffle = false,
    this.fadeIn = const Duration(seconds: 60),
  });

  final String id;
  final int hour;
  final int minute;
  final Set<int> weekdays;
  final int? playlistId;
  final String label;
  final bool enabled;
  final bool shuffle;
  final Duration fadeIn;

  /// Next firing strictly after [now] (local time).
  DateTime nextAfter(DateTime now) {
    for (var i = 0; i < 8; i++) {
      final candidate = DateTime(
        now.year,
        now.month,
        now.day + i,
        hour,
        minute,
      );
      if (!candidate.isAfter(now)) continue;
      if (weekdays.isEmpty || weekdays.contains(candidate.weekday)) {
        return candidate;
      }
    }
    return DateTime(now.year, now.month, now.day + 7, hour, minute);
  }

  WakeAlarm copyWith({
    int? hour,
    int? minute,
    Set<int>? weekdays,
    int? Function()? playlistId,
    String? label,
    bool? enabled,
    bool? shuffle,
    Duration? fadeIn,
  }) => WakeAlarm(
    id: id,
    hour: hour ?? this.hour,
    minute: minute ?? this.minute,
    weekdays: weekdays ?? this.weekdays,
    playlistId: playlistId == null ? this.playlistId : playlistId(),
    label: label ?? this.label,
    enabled: enabled ?? this.enabled,
    shuffle: shuffle ?? this.shuffle,
    fadeIn: fadeIn ?? this.fadeIn,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'hour': hour,
    'minute': minute,
    'weekdays': weekdays.toList()..sort(),
    'playlistId': playlistId,
    'label': label,
    'enabled': enabled,
    'shuffle': shuffle,
    'fadeInMs': fadeIn.inMilliseconds,
  };

  static WakeAlarm? fromJson(Object? j) {
    if (j is! Map<String, Object?>) return null;
    final id = j['id'];
    final h = jsonInt(j['hour']);
    final m = jsonInt(j['minute']);
    if (id is! String || h == null || m == null) return null;
    return WakeAlarm(
      id: id,
      hour: h.clamp(0, 23),
      minute: m.clamp(0, 59),
      weekdays: {
        if (j['weekdays'] case final List<Object?> l)
          for (final d in l)
            if (jsonInt(d) case final int v when v >= 1 && v <= 7) v,
      },
      playlistId: jsonInt(j['playlistId']),
      label: j['label'] is String ? j['label']! as String : '',
      enabled: j['enabled'] != false,
      shuffle: j['shuffle'] == true,
      fadeIn: Duration(milliseconds: jsonInt(j['fadeInMs']) ?? 60000),
    );
  }
}

/// Stores alarms, keeps them scheduled with the OS ([AlarmFacade]) and
/// plays music when one fires.
final class WakeAlarms {
  WakeAlarms({
    required this.facade,
    required this.prefs,
    required this.player,
    required this.engine,
    required this.db,
    required this.library,
    DateTime Function()? clock,
    this.fadeStep = const Duration(milliseconds: 500),
  }) : _clock = clock ?? DateTime.now;

  final AlarmFacade facade;
  final MusicPrefs prefs;
  final MusicPlayer player;
  final PlaybackEngine engine;
  final LibraryDatabase db;
  final MusicLibrary library;
  final DateTime Function() _clock;
  final Duration fadeStep;

  final _changes = StreamController<List<WakeAlarm>>.broadcast();
  StreamSubscription<String>? _fired;
  List<WakeAlarm> _alarms = const [];

  List<WakeAlarm> get alarms => _alarms;
  Stream<List<WakeAlarm>> get changes => _changes.stream;

  Future<void> start() async {
    _alarms = [
      for (final j in await prefs.readList('alarms') ?? const <Object?>[])
        ?WakeAlarm.fromJson(j),
    ];
    _fired ??= facade.fired.listen((id) => unawaited(onFired(id)));
    await _scheduleAll();
  }

  Future<void> dispose() async {
    await _fired?.cancel();
    await _changes.close();
  }

  Future<void> save(WakeAlarm alarm) async {
    _alarms =
        [
          for (final a in _alarms)
            if (a.id != alarm.id) a,
          alarm,
        ]..sort(
          (a, b) => (a.hour * 60 + a.minute).compareTo(b.hour * 60 + b.minute),
        );
    await _persist();
    await _schedule(alarm);
  }

  Future<void> delete(String id) async {
    _alarms = [
      for (final a in _alarms)
        if (a.id != id) a,
    ];
    await _persist();
    await facade.cancel(id);
  }

  /// A new alarm id.
  String newId() =>
      'music-${_clock().microsecondsSinceEpoch}-${math.Random().nextInt(1 << 20)}';

  /// The OS fired [id]: play its music with a fade-in, then schedule the
  /// next repeat (one-off alarms turn off).
  Future<void> onFired(String id) async {
    final alarm = _alarms.where((a) => a.id == id).firstOrNull;
    if (alarm == null) return;
    if (alarm.weekdays.isEmpty) {
      await save(alarm.copyWith(enabled: false));
    } else {
      await _schedule(alarm);
    }
    final volume = engine.current.volume;
    await engine.setVolume(0);
    final pid = alarm.playlistId;
    if (pid != null) {
      final rows =
          await (db.select(db.playlistItems)
                ..where((p) => p.playlistId.equals(pid))
                ..orderBy([(p) => OrderingTerm.asc(p.position)]))
              .get();
      final tracks = await library.tracksByIds([
        for (final r in rows)
          if (r.itemId != null) r.itemId!,
      ]);
      if (tracks.isNotEmpty) {
        await player.playTracks(tracks, shuffle: alarm.shuffle);
      } else {
        await player.play();
      }
    } else {
      await player.play();
    }
    await _fadeIn(volume <= 0 ? 1 : volume, alarm.fadeIn);
  }

  Future<void> _fadeIn(double target, Duration length) async {
    final steps = math.max(1, length.inMilliseconds ~/ fadeStep.inMilliseconds);
    for (var i = 1; i <= steps; i++) {
      await engine.setVolume(target * i / steps);
      if (i < steps) await Future<void>.delayed(fadeStep);
    }
  }

  Future<void> _scheduleAll() async {
    for (final a in _alarms) {
      await _schedule(a);
    }
  }

  Future<void> _schedule(WakeAlarm a) async {
    if (!a.enabled) {
      await facade.cancel(a.id);
      return;
    }
    await facade.schedule(
      ScheduledAlarm(
        id: a.id,
        at: a.nextAfter(_clock()),
        label: a.label,
        repeatWeekdays: a.weekdays,
      ),
    );
  }

  Future<void> _persist() async {
    await prefs.write('alarms', [for (final a in _alarms) a.toJson()]);
    if (!_changes.isClosed) _changes.add(_alarms);
  }
}
