import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediahro/app/capabilities.dart';
import 'package:mediahro/app/providers.dart';
import 'package:mediahro/core/net/network_policy.dart';
import 'package:mediahro/features/settings/core_settings.dart';
import 'package:mediahro/features/settings/privacy/privacy_source.dart';
import 'package:mediahro_design/mediahro_design.dart';

import '../../helpers.dart';

void main() {
  Future<void> scrollTo(WidgetTester tester, Finder f) async {
    await tester.ensureVisible(f);
    await tester.pumpAndSettle();
  }

  testWidgets('CORE-015 lists every allow-listed endpoint with a toggle', (
    tester,
  ) async {
    await pumpApp(tester, initialLocation: '/settings/privacy');
    for (final e in Endpoints.all) {
      final row = find.byKey(ValueKey('privacy.${e.id}'));
      await scrollTo(tester, row);
      expect(row, findsOneWidget, reason: e.id);
      expect(
        find.descendant(of: row, matching: find.byType(Switch)),
        findsOneWidget,
      );
    }
  });

  testWidgets('PRIV-001 telemetry is explained first and off by default', (
    tester,
  ) async {
    await pumpApp(tester, initialLocation: '/settings/privacy');
    expect(find.text('Off unless you turn them on'), findsOneWidget);
    for (final id in telemetryEndpointIds) {
      final sw = tester.widget<Switch>(
        find.descendant(
          of: find.byKey(ValueKey('privacy.$id')),
          matching: find.byType(Switch),
        ),
      );
      expect(sw.value, isFalse);
    }
    expect(find.text('Check for updates'), findsOneWidget);
  });

  testWidgets('PRIV-004 toggling an endpoint writes its privacy key', (
    tester,
  ) async {
    final store = await pumpApp(tester, initialLocation: '/settings/privacy');
    final row = find.byKey(const ValueKey('privacy.tmdb'));
    await scrollTo(tester, row);
    await tester.tap(row);
    await tester.pumpAndSettle();
    expect(store.get(CoreSettings.endpoint('tmdb')), isTrue);
    expect(store.get(endpointToggle(Endpoints.tmdb)), isTrue);
  });

  testWidgets('CORE-015 shows last-used time and user-configured hosts', (
    tester,
  ) async {
    final usage = RecordingPrivacyUsage()
      ..record(Endpoints.lrclib, DateTime(2026, 10, 18, 21, 30))
      ..recordHost('nas.local', at: DateTime(2026, 10, 19, 8));
    await pumpApp(
      tester,
      initialLocation: '/settings/privacy',
      overrides: [privacyUsageProvider.overrideWithValue(usage)],
    );
    final row = find.byKey(const ValueKey('privacy.lrclib'));
    await scrollTo(tester, row);
    expect(
      find.descendant(
        of: row,
        matching: find.textContaining('Last used Oct 18, 2026'),
      ),
      findsOneWidget,
    );
    await scrollTo(tester, find.text('nas.local'));
    expect(find.text('nas.local'), findsOneWidget);
    expect(find.textContaining('Never used'), findsWidgets);
  });

  testWidgets('CORE-015 managed endpoints are locked', (tester) async {
    final store = await pumpApp(tester, initialLocation: '/settings/privacy');
    store.applyManaged({'privacy.endpoint.crash': false});
    await tester.pumpAndSettle();
    expect(find.text('Managed by your organisation'), findsOneWidget);
  });

  testWidgets('PRIV-001 store builds say updates come from the store', (
    tester,
  ) async {
    await pumpApp(
      tester,
      initialLocation: '/settings/privacy',
      overrides: [
        capabilitiesProvider.overrideWithValue(
          const Capabilities(
            flavor: Flavor.store,
            platform: AppPlatform.android,
          ),
        ),
      ],
    );
    expect(
      find.text('Your app store handles updates for this build.'),
      findsOneWidget,
    );
  });

  testWidgets('CORE-015 search reaches individual services', (tester) async {
    await pumpApp(tester, initialLocation: '/settings');
    await tester.enterText(find.byType(TextField), 'privacy');
    await tester.pumpAndSettle();
    expect(find.byType(KSettingsRow), findsWidgets);
  });

  testWidgets('CORE-002 first-run privacy line opens the dashboard', (
    tester,
  ) async {
    await pumpApp(tester);
    await tester.tap(
      find.text('Privacy: nothing leaves this device unless you turn it on'),
    );
    await tester.pumpAndSettle();
    expect(find.text('Off unless you turn them on'), findsOneWidget);
  });
}
