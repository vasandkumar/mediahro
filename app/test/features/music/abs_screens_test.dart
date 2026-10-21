import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediahro/app/app.dart';
import 'package:mediahro/app/router.dart';
import 'package:mediahro/core/db/library_database.dart';
import 'package:mediahro/core/providers.dart';
import 'package:mediahro/engine/engine_pool.dart';
import 'package:mediahro/features/music/abs/abs_account.dart';
import 'package:mediahro/features/music/abs/abs_service.dart';
import 'package:mediahro/features/music/abs/abs_store.dart';
import 'package:mediahro/features/music/music_providers.dart';
import 'package:mediahro/features/music/music_wiring.dart';
import 'package:mediahro/features/music/player/music_prefs.dart';
import 'package:mediahro/features/settings/settings_providers.dart';
import 'package:mediahro_engine/mediahro_engine.dart';
import 'package:mediahro_servers/mediahro_servers.dart';

import '../../helpers.dart';
import 'abs_test.dart' show FakeServer;
import 'music_test_support.dart';
import 'podcast_test_support.dart';

/// POD-003 on screen, against a pretend Audiobookshelf server.
void main() {
  late LibraryDatabase db;
  late ScriptedMusicEngine engine;
  late Directory data;
  late FakeServer server;
  late FakeDownloads downloads;
  late AbsAccount account;

  setUp(() async {
    db = LibraryDatabase.memory();
    engine = ScriptedMusicEngine();
    data = Directory.systemTemp.createTempSync('c2_abs_ui');
    server = FakeServer();
    downloads = FakeDownloads();
    account = AbsAccount(
      ServerAccount(
        id: 'acc1',
        kind: ServerKind.audiobookshelf,
        baseUri: Uri.parse('https://abs.example'),
        displayName: 'Home server',
      ),
      server,
    );
  });
  tearDown(() async {
    await db.close();
    try {
      data.deleteSync(recursive: true);
    } on FileSystemException {
      // Best effort on Windows.
    }
  });

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 30; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> pump(
    WidgetTester tester, {
    List<AbsAccount> accounts = const [],
  }) async {
    tester.view
      ..physicalSize = const Size(420, 900) * tester.view.devicePixelRatio
      ..devicePixelRatio = tester.view.devicePixelRatio;
    addTearDown(tester.view.resetPhysicalSize);
    final settings = await tester.runAsync(memoryStore);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsStoreProvider.overrideWithValue(settings!),
          ...musicOverrides,
          libraryDatabaseProvider.overrideWithValue(db),
          appDataDirectoryProvider.overrideWithValue(data),
          sourceResolverProvider.overrideWithValue(
            localMusicFiles(db).resolver,
          ),
          playbackEngineFactoryProvider.overrideWithValue((_) => engine),
          audiobookshelfAccountsProvider.overrideWithValue(accounts),
          absServiceProvider.overrideWithValue(
            AbsService(store: AbsStore(MusicPrefs(db)), downloads: downloads),
          ),
        ],
        child: MediahroApp(router: buildRouter(initialLocation: '/music')),
      ),
    );
    await settle(tester);
  }

  Future<void> openTab(WidgetTester tester) async {
    await tester.ensureVisible(find.text('Audiobookshelf'));
    await tester.tap(find.text('Audiobookshelf'));
    await settle(tester);
  }

  Future<void> finish(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await settle(tester);
  }

  testWidgets('POD-003 without a connected server there is no tab', (
    tester,
  ) async {
    await pump(tester);
    expect(find.text('Audiobookshelf'), findsNothing);
    await finish(tester);
  });

  testWidgets('POD-003 with a server: continue listening, then its '
      'libraries; a library lists its books, a page at a time', (tester) async {
    await pump(tester, accounts: [account]);
    await openTab(tester);
    expect(find.text('Continue listening'), findsOneWidget);
    expect(find.text('Dune'), findsOneWidget);
    expect(find.text('Home server'), findsOneWidget);
    expect(find.widgetWithText(ListTile, 'Audiobooks'), findsOneWidget);
    expect(find.widgetWithText(ListTile, 'Podcasts'), findsOneWidget);

    await tester.tap(find.widgetWithText(ListTile, 'Audiobooks'));
    await settle(tester);
    expect(find.text('Dune'), findsOneWidget);
    expect(find.text('Emma'), findsOneWidget);
    // The next page arrives when the end of the list is reached.
    expect(find.text('Persuasion'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'emm');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await settle(tester);
    expect(find.text('Emma'), findsOneWidget);
    expect(find.text('Persuasion'), findsNothing);
    await finish(tester);
  });

  testWidgets('POD-003 a book: play, keep an offline copy, mark finished', (
    tester,
  ) async {
    await pump(tester, accounts: [account]);
    await openTab(tester);
    await tester.tap(find.widgetWithText(ListTile, 'Audiobooks'));
    await settle(tester);
    await tester.tap(find.text('Emma'));
    await settle(tester);
    expect(find.text('Play'), findsOneWidget);

    await tester.tap(find.text('Download'));
    await settle(tester);
    expect(
      downloads.enqueued.single.$1.toString(),
      'https://abs.example/download/emma?token=t1',
    );
    expect(find.text('Waiting to download'), findsOneWidget);

    await tester.tap(find.text('Mark as finished'));
    await settle(tester);
    expect(server.played, [('emma', true)]);
    expect(find.text('Mark as not finished'), findsOneWidget);

    await tester.tap(find.text('Play'));
    await settle(tester);
    expect((engine.opened.last as UriSource).uri.path, '/audio/emma');
    expect(find.text('Audiobookshelf'), findsOneWidget);
    expect(find.text('Emma'), findsWidgets);
    await tester.tap(find.byTooltip('Forward 30 seconds'));
    await settle(tester);
    expect(engine.current.position, const Duration(seconds: 30));
    await finish(tester);
  });

  testWidgets('POD-003 a server that cannot be reached says so, and Try '
      'again asks it again', (tester) async {
    server.unreachable = true;
    await pump(tester, accounts: [account]);
    await openTab(tester);
    expect(find.text("Couldn't reach Home server."), findsOneWidget);
    server.unreachable = false;
    await tester.tap(find.text('Try again'));
    await settle(tester);
    expect(find.widgetWithText(ListTile, 'Audiobooks'), findsOneWidget);
    await finish(tester);
  });
}
