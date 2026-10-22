import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mediahro/app/app.dart';
import 'package:mediahro/features/settings/core_settings.dart';
import 'package:mediahro/features/settings/settings_providers.dart';
import 'package:mediahro/features/settings/settings_store.dart';

/// CORE-001 as the device test sees it (`b3_foundations_test.dart`): the app
/// is launched twice with a settings document that outlives a launch, and the
/// store of each launch is the default one, which loads lazily after the first
/// frame.
void main() {
  late MemorySettingsPersistence disk;

  setUp(() => disk = MemorySettingsPersistence());

  /// A launch like the device test's: a fresh scope whose store loads the
  /// document asynchronously.
  Future<ProviderContainer> launch(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        key: UniqueKey(),
        overrides: [
          settingsStoreProvider.overrideWith((ref) {
            final store = SettingsStore(disk);
            unawaited(store.load());
            ref.onDispose(store.dispose);
            return store;
          }),
        ],
        child: const MediahroApp(),
      ),
    );
    await tester.pumpAndSettle();
    return ProviderScope.containerOf(tester.element(find.byType(MediahroApp)));
  }

  GoRouter router(WidgetTester tester) =>
      GoRouter.of(tester.element(find.byType(Scaffold).first));

  String location(WidgetTester tester) =>
      router(tester).routerDelegate.currentConfiguration.uri.path;

  Future<void> goAndSave(
    WidgetTester tester,
    ProviderContainer c,
    String path,
  ) async {
    router(tester).go(path);
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 50));
    await c.read(settingsStoreProvider).flush();
  }

  testWidgets('CORE-001 last mode is restored after relaunch', (tester) async {
    var c = await launch(tester);
    await goAndSave(tester, c, '/photos');

    c = await launch(tester);

    expect(location(tester), '/photos');
  });

  testWidgets('CORE-001 a first launch opens Video', (tester) async {
    await launch(tester);
    expect(location(tester), '/video');
  });

  testWidgets('CORE-001 the mode survives two relaunches', (tester) async {
    var c = await launch(tester);
    await goAndSave(tester, c, '/music');

    c = await launch(tester);
    expect(location(tester), '/music');
    await c.read(settingsStoreProvider).flush();

    await launch(tester);
    expect(location(tester), '/music');
  });

  testWidgets(
    'CORE-001 a reset of all settings does not forget the mode in use',
    (tester) async {
      disk.document = {
        'values': {'shell.lastMode': 'photos'},
      };
      final c = await launch(tester);
      final store = c.read(settingsStoreProvider);
      expect(location(tester), '/photos');

      store.resetAll();
      await tester.pumpAndSettle();

      expect(store.get(CoreSettings.lastMode), 'photos');
    },
  );

  testWidgets(
    'CORE-001 relaunch after a reset made while a mode was already open',
    (tester) async {
      // What the device test does after an earlier run left Photos behind:
      // launch (restores Photos), reset every setting, "go" to Photos (it is
      // already there, so nothing changes), launch again.
      disk.document = {
        'values': {'shell.lastMode': 'photos'},
      };
      var c = await launch(tester);
      expect(location(tester), '/photos');
      c.read(settingsStoreProvider).resetAll();
      await goAndSave(tester, c, '/photos');

      c = await launch(tester);

      expect(location(tester), '/photos');
    },
  );

  testWidgets('CORE-001 resetting from Settings keeps the mode before it', (
    tester,
  ) async {
    disk.document = {
      'values': {'shell.lastMode': 'music'},
    };
    final c = await launch(tester);
    router(tester).go('/settings');
    await tester.pumpAndSettle();
    final store = c.read(settingsStoreProvider)..resetAll();
    await tester.pumpAndSettle();

    expect(store.get(CoreSettings.lastMode), 'music');
  });

  testWidgets('CORE-001 Search and Settings are not modes', (tester) async {
    var c = await launch(tester);
    await goAndSave(tester, c, '/photos');
    await goAndSave(tester, c, '/search');
    await goAndSave(tester, c, '/settings');

    expect(c.read(settingsStoreProvider).get(CoreSettings.lastMode), 'photos');
    c = await launch(tester);
    expect(location(tester), '/photos');
  });

  testWidgets('CORE-001 a cold start opens the last mode, whatever it was', (
    tester,
  ) async {
    for (final mode in ['video', 'music', 'photos']) {
      disk.document = {
        'values': {'shell.lastMode': mode},
      };
      await launch(tester);
      expect(location(tester), '/$mode');
    }
  });

  testWidgets('CORE-001 restoring off opens Video and still remembers', (
    tester,
  ) async {
    disk.document = {
      'values': {
        'shell.lastMode': 'music',
        'appearance.restoreLastMode': false,
      },
    };
    final c = await launch(tester);
    expect(location(tester), '/video');
    await goAndSave(tester, c, '/photos');
    expect(c.read(settingsStoreProvider).get(CoreSettings.lastMode), 'photos');
  });
}
