import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:mediahro/features/video/player/video_player_controller.dart';
import 'package:mediahro_engine/mediahro_engine.dart';

/// What the sleep timer is set to (VID-069).
sealed class SleepSetting {
  const SleepSetting();
}

final class SleepOff extends SleepSetting {
  const SleepOff();
}

/// Pause after [duration].
final class SleepAfterTime extends SleepSetting {
  const SleepAfterTime(this.duration);

  final Duration duration;
}

/// Pause when this video ends.
final class SleepAtEndOfItem extends SleepSetting {
  const SleepAtEndOfItem();
}

/// Pause when the last queued video ends.
final class SleepAtEndOfQueue extends SleepSetting {
  const SleepAtEndOfQueue();
}

/// Sleep timer and auto-off (VID-069): after a time, at the end of the
/// video or at the end of the queue, with the sound fading out over
/// [fade] before playback pauses. The user's volume is restored after the
/// fade, so the next play starts at the usual level.
final class SleepTimer extends ChangeNotifier {
  SleepTimer(this.controller, {this.fade = const Duration(seconds: 30)}) {
    controller.onSleep = _finished;
  }

  final VideoPlayerController controller;
  final Duration fade;

  static const presets = [
    Duration(minutes: 15),
    Duration(minutes: 30),
    Duration(minutes: 45),
    Duration(minutes: 60),
    Duration(minutes: 90),
  ];

  SleepSetting _setting = const SleepOff();
  Duration? _left;
  Timer? _tick;
  double? _fadingFrom;

  SleepSetting get setting => _setting;
  bool get active => _setting is! SleepOff;

  /// Time until playback pauses: the countdown, or what is left of the
  /// item (or, for the queue, of the current item when it is the last).
  Duration? get remaining => switch (_setting) {
    SleepOff() => null,
    SleepAfterTime() => _left,
    SleepAtEndOfItem() || SleepAtEndOfQueue() => _toItemEnd(),
  };

  Duration? _toItemEnd() {
    final s = controller.state;
    final d = s.duration;
    if (d == null) return null;
    if (_setting is SleepAtEndOfQueue &&
        (controller.request?.next.isNotEmpty ?? false)) {
      return null;
    }
    final left = d - s.position;
    return left.isNegative ? Duration.zero : left;
  }

  void set(SleepSetting setting) {
    _stop(restore: true);
    _setting = setting;
    switch (setting) {
      case SleepOff():
        controller.stopAfter = null;
      case SleepAfterTime(:final duration):
        controller.stopAfter = null;
        _left = duration;
        _startTicking();
      case SleepAtEndOfItem():
        controller.stopAfter = StopAfter.item;
        _startTicking();
      case SleepAtEndOfQueue():
        controller.stopAfter = StopAfter.queue;
        _startTicking();
    }
    notifyListeners();
  }

  void _startTicking() {
    _tick = Timer.periodic(const Duration(seconds: 1), (_) => _onTick());
  }

  void _onTick() {
    final playing = controller.state.status == PlaybackStatus.playing;
    if (_setting case SleepAfterTime()) {
      // The countdown runs while the video plays.
      if (!playing) return;
      _left = _left! - const Duration(seconds: 1);
      if (_left! <= Duration.zero) {
        unawaited(_pauseNow());
        return;
      }
    }
    final left = remaining;
    if (left != null && playing && left <= fade) _fadeTo(left);
    notifyListeners();
  }

  void _fadeTo(Duration left) {
    _fadingFrom ??= controller.volume;
    final level = _fadingFrom! * (left.inMilliseconds / fade.inMilliseconds);
    unawaited(controller.engine.setVolume(level.clamp(0.0, 3.0)));
  }

  Future<void> _pauseNow() async {
    await controller.engine.pause();
    _finished();
  }

  /// Playback stopped for the timer: put the volume back and switch off.
  void _finished() {
    _stop(restore: true);
    _setting = const SleepOff();
    controller.stopAfter = null;
    notifyListeners();
  }

  void _stop({required bool restore}) {
    _tick?.cancel();
    _tick = null;
    _left = null;
    final v = _fadingFrom;
    _fadingFrom = null;
    if (restore && v != null) unawaited(controller.engine.setVolume(v));
  }

  @override
  void dispose() {
    _stop(restore: true);
    if (controller.onSleep == _finished) controller.onSleep = null;
    super.dispose();
  }
}
