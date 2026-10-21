import 'dart:developer' show Timeline;
import 'dart:ui' show FramePhase, FrameTiming;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

/// One measured tab switch.
@immutable
final class ModeSwitchSample {
  const ModeSwitchSample(this.destination, this.milliseconds);

  /// The destination switched to (`video`, `music`, `photos`, ...).
  final String destination;

  /// From the tap to the end of rasterising the first frame that shows it.
  final double milliseconds;

  @override
  String toString() => 'ModeSwitchSample($destination, $milliseconds ms)';
}

/// Measures how long switching tabs takes on the device itself (CORE-001:
/// under 100 ms, docs/11 §5).
///
/// The shell calls [begin] when a tab is tapped. The first frame that starts
/// after that carries the new destination; its [FrameTiming] tells when the
/// raster thread finished it. The engine's frame timings and `Timeline.now`
/// share one clock, so the sample is `rasterFinish - tap`. It needs no VM
/// service, so it works on a phone over wireless adb. Each sample is logged as
/// `perf: mode-switch <ms>` and kept in [samples].
///
/// It is on in debug and profile builds, and in a release build made with
/// `--dart-define=MEDIAHRO_PERF=true`; otherwise it does nothing.
final class ModeSwitchProbe {
  ModeSwitchProbe({
    int Function()? clock,
    void Function(String line)? log,
    bool? enabled,
  }) : _clock = clock ?? (() => Timeline.now),
       _log = log ?? debugPrint,
       _enabled = enabled ?? _defaultEnabled;

  /// The app's probe.
  static final ModeSwitchProbe instance = ModeSwitchProbe();

  static const bool _defaultEnabled =
      kDebugMode || kProfileMode || bool.fromEnvironment('MEDIAHRO_PERF');

  final int Function() _clock;
  final void Function(String line) _log;
  bool _enabled;
  bool _listening = false;

  // Taps whose frame timings have not arrived yet, oldest first. The engine
  // reports timings in batches, so several taps can be waiting.
  final List<({String destination, int tapMicros})> _pending = [];
  final List<ModeSwitchSample> _samples = [];

  /// The samples taken so far, oldest first.
  List<ModeSwitchSample> get samples => List.unmodifiable(_samples);

  bool get enabled => _enabled;

  /// Turns the probe on (an integration test does this for any build mode).
  void enable() {
    _enabled = true;
  }

  /// Forgets the samples taken so far.
  void reset() {
    _samples.clear();
    _pending.clear();
  }

  /// A tab was tapped: start timing the switch to [destination].
  void begin(String destination) {
    if (!_enabled) return;
    if (!_listening) {
      _listening = true;
      SchedulerBinding.instance.addTimingsCallback(onTimings);
    }
    if (_pending.length >= 100) _pending.removeAt(0);
    _pending.add((destination: destination, tapMicros: _clock()));
  }

  /// Frame timings from the engine, oldest first. Called by the scheduler;
  /// tests call it with built timings.
  @visibleForTesting
  void onTimings(List<FrameTiming> timings) {
    for (final t in timings) {
      if (_pending.isEmpty) return;
      final built = t.timestampInMicroseconds(FramePhase.buildStart);
      // The first frame to begin after a tap carries the new destination; a
      // frame that began before it cannot.
      final at = _pending.indexWhere((p) => p.tapMicros <= built);
      if (at < 0) continue;
      final tap = _pending.removeAt(at);
      final ms =
          (t.timestampInMicroseconds(FramePhase.rasterFinish) - tap.tapMicros) /
          1000;
      // A clock that does not match would give nonsense; drop it, loudly.
      if (ms < 0 || ms > 60000) {
        _log('perf: mode-switch invalid ($ms ms for ${tap.destination})');
        continue;
      }
      _samples.add(ModeSwitchSample(tap.destination, ms));
      _log('perf: mode-switch ${ms.toStringAsFixed(1)} (${tap.destination})');
    }
  }

  /// Waits until [count] samples exist, polling the frame timings the engine
  /// reports in batches; returns false on timeout.
  Future<bool> waitForSamples(
    int count, {
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final end = DateTime.now().add(timeout);
    while (_samples.length < count) {
      if (DateTime.now().isAfter(end)) return false;
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    return true;
  }
}

/// The value at percentile [p] (0..1) of [values], nearest rank.
double percentile(List<double> values, double p) {
  assert(values.isNotEmpty, 'no samples');
  final sorted = [...values]..sort();
  final rank = (p * sorted.length).ceil().clamp(1, sorted.length);
  return sorted[rank - 1];
}
