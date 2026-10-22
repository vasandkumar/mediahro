import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mediahro/app/perf/mode_switch_probe.dart';
import 'package:mediahro/app/root.dart';
import 'package:mediahro/app/router.dart';
import 'package:mediahro/app/services.dart';
import 'package:mediahro/ui/adaptive_shell.dart';

/// CORE-001 on the device itself: the time from tapping a tab to the first
/// frame of the new mode, taken from the engine's frame timings
/// (`ModeSwitchProbe`), so it needs no profiler and works over wireless adb.
/// Each switch logs `perf: mode-switch <ms>`.
///
/// The budget (p95 of 20 warm switches within 100 ms, docs/11 §5) binds
/// profile and release builds. A debug build is far slower than the shipped
/// app, so it reports the numbers only, unless
/// `--dart-define=MEDIAHRO_ENFORCE_BUDGET=true` asks for the check.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const enforce =
      !kDebugMode || bool.fromEnvironment('MEDIAHRO_ENFORCE_BUDGET');
  const budgetMs = 100.0;

  testWidgets('CORE-001 mode switch p95 is within 100 ms on the device', (
    tester,
  ) async {
    final probe = ModeSwitchProbe.instance
      ..enable()
      ..reset();
    final dir = await Directory.systemTemp.createTemp('mediahro-mode-switch-');
    final services = await AppServices.open(directory: dir);
    addTearDown(() async {
      await services.close();
      await dir.delete(recursive: true);
    });
    await tester.pumpWidget(
      mediahroRoot(services.settings, overrides: services.overrides),
    );
    await tester.pumpAndSettle();

    const cycle = [
      AppDestination.music,
      AppDestination.photos,
      AppDestination.video,
    ];
    Future<void> switchTo(AppDestination d) async {
      await tester.tap(find.byKey(destinationKey(d)));
      await tester.pumpAndSettle();
    }

    // The first visit of each mode builds it once, as on a real launch.
    // Reported, not budgeted.
    for (final d in cycle) {
      await switchTo(d);
    }
    expect(
      await probe.waitForSamples(cycle.length),
      isTrue,
      reason: 'the engine reported no frame timings for the first visits',
    );
    final cold = [for (final s in probe.samples) s.milliseconds];
    debugPrint(
      'perf: mode-switch first visits ${cold.map((m) => m.toStringAsFixed(1))}',
    );

    probe.reset();
    const switches = 20;
    for (var i = 0; i < switches; i++) {
      await switchTo(cycle[i % cycle.length]);
    }
    expect(
      await probe.waitForSamples(
        switches,
        timeout: const Duration(seconds: 15),
      ),
      isTrue,
      reason: 'only ${probe.samples.length} of $switches switches were timed',
    );

    final ms = [for (final s in probe.samples.take(switches)) s.milliseconds];
    final p50 = percentile(ms, 0.5);
    final p95 = percentile(ms, 0.95);
    final report = {
      'mode': kDebugMode ? 'debug' : (kProfileMode ? 'profile' : 'release'),
      'budget_enforced': enforce,
      'samples': ms.length,
      'first_visits_ms': cold,
      'p50_ms': p50,
      'p95_ms': p95,
      'max_ms': ms.reduce((a, b) => a > b ? a : b),
    };
    binding.reportData = {
      ...?binding.reportData,
      'core001_device_mode_switch': report,
    };
    debugPrint(
      'perf: mode-switch p95 ${p95.toStringAsFixed(1)} (p50 ${p50.toStringAsFixed(1)}, n=${ms.length}, ${report['mode']})',
    );

    if (enforce) {
      expect(
        p95,
        lessThanOrEqualTo(budgetMs),
        reason: 'p95 over 100 ms: $report',
      );
    }
  });
}
