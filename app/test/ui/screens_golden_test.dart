import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediahro/app/app_strings.dart';
import 'package:mediahro/app/l10n/gen/app_localizations.dart';
import 'package:mediahro/app/router.dart';
import 'package:mediahro/app/shortcuts/cheat_sheet.dart';
import 'package:mediahro/features/onboarding/first_run_panel.dart';
import 'package:mediahro/features/settings/privacy/privacy_dashboard.dart';
import 'package:mediahro/features/settings/settings_providers.dart';
import 'package:mediahro/features/settings/settings_registry.dart';
import 'package:mediahro/features/settings/settings_screen.dart';
import 'package:mediahro/features/settings/settings_store.dart';
import 'package:mediahro_design/mediahro_design.dart';
import 'package:mediahro_design/testing.dart';

/// Goldens for B3's screens (docs/11 §1): per platform family × light/dark,
/// each file holding 1.0/1.5/2.0 text × LTR/RTL plus reduced motion.
void main() {
  final screens = <String, Widget Function()>{
    'first_run': () => const Scaffold(body: FirstRunPanel()),
    'settings_list': () => const SettingsScreen(),
    'settings_appearance': () => const Scaffold(
      body: SettingsSectionBody(section: SettingsSectionId.appearance),
    ),
    'privacy_dashboard': () =>
        const Scaffold(body: SingleChildScrollView(child: PrivacyDashboard())),
    'shortcut_sheet': () => const Scaffold(
      body: SingleChildScrollView(child: ShortcutCheatSheet()),
    ),
  };

  const shells = {'shell_phone': (360.0, 4), 'shell_tablet': (760.0, 2)};
  const platforms = {
    PlatformFamily.material: TargetPlatform.android,
    PlatformFamily.apple: TargetPlatform.iOS,
    PlatformFamily.fluent: TargetPlatform.windows,
  };

  for (final family in PlatformFamily.values) {
    for (final brightness in Brightness.values) {
      for (final MapEntry(key: name, value: (width, columns))
          in shells.entries) {
        testWidgets('CORE-001 $name ${family.name}/${brightness.name}', (
          tester,
        ) async {
          final store = await tester.runAsync(
            () => SettingsStore.open(MemorySettingsPersistence(), null),
          );
          debugDefaultTargetPlatformOverride = platforms[family];
          try {
            await expectGoldenMatrix(
              tester,
              name: name,
              family: family,
              brightness: brightness,
              cellWidth: width,
              columns: columns,
              cellHeight: 640,
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              stringsBuilder: (c) => AppKStrings(AppLocalizations.of(c)),
              builder: (_) => SizedBox(
                height: 640,
                child: ProviderScope(
                  overrides: [settingsStoreProvider.overrideWithValue(store!)],
                  child: Router.withConfig(
                    config: buildRouter(initialLocation: '/music'),
                  ),
                ),
              ),
            );
          } finally {
            debugDefaultTargetPlatformOverride = null;
          }
        });
      }
      group(
        'CORE-006/007/009/015 screens ${family.name}/${brightness.name}',
        () {
          for (final e in screens.entries) {
            testWidgets(e.key, (tester) async {
              final store = await tester.runAsync(
                () => SettingsStore.open(MemorySettingsPersistence(), null),
              );
              await expectGoldenMatrix(
                tester,
                name: e.key,
                family: family,
                brightness: brightness,
                localizationsDelegates: AppLocalizations.localizationsDelegates,
                supportedLocales: AppLocalizations.supportedLocales,
                stringsBuilder: (c) => AppKStrings(AppLocalizations.of(c)),
                builder: (_) => SizedBox(
                  height: 640,
                  child: ProviderScope(
                    overrides: [
                      settingsStoreProvider.overrideWithValue(store!),
                    ],
                    child: e.value(),
                  ),
                ),
              );
            });
          }
        },
      );
    }
  }
}
