import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart' show RouteBase;
import 'package:mediahro/app/app.dart';
import 'package:mediahro/app/router.dart';
import 'package:mediahro/core/db/library_database.dart';
import 'package:mediahro/core/library/library_views.dart';
import 'package:mediahro/core/providers.dart';
import 'package:mediahro/engine/engine_pool.dart';
import 'package:mediahro/features/music/music_wiring.dart';
import 'package:mediahro/features/settings/settings_providers.dart';
import 'package:mediahro/features/video/video_open.dart';
import 'package:mediahro_design/mediahro_design.dart';

import '../../core/seed.dart';
import '../../helpers.dart';
import '../music/music_test_support.dart';
import '../photos/photos_harness.dart';

/// LIB-004 (hand check H1): each mode's app bar has a toggle between its
/// curated library view and its folder view; the choice is kept per mode and
/// comes back when the mode is opened again.
void main() {
  /// Database work runs on the real event loop; some screens poll, so
  /// `pumpAndSettle` would never finish.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 20; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  /// Takes the screen down so the database's streams close before it does.
  Future<void> leave(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await settle(tester);
  }

  const showFolders = 'Show folders';
  const showLibrary = 'Show library';

  /// The toggle by its label, so a missing or mislabelled one fails the test.
  Finder toggle(String label) => find.byTooltip(label);

  Future<void> pumpApp(
    WidgetTester tester, {
    required String route,
    required List<Override> overrides,
    List<RouteBase> routes = const [],
  }) async {
    tester.view
      ..physicalSize = const Size(420, 860) * tester.view.devicePixelRatio
      ..devicePixelRatio = tester.view.devicePixelRatio;
    addTearDown(tester.view.resetPhysicalSize);
    final store = await tester.runAsync(memoryStore);
    await tester.pumpWidget(
      ProviderScope(
        key: UniqueKey(),
        overrides: [
          settingsStoreProvider.overrideWithValue(store!),
          ...overrides,
        ],
        child: MediahroApp(
          router: buildRouter(initialLocation: route, fullScreenRoutes: routes),
        ),
      ),
    );
    await settle(tester);
  }

  /// Both views of one mode, through the toggle, then a relaunch.
  Future<void> exerciseToggle(
    WidgetTester tester, {
    required Future<void> Function() launch,
    required void Function() expectLibrary,
    required void Function() expectFolders,
    required LibraryDatabase db,
    required LibraryMode mode,
  }) async {
    final semantics = tester.ensureSemantics();
    await launch();
    expectLibrary();
    expect(toggle(showLibrary), findsNothing);

    // 44 pt target and a label (accessibility).
    final size = tester.getSize(toggle(showFolders));
    expect(size.width, greaterThanOrEqualTo(44));
    expect(size.height, greaterThanOrEqualTo(44));
    final node = tester.getSemantics(toggle(showFolders));
    expect('${node.label} ${node.tooltip}', contains(showFolders));

    await tester.tap(toggle(showFolders));
    await settle(tester);
    expectFolders();
    expect(toggle(showFolders), findsNothing);
    expect(toggle(showLibrary), findsOneWidget);

    // Persisted in the library database, per mode.
    final stored = await tester.runAsync(() => LibraryViews(db).viewMode(mode));
    expect(stored, ViewMode.folders);
    for (final other in LibraryMode.values.where((m) => m != mode)) {
      final v = await tester.runAsync(() => LibraryViews(db).viewMode(other));
      expect(v, ViewMode.library, reason: '${other.name} is not affected');
    }

    // Coming back to the mode in a new launch restores the choice.
    await launch();
    expectFolders();

    await tester.tap(toggle(showLibrary));
    await settle(tester);
    expectLibrary();
    final back = await tester.runAsync(() => LibraryViews(db).viewMode(mode));
    expect(back, ViewMode.library);
    semantics.dispose();
    await leave(tester);
  }

  group('LIB-004 view toggle', () {
    testWidgets('LIB-004 Video switches between the library and its folders', (
      tester,
    ) async {
      final db = LibraryDatabase.memory();
      addTearDown(() => tester.runAsync(db.close));
      await tester.runAsync(() async {
        final seed = Seed(db);
        await seed.item('Movies/Alien.mkv');
        await seed.item('Movies/Heat.mkv');
        await seed.item('Loose.mkv');
      });
      await exerciseToggle(
        tester,
        db: db,
        mode: LibraryMode.video,
        launch: () => pumpApp(
          tester,
          route: '/video',
          overrides: [
            libraryDatabaseProvider.overrideWithValue(db),
            ...videoOverrides,
          ],
          routes: videoRoutes,
        ),
        expectLibrary: () {
          expect(find.text('All videos'), findsOneWidget);
          expect(find.text('Alien'), findsWidgets);
        },
        expectFolders: () {
          // The root's folder and the file directly in it; no flat list.
          expect(find.text('All videos'), findsNothing);
          expect(find.text('Movies'), findsOneWidget);
          expect(find.text('Loose'), findsOneWidget);
          expect(find.text('Alien'), findsNothing);
        },
      );
    });

    testWidgets('LIB-004 Video folder view opens into a folder', (
      tester,
    ) async {
      final db = LibraryDatabase.memory();
      addTearDown(() => tester.runAsync(db.close));
      await tester.runAsync(() async {
        final seed = Seed(db);
        await seed.item('Movies/Alien.mkv');
      });
      await pumpApp(
        tester,
        route: '/video',
        overrides: [
          libraryDatabaseProvider.overrideWithValue(db),
          ...videoOverrides,
        ],
        routes: videoRoutes,
      );
      await tester.tap(toggle(showFolders));
      await settle(tester);

      await tester.tap(find.text('Movies'));
      await settle(tester);

      expect(find.text('Alien'), findsOneWidget);
      await leave(tester);
    });

    testWidgets('LIB-004 Music switches between its tabs and its folders', (
      tester,
    ) async {
      final db = LibraryDatabase.memory();
      final data = Directory.systemTemp.createTempSync('lib004_music');
      addTearDown(() async {
        await tester.runAsync(db.close);
        try {
          data.deleteSync(recursive: true);
        } on FileSystemException {
          // Best effort on Windows.
        }
      });
      await tester.runAsync(() async {
        final seed = MusicSeed(db);
        await seed.song(
          'a/1.flac',
          title: 'Alpha',
          artist: 'Amy',
          album: 'First',
        );
        await seed.song(
          'b/1.mp3',
          title: 'Gamma',
          artist: 'Bob',
          album: 'Second',
        );
      });
      final engine = ScriptedMusicEngine();
      await exerciseToggle(
        tester,
        db: db,
        mode: LibraryMode.music,
        launch: () => pumpApp(
          tester,
          route: '/music',
          overrides: [
            ...musicOverrides,
            libraryDatabaseProvider.overrideWithValue(db),
            appDataDirectoryProvider.overrideWithValue(data),
            sourceResolverProvider.overrideWithValue(
              localMusicFiles(db).resolver,
            ),
            playbackEngineFactoryProvider.overrideWithValue((_) => engine),
          ],
        ),
        expectLibrary: () {
          expect(find.text('Albums'), findsWidgets);
          expect(find.text('Alpha'), findsOneWidget);
        },
        expectFolders: () {
          // One list of folders; the tab bar is gone.
          expect(find.text('Albums'), findsNothing);
          expect(find.text('Alpha'), findsNothing);
          expect(find.byType(TabBar), findsNothing);
          // The source's row.
          expect(find.widgetWithText(KRow, 'Music'), findsOneWidget);
        },
      );
    });

    testWidgets('LIB-004 Photos switches between its tabs and its folders', (
      tester,
    ) async {
      final h = await PhotosHarness.create(tester);
      final entries = fakeEntries(days: 1, perDay: 3, folder: (_) => 'Trip');
      await exerciseToggle(
        tester,
        db: h.db,
        mode: LibraryMode.photos,
        launch: () => h.pump(tester, entries: entries),
        expectLibrary: () {
          expect(find.text('Timeline'), findsOneWidget);
          expect(find.byType(TabBar), findsOneWidget);
        },
        expectFolders: () {
          expect(find.text('Timeline'), findsNothing);
          expect(find.byType(TabBar), findsNothing);
          // The single source opens at its root: the folder is listed.
          expect(find.text('Trip'), findsOneWidget);
        },
      );
    });
  });
}
