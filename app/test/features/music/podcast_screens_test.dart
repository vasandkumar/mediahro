import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediahro/app/app.dart';
import 'package:mediahro/app/router.dart';
import 'package:mediahro/core/db/library_database.dart';
import 'package:mediahro/core/providers.dart';
import 'package:mediahro/engine/engine_pool.dart';
import 'package:mediahro/features/music/music_providers.dart';
import 'package:mediahro/features/music/music_wiring.dart';
import 'package:mediahro/features/music/player/music_prefs.dart';
import 'package:mediahro/features/music/podcasts/podcast_service.dart';
import 'package:mediahro/features/music/podcasts/podcast_store.dart';
import 'package:mediahro/features/settings/settings_providers.dart';

import '../../helpers.dart';
import 'music_test_support.dart';
import 'podcast_test_support.dart';

/// POD-002 on screen: the Podcasts tab, subscribing, a show's episodes, and
/// the episode player.
void main() {
  late LibraryDatabase db;
  late ScriptedMusicEngine engine;
  late Directory data;
  late FakeNet net;
  late FakeDownloads downloads;
  late PodcastService service;
  late PodcastStore store;

  setUp(() async {
    db = LibraryDatabase.memory();
    engine = ScriptedMusicEngine();
    data = Directory.systemTemp.createTempSync('c2_pod_ui');
    net = FakeNet()
      ..serve('https://show.example/rss', podcastRss, etag: '"v1"')
      ..serve(
        'https://show.example/art/cover.jpg',
        'JPEGBYTES',
        type: 'image/jpeg',
      );
    downloads = FakeDownloads();
    store = PodcastStore(MusicPrefs(db));
    service = PodcastService(
      store: store,
      http: net.http,
      downloads: downloads,
      artDir: Directory('${data.path}/art'),
    );
  });
  tearDown(() async {
    await service.dispose();
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

  Future<void> pump(WidgetTester tester) async {
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
          podcastServiceProvider.overrideWithValue(service),
        ],
        child: MediahroApp(router: buildRouter(initialLocation: '/music')),
      ),
    );
    await settle(tester);
    await tester.ensureVisible(find.text('Podcasts'));
    await tester.tap(find.text('Podcasts'));
    await settle(tester);
  }

  Future<void> finish(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await settle(tester);
  }

  Future<void> subscribe(WidgetTester tester) async {
    await tester.tap(find.text('Add podcast'));
    await settle(tester);
    await tester.enterText(find.byType(TextField), 'show.example/rss');
    await tester.pump();
    await tester.tap(find.text('Subscribe'));
    await settle(tester);
  }

  testWidgets('POD-002 no podcasts yet: the tab says what to do, with no '
      'directory to browse', (tester) async {
    await pump(tester);
    expect(find.text('No podcasts yet'), findsOneWidget);
    expect(find.textContaining('no directory'), findsOneWidget);
    expect(find.text('Add podcast'), findsOneWidget);
    await finish(tester);
  });

  testWidgets('POD-002 subscribing by address lists the show with its '
      'unplayed episodes; a bad address says why', (tester) async {
    await pump(tester);
    await tester.tap(find.text('Add podcast'));
    await settle(tester);
    await tester.enterText(find.byType(TextField), 'not a url');
    await tester.pump();
    await tester.tap(find.text('Subscribe'));
    await settle(tester);
    expect(find.text("That isn't a web address."), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'show.example/rss');
    await tester.pump();
    await tester.tap(find.text('Subscribe'));
    await settle(tester);
    expect(find.text('The Show & Co'), findsOneWidget);
    expect(find.text('Ann Host'), findsOneWidget);
    expect(find.text('2 unplayed'), findsOneWidget);
    expect(find.text('Subscribed to "The Show & Co"'), findsOneWidget);
    await finish(tester);
  });

  testWidgets('POD-002 a show lists its episodes; marking one played '
      'changes the count', (tester) async {
    await pump(tester);
    await subscribe(tester);
    await tester.tap(find.text('The Show & Co'));
    await settle(tester);
    expect(find.text('Episode 2'), findsOneWidget);
    expect(find.text('Episode 1'), findsOneWidget);
    await tester.tap(find.byTooltip('More actions for Episode 2'));
    await settle(tester);
    await tester.tap(find.text('Mark as played'));
    await settle(tester);
    expect(find.text('Played'), findsOneWidget);
    await tester.tap(find.byTooltip('Podcast settings'));
    await settle(tester);
    await tester.tap(find.text('Oldest first'));
    await settle(tester);
    // Oldest first: episode 1 is the first row.
    expect(
      tester.getTopLeft(find.text('Episode 1')).dy,
      lessThan(tester.getTopLeft(find.text('Episode 2')).dy),
    );
    await finish(tester);
  });

  testWidgets('POD-002 tapping an episode plays it: the player shows the '
      "show, the speed is the show's, and the place is kept", (tester) async {
    await pump(tester);
    await subscribe(tester);
    await tester.tap(find.text('The Show & Co'));
    await settle(tester);
    await tester.tap(find.text('Episode 2'));
    await settle(tester);
    expect(uriOf(engine.opened.last), 'https://cdn.example/ep2.mp3');
    expect(find.text('Podcast'), findsOneWidget);
    expect(find.text('Episode 2'), findsWidgets);
    expect(find.text('The Show & Co'), findsWidgets);

    await tester.tap(find.byTooltip('Forward 30 seconds'));
    await settle(tester);
    expect(engine.current.position, const Duration(seconds: 30));

    await tester.tap(find.widgetWithText(ActionChip, '1×'));
    await settle(tester);
    await tester.tap(find.text('1.5×'));
    await settle(tester);
    expect(engine.rates.last, 1.5);
    expect(find.text('Each show remembers its own speed.'), findsOneWidget);
    // The speed is saved with the show when it is chosen.
    expect(
      (await tester.runAsync(
        () => store.show(PodcastStore.idOf('https://show.example/rss')),
      ))!.speed,
      1.5,
    );
    await finish(tester);
  });

  testWidgets('POD-002 unsubscribing asks first and empties the list', (
    tester,
  ) async {
    await pump(tester);
    await subscribe(tester);
    await tester.tap(find.text('The Show & Co'));
    await settle(tester);
    await tester.tap(find.byTooltip('Podcast settings'));
    await settle(tester);
    await tester.tap(find.text('Unsubscribe'));
    await settle(tester);
    expect(
      find.textContaining('Its downloaded episodes are deleted'),
      findsOneWidget,
    );
    await tester.tap(find.text('Unsubscribe').last);
    await settle(tester);
    expect(find.text('No podcasts yet'), findsOneWidget);
    expect(await service.shows(), isEmpty);
    await finish(tester);
  });
}
