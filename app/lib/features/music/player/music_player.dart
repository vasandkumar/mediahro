import 'dart:async';

import 'package:mediahro/core/library/progress.dart';
import 'package:mediahro/core/library/queues.dart';
import 'package:mediahro/features/music/library/music_files.dart';
import 'package:mediahro/features/music/library/music_library.dart';
import 'package:mediahro_engine/mediahro_engine.dart';
import 'package:meta/meta.dart';

/// Snapshot of the music player for the UI, mini player and media session.
@immutable
final class MusicPlayerState {
  const MusicPlayerState({
    this.queue = const [],
    this.index = 0,
    this.playback = const PlaybackState(),
    this.repeat = RepeatMode.off,
    this.shuffle = false,
    this.queueId,
    this.restoredPosition,
  });

  final List<MusicTrack> queue;
  final int index;
  final PlaybackState playback;
  final RepeatMode repeat;
  final bool shuffle;
  final int? queueId;

  /// Resume point of a queue restored after relaunch, before playback
  /// starts again.
  final Duration? restoredPosition;

  MusicTrack? get current =>
      index >= 0 && index < queue.length ? queue[index] : null;

  bool get playing =>
      playback.status == PlaybackStatus.playing ||
      playback.status == PlaybackStatus.buffering ||
      playback.status == PlaybackStatus.opening;

  bool get hasNext => repeat != RepeatMode.off || index + 1 < queue.length;
  bool get hasPrevious => queue.isNotEmpty;

  Duration get position => restoredPosition ?? playback.position;
  Duration? get duration => playback.duration ?? current?.duration;

  MusicPlayerState copyWith({
    List<MusicTrack>? queue,
    int? index,
    PlaybackState? playback,
    RepeatMode? repeat,
    bool? shuffle,
    int? queueId,
    Duration? Function()? restoredPosition,
  }) => MusicPlayerState(
    queue: queue ?? this.queue,
    index: index ?? this.index,
    playback: playback ?? this.playback,
    repeat: repeat ?? this.repeat,
    shuffle: shuffle ?? this.shuffle,
    queueId: queueId ?? this.queueId,
    restoredPosition: restoredPosition == null
        ? this.restoredPosition
        : restoredPosition(),
  );
}

/// Plays music on the pool's music engine (docs/05 §4.4) from a persisted
/// queue (MUS-007, B2's [QueueRepository]) with gapless hand-off: the next
/// track is always prepared with [PlaybackEngine.setNext] (AUD-002/003), and
/// the engine's item counter tells the player when it advanced by itself.
final class MusicPlayer {
  MusicPlayer({
    required this.engine,
    required this.queues,
    required this.library,
    required this.files,
    this.progress,
    this.openTimeout = const Duration(seconds: 3),
  });

  final PlaybackEngine engine;
  final QueueRepository queues;
  final MusicLibrary library;
  final MusicFiles files;
  final ProgressRepository? progress;
  final Duration openTimeout;

  final _states = StreamController<MusicPlayerState>.broadcast();
  MusicPlayerState _state = const MusicPlayerState();
  StreamSubscription<PlaybackState>? _sub;
  Future<void> _ops = Future.value();
  int _currentItem = 0;
  int? _preparedIndex;
  int? _endedItem;
  bool _busy = false;
  Duration _lastPosition = Duration.zero;
  Timer? _saveTimer;
  bool _disposed = false;

  MusicPlayerState get state => _state;

  /// Current state first, then every change.
  Stream<MusicPlayerState> get states => Stream.multi((l) {
    l.add(_state);
    final s = _states.stream.listen(l.add, onDone: l.close);
    l.onCancel = s.cancel;
  });

  /// Restores the active audio queue (not playing) and follows the engine.
  Future<void> init() async {
    _sub ??= engine.state.listen(_onEngine);
    final active = await queues.active(QueueMode.audio);
    if (active == null) return;
    final q = await queues.load(active.id);
    final tracks = await library.tracksByIds([
      for (final e in q.entries)
        if (e.itemId != null) e.itemId!,
    ]);
    if (tracks.isEmpty) return;
    _emit(
      _state.copyWith(
        queue: tracks,
        index: q.currentIndex.clamp(0, tracks.length - 1),
        queueId: active.id,
        repeat: RepeatMode.values.byName(q.row.repeat),
        shuffle: q.row.shuffle,
        restoredPosition: () => Duration(milliseconds: q.row.positionMs),
      ),
    );
  }

  // ---------------------------------------------------------------- queue --

  /// Replaces the queue with [tracks] and plays from [start].
  Future<void> playTracks(
    List<MusicTrack> tracks, {
    int start = 0,
    bool shuffle = false,
  }) => _serial(() async {
    if (tracks.isEmpty) return;
    final id = await _queueId();
    await queues.replace(id, [
      for (final t in tracks) t.itemId,
    ], startIndex: start);
    await queues.shuffle(id, enabled: shuffle);
    await _reload(id);
    await _openCurrent();
  });

