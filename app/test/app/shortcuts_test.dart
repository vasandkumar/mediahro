import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediahro/app/capabilities.dart';
import 'package:mediahro/app/l10n/gen/app_localizations.dart';
import 'package:mediahro/app/shortcuts/cheat_sheet.dart';
import 'package:mediahro/app/shortcuts/key_spec.dart';
import 'package:mediahro/app/shortcuts/shortcut_bindings.dart';
import 'package:mediahro/app/shortcuts/shortcut_catalog.dart';
import 'package:mediahro/app/shortcuts/shortcut_scope.dart';
import 'package:mediahro/features/settings/settings_store.dart';

import '../helpers.dart';

ShortcutAction _action(String id) =>
    ShortcutCatalog.all.firstWhere((a) => a.id == id);

void main() {
  group('CORE-009 key specs', () {
    test('encode and decode round-trip', () {
      for (final k in [
        const KeySpec(LogicalKeyboardKey.keyS, primary: true, shift: true),
        const KeySpec(LogicalKeyboardKey.arrowLeft, alt: true),
        const KeySpec.character('?'),
      ]) {
        expect(KeySpec.decode(k.encode()), k);
      }
      expect(KeySpec.decode('banana'), isNull);
      expect(KeySpec.decode('hyper+12'), isNull);
    });

    test('primary is Cmd on Apple and Ctrl elsewhere', () {
      const k = KeySpec(LogicalKeyboardKey.keyO, primary: true);
      final mac = k.activator(AppPlatform.macos) as SingleActivator;
      final win = k.activator(AppPlatform.windows) as SingleActivator;
      expect(mac.meta, isTrue);
      expect(mac.control, isFalse);
      expect(win.control, isTrue);
      expect(win.meta, isFalse);
    });
  });

  group('CORE-009 default map (docs/06 §6.2)', () {
    ShortcutBindings bindings(AppPlatform p, [SettingsSnapshot? s]) =>
        ShortcutBindings.resolve(
          actions: ShortcutCatalog.all,
          platform: p,
          settings: s ?? const SettingsSnapshot(),
        );

    test('covers every key in the table', () {
      final b = bindings(AppPlatform.windows);
      expect(b.keysFor('player.playPause'), hasLength(2));
      expect(b.keysFor('player.seekForward10'), [
        const KeySpec(LogicalKeyboardKey.keyL),
      ]);
      expect(b.keysFor('player.screenshot'), [
        const KeySpec(LogicalKeyboardKey.keyS, primary: true),
      ]);
      expect(b.keysFor('app.shortcutSheet'), [const KeySpec.character('?')]);
      for (var i = 1; i <= 9; i++) {
        expect(b.keysFor('player.jump${i}0'), hasLength(1));
      }
    });

    test('platform conventions: F11 on Windows, Cmd+Ctrl+F on macOS', () {
      expect(
        bindings(AppPlatform.windows).keysFor('player.fullscreen'),
        contains(const KeySpec(LogicalKeyboardKey.f11)),
      );
      expect(
        bindings(AppPlatform.macos).keysFor('player.fullscreen'),
        contains(
          const KeySpec(LogicalKeyboardKey.keyF, primary: true, control: true),
        ),
      );
    });

    test('defaults have no conflicts on any platform', () {
      for (final p in AppPlatform.values) {
        expect(bindings(p).conflicts, isEmpty, reason: p.name);
      }
    });

    test('remapping replaces the default; empty unbinds', () async {
      final store = await SettingsStore.open(MemorySettingsPersistence(), null);
      setShortcut(store, _action('player.mute'), const [
        KeySpec(LogicalKeyboardKey.keyQ),
      ]);
      setShortcut(store, _action('player.info'), const []);
      final b = bindings(AppPlatform.windows, store.snapshot);
      expect(b.keysFor('player.mute'), [
        const KeySpec(LogicalKeyboardKey.keyQ),
      ]);
      expect(b.keysFor('player.info'), isEmpty);
      setShortcut(store, _action('player.mute'), null);
      expect(
        bindings(AppPlatform.windows, store.snapshot).keysFor('player.mute'),
        [const KeySpec(LogicalKeyboardKey.keyM)],
      );
    });

    test('conflict detection includes global keys inside the player', () async {
      final store = await SettingsStore.open(MemorySettingsPersistence(), null);
      setShortcut(store, _action('player.mute'), const [
        KeySpec(LogicalKeyboardKey.comma, primary: true),
      ]);
      final b = bindings(AppPlatform.windows, store.snapshot);
      expect(b.conflicts, hasLength(1));
      expect(
        b.clashesWith(
          _action('player.info'),
          const KeySpec(LogicalKeyboardKey.keyM),
        ),
        isEmpty,
      );
      expect(
        b
            .clashesWith(
              _action('player.info'),
              const KeySpec(LogicalKeyboardKey.keyL),
            )
            .map((a) => a.id),
        ['player.seekForward10'],
      );
    });

    test('cheat sheet text lists every action with its keys', () async {
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      final text = ShortcutCheatSheet.asText(bindings(AppPlatform.macos), l10n);
      for (final a in ShortcutCatalog.all) {
        expect(text, contains(a.label(l10n)));
      }
      expect(text, contains('⌘S'));
    });
  });

  group('CORE-009 in the app', () {
    testWidgets('? opens the cheat sheet; Copy produces printable text', (
      tester,
    ) async {
      await pumpApp(tester, size: const Size(1280, 800));
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.slash, character: '?');
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pumpAndSettle();
      expect(find.text('Keyboard shortcuts'), findsWidgets);
      expect(find.text('Play or pause'), findsOneWidget);

      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String?;
          }
          return null;
        },
      );
      await tester.tap(find.text('Copy as text'));
      await tester.pumpAndSettle();
      expect(copied, contains('Play or pause'));
      expect(copied, contains('Ctrl+S'));
    });

    testWidgets('Ctrl+, opens settings', (tester) async {
      await pumpApp(tester, size: const Size(1280, 800));
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.comma);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      expect(find.text('Search settings'), findsOneWidget);
    });

    testWidgets('Ctrl+2 switches to Music; remapped keys take effect', (
      tester,
    ) async {
      final store = await pumpApp(tester, size: const Size(1280, 800));
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.digit2);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      expect(find.text('Music arrives in milestone M4.'), findsOneWidget);

      setShortcut(store, _action('app.modePhotos'), const [
        KeySpec(LogicalKeyboardKey.f2),
      ]);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.f2);
      await tester.pumpAndSettle();
      expect(find.text('Photos arrives in milestone M5.'), findsOneWidget);
    });

    testWidgets('? typed in a text field reaches the field', (tester) async {
      await pumpApp(tester, initialLocation: '/settings');
      await tester.tap(find.byType(TextField));
      await tester.sendKeyEvent(LogicalKeyboardKey.slash, character: '?');
      await tester.pumpAndSettle();
      expect(find.byType(ShortcutCheatSheet), findsNothing);
    });

    testWidgets('player scope binds handlers without hard-coded keys', (
      tester,
    ) async {
      var toggled = 0;
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: ShortcutScopeWidget(
              scope: ShortcutScope.player,
              handlers: {'player.playPause': () => toggled++},
              child: const Focus(autofocus: true, child: SizedBox()),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
      expect(toggled, 2);
    });

    testWidgets('remapping UI captures a key and warns about conflicts', (
      tester,
    ) async {
      final store = await pumpApp(
        tester,
        initialLocation: '/settings/shortcuts',
      );
      await tester.ensureVisible(find.text('Mute'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Mute'));
      await tester.pumpAndSettle();
      expect(find.text('Press the new key combination.'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyL);
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Already used by Forward 10 seconds'),
        findsOneWidget,
      );
      await tester.tap(find.text('Replace'));
      await tester.pumpAndSettle();
      final b = ShortcutBindings.resolve(
        actions: ShortcutCatalog.all,
        platform: AppPlatform.android,
        settings: store.snapshot,
      );
      expect(b.keysFor('player.mute'), [
        const KeySpec(LogicalKeyboardKey.keyL),
      ]);
      expect(b.keysFor('player.seekForward10'), isEmpty);
      expect(b.conflicts, isEmpty);
    });
  });
}
