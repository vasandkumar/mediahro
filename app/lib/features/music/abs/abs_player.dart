import 'dart:async';

import 'package:mediahro/features/music/abs/abs_account.dart';
import 'package:mediahro/features/music/abs/abs_service.dart';
import 'package:mediahro/features/music/abs/abs_store.dart';
import 'package:mediahro/features/music/player/music_dsp.dart';
import 'package:mediahro/features/music/player/music_player.dart';
import 'package:mediahro/features/music/player/spoken_mode.dart';
import 'package:mediahro_engine/mediahro_engine.dart';
import 'package:mediahro_servers/mediahro_servers.dart';
import 'package:meta/meta.dart';

/// What the Audiobookshelf player shows (POD-003).
@immutable
final class AbsPlayerState {
  const AbsPlayerState({
    this.account,
    this.item,
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.speed = 1,
    this.skipSilence = false,
    this.playing = false,
    this.offline = false,
    this.chapters = const [],
    this.artPath,
  });

  final AbsAccount? account;
  final ServerItem? item;
  final Duration position;
  final Duration duration;
  final double speed;
  final bool skipSilence;
  final bool playing;

  /// Playing the downloaded copy.
  final bool offline;

  /// From the file itself (the engine reads them while it plays).
  final List<Chapter> chapters;
  final String? artPath;

  bool get active => item != null;

  AbsPlayerState copyWith({
    Duration? position,
    Duration? duration,
    double? speed,
    bool? skipSilence,
    bool? playing,
    List<Chapter>? chapters,
  }) => AbsPlayerState(
    account: account,
    item: item,
    artPath: artPath,
    offline: offline,
    position: position ?? this.position,
    duration: duration ?? this.duration,
    speed: speed ?? this.speed,
    skipSilence: skipSilence ?? this.skipSilence,
    playing: playing ?? this.playing,
    chapters: chapters ?? this.chapters,
  );
}

