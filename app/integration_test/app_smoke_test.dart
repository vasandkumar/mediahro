import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mediahro/app/app.dart';
import 'package:mediahro_engine/mediahro_engine.dart';

/// M0 exit: the app launches on every platform from the CI artefact and the
/// engine plugin's native half is linked (docs/10 §3).
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('M0 app launches to the three-mode shell', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: MediahroApp()));
    await tester.pumpAndSettle();
    expect(find.text('Open a file'), findsOneWidget);
    expect(find.text('Music'), findsWidgets);
    expect(find.text('Photos'), findsWidgets);
  });

  testWidgets('M0 engine render bridge is linked natively', (tester) async {
    final info = await RenderBridge().bridgeInfo();
    expect(info, isNotEmpty);
    expect(info, isNot('unknown'));
  });

  testWidgets('CORE-001 mode switch completes within 100 ms', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: MediahroApp()));
    await tester.pumpAndSettle();
    final target = find.text('Photos').first;
    final sw = Stopwatch()..start();
    await tester.tap(target);
    await tester.pump();
    await tester.pump();
    sw.stop();
    expect(find.byType(Scaffold), findsWidgets);
    // Budgets apply to profile/release builds (docs/11 §5); JIT debug runs only report.
    binding.reportData = {'core001_mode_switch_ms': sw.elapsedMilliseconds};
    if (!kDebugMode) expect(sw.elapsedMilliseconds, lessThan(100));
  });
}
