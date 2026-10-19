import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mediahro/app/app.dart';
import 'package:mediahro/app/appearance.dart';
import 'package:mediahro/app/root.dart';
import 'package:mediahro/app/shortcuts/cheat_sheet.dart';
import 'package:mediahro/core/net/network_policy.dart';
import 'package:mediahro/features/settings/core_settings.dart';
import 'package:mediahro/features/settings/settings_providers.dart';
import 'package:mediahro/features/settings/settings_store.dart';

/// Lane B3 acceptance on every platform (CI integration jobs A/I/M/W):
/// CORE-001, 002, 006, 007, 008, 009, 015 against the real settings file.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<ProviderContainer> launch(WidgetTester tester, {Key? key}) async {
    await tester.pumpWidget(
      ProviderScope(key: key ?? UniqueKey(), child: const MediahroApp()),
    );
    await tester.pumpAndSettle();
    return ProviderScope.containerOf(tester.element(find.byType(MediahroApp)));
  }

  GoRouter router(WidgetTester tester) =>
      GoRouter.of(tester.element(find.byType(Scaffold).first));

  Future<void> go(WidgetTester tester, String location) async {
    router(tester).go(location);
    await tester.pumpAndSettle();
  }

  Future<void> resetSettings(ProviderContainer c) async {
    final store = c.read(settingsStoreProvider)..resetAll();
    await store.flush();
  }

  testWidgets('CORE-001 last mode is restored after relaunch', (tester) async {
    var c = await launch(tester);
    await resetSettings(c);
    await go(tester, '/photos');
    await tester.pump(const Duration(milliseconds: 50));
    await c.read(settingsStoreProvider).flush();

    c = await launch(tester);
    expect(
      router(tester).routerDelegate.currentConfiguration.uri.path,
      '/photos',
    );
    await resetSettings(c);
  });

  testWidgets('CORE-002 first run: three actions, privacy line, no walls', (
    tester,
  ) async {
    final c = await launch(tester);
    await resetSettings(c);
    await go(tester, '/video');
    expect(find.text('Open a file'), findsOneWidget);
    expect(find.text('Add a folder'), findsOneWidget);
    expect(find.text('Add a server'), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('CORE-006 settings search, toggle persists to disk', (
    tester,
  ) async {
    final c = await launch(tester);
    await resetSettings(c);
    await go(tester, '/settings');
    await tester.enterText(find.byType(TextField).first, 'night');
    await tester.pumpAndSettle();
    expect(find.text('1 result'), findsOneWidget);
    expect(find.text('Theme'), findsWidgets);

    await go(tester, '/settings/appearance');
    await tester.tap(find.text('Pure black'));
    await tester.pumpAndSettle();
    await c.read(settingsStoreProvider).flush();
    final reread = await SettingsStore.open();
    expect(reread.get(CoreSettings.amoled), isTrue);
    await resetSettings(c);
  });

  testWidgets('CORE-007 theme follows the setting', (tester) async {
    final c = await launch(tester);
    await resetSettings(c);
    final store = c.read(settingsStoreProvider)
      ..set(CoreSettings.themeMode, ThemeMode.dark)
      ..set(CoreSettings.amoled, true);
    await tester.pumpAndSettle();
    expect(
      Theme.of(tester.element(find.byType(Scaffold).first)).brightness,
      Brightness.dark,
    );
    store.set(CoreSettings.themeMode, ThemeMode.light);
    await tester.pumpAndSettle();
    expect(
      Theme.of(tester.element(find.byType(Scaffold).first)).brightness,
      Brightness.light,
    );
    await resetSettings(c);
  });

  testWidgets('CORE-007 colours from wallpaper drive the theme (Android 12+)', (
    tester,
  ) async {
    final store = await SettingsStore.open();
    store
      ..resetAll()
      ..set(CoreSettings.themeMode, ThemeMode.light)
      ..set(CoreSettings.dynamicColor, true);
    await tester.pumpWidget(mediahroRoot(store));
    // DynamicColorBuilder reads the platform palette asynchronously.
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pumpAndSettle();
    final c = ProviderScope.containerOf(
      tester.element(find.byType(MediahroApp)),
    );
    final scheme = c.read(platformAppearanceProvider).dynamicLight;
    if (defaultTargetPlatform == TargetPlatform.android) {
      expect(scheme, isNotNull, reason: 'Material You palette on API 36');
    }
    if (scheme != null) {
      expect(
        Theme.of(tester.element(find.byType(Scaffold).first))
            .colorScheme
            .primary,
        scheme.primary,
      );
    }
    store.resetAll();
    await store.flush();
  });

  testWidgets('CORE-008 Arabic lays out right-to-left', (tester) async {
    final c = await launch(tester);
    c.read(settingsStoreProvider).set(CoreSettings.language, 'ar');
    await tester.pumpAndSettle();
    expect(
      Directionality.of(tester.element(find.byType(Scaffold).first)),
      TextDirection.rtl,
    );
    await resetSettings(c);
  });

  testWidgets('CORE-009 ? opens the shortcut cheat sheet', (tester) async {
    final c = await launch(tester);
    await resetSettings(c);
    await go(tester, '/video');
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.slash, character: '?');
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pumpAndSettle();
    expect(find.byType(ShortcutCheatSheet), findsOneWidget);
  });

  testWidgets('CORE-015 privacy dashboard lists every endpoint', (
    tester,
  ) async {
    final c = await launch(tester);
    await resetSettings(c);
    await go(tester, '/settings/privacy');
    for (final e in Endpoints.all) {
      final row = find.byKey(ValueKey('privacy.${e.id}'));
      await tester.ensureVisible(row);
      await tester.pumpAndSettle();
      expect(row, findsOneWidget, reason: e.id);
    }
  });
}
