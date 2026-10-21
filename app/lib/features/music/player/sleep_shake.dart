import 'dart:async';
import 'dart:math' as math;

import 'package:mediahro/features/music/player/sleep_timer.dart';
import 'package:mediahro/platform/motion.dart';

/// Recognises a shake of the phone from its attitude (POD-001
/// shake-to-extend). The attitude facade (ADR-042) reports where the back of
/// the device points, so a shake shows as the aim swinging back and forth
/// quickly: several fast moves in alternating directions within a short
/// window. A slow turn, picking the phone up or setting it down is a single
/// direction and never counts.
final class ShakeDetector {
  ShakeDetector({
    this.minSpeed = 3.5,
    this.reversals = 3,
    this.window = const Duration(milliseconds: 1000),
    this.cooldown = const Duration(seconds: 2),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  /// Radians per second an aim move needs to count as a jerk.
  final double minSpeed;

  /// Jerks in alternating directions that make a shake.
  final int reversals;
  final Duration window;
  final Duration cooldown;
  final DateTime Function() _clock;

  MotionAttitude? _last;
  DateTime? _lastAt;
  DateTime? _firedAt;
  final _jerks = <(DateTime, double, double)>[];

  /// Feeds one reading; true when it completes a shake.
  bool add(MotionAttitude a) {
    final now = _clock();
    final prev = _last;
    final prevAt = _lastAt;
    _last = a;
    _lastAt = now;
    if (prev == null || prevAt == null) return false;
    final dt = math.max(
      0.005,
      now.difference(prevAt).inMicroseconds / Duration.microsecondsPerSecond,
    );
    var dy = a.yaw - prev.yaw;
    // The heading wraps around at half a turn.
    if (dy > math.pi) dy -= 2 * math.pi;
    if (dy < -math.pi) dy += 2 * math.pi;
    final dp = a.pitch - prev.pitch;
    if (math.sqrt(dy * dy + dp * dp) / dt < minSpeed) return false;
    final last = _jerks.lastOrNull;
    // Only a swing back against the previous one adds to the shake.
    if (last == null || last.$2 * dy + last.$3 * dp < 0) {
      _jerks.add((now, dy, dp));
    } else {
      _jerks[_jerks.length - 1] = (now, dy, dp);
    }
    _jerks.removeWhere((j) => now.difference(j.$1) > window);
    final fired = _firedAt;
    if (_jerks.length >= reversals &&
        (fired == null || now.difference(fired) >= cooldown)) {
      _firedAt = now;
      _jerks.clear();
      return true;
    }
    return false;
  }

  void reset() {
    _last = null;
    _lastAt = null;
    _jerks.clear();
  }
}

/// While a sleep timer runs, a shake of the phone extends it
/// ([SleepTimer.shake]). The sensor is listened to only while a timer is
/// active, so it costs nothing otherwise.
final class SleepShakeExtender {
  SleepShakeExtender({
    required this.timer,
    required this.motion,
    ShakeDetector? detector,
  }) : _detector = detector ?? ShakeDetector();

  final SleepTimer timer;
  final MotionFacade motion;
  final ShakeDetector _detector;

  StreamSubscription<SleepTimerState>? _timerSub;
  StreamSubscription<MotionAttitude>? _motionSub;
  bool _disposed = false;

  void start() {
    _timerSub ??= timer.states.listen((s) => unawaited(_onTimer(s.active)));
  }

  Future<void> _onTimer(bool active) async {
    if (active && _motionSub == null) {
      if (!await motion.available || _disposed) return;
      _detector.reset();
      _motionSub ??= motion.attitude.listen((a) {
        if (_detector.add(a)) timer.shake();
      });
    } else if (!active) {
      await _motionSub?.cancel();
      _motionSub = null;
    }
  }

  Future<void> dispose() async {
    _disposed = true;
    await _timerSub?.cancel();
    await _motionSub?.cancel();
  }
}