  /// "Play next": after the current track.
  Future<void> playNext(List<MusicTrack> tracks) => _serial(() async {
    if (_state.queue.isEmpty) {
      await _replaceAndOpen(tracks);
      return;
    }
    final id = await _queueId();
    await queues.playNext(id, [for (final t in tracks) t.itemId]);
    await _reload(id);
    await _prepareNext();
  });

  /// "Add to queue": at the end.
  Future<void> addToQueue(List<MusicTrack> tracks) => _serial(() async {
    if (_state.queue.isEmpty) {
      await _replaceAndOpen(tracks);
      return;
    }
    final id = await _queueId();
    await queues.append(id, [for (final t in tracks) t.itemId]);
    await _reload(id);
    await _prepareNext();
  });

  Future<void> removeAt(int index) => _serial(() async {
    final id = _state.queueId;
    if (id == null || index < 0 || index >= _state.queue.length) return;
    final wasCurrent = index == _state.index;
    await queues.removeAt(id, index);
    await _reload(id);
    if (_state.queue.isEmpty) {
      await engine.stop();
    } else if (wasCurrent) {
      await _openCurrent(autoplay: _state.playing);
    } else {
      await _prepareNext();
    }
  });

  Future<void> move(int from, int to) => _serial(() async {
    final id = _state.queueId;
    if (id == null) return;
    await queues.move(id, from, to);
    await _reload(id);
    await _prepareNext();
  });

  /// Plays the queue entry at [index].
  Future<void> jumpTo(int index) => _serial(() async {
    final id = _state.queueId;
    if (id == null || index < 0 || index >= _state.queue.length) return;
    await queues.savePosition(id, index, Duration.zero);
    _emit(_state.copyWith(index: index, restoredPosition: () => null));
    await _openCurrent();
  });

  Future<void> setRepeat(RepeatMode mode) => _serial(() async {
    final id = _state.queueId;
    if (id != null) await queues.setRepeat(id, mode);
    _emit(_state.copyWith(repeat: mode));
    await _prepareNext();
  });

  Future<void> setShuffle({required bool enabled}) => _serial(() async {
    final id = _state.queueId;
    if (id == null) return;
    await queues.shuffle(id, enabled: enabled);
    await _reload(id);
    await _prepareNext();
  });

  // ------------------------------------------------------------ transport --

  Future<void> play() => _serial(() async {
    if (_state.current == null) return;
    final s = engine.current.status;
    if (s == PlaybackStatus.idle ||
        s == PlaybackStatus.error ||
        (s == PlaybackStatus.ended && !_state.playback.nextPrepared) ||
        _state.restoredPosition != null) {
      await _openCurrent(start: _state.restoredPosition);
    } else {
      await engine.play();
    }
  });

  Future<void> pause() => _serial(engine.pause);

  Future<void> togglePlayPause() => _state.playing ? pause() : play();

  Future<void> seek(Duration to) => _serial(() async {
    if (_state.restoredPosition != null) {
      _emit(_state.copyWith(restoredPosition: () => to));
      return;
    }
    await engine.seek(to, mode: SeekMode.exact);
  });

  Future<void> next() => _serial(() async {
    if (_state.queue.isEmpty) return;
    if (_preparedIndex != null && engine.current.nextPrepared) {
      final to = _preparedIndex!;
      await _awaitItem(engine.skipToNext);
      await _advanced(to, manual: true);
      return;
    }
    final n = _nextIndex(manual: true);
    if (n == null) return;
    await _recordFinished(manual: true);
    _emit(_state.copyWith(index: n, restoredPosition: () => null));
    await _openCurrent();
  });

  /// Restarts the track after 3 s, otherwise goes to the previous one.
  Future<void> previous() => _serial(() async {
    if (_state.queue.isEmpty) return;
    if (_state.position > const Duration(seconds: 3)) {
      await engine.seek(Duration.zero, mode: SeekMode.exact);
      return;
    }
    final p = _state.index > 0
        ? _state.index - 1
        : (_state.repeat == RepeatMode.all ? _state.queue.length - 1 : 0);
    _emit(_state.copyWith(index: p, restoredPosition: () => null));
    await _openCurrent();
  });

  Future<void> stop() => _serial(() async {
    await engine.stop();
    await _savePosition();
  });

  Future<void> dispose() async {
    _disposed = true;
    _saveTimer?.cancel();
    await _savePosition();
    await _sub?.cancel();
    await _states.close();
  }

  // ------------------------------------------------------------- internals --

  Future<void> _replaceAndOpen(List<MusicTrack> tracks) async {
    final id = await _queueId();
    await queues.replace(id, [for (final t in tracks) t.itemId]);
    await _reload(id);
    await _openCurrent();
  }

  Future<int> _queueId() async {
    final id = _state.queueId ?? (await queues.active(QueueMode.audio))?.id;
    if (id != null) return id;
    final created = await queues.createAudioQueue('default');
    await queues.activate(created);
    return created;
  }

