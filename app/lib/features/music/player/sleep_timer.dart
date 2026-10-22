import 'dart:async';
import 'dart:math' as math;

import 'package:mediahro/features/music/player/music_player.dart';
import 'package:mediahro_engine/mediahro_engine.dart';
import 'package:meta/meta.dart';

/// What the sleep timer waits for (MUS-011).
enum SleepMode { off, time, endOfTrack, tracks }

@immutable
final class SleepTimerState {
  const SleepTimerState({
    this.mode = SleepMode.off,
    this.remaining,
    this.tracksLeft,
    this.fading = false,
  });

  static const off = SleepTimerState();

  final SleepMode mode;

  /// Time left in [SleepMode.time].
  final Duration? remaining;

  /// Tracks left, counting the current one, in [SleepMode.tracks] and
  /// [SleepMode.endOfTrack].
  final int? tracksLeft;
  final bool fading;

  bool get active => mode != SleepMode.off;
}

/// Sleep timer by time or by tracks, with a fade-out (MUS-011, and the
/// audiobook sleep timer of POD-001). The fade ramps the engine volume
/// down, pauses, then restores the user's volume so the next play starts
/// normally.
final class SleepTimer {
  SleepTimer({
    required this.player,
    required this.engine,
    this.fade = const Duration(seconds: 30),
    this.tick = const Duration(seconds: 1),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final MusicPlayer player;
  final PlaybackEngine engine;

  /// Fade-out length before pausing.
  final Duration fade;
  final Duration tick;
  final DateTime Function() _clock;

  final _states = StreamController<SleepTimerState>.broadcast();
  SleepTimerState _state = SleepTimerState.off;
  Timer? _timer;
  DateTime? _deadline;
  StreamSubscription<MusicPlayerState>? _sub;
  int _lastItem = -1;
  double? _volumeBefore;

  SleepTimerState get state => _state;

  Stream<SleepTimerState> get states => Stream.multi((l) {
    l.add(_state);
    final s = _states.stream.listen(l.add, onDone: l.close);
    l.onCancel = s.cancel;
  });

  /// Pauses after [d] of playback time (wall clock), fading out first.
  void startTime(Duration d) {
    _reset();
    _deadline = _clock().add(d);
    _emit(SleepTimerState(mode: SleepMode.time, remaining: d));
    _timer = Timer.periodic(tick, (_) => _onTick());
  }

  /// Pauses when the current track ends.
  void startEndOfTrack() => _startTracks(1, SleepMode.endOfTrack);

  /// Pauses when [n] tracks (the current one included) have ended.
  void startTracks(int n) => _startTracks(math.max(1, n), SleepMode.tracks);

  /// Adds time (shake-to-extend, POD-001; "+5 min" in the sheet).
  void extend(Duration by) {
    final d = _deadline;
    if (_state.mode != SleepMode.time || d == null) return;
    _deadline = d.add(by);
    unawaited(_restoreVolume());
    _emit(
      SleepTimerState(
        mode: SleepMode.time,
        remaining: _deadline!.difference(_clock()),
      ),
    );
  }

  /// A shake of the phone while the timer runs (POD-001): five more minutes
  /// for a timer by time, one more track for a timer by tracks. A timer
  /// already fading out is brought back to full volume.
  void shake() {
    switch (_state.mode) {
      case SleepMode.time:
        extend(const Duration(minutes: 5));
      case SleepMode.tracks || SleepMode.endOfTrack:
        final left = _state.tracksLeft;
        if (left == null) return;
        unawaited(_restoreVolume());
        // One more track: the current one is no longer the last.
        player.holdAtEnd = false;
        _emit(SleepTimerState(mode: SleepMode.tracks, tracksLeft: left + 1));
      case SleepMode.off:
        break;
    }
  }

  void cancel() {
    _reset();
    unawaited(_restoreVolume());
    _emit(SleepTimerState.off);
  }

  Future<void> dispose() async {
    _reset();
    await _states.close();
  }

  void _startTracks(int n, SleepMode mode) {
    _reset();
    _lastItem = engine.current.item;
    _emit(SleepTimerState(mode: mode, tracksLeft: n));
    player.holdAtEnd = n == 1;
    _sub = player.states.listen(_onPlayer);
    // The last track's tail fades too.
    _timer = Timer.periodic(tick, (_) => _onTrackTick());
  }

  void _onPlayer(MusicPlayerState s) {
    final left = _state.tracksLeft;
    if (left == null) return;
    // The engine's item counter moves once per track start (gapless,
    // skip or repeat-one alike); the queue index may follow a frame later.
    final advanced = s.playback.item != _lastItem;
    final ended = s.playback.status == PlaybackStatus.ended;
    if (!advanced && !ended) return;
    // An item that ended with nothing prepared (DSD over DoP): the player
    // opens the next one itself, and that start is what counts.
    if (ended && !advanced && left > 1 && player.opensNextAfterEnd) return;
    _lastItem = s.playback.item;
    final now = left - 1;
    if (now <= 0 || ended) {
      unawaited(_finish());
    } else {
      _emit(SleepTimerState(mode: _state.mode, tracksLeft: now));
      player.holdAtEnd = now == 1;
    }
  }

  void _onTrackTick() {
    final s = player.state;
    if (_state.tracksLeft != 1 || s.duration == null) return;
    final left = s.duration! - s.position;
    if (left <= fade && s.playing) unawaited(_fadeTo(left));
  }

  void _onTick() {
    final d = _deadline;
    if (d == null) return;
    final left = d.difference(_clock());
    if (left <= Duration.zero) {
      unawaited(_finish());
      return;
    }
    if (left <= fade && player.state.playing) unawaited(_fadeTo(left));
    _emit(
      SleepTimerState(
        mode: SleepMode.time,
        remaining: left,
        fading: left <= fade,
      ),
    );
  }

  /// Sets the volume for [left] time remaining in the fade (linear).
  Future<void> _fadeTo(Duration left) async {
    _volumeBefore ??= engine.current.volume;
    final x = left.inMilliseconds / math.max(1, fade.inMilliseconds);
    await engine.setVolume(_volumeBefore! * x.clamp(0.0, 1.0));
  }

  Future<void> _finish() async {
    _reset();
    _emit(SleepTimerState.off);
    await player.pause();
    await _restoreVolume();
  }

  Future<void> _restoreVolume() async {
    final v = _volumeBefore;
    _volumeBefore = null;
    if (v != null) await engine.setVolume(v);
  }

  void _reset() {
    _timer?.cancel();
    _timer = null;
    unawaited(_sub?.cancel());
    _sub = null;
    _deadline = null;
    player.holdAtEnd = false;
  }

  void _emit(SleepTimerState s) {
    _state = s;
    if (!_states.isClosed) _states.add(s);
  }
}
