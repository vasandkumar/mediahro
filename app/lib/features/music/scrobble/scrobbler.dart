import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:drift/drift.dart';
import 'package:mediahro/core/db/library_database.dart';
import 'package:mediahro/core/net/network_policy.dart';
import 'package:mediahro/features/music/library/music_library.dart';
import 'package:mediahro/features/music/player/music_player.dart';
import 'package:mediahro/features/music/player/music_prefs.dart';
import 'package:mediahro/features/music/scrobble/scrobble_services.dart';
import 'package:mediahro_engine/mediahro_engine.dart';

/// Scrobbling (MUS-009): a song counts once it has played for half its
/// length or four minutes, whichever comes first (songs under 30 s never
/// count). Listens wait in the `scrobble_queue` table until they are sent,
/// so they survive being offline and app restarts. Each service can be
/// switched on and off, and sources can be excluded.
final class Scrobbler {
  Scrobbler({
    required this.db,
    required this.prefs,
    required this.player,
    required this.services,
    DateTime Function()? clock,
    this.retryEvery = const Duration(minutes: 5),
  }) : _clock = clock ?? DateTime.now;

  final LibraryDatabase db;
  final MusicPrefs prefs;
  final MusicPlayer player;
  final List<ScrobbleService> services;
  final DateTime Function() _clock;
  final Duration retryEvery;

  StreamSubscription<MusicPlayerState>? _sub;
  Timer? _retry;
  bool _flushing = false;
  bool _disposed = false;
  Future<void> _chain = Future.value();

  // The song being timed.
  int? _itemId;
  int? _engineItem;
  MusicTrack? _track;
  late DateTime _startedAt;
  Duration _listened = Duration.zero;
  Duration? _lastPos;
  bool _counted = false;

  void start() {
    if (services.isEmpty) return;
    // One state at a time, in order.
    _sub ??= player.states.listen(
      (s) => _chain = _chain.then((_) => _onState(s)).onError((_, _) {}),
    );
    unawaited(flush());
  }

  Future<void> dispose() async {
    _disposed = true;
    await _sub?.cancel();
    _retry?.cancel();
  }

  /// Tries again later while listens are waiting (offline, server error).
  void _retryLater() {
    if (_disposed || (_retry?.isActive ?? false)) return;
    _retry = Timer(retryEvery, () => unawaited(flush()));
  }

  // ------------------------------------------------------------ settings --

  Future<Set<String>> enabledServices() async => {
    for (final v in await prefs.readList('scrobble.services') ?? const [])
      if (v is String) v,
  };

  Future<void> setEnabled(String service, {required bool enabled}) async {
    final s = await enabledServices();
    enabled ? s.add(service) : s.remove(service);
    await prefs.write('scrobble.services', s.toList()..sort());
  }

  /// Library sources whose songs are never scrobbled.
  Future<Set<int>> excludedSources() async => {
    for (final v in await prefs.readList('scrobble.excludeSources') ?? const [])
      if (v is int) v,
  };

  Future<void> setSourceExcluded(int sourceId, {required bool excluded}) async {
    final s = await excludedSources();
    excluded ? s.add(sourceId) : s.remove(sourceId);
    await prefs.write('scrobble.excludeSources', s.toList()..sort());
  }

  /// Listens waiting to be sent, per service.
  Future<Map<String, int>> pending() async {
    final rows = await db
        .customSelect(
          'SELECT service, count(*) AS n FROM scrobble_queue GROUP BY service',
          readsFrom: {db.scrobbleQueue},
        )
        .get();
    return {for (final r in rows) r.read<String>('service'): r.read<int>('n')};
  }

  // -------------------------------------------------------------- timing --

  Future<void> _onState(MusicPlayerState s) async {
    final t = s.live ? null : s.current;
    final status = s.playback.status;
    final newSong = t?.itemId != _itemId || s.playback.item != _engineItem;
    if (newSong) {
      await _finishCurrent();
      _itemId = t?.itemId;
      _engineItem = s.playback.item;
      _track = t;
      _startedAt = _clock().toUtc();
      _listened = Duration.zero;
      _lastPos = null;
      _counted = false;
      if (t != null && status == PlaybackStatus.playing) {
        unawaited(_nowPlaying(t));
      }
    }
    if (t == null) return;
    final pos = s.playback.position;
    if (status == PlaybackStatus.playing) {
      final last = _lastPos;
      if (last != null) {
        final d = pos - last;
        // Count real playback only: no seeks or jumps.
        if (d > Duration.zero && d < const Duration(seconds: 5)) {
          _listened += d;
        }
      }
      _lastPos = pos;
      if (!_counted && _eligible(t, _listened)) {
        _counted = true;
        await _enqueue(t, _startedAt);
      }
    } else {
      _lastPos = null;
      if (status == PlaybackStatus.ended &&
          !_counted &&
          _eligible(t, t.duration ?? _listened)) {
        _counted = true;
        await _enqueue(t, _startedAt);
      }
    }
  }