  Future<void> _reload(int id) async {
    final q = await queues.load(id);
    final tracks = await library.tracksByIds([
      for (final e in q.entries)
        if (e.itemId != null) e.itemId!,
    ]);
    _emit(
      _state.copyWith(
        queue: tracks,
        index: tracks.isEmpty ? 0 : q.currentIndex.clamp(0, tracks.length - 1),
        queueId: id,
        repeat: RepeatMode.values.byName(q.row.repeat),
        shuffle: q.row.shuffle,
      ),
    );
  }

  Future<void> _openCurrent({Duration? start, bool autoplay = true}) async {
    final t = _state.current;
    if (t == null) return;
    _preparedIndex = null;
    final src = await files.mediaSource(t.sourceId, t.relPath, title: t.title);
    _lastPosition = start ?? Duration.zero;
    _emit(_state.copyWith(restoredPosition: () => null));
    await _awaitItem(
      () => engine.open(
        src,
        opts: OpenOptions(audioOnly: true, start: start, autoplay: autoplay),
      ),
    );
    final id = _state.queueId;
    if (id != null) {
      await queues.savePosition(id, _state.index, start ?? Duration.zero);
    }
    await _prepareNext();
  }

  /// Runs [op] (an open or a skip) and waits until the engine reports the
  /// new item, so its item counter is not mistaken for a natural advance.
  Future<void> _awaitItem(Future<void> Function() op) async {
    final before = engine.current.item;
    _busy = true;
    try {
      final changed = engine.state
          .firstWhere((s) => s.item != before)
          .timeout(openTimeout, onTimeout: () => engine.current);
      await op();
      final s = await changed;
      _currentItem = s.item;
    } finally {
      _busy = false;
    }
  }

  int? _nextIndex({bool manual = false}) {
    final n = _state.queue.length;
    if (n == 0) return null;
    if (_state.repeat == RepeatMode.one && !manual) return _state.index;
    if (_state.index + 1 < n) return _state.index + 1;
    if (_state.repeat != RepeatMode.off) return 0;
    return null;
  }

  Future<void> _prepareNext() async {
    final n = _nextIndex();
    final cur = _state.current;
    if (n == null || cur == null) {
      _preparedIndex = null;
      await engine.setNext(null);
      return;
    }
    final next = _state.queue[n];
    final src = await files.mediaSource(
      next.sourceId,
      next.relPath,
      title: next.title,
    );
    _preparedIndex = n;
    await engine.setNext(
      src,
      sameAlbum: cur.albumKey != null && cur.albumKey == next.albumKey,
    );
  }

  void _onEngine(PlaybackState s) {
    if (_disposed) return;
    if (s.status == PlaybackStatus.playing) _lastPosition = s.position;
    _emit(_state.copyWith(playback: s));
    if (!_busy && s.item != _currentItem && _preparedIndex != null) {
      final to = _preparedIndex!;
      _currentItem = s.item;
      unawaited(_serial(() => _advanced(to, manual: false)));
    } else if (!_busy &&
        s.status == PlaybackStatus.ended &&
        _endedItem != s.item) {
      _endedItem = s.item;
      unawaited(_serial(() => _recordFinished(manual: false)));
    }
    _scheduleSave();
  }

  /// The engine moved to the prepared track (gapless, crossfade or skip).
  Future<void> _advanced(int to, {required bool manual}) async {
    await _recordFinished(manual: manual);
    _emit(_state.copyWith(index: to, restoredPosition: () => null));
    _lastPosition = Duration.zero;
    final id = _state.queueId;
    if (id != null) await queues.savePosition(id, to, Duration.zero);
    await _prepareNext();
  }

  /// Play count, last played and a play event (LIB-015) for the track that
  /// just finished or was skipped after real listening.
  Future<void> _recordFinished({required bool manual}) async {
    final t = _state.current;
    final p = progress;
    if (t == null || p == null) return;
    final listened = manual ? _lastPosition : (t.duration ?? _lastPosition);
    if (listened < const Duration(seconds: 5)) return;
    await p.recordPlay(t.itemId, listened);
  }

  void _scheduleSave() {
    _saveTimer ??= Timer(const Duration(seconds: 5), () {
      _saveTimer = null;
      unawaited(_savePosition());
    });
  }

  /// Best effort: the play head is saved again within seconds, and the
  /// database may already be closed while the app shuts down.
  Future<void> _savePosition() async {
    final id = _state.queueId;
    if (id == null || _state.current == null) return;
    try {
      await queues.savePosition(id, _state.index, _state.position);
    } on Object {
      // Next save or the next transition writes it.
    }
  }

  Future<void> _serial(Future<void> Function() op) {
    final f = _ops.then((_) => op());
    _ops = f.catchError((Object _) {});
    return f;
  }

  void _emit(MusicPlayerState s) {
    _state = s;
    if (!_states.isClosed) _states.add(s);
  }
}