/// Plays Audiobookshelf books and podcast episodes on the music player
/// (POD-003): from where the server says the listener is, tells the server
/// as they listen, remembers speed and silence per item, plays the offline
/// copy when there is one, and carries on with the next item of the list it
/// was started from.
///
/// The server keeps the place. If it cannot be reached when the listener
/// pauses, the place is kept here and told to the server next time; until
/// then it is this device's place that counts.
final class AbsPlayer {
  AbsPlayer({
    required this.player,
    required this.engine,
    required this.dsp,
    required this.service,
    this.holdAtEnd,
    this.syncEvery = const Duration(seconds: 30),
    SpokenMode? mode,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now,
       _mode = mode ?? SpokenMode();

  final MusicPlayer player;
  final PlaybackEngine engine;
  final MusicDsp dsp;
  final AbsService service;

  /// True while a sleep timer wants playback to stop at the end of this
  /// item: the next one is not started.
  final bool Function()? holdAtEnd;
  final Duration syncEvery;
  final DateTime Function() _clock;
  final SpokenMode _mode;

  AbsStore get _store => service.store;

  /// An item counts as finished with this much left (or less).
  static const finishedWithin = Duration(seconds: 20);

  /// Earlier than this into an item is not a place worth keeping.
  static const minPlace = Duration(seconds: 5);

  final _states = StreamController<AbsPlayerState>.broadcast();
  AbsPlayerState _state = const AbsPlayerState();
  StreamSubscription<MusicPlayerState>? _sub;
  Future<void> _ops = Future.value();
  List<ServerItem> _queue = const [];
  bool _opening = false;
  bool _wasPlaying = false;
  bool _finishedSent = false;
  bool _ended = false;
  DateTime? _lastSync;
  bool _disposed = false;

  AbsPlayerState get state => _state;

  Stream<AbsPlayerState> get states => Stream.multi((l) {
    l.add(_state);
    final s = _states.stream.listen(l.add, onDone: l.close);
    l.onCancel = s.cancel;
  });

  /// The id the music player shows for an item.
  static String idOf(AbsAccount a, ServerItem i) => 'abs:${a.id}:${i.id}';

  /// Plays [item] of [account]. [queue] is the list it was picked from: the
  /// next unplayed one after it plays when it ends. Throws [ServerException]
  /// when the server cannot say where to stream from and there is no
  /// offline copy.
  Future<void> play(
    AbsAccount account,
    ServerItem item, {
    List<ServerItem> queue = const [],
    bool autoplay = true,
  }) => _serial(() async {
    if (_state.active) await _sync(force: true);
    _queue = queue;
    await _open(account, item, autoplay: autoplay);
  });

  Future<void> pause() => _serial(() async {
    if (_state.active) await player.pause();
  });

  Future<void> resume() => _serial(() async {
    if (!_state.active) return;
    if (_ended) {
      _ended = false;
      _finishedSent = false;
    }
    await player.play();
  });

  Future<void> togglePlayPause() => _state.playing ? pause() : resume();

  Future<void> seek(Duration position) => _serial(() async {
    if (!_state.active) return;
    final to = position < Duration.zero ? Duration.zero : position;
    await player.seek(to);
    _set(_state.copyWith(position: to));
    await _sync(force: true);
  });

  Future<void> skip(Duration by) => seek(_state.position + by);

  /// 0.5 to 3, remembered for this item and offered to the next one.
  Future<void> setSpeed(double speed) => _serial(() async {
    final a = _state.account;
    final item = _state.item;
    if (a == null || item == null) return;
    final s = speed.clamp(0.5, 3.0);
    // The wanted speed first: the engine's own report of it must not look
    // like a speed that fell back.
    _set(_state.copyWith(speed: s));
    await engine.setRate(s);
    final cur = await _store.item(a.id, item.id);
    await _store.save(a.id, item.id, cur.copyWith(speed: s));
    await _store.setLastSpeed(s);
  });

  Future<void> setSkipSilence({required bool enabled}) => _serial(() async {
    final a = _state.account;
    final item = _state.item;
    if (a == null || item == null) return;
    await dsp.setSkipSilence(enabled: enabled);
    final cur = await _store.item(a.id, item.id);
    await _store.save(a.id, item.id, cur.copyWith(skipSilence: enabled));
    _set(_state.copyWith(skipSilence: enabled));
  });

  /// Marks the playing item finished on the server without stopping it.
  Future<void> markFinished() async {
    final a = _state.account;
    final item = _state.item;
    if (a == null || item == null) return;
    _finishedSent = true;
    await _finish(a, item);
  }

  Future<void> dispose() async {
    _disposed = true;
    await _sub?.cancel();
    if (_state.active) await _sync(force: true);
    await _states.close();
  }

  // ------------------------------------------------------------ internals --

  Future<void> _open(
    AbsAccount a,
    ServerItem item, {
    required bool autoplay,
  }) async {
    final local = await _store.item(a.id, item.id);
    final start = await _startAt(a, item, local);
    final file = await service.localFile(a, item);
    final MediaSource source;
    if (file != null) {
      source = UriSource(file.uri, title: item.title);
    } else {
      final info = await a.library.streamInfo(item.id);
      source = UriSource(info.uri, headers: info.headers, title: item.title);
    }
    final speed = local.speed ?? await _store.lastSpeed();
    final art = await service.artPath(item);
    _mode.claim(this);
    _opening = true;
    _finishedSent = false;
    _ended = false;
    _wasPlaying = false;
    _lastSync = null;
    try {
      _set(
        AbsPlayerState(
          account: a,
          item: item,
          position: start,
          duration: item.duration ?? Duration.zero,
          speed: speed,
          skipSilence: local.skipSilence,
          offline: file != null,
          artPath: art,
        ),
      );
      await dsp.setSkipSilence(enabled: local.skipSilence);
      await player.playEpisode(
        NowPlayingEpisode(
          id: idOf(a, item),
          title: item.title,
          show: item.author ?? a.name,
          artPath: art,
        ),
        source,
        start: start > minPlace ? start : null,
        autoplay: autoplay,
      );
      await engine.setRate(speed);
    } finally {
      _opening = false;
    }
    _sub ??= player.states.listen(_onPlayer);
    _set(_state.copyWith(playing: autoplay));
  }

  /// Where to start. A place this device could not report wins. Once the
  /// server has been told, ours stands unless the server says the item
  /// changed since (another device listened); an item never played here
  /// starts where its listing says, or over when it is finished.
  Future<Duration> _startAt(
    AbsAccount a,
    ServerItem item,
    AbsItemState local,
  ) async {
    if (!local.synced) return local.position;
    final since = local.syncedAt;
    if (since == null) {
      return item.played ? Duration.zero : item.playedPosition ?? Duration.zero;
    }
    try {
      final changed = await a.library.userData(changedSince: since);
      final u = changed.where((d) => d.itemId == item.id).firstOrNull;
      if (u == null) return local.position;
      return u.played ? Duration.zero : u.position ?? Duration.zero;
    } on Object {
      // The server cannot be asked: ours is the best there is.
      return local.position;
    }
  }

  void _onPlayer(MusicPlayerState s) {
    final a = _state.account;
    final item = _state.item;
    if (a == null || item == null || _opening || _disposed) return;
    if (s.episode?.id != idOf(a, item)) {
      unawaited(_serial(_release));
      return;
    }
    final position = s.position;
    final playing = s.playing;
    final ended = s.playback.status == PlaybackStatus.ended;
    final duration = s.duration ?? _state.duration;
    _set(
      _state.copyWith(
        position: position,
        duration: duration,
        playing: playing,
        chapters: s.playback.chapters,
      ),
    );
    if (engine.current.rate != _state.speed &&
        s.playback.status != PlaybackStatus.idle) {
      unawaited(engine.setRate(_state.speed));
    }
    final nearEnd =
        duration > Duration.zero &&
        duration - position <= finishedWithin &&
        position > finishedWithin;
    if ((ended || nearEnd) && !_finishedSent) {
      _finishedSent = true;
      unawaited(_finish(a, item));
    }
    if (ended && !_ended) {
      _ended = true;
      unawaited(_serial(() => _continueAfter(a, item)));
      return;
    }
    if (_wasPlaying && !playing) {
      unawaited(_sync(force: true));
    } else if (playing) {
      unawaited(_sync());
    }
    _wasPlaying = playing;
  }

  /// Tells the server the item is done (and that it is played).
  Future<void> _finish(AbsAccount a, ServerItem item) async {
    final duration = _state.duration;
    try {
      await a.library.reportProgress(item.id, duration, finished: true);
      await a.library.setPlayed(item.id, played: true);
      final cur = await _store.item(a.id, item.id);
      await _store.save(
        a.id,
        item.id,
        cur.copyWith(
          position: Duration.zero,
          synced: true,
          syncedAt: _clock().toUtc(),
        ),
      );
    } on Object {
      final cur = await _store.item(a.id, item.id);
      await _store.save(
        a.id,
        item.id,
        cur.copyWith(position: duration, synced: false),
      );
    }
  }

  Future<void> _continueAfter(AbsAccount a, ServerItem ended) async {
    if (_disposed || (holdAtEnd?.call() ?? false)) return;
    final at = _queue.indexWhere((i) => i.id == ended.id);
    final next = _queue
        .skip(at < 0 ? 0 : at + 1)
        .where((i) => !i.played)
        .firstOrNull;
    if (next == null) return;
    try {
      await _open(a, next, autoplay: true);
    } on ServerException {
      // The next one cannot be reached: stay on the one that ended.
    }
  }

  /// Keeps the place here, and tells the server, when [force] or
  /// [syncEvery] has passed.
  Future<void> _sync({bool force = false}) async {
    final a = _state.account;
    final item = _state.item;
    // Once the item is finished the server has been told so; a place near
    // its end must not undo that.
    if (a == null || item == null || _finishedSent) return;
    final now = _clock();
    final last = _lastSync;
    if (!force && last != null && now.difference(last) < syncEvery) return;
    _lastSync = now;
    final p = _state.position;
    if (p < minPlace) return;
    final cur = await _store.item(a.id, item.id);
    await _store.save(a.id, item.id, cur.copyWith(position: p, synced: false));
    try {
      await a.library.reportProgress(item.id, p);
      await _store.save(
        a.id,
        item.id,
        (await _store.item(
          a.id,
          item.id,
        )).copyWith(synced: true, syncedAt: _clock().toUtc()),
      );
    } on Object {
      // Not reachable: the place is kept here and told next time.
    }
  }

  /// Leaves Audiobookshelf mode: tells the server, and gives the music
  /// player its normal speed and silences back.
  Future<void> _release() async {
    if (!_state.active) return;
    await _sync(force: true);
    _lastSync = null;
    _wasPlaying = false;
    _set(const AbsPlayerState());
    if (_mode.release(this)) {
      await dsp.setSkipSilence(enabled: false);
      await engine.setRate(1);
    }
  }

  Future<void> _serial(Future<void> Function() op) {
    final f = _ops.then((_) => op());
    _ops = f.catchError((Object _) {});
    return f;
  }

  void _set(AbsPlayerState s) {
    _state = s;
    if (!_states.isClosed) _states.add(s);
  }
}
