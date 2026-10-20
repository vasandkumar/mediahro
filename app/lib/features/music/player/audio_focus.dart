import 'dart:async';

import 'package:mediahro/features/music/player/music_player.dart';
import 'package:mediahro/platform/platform_facades.dart';
import 'package:mediahro_engine/mediahro_engine.dart';

/// Audio focus for music (AUD-045 behaviour on C4's [AudioOutputFacade]):
/// takes focus when playback starts, pauses for calls and other players and
/// resumes when the OS says so, ducks for notifications, and pauses when
/// headphones are unplugged.
final class MusicFocusBridge {
  MusicFocusBridge({
    required this.player,
    required this.engine,
    required this.output,
    this.duckGain = 0.25,
  });

  final MusicPlayer player;
  final PlaybackEngine engine;
  final AudioOutputFacade output;

  /// Output level while ducked (0…1).
  final double duckGain;

  StreamSubscription<MusicPlayerState>? _states;
  StreamSubscription<AudioInterruption>? _interruptions;
  bool _hasFocus = false;
  bool _pausedByInterruption = false;

  void start() {
    _interruptions ??= output.interruptions.listen(
      (i) => unawaited(_onInterruption(i.kind)),
    );
    _states ??= player.states.listen((s) => unawaited(_onState(s)));
  }

  Future<void> dispose() async {
    await _states?.cancel();
    await _interruptions?.cancel();
    if (_hasFocus) await output.abandonFocus();
  }

  Future<void> _onState(MusicPlayerState s) async {
    if (s.playback.status == PlaybackStatus.playing && !_hasFocus) {
      _hasFocus = true;
      final granted = await output.requestFocus();
      if (!granted) {
        _hasFocus = false;
        await player.pause();
      }
    }
  }

  Future<void> _onInterruption(AudioInterruptionKind kind) async {
    switch (kind) {
      case AudioInterruptionKind.began:
        _hasFocus = false;
        if (player.state.playing) {
          _pausedByInterruption = true;
          await player.pause();
        }
      case AudioInterruptionKind.endedShouldResume:
        if (_pausedByInterruption) {
          _pausedByInterruption = false;
          await player.play();
        }
      case AudioInterruptionKind.endedNoResume:
        _pausedByInterruption = false;
      case AudioInterruptionKind.duck:
        await engine.setDucking(duckGain);
      case AudioInterruptionKind.unduck:
        await engine.setDucking(1);
      case AudioInterruptionKind.becomingNoisy:
        _pausedByInterruption = false;
        await player.pause();
    }
  }
}
