import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mediahro/app/root.dart';
import 'package:mediahro/app/router.dart';
import 'package:mediahro/app/services.dart';
import 'package:mediahro/ui/adaptive_shell.dart';

/// CORE-001: switching between Video, Music and Photos completes within
/// 100 ms (docs/11 §5). The budget binds profile and release builds, so the
/// perf job runs this file with `flutter drive --profile` and
/// `test_driver/integration_test.dart` on each desktop device. Debug runs
/// (the regular integration jobs) only report the numbers.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('CORE-001 mode switch completes within 100 ms (profile)', (
    tester,
  ) async {
    final dir = await Directory.systemTemp.createTemp('mediahro-perf-');
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
    // Warm-up: first visit builds each branch once, as on a real launch.
    for (final d in cycle) {
      await tester.tap(find.byKey(destinationKey(d)));
      await tester.pumpAndSettle();
    }

    final samples = <int>[];
    await binding.watchPerformance(() async {
      for (var round = 0; round < 10; round++) {
        for (final d in cycle) {
          final sw = Stopwatch()..start();
          await tester.tap(find.byKey(destinationKey(d)));
          // The frame that shows the new destination.
          await tester.pump();
          sw.stop();
          samples.add(sw.elapsedMicroseconds);
          await tester.pumpAndSettle();
        }
      }
    }, reportKey: 'core001_mode_switch_frames');

    samples.sort();
    int pct(double p) => samples[((samples.length - 1) * p).round()];
    final report = {
      'mode': kDebugMode ? 'debug' : (kProfileMode ? 'profile' : 'release'),
      'samples': samples.length,
      'median_ms': pct(0.5) / 1000,
      'p90_ms': pct(0.9) / 1000,
      'max_ms': samples.last / 1000,
    };
    binding.reportData = {
      ...?binding.reportData,
      'core001_mode_switch': report,
    };
    debugPrint('CORE-001 mode switch: $report');
    // Budgets apply to profile/release builds (docs/11 §5).
    if (!kDebugMode) {
      expect(pct(0.9), lessThan(100000), reason: 'p90 over 100 ms: $report');
      expect(
        samples.last,
        lessThan(100000),
        reason: 'max over 100 ms: $report',
      );
    }
  });
}
