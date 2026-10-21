import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mediahro/platform/android/audio_route_watcher.dart';
import 'package:mediahro/platform/audio_output.dart';

/// Only the two streams the watcher listens to; any other call is a test bug.
final class _Output implements AudioOutputFacade {
  final deviceEvents = StreamController<List<AudioDevice>>.broadcast(
    sync: true,
  );
  final interruptionEvents = StreamController<AudioInterruption>.broadcast(
    sync: true,
  );

  @override
  Stream<List<AudioDevice>> get deviceChanges => deviceEvents.stream;

  @override
  Stream<AudioInterruption> get interruptions => interruptionEvents.stream;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const _settle = Duration(milliseconds: 30);

/// Long enough for several settle periods, so a missing call shows up.
Future<void> _wait([int ms = 200]) =>
    Future<void>.delayed(Duration(milliseconds: ms));

void main() {
  test(
    'AUD-043 a device change calls the engine once, after it settles',
    () async {
      final out = _Output();
      var calls = 0;
      final w = AudioRouteWatcher(
        output: out,
        settle: _settle,
        onChange: () async => calls++,
      );
      addTearDown(w.dispose);
      out.deviceEvents.add(const []);
      expect(calls, 0);
      await _wait();
      expect(calls, 1);
    },
  );

  test('AUD-043 a burst of events is one call', () async {
    final out = _Output();
    var calls = 0;
    final w = AudioRouteWatcher(
      output: out,
      settle: const Duration(milliseconds: 80),
      onChange: () async => calls++,
    );
    addTearDown(w.dispose);
    for (var i = 0; i < 5; i++) {
      out.deviceEvents.add(const []);
      await _wait(20);
    }
    await _wait(300);
    expect(calls, 1);
  });

  test(
    'AUD-043 headphones pulled out (becoming noisy) is a route change',
    () async {
      final out = _Output();
      var calls = 0;
      final w = AudioRouteWatcher(
        output: out,
        settle: _settle,
        onChange: () async => calls++,
      );
      addTearDown(w.dispose);
      out.interruptionEvents.add(
        const AudioInterruption(AudioInterruptionKind.becomingNoisy),
      );
      await _wait();
      expect(calls, 1);
      // Other interruptions (a call, ducking) are not route changes.
      for (final k in [
        AudioInterruptionKind.began,
        AudioInterruptionKind.endedShouldResume,
        AudioInterruptionKind.duck,
      ]) {
        out.interruptionEvents.add(AudioInterruption(k));
      }
      await _wait();
      expect(calls, 1);
    },
  );

  test(
    'AUD-043 a change during a running re-check runs once more after it',
    () async {
      final out = _Output();
      final gate = Completer<void>();
      var calls = 0;
      var concurrent = 0;
      var maxConcurrent = 0;
      final w = AudioRouteWatcher(
        output: out,
        settle: _settle,
        onChange: () async {
          calls++;
          concurrent++;
          if (concurrent > maxConcurrent) maxConcurrent = concurrent;
          if (calls == 1) await gate.future;
          concurrent--;
        },
      );
      addTearDown(w.dispose);
      out.deviceEvents.add(const []);
      await _wait();
      expect(calls, 1);
      // A second change while the first re-check is still running.
      out.deviceEvents.add(const []);
      await _wait();
      expect(calls, 1);
      gate.complete();
      await _wait();
      expect(calls, 2);
      expect(maxConcurrent, 1);
    },
  );

  test('AUD-043 a failing re-check does not stop the next one', () async {
    final out = _Output();
    var calls = 0;
    final w = AudioRouteWatcher(
      output: out,
      settle: _settle,
      onChange: () async {
        calls++;
        throw StateError('engine busy');
      },
    );
    addTearDown(w.dispose);
    out.deviceEvents.add(const []);
    await _wait();
    out.deviceEvents.add(const []);
    await _wait();
    expect(calls, 2);
  });

  test('AUD-043 after dispose nothing is called', () async {
    final out = _Output();
    var calls = 0;
    final w = AudioRouteWatcher(
      output: out,
      settle: _settle,
      onChange: () async => calls++,
    );
    out.deviceEvents.add(const []);
    await w.dispose();
    await _wait();
    expect(calls, 0);
    out.deviceEvents.add(const []);
    await _wait();
    expect(calls, 0);
  });
}
