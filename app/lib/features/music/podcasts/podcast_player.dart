import 'dart:async';

import 'package:mediahro/features/music/player/music_dsp.dart';
import 'package:mediahro/features/music/player/music_player.dart';
import 'package:mediahro/features/music/player/spoken_mode.dart';
import 'package:mediahro/features/music/podcasts/feed_parser.dart';
import 'package:mediahro/features/music/podcasts/podcast_service.dart';
import 'package:mediahro/features/music/podcasts/podcast_store.dart';
import 'package:mediahro_engine/mediahro_engine.dart';
import 'package:meta/meta.dart';

/// What the episode player shows (POD-002).
@immutable
final class PodcastPlayerState {
  const PodcastPlayerState({
    this.show,
    this.episode,
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.speed = 1,
    this.skipSilence = false,
    this.playing = false,
    this.offline = false,
  });

  final PodcastShow? show;
  final ParsedEpisode? episode;
  final Duration position;
  final Duration duration;
  final double speed;
  final bool skipSilence;
  final bool playing;

  /// Playing the downloaded copy.
  final bool offline;

  bool get active => episode != null;

  Duration get remaining => Duration(
    microseconds: ((duration - position).inMicroseconds / speed).round().clamp(
      0,
      1 << 62,
    ),
  );

  PodcastPlayerState copyWith({
    PodcastShow? show,
    ParsedEpisode? episode,
    Duration? position,
    Duration? duration,
    double? speed,
    bool? skipSilence,
    bool? playing,
    bool? offline,
  }) => PodcastPlayerState(
    show: show ?? this.show,
    episode: episode ?? this.episode,
    position: position ?? this.position,
    duration: duration ?? this.duration,
    speed: speed ?? this.speed,
    skipSilence: skipSilence ?? this.skipSilence,
    playing: playing ?? this.playing,
    offline: offline ?? this.offline,
  );
}

