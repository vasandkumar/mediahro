import 'dart:developer' show Timeline;
import 'dart:ui' show FrameTiming;

import 'package:flutter_test/flutter_test.dart';
import 'package:mediahro/app/perf/mode_switch_probe.dart';
import 'package:mediahro/app/router.dart';
import 'package:mediahro/ui/adaptive_shell.dart';

import '../helpers.dart';

FrameTiming timing({required int buildStart, required int rasterFinish}) =>
    FrameTiming(
      vsyncStart: buildStart - 100,
      buildStart: buildStart,
      buildFinish: buildStart + 2000,
      rasterStart: buildStart + 2500,
      rasterFinish: rasterFinish,
      rasterFinishWallTime: rasterFinish,
    );

void main() {
  late int now;
  late List<String> logs;
  late ModeSwitchProbe probe;

  setUp(() {
    now = 1000000;
    logs = [];
    probe = ModeSwitchProbe(clock: () => now, log: logs.add, enabled: true);
  });

  test('CORE-001 the sample runs from the tap to the end of rasterising', () {
    probe
      ..begin('music')
      ..onTimings([timing(buildStart: now + 3000, rasterFinish: now + 41500)]);
    expect(probe.samples, hasLength(1));
    expect(probe.samples.single.destination, 'music');
    expect(probe.samples.single.milliseconds, closeTo(41.5, 1e-9));
    expect(logs, ['perf: mode-switch 41.5 (music)']);
  });

  test('CORE-001 a frame that began before the tap is not the switch', () {
    probe
      ..begin('photos')
      ..onTimings([
        timing(buildStart: now - 5000, rasterFinish: now + 4000),
        timing(buildStart: now + 1000, rasterFinish: now + 30000),
      ]);
    expect(probe.samples.single.milliseconds, closeTo(30, 1e-9));
  });

  test('CORE-001 timings that arrive before the next tap are ignored', () {
    probe.onTimings([timing(buildStart: now, rasterFinish: now + 9000)]);
    expect(probe.samples, isEmpty);
    probe
      ..begin('video')
      ..onTimings([timing(buildStart: now + 10, rasterFinish: now + 20000)])
      ..onTimings([timing(buildStart: now + 40000, rasterFinish: now + 50000)]);
    expect(probe.samples, hasLength(1));
  });

  test('CORE-001 each switch takes its own sample', () {
    for (final (dest, ms) in [('music', 20), ('photos', 35), ('video', 50)]) {
      now += 1000000;
      probe
        ..begin(dest)
        ..onTimings([
          timing(buildStart: now + 100, rasterFinish: now + ms * 1000),
        ]);
    }
    expect(
      [for (final s in probe.samples) s.destination],
      ['music', 'photos', 'video'],
    );
    expect([for (final s in probe.samples) s.milliseconds], [20, 35, 50]);
  });

  test('CORE-001 taps whose timings arrive together each get a sample', () {
    probe.begin('music');
    now += 400000;
    probe.begin('photos');
    now += 400000;
    probe.begin('video');
    final base = now - 800000;
    probe.onTimings([
      timing(buildStart: base + 1000, rasterFinish: base + 30000),
      timing(buildStart: base + 100000, rasterFinish: base + 120000),
      timing(buildStart: base + 401000, rasterFinish: base + 450000),
      timing(buildStart: base + 801000, rasterFinish: base + 870000),
    ]);
    expect(
      [for (final s in probe.samples) (s.destination, s.milliseconds)],
      [('music', 30.0), ('photos', 50.0), ('video', 70.0)],
    );
  });

  test('CORE-001 a mismatched clock is reported, not recorded', () {
    probe
      ..begin('music')
      ..onTimings([
        timing(buildStart: now + 100, rasterFinish: now + 900000000),
      ]);
    expect(probe.samples, isEmpty);
    expect(logs.single, startsWith('perf: mode-switch invalid'));
  });

  test('CORE-001 a probe that is off does nothing', () {
    final off = ModeSwitchProbe(clock: () => now, log: logs.add, enabled: false)
      ..begin('music')
      ..onTimings([timing(buildStart: now + 100, rasterFinish: now + 9000)]);
    expect(off.samples, isEmpty);
    expect(logs, isEmpty);
    off.enable();
    expect(off.enabled, isTrue);
  });

  test('CORE-001 reset forgets the samples and a pending switch', () {
    probe
      ..begin('music')
      ..reset()
      ..onTimings([timing(buildStart: now + 100, rasterFinish: now + 9000)]);
    expect(probe.samples, isEmpty);
  });

  test(
    'CORE-001 waiting for samples ends when they are there or time is up',
    () async {
      expect(
        await probe.waitForSamples(
          1,
          timeout: const Duration(milliseconds: 120),
        ),
        isFalse,
      );
      probe
        ..begin('music')
        ..onTimings([timing(buildStart: now + 100, rasterFinish: now + 9000)]);
      expect(await probe.waitForSamples(1), isTrue);
    },
  );

  test('CORE-001 percentiles use the nearest rank', () {
    final v = [for (var i = 1; i <= 20; i++) i.toDouble()];
    expect(percentile(v, 0.5), 10);
    expect(percentile(v, 0.95), 19);
    expect(percentile(v, 1), 20);
    expect(percentile([7], 0.95), 7);
    expect(percentile([5, 1, 3], 0.5), 3);
  });

  testWidgets('CORE-001 tapping another tab starts a measurement', (
    tester,
  ) async {
    final probe = ModeSwitchProbe.instance
      ..reset()
      ..enable();
    addTearDown(probe.reset);
    await pumpApp(tester);

    await tester.tap(find.byKey(destinationKey(AppDestination.music)));
    await tester.pumpAndSettle();

    // The probe is waiting for the frame timings of the switch.
    final after = Timeline.now;
    probe.onTimings([
      timing(buildStart: after + 1, rasterFinish: after + 5000),
    ]);
    expect(probe.samples, hasLength(1));
    expect(probe.samples.single.destination, 'music');
    expect(probe.samples.single.milliseconds, inInclusiveRange(5, 5000));
  });

  testWidgets('CORE-001 tapping the tab already shown does not', (
    tester,
  ) async {
    final probe = ModeSwitchProbe.instance
      ..reset()
      ..enable();
    addTearDown(probe.reset);
    await pumpApp(tester);

    await tester.tap(find.byKey(destinationKey(AppDestination.video)));
    await tester.pumpAndSettle();
    final after = Timeline.now;
    probe.onTimings([
      timing(buildStart: after + 1, rasterFinish: after + 5000),
    ]);

    expect(probe.samples, isEmpty);
  });
}
