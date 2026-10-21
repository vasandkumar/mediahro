import 'dart:async';

import 'package:mediahro/platform/audio_output.dart';

/// Tells the engine when the OS audio route changes (AUD-043): a DAC or
/// headset plugged or unplugged, the default output switched, headphones
/// pulled out (`ACTION_AUDIO_BECOMING_NOISY`). `AudioOutputModule` emits all
/// of these as [AudioOutputFacade.deviceChanges] and
/// [AudioInterruptionKind.becomingNoisy]; this turns them into one call per
/// burst, so a DoP or exclusive output is re-checked at once and never plays
/// noise into a different device.
///
/// A burst of events (a USB DAC reports several) is coalesced over [settle];
/// [onChange] never runs twice at the same time, and a change that arrives
/// while it runs triggers one more call afterwards.
final class AudioRouteWatcher {
  AudioRouteWatcher({
    required AudioOutputFacade output,
    required this.onChange,
    this.settle = const Duration(milliseconds: 150),
  }) {
    _subscriptions = [
      output.deviceChanges.listen((_) => _changed()),
      output.interruptions
          .where((i) => i.kind == AudioInterruptionKind.becomingNoisy)
          .listen((_) => _changed()),
    ];
  }

  /// Called once per settled change; the engine's `audioRouteChanged`.
  final Future<void> Function() onChange;

  final Duration settle;

  late final List<StreamSubscription<Object?>> _subscriptions;
  Timer? _timer;
  bool _running = false;
  bool _again = false;
  bool _closed = false;

  void _changed() {
    if (_closed) return;
    _timer?.cancel();
    _timer = Timer(settle, _fire);
  }

  Future<void> _fire() async {
    if (_closed) return;
    if (_running) {
      _again = true;
      return;
    }
    _running = true;
    try {
      do {
        _again = false;
        try {
          await onChange();
        } on Object {
          // A failed re-check must not stop later route changes from being seen.
        }
      } while (_again && !_closed);
    } finally {
      _running = false;
    }
  }

  Future<void> dispose() async {
    _closed = true;
    _timer?.cancel();
    for (final s in _subscriptions) {
      await s.cancel();
    }
  }
}