  Future<void> _finishCurrent() async {
    final t = _track;
    if (t == null || _counted) return;
    if (_eligible(t, _listened)) {
      _counted = true;
      await _enqueue(t, _startedAt);
    }
  }

  static bool _eligible(MusicTrack t, Duration listened) {
    final d = t.duration;
    if (d == null || d < const Duration(seconds: 30)) return false;
    final need = Duration(
      milliseconds: math.min(d.inMilliseconds ~/ 2, 240000),
    );
    return listened >= need;
  }

  ScrobbleTrack? _scrobble(MusicTrack t, DateTime at) {
    final artist = t.artist ?? t.albumArtist;
    if (artist == null || artist.trim().isEmpty) return null;
    return ScrobbleTrack(
      artist: artist,
      title: t.title,
      album: t.album,
      albumArtist: t.albumArtist,
      duration: t.duration,
      trackNumber: t.trackNumber,
      playedAt: at,
    );
  }

  Future<void> _nowPlaying(MusicTrack t) async {
    if ((await excludedSources()).contains(t.sourceId)) return;
    final s = _scrobble(t, _clock().toUtc());
    if (s == null) return;
    final on = await enabledServices();
    for (final svc in services) {
      if (!on.contains(svc.id) || !await svc.connected()) continue;
      try {
        await svc.nowPlaying(s);
      } on Exception {
        // "Now playing" is best effort.
      }
    }
  }

  Future<void> _enqueue(MusicTrack t, DateTime at) async {
    if ((await excludedSources()).contains(t.sourceId)) return;
    final s = _scrobble(t, at);
    if (s == null) return;
    final on = await enabledServices();
    if (on.isEmpty) return;
    await db.batch((b) {
      b.insertAll(db.scrobbleQueue, [
        for (final svc in services)
          if (on.contains(svc.id))
            ScrobbleQueueCompanion.insert(
              itemId: Value(t.itemId),
              service: svc.id,
              payload: jsonEncode(s.toJson()),
              playedAt: at,
            ),
      ]);
    });
    unawaited(flush());
  }

  // ------------------------------------------------------------- sending --

  /// Sends queued listens. Stops at the first auth problem per service
  /// (the user signs in again) and leaves the rest for the next try when
  /// offline or when the endpoint is switched off.
  Future<void> flush() async {
    if (_flushing || _disposed || services.isEmpty) return;
    _flushing = true;
    try {
      final on = await enabledServices();
      for (final svc in services) {
        if (!on.contains(svc.id) || !await svc.connected()) continue;
        while (true) {
          final rows =
              await (db.select(db.scrobbleQueue)
                    ..where((q) => q.service.equals(svc.id))
                    ..orderBy([(q) => OrderingTerm.asc(q.playedAt)])
                    ..limit(svc.batchSize))
                  .get();
          if (rows.isEmpty) break;
          final listens = <ScrobbleTrack>[];
          final ids = <int>[];
          for (final r in rows) {
            final t = ScrobbleTrack.fromJson(_decode(r.payload));
            if (t == null) {
              await (db.delete(
                db.scrobbleQueue,
              )..where((q) => q.id.equals(r.id))).go();
              continue;
            }
            listens.add(t);
            ids.add(r.id);
          }
          if (listens.isEmpty) continue;
          try {
            await svc.submit(listens);
            await (db.delete(
              db.scrobbleQueue,
            )..where((q) => q.id.isIn(ids))).go();
          } on ScrobbleError catch (e) {
            await _bump(ids);
            if (e.auth) {
              await setEnabled(svc.id, enabled: false);
            } else {
              _retryLater();
            }
            break;
          } on NetworkBlocked {
            _retryLater();
            break;
          } on Exception {
            await _bump(ids);
            _retryLater();
            break;
          }
        }
      }
    } finally {
      _flushing = false;
    }
  }

  Future<void> _bump(List<int> ids) => db.customStatement(
    'UPDATE scrobble_queue SET attempts = attempts + 1 WHERE id IN (${ids.join(',')})',
  );

  static Object? _decode(String s) {
    try {
      return jsonDecode(s);
    } on FormatException {
      return null;
    }
  }
}
