import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediahro/core/db/library_database.dart';
import 'package:mediahro/core/net/network_policy.dart';
import 'package:mediahro/core/net/persistent_network_policy.dart';
import 'package:mediahro/features/settings/core_settings.dart';
import 'package:mediahro/features/settings/privacy/policy_privacy_usage.dart';
import 'package:mediahro/features/settings/privacy/privacy_source.dart';
import 'package:mediahro/features/settings/settings_store.dart';

import '../../helpers.dart';

void main() {
  late LibraryDatabase db;
  late SettingsStore settings;
  late PersistentNetworkPolicy policy;
  late PolicyPrivacyUsage usage;

  Future<void> open() async {
    db = LibraryDatabase.memory();
    settings = await SettingsStore.open(MemorySettingsPersistence(), null);
    policy = await PersistentNetworkPolicy.load(
      db,
      isToggledOn: (id) => settings.get(CoreSettings.endpoint(id)),
    );
    usage = PolicyPrivacyUsage(policy, settings);
  }

  Future<void> close() async {
    usage.dispose();
    await policy.dispose();
    await db.close();
  }

  group('CORE-015 dashboard over the B2 network policy', () {
    setUp(open);
    tearDown(close);

    test('PRIV-004 the policy reads the dashboard switches from settings', () {
      expect(policy.isEnabled(Endpoints.tmdb), isFalse);
      settings.set(endpointToggle(Endpoints.tmdb), true);
      expect(policy.isEnabled(Endpoints.tmdb), isTrue);
    });

    test(
      'PRIV-004 the gateway refuses an endpoint until it is switched on',
      () {
        final gateway = NetworkGateway(policy);
        addTearDown(gateway.close);
        final uri = Uri.parse('https://lrclib.net/api/get');
        expect(() => gateway.authorize(uri), throwsA(isA<NetworkBlocked>()));
        settings.set(endpointToggle(Endpoints.lrclib), true);
        expect(gateway.authorize(uri), Endpoints.lrclib);
        expect(usage.lastUsed(Endpoints.lrclib), isNotNull);
      },
    );

    test('last use and switch changes notify the dashboard', () async {
      var notified = 0;
      usage.addListener(() => notified++);
      policy.recordUse(Endpoints.musicBrainz, DateTime.utc(2026, 10, 20, 9));
      settings.set(endpointToggle(Endpoints.tmdb), true);
      await Future<void>.delayed(Duration.zero);
      expect(
        usage.lastUsed(Endpoints.musicBrainz),
        DateTime.utc(2026, 10, 20, 9),
      );
      expect(notified, greaterThanOrEqualTo(2));
    });

    test('managed configuration forces an endpoint off', () {
      settings.set(endpointToggle(Endpoints.tmdb), true);
      policy.applyManagedOverlay({'tmdb'});
      expect(usage.isForcedOff(Endpoints.tmdb), isTrue);
      expect(policy.isEnabled(Endpoints.tmdb), isFalse);
    });

    test('LAN discovery switch goes to the policy', () async {
      expect(usage.lanDiscovery, isTrue);
      await usage.setLanDiscovery(enabled: false);
      expect(policy.lanDiscovery, isFalse);
    });
  });

  testWidgets('CORE-015 dashboard shows last use, locks and LAN discovery', (
    tester,
  ) async {
    await tester.runAsync(open);
    policy
      ..recordUse(Endpoints.lrclib, DateTime(2026, 10, 18, 21, 30))
      ..applyManagedOverlay({'opensubtitles'});
    await pumpApp(
      tester,
      settings: settings,
      initialLocation: '/settings/privacy',
      overrides: [privacyUsageProvider.overrideWithValue(usage)],
    );
    final lrclib = find.byKey(const ValueKey('privacy.lrclib'));
    await tester.ensureVisible(lrclib);
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: lrclib,
        matching: find.textContaining('Last used Oct 18, 2026'),
      ),
      findsOneWidget,
    );
    final os = find.byKey(const ValueKey('privacy.opensubtitles'));
    await tester.ensureVisible(os);
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: os,
        matching: find.text('Managed by your organisation'),
      ),
      findsOneWidget,
    );
    final lan = find.byKey(const ValueKey('privacy.lanDiscovery'));
    await tester.ensureVisible(lan);
    await tester.pumpAndSettle();
    await tester.tap(lan);
    await tester.pumpAndSettle();
    expect(policy.lanDiscovery, isFalse);
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(close);
  });
}
