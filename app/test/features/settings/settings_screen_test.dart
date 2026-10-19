import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediahro/app/l10n/gen/app_localizations.dart';
import 'package:mediahro/features/settings/core_sections.dart';
import 'package:mediahro/features/settings/core_settings.dart';
import 'package:mediahro/features/settings/settings_providers.dart';
import 'package:mediahro/features/settings/settings_registry.dart';
import 'package:mediahro/features/settings/settings_store.dart';
import 'package:mediahro_design/mediahro_design.dart';

import '../../helpers.dart';

void main() {
  testWidgets('CORE-006 every row has a title and a one-line description', (
    tester,
  ) async {
    await pumpApp(tester, initialLocation: '/settings');
    final container = ProviderScope.containerOf(
      tester.element(find.byType(Scaffold).first),
    );
    final l10n = AppLocalizations.of(
      tester.element(find.byType(Scaffold).first),
    );
    final registry = container.read(settingsRegistryProvider);
    expect(registry.sections, isNotEmpty);
    for (final s in registry.sections) {
      for (final e in s.entries) {
        expect(e.title(l10n), isNotEmpty, reason: e.id);
        final d = e.description(l10n);
        expect(d, isNotEmpty, reason: e.id);
        expect(d.contains('\n'), isFalse, reason: '${e.id}: one line');
      }
    }
  });

  testWidgets('CORE-006 sections follow docs/06 order', (tester) async {
    await pumpApp(tester, initialLocation: '/settings');
    final titles = ['Appearance', 'Keyboard shortcuts', 'Privacy'];
    final ys = [for (final t in titles) tester.getTopLeft(find.text(t)).dy];
    expect(ys, orderedEquals([...ys]..sort()));
  });

  testWidgets('CORE-006 search finds rows by title, description and keyword', (
    tester,
  ) async {
    await pumpApp(tester, initialLocation: '/settings');
    await tester.enterText(find.byType(TextField), 'night');
    await tester.pumpAndSettle();
    expect(find.text('Theme'), findsOneWidget);
    expect(find.text('1 result'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'pure black');
    await tester.pumpAndSettle();
    expect(find.byType(KSettingsRow), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'zzzz');
    await tester.pumpAndSettle();
    expect(find.textContaining('No settings match'), findsOneWidget);
  });

  testWidgets('CORE-006 toggling a row persists the setting', (tester) async {
    final store = await pumpApp(
      tester,
      initialLocation: '/settings/appearance',
    );
    await tester.tap(find.text('Pure black'));
    await tester.pumpAndSettle();
    expect(store.get(CoreSettings.amoled), isTrue);
  });

  testWidgets('CORE-006 choice rows open a sheet of options', (tester) async {
    final store = await pumpApp(
      tester,
      initialLocation: '/settings/appearance',
    );
    await tester.tap(find.text('Theme'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dark'));
    await tester.pumpAndSettle();
    expect(store.get(CoreSettings.themeMode), ThemeMode.dark);
  });

  testWidgets('CORE-007 changing the theme recolours the app', (tester) async {
    final store = await pumpApp(
      tester,
      initialLocation: '/settings/appearance',
    );
    Color bg() =>
        Theme.of(tester.element(find.text('Theme'))).colorScheme.surface;
    final light = bg();
    store.set(CoreSettings.themeMode, ThemeMode.dark);
    await tester.pumpAndSettle();
    expect(bg(), isNot(light));
    store.set(CoreSettings.amoled, true);
    await tester.pumpAndSettle();
    expect(bg(), const Color(0xFF000000));
  });

  testWidgets('CORE-008 choosing a language switches the UI', (tester) async {
    final store = await pumpApp(
      tester,
      initialLocation: '/settings/appearance',
    );
    store.set(CoreSettings.language, 'ar');
    await tester.pumpAndSettle();
    expect(
      Directionality.of(tester.element(find.byType(KSettingsRow).first)),
      TextDirection.rtl,
    );
  });

  testWidgets('CORE-006 advanced rows are collapsed', (tester) async {
    await pumpApp(tester, initialLocation: '/settings/appearance');
    expect(find.text('Reduce motion'), findsNothing);
    await tester.scrollUntilVisible(find.text('Show advanced options'), 200);
    await tester.tap(find.text('Show advanced options'));
    await tester.pumpAndSettle();
    expect(find.text('Reduce motion'), findsOneWidget);
  });

  testWidgets('CORE-006 reset section asks, then restores defaults', (
    tester,
  ) async {
    final store = await pumpApp(
      tester,
      initialLocation: '/settings/appearance',
    );
    store.set(CoreSettings.amoled, true);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Reset section'), 200);
    await tester.drag(find.byType(Scrollable).last, const Offset(0, -300));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reset section'));
    await tester.pumpAndSettle();
    expect(find.text('Reset Appearance?'), findsOneWidget);
    await tester.tap(find.text('Reset'));
    await tester.pumpAndSettle();
    expect(store.get(CoreSettings.amoled), isFalse);
  });

  testWidgets('CORE-006 managed rows show the lock and cannot change', (
    tester,
  ) async {
    final store = await pumpApp(
      tester,
      initialLocation: '/settings/appearance',
    );
    store.applyManaged({'appearance.amoled': true});
    await tester.pumpAndSettle();
    expect(find.text('Managed by your organisation'), findsOneWidget);
    await tester.tap(find.text('Pure black'));
    await tester.pumpAndSettle();
    expect(store.get(CoreSettings.amoled), isTrue);
  });

  testWidgets('CORE-006 wide windows show list and detail together', (
    tester,
  ) async {
    await pumpApp(
      tester,
      initialLocation: '/settings',
      size: const Size(1280, 800),
    );
    expect(find.text('Search settings'), findsOneWidget);
    expect(find.text('Theme'), findsOneWidget);
  });

  testWidgets('CORE-006 lanes contribute sections without editing B3 files', (
    tester,
  ) async {
    final key = SettingKey.boolean('video.demo', defaultValue: false);
    final store = await pumpApp(
      tester,
      initialLocation: '/settings',
      overrides: [
        settingsContributionsProvider.overrideWithValue([
          ...coreSettingsContributions,
          SettingsContribution(
            section: SettingsSectionId.video,
            entries: [
              ToggleSetting(
                key: key,
                title: (l) => l.appComingInMilestone('demo', 'M3'),
                description: (l) => l.appTitle,
              ),
            ],
          ),
        ]),
      ],
    );
    expect(find.text('Picture, hardware decoding and HDR'), findsOneWidget);
    await tester.tap(find.text('Picture, hardware decoding and HDR'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('demo arrives in milestone M3.'));
    await tester.pumpAndSettle();
    expect(store.get(key), isTrue);
  });

  testWidgets('CORE-006 export menu shows the JSON document', (tester) async {
    await pumpApp(tester, initialLocation: '/settings');
    await tester.tap(find.byTooltip('More actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Export settings'));
    await tester.pumpAndSettle();
    expect(find.textContaining('mediahro.settings'), findsOneWidget);
  });

  testWidgets('CORE-006 import applies pasted settings', (tester) async {
    final store = await pumpApp(tester, initialLocation: '/settings');
    await tester.tap(find.byTooltip('More actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Import settings'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextField).last,
      '{"format": "mediahro.settings", "schema": 1, '
      '"values": {"appearance.amoled": true}}',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Import settings'));
    await tester.pumpAndSettle();
    expect(store.get(CoreSettings.amoled), isTrue);
    expect(find.textContaining('Settings imported: 1'), findsOneWidget);
  });

  testWidgets('SYS-008 settings at 200 % text and in RTL do not overflow', (
    tester,
  ) async {
    await pumpApp(
      tester,
      initialLocation: '/settings/appearance',
      textScale: 2,
      locale: const Locale('ar'),
    );
    expect(tester.takeException(), isNull);
  });

  test('CORE-006 search folds case and accents', () {
    expect(SettingsRegistry.fold('Contraste Élevé'), 'contraste eleve');
  });
}