/// Podcast playback on the music player (POD-002): streams or plays the
/// downloaded copy, remembers the place in each episode and the speed and
/// silence setting of each show, marks an episode played near its end, and
/// carries on with the next unplayed episode of the show.
final class PodcastPlayer {
  PodcastPlayer({
    required this.player,
    required this.engine,
    required this.dsp,
    required this.service,
    this.holdAtEnd,
    this.saveEvery = const Duration(seconds: 5),
    SpokenMode? mode,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now,
       _mode = mode ?? SpokenMode();

  final MusicPlayer player;
  final PlaybackEngine engine;
  final MusicDsp dsp;
  final PodcastService service;

  /// True while a sleep timer wants playback to stop at the end of this
  /// episode: the next one is not started.
  final bool Function()? holdAtEnd;
  final Duration saveEvery;
  final DateTime Function() _clock;
  final SpokenMode _mode;

  PodcastStore get _store => service.store;

  /// An episode counts as played with this much left (or less).
  static const playedWithin = Duration(seconds: 20);

  /// Earlier than this into an episode is not a place worth keeping.
  static const minPlace = Duration(seconds: 5);

  final _states = StreamController<PodcastPlayerState>.broadcast();
  PodcastPlayerState _state = const PodcastPlayerState();
  StreamSubscription<MusicPlayerState>? _sub;
  Future<void> _ops = Future.value();
  bool _opening = false;
  bool _wasPlaying = false;
  bool _playedMarked = false;
  bool _ended = false;
  DateTime? _lastSave;
  bool _disposed = false;

  PodcastPlayerState get state => _state;

  Stream<PodcastPlayerState> get states => Stream.multi((l) {
    l.add(_state);
    final s = _states.stream.listen(l.add, onDone: l.close);
    l.onCancel = s.cancel;
  });

  /// Plays [episode] of [show]: from where the listener left off, or from
  /// the start when it was played. [autoplay] false opens it paused.
  Future<void> play(
    PodcastShow show,
    ParsedEpisode episode, {
    bool autoplay = true,
  }) => _serial(() async {
    if (_state.active) await _save(force: true);
    final progress = (await _store.progress(show.id))[episode.guid];
    final resume = progress != null && !progress.played
        ? progress.position
        : Duration.zero;
    final speed = show.speed ?? await _store.lastSpeed();
    final local = await service.localFile(episode);
    final source = local != null
        ? UriSource(local.uri, title: episode.title)
        : UriSource(Uri.parse(episode.url), title: episode.title);
    _mode.claim(this);
    _opening = true;
    _playedMarked = false;
    _ended = false;
    try {
      _set(
        PodcastPlayerState(
          show: show,
          episode: episode,
          position: resume,
          duration: episode.duration ?? Duration.zero,
          speed: speed,
          skipSilence: show.skipSilence,
          offline: local != null,
        ),
      );
      await dsp.setSkipSilence(enabled: show.skipSilence);
      await player.playEpisode(
        NowPlayingEpisode(
          id: '${show.id}:${episode.guid}',
          title: episode.title,
          show: show.title,
          artPath: show.artPath,
        ),
        source,
        start: resume > minPlace ? resume : null,
        autoplay: autoplay,
      );
      await engine.setRate(speed);
    } finally {
      _opening = false;
    }
    _sub ??= player.states.listen(_onPlayer);
    _set(_state.copyWith(playing: autoplay));
  });

  Future<void> pause() => _serial(() async {
    if (_state.active) await player.pause();
  });

  Future<void> resume() => _serial(() async {
    if (!_state.active) return;
    if (_ended) {
      final show = _state.show!;
      final episode = _state.episode!;
      _ended = false;
      await _store.saveProgress(show.id, episode.guid, const EpisodeProgress());
    }
    await player.play();
  });

  Future<void> togglePlayPause() => _state.playing ? pause() : resume();

  Future<void> seek(Duration position) => _serial(() async {
    if (!_state.active) return;
    final to = position < Duration.zero ? Duration.zero : position;
    await player.seek(to);
    _set(_state.copyWith(position: to));
    await _save(force: true);
  });

  Future<void> skip(Duration by) => seek(_state.position + by);

  /// 0.5 to 3, remembered for this show and offered to the next one.
  Future<void> setSpeed(double speed) => _serial(() async {
    final show = _state.show;
    if (show == null) return;
    final s = speed.clamp(0.5, 3.0);
    // The wanted speed first: the engine's own report of it must not look
    // like a speed that fell back.
    _set(_state.copyWith(speed: s));
    await engine.setRate(s);
    await service.configure(show.id, speed: s);
    await _store.setLastSpeed(s);
  });

  Future<void> setSkipSilence({required bool enabled}) => _serial(() async {
    final show = _state.show;
    if (show == null) return;
    await dsp.setSkipSilence(enabled: enabled);
    await service.configure(show.id, skipSilence: enabled);
    _set(_state.copyWith(skipSilence: enabled));
  });

  /// Marks the playing episode played (or not) without stopping it.
  Future<void> markPlayed({required bool played}) async {
    final show = _state.show;
    final ep = _state.episode;
    if (show == null || ep == null) return;
    _playedMarked = played;
    await service.markPlayed(show.id, [ep.guid], played: played);
  }

  Future<void> dispose() async {
    _disposed = true;
    await _sub?.cancel();
    if (_state.active) await _save(force: true);
    await _states.close();
  }

  // ------------------------------------------------------------ internals --

  void _onPlayer(MusicPlayerState s) {
    final show = _state.show;
    final ep = _state.episode;
    if (show == null || ep == null || _opening || _disposed) return;
    if (s.episode?.id != '${show.id}:${ep.guid}') {
      unawaited(_serial(_release));
      return;
    }
    final position = s.position;
    final playing = s.playing;
    final ended = s.playback.status == PlaybackStatus.ended;
    final duration = s.duration ?? _state.duration;
    _set(
      _state.copyWith(position: position, duration: duration, playing: playing),
    );
    if (engine.current.rate != _state.speed &&
        s.playback.status != PlaybackStatus.idle) {
      unawaited(engine.setRate(_state.speed));
    }
    final nearEnd =
        duration > Duration.zero &&
        duration - position <= playedWithin &&
        position > playedWithin;
    if ((ended || nearEnd) && !_playedMarked) {
      _playedMarked = true;
      unawaited(service.markPlayed(show.id, [ep.guid], played: true));
    }
    if (ended && !_ended) {
      _ended = true;
      unawaited(_serial(() => _continueAfter(show, ep)));
      return;
    }
    if (_wasPlaying && !playing) {
      unawaited(_save(force: true));
    } else if (playing) {
      unawaited(_save());
    }
    _wasPlaying = playing;
  }

  /// The episode ended: on to the next unplayed one in the show's order,
  /// unless a sleep timer says to stop.
  Future<void> _continueAfter(PodcastShow show, ParsedEpisode ended) async {
    await _store.saveProgress(
      show.id,
      ended.guid,
      EpisodeProgress(played: true, updatedAt: _clock().toUtc()),
    );
    if (_disposed || (holdAtEnd?.call() ?? false)) return;
    final list = await service.episodes(show.id);
    final at = list.indexWhere((e) => e.episode.guid == ended.guid);
    final next = list
        .skip(at < 0 ? 0 : at + 1)
        .where((e) => !e.played)
        .firstOrNull;
    if (next == null) return;
    final fresh = await _store.show(show.id) ?? show;
    _ops = Future.value();
    await _openNext(fresh, next.episode);
  }

  Future<void> _openNext(PodcastShow show, ParsedEpisode episode) async {
    final speed = show.speed ?? _state.speed;
    final local = await service.localFile(episode);
    final source = local != null
        ? UriSource(local.uri, title: episode.title)
        : UriSource(Uri.parse(episode.url), title: episode.title);
    _mode.claim(this);
    _opening = true;
    _playedMarked = false;
    _ended = false;
    _wasPlaying = false;
    try {
      _set(
        PodcastPlayerState(
          show: show,
          episode: episode,
          duration: episode.duration ?? Duration.zero,
          speed: speed,
          skipSilence: show.skipSilence,
          offline: local != null,
        ),
      );
      await player.playEpisode(
        NowPlayingEpisode(
          id: '${show.id}:${episode.guid}',
          title: episode.title,
          show: show.title,
          artPath: show.artPath,
        ),
        source,
      );
      await engine.setRate(speed);
    } finally {
      _opening = false;
    }
    _set(_state.copyWith(playing: true));
  }

  /// Writes the place, unless the episode is played (then it starts over
  /// next time).
  Future<void> _save({bool force = false}) async {
    final show = _state.show;
    final ep = _state.episode;
    if (show == null || ep == null || _playedMarked && !force) return;
    final now = _clock();
    final last = _lastSave;
    if (!force && last != null && now.difference(last) < saveEvery) return;
    _lastSave = now;
    final p = _state.position;
    if (!_playedMarked && p < minPlace) return;
    await _store.saveProgress(
      show.id,
      ep.guid,
      EpisodeProgress(
        position: _playedMarked ? Duration.zero : p,
        played: _playedMarked,
        updatedAt: now.toUtc(),
      ),
    );
  }

  /// Leaves podcast mode: saves, and gives the music player its normal
  /// speed and silences back.
  Future<void> _release() async {
    if (!_state.active) return;
    await _save(force: true);
    _lastSave = null;
    _wasPlaying = false;
    _set(const PodcastPlayerState());
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

  void _set(PodcastPlayerState s) {
    _state = s;
    if (!_states.isClosed) _states.add(s);
  }
}
