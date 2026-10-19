import 'dart:async';

import 'package:mediahro_engine/src/api/models.dart';
import 'package:mediahro_engine/src/api/playback_engine.dart';
import 'package:meta/meta.dart';

/// A resume point to persist (CORE-011).
@immutable
final class PlaybackCheckpoint {
  const PlaybackCheckpoint({
    required this.item,
    required this.position,
    this.duration,
    this.finished = false,
  });

  /// `PlaybackState.item` of the item the position belongs to.
  final int item;
  final Duration position;
  final Duration? duration;

  /// True when the item played to its end (clear its resume point).
  final bool finished;

  @override
  bool operator ==(Object other) =>
      other is PlaybackCheckpoint &&
      other.item == item &&
      other.position == position &&
      other.duration == duration &&
      other.finished == finished;

  @override
  int get hashCode => Object.hash(item, position, duration, finished);

  @override
  String toString() =>
      'PlaybackCheckpoint(item $item, $position${finished ? ', finished' : ''})';
}

/// Emits a checkpoint every [interval] while playing, plus on pause, stop,
/// item change, end and engine fault, so a crash or kill never loses more
/// than [interval] of progress (CORE-011: auto-save every 5 s).
///
/// The library lane persists the checkpoints (`progress` table); the engine
/// only produces them.
final class PlaybackCheckpointer {
  PlaybackCheckpointer(
    this._engine, {
    this.interval = const Duration(seconds: 5),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now {
    _sub = _engine.state.listen(_onState);
  }

  final PlaybackEngine _engine;
  final Duration interval;
  final DateTime Function() _clock;
  late final StreamSubscription<PlaybackState> _sub;
  final _out = StreamController<PlaybackCheckpoint>.broadcast();
  PlaybackState? _last;
  DateTime? _lastSaved;

  Stream<PlaybackCheckpoint> get checkpoints => _out.stream;

  void _emit(PlaybackState s, {bool finished = false}) {
    if (s.duration == null && s.position == Duration.zero && !finished) return;
    _lastSaved = _clock();
    _out.add(
      PlaybackCheckpoint(
        item: s.item,
        position: s.position,
        duration: s.duration,
        finished: finished,
      ),
    );
  }

  void _onState(PlaybackState s) {
    final prev = _last;
    _last = s;
    if (prev != null && prev.item != s.item) {
      // Save the previous item's last known position before switching.
      _emit(prev, finished: prev.status == PlaybackStatus.ended);
      _lastSaved = null;
    }
    final statusChanged = prev?.status != s.status;
    switch (s.status) {
      case PlaybackStatus.playing:
        final last = _lastSaved;
        if (last == null || _clock().difference(last) >= interval) _emit(s);
      case PlaybackStatus.paused || PlaybackStatus.idle || PlaybackStatus.error:
        if (statusChanged && prev?.status == PlaybackStatus.playing) {
          _emit(
            prev!.copyWith(
              position: s.position == Duration.zero
                  ? prev.position
                  : s.position,
            ),
          );
        }
      case PlaybackStatus.ended:
        if (statusChanged) _emit(s, finished: true);
      case PlaybackStatus.opening || PlaybackStatus.buffering:
        break;
    }
  }

  Future<void> dispose() async {
    await _sub.cancel();
    await _out.close();
  }
}
