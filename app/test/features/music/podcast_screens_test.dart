import 'dart:async';
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
///
/// What the screens wait for (a feed parsed on an isolate, files written,
/// the database) runs in real time, so every step waits for what it expects
/// to see instead of for a fixed number of frames: `until` lets real time
/// pass and pumps frames until the condition holds, however busy the machine
/// is.
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

  /// Lets real time pass (isolates, files, the database) and pumps frames
  /// until [done]; then a few more frames so transitions finish. [what] says
  /// what was waited for if it never happens.
  Future<void> until(
    WidgetTester tester,
    FutureOr<bool> Function() done, {
    required String what,
  }) async {
    // Only a bound for a test that would hang: not a time anything is
    // expected to take.
    final bound = DateTime.now().add(const Duration(seconds: 90));
    Future<bool> check() async => await done();
    while (!(await tester.runAsync(check))!) {
      if (DateTime.now().isAfter(bound)) fail('never happened: $what');
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> untilFound(WidgetTester tester, Finder finder) => until(
    tester,
    () => finder.evaluate().isNotEmpty,
    what: finder.describeMatch(Plurality.zero),
  );

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
    await untilFound(tester, find.text('Podcasts'));
    await tester.ensureVisible(find.text('Podcasts'));
    await tester.tap(find.text('Podcasts'));
    await untilFound(tester, find.text('Add podcast'));
  }

  Future<void> finish(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    // Let drift's stream-close timers and the last file operations run.
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> subscribe(WidgetTester tester) async {
    await tester.tap(find.text('Add podcast'));
    await untilFound(tester, find.byType(TextField));
    await tester.enterText(find.byType(TextField), 'show.example/rss');
    await tester.pump();
    await tester.tap(find.text('Subscribe'));
    await untilFound(tester, find.text('The Show & Co'));
  }

  Future<void> openShow(WidgetTester tester) async {
    await tester.tap(find.text('The Show & Co'));
    await untilFound(tester, find.text('Episode 2'));
  }

  testWidgets('POD-002 no podcasts yet: the tab says what to do, with no '
      'directory to browse', (tester) async {
    await pump(tester);
    await untilFound(tester, find.text('No podcasts yet'));
    expect(find.textContaining('no directory'), findsOneWidget);
    expect(find.text('Add podcast'), findsOneWidget);
    await finish(tester);
  });

  testWidgets('POD-002 subscribing by address lists the show with its '
      'unplayed episodes; a bad address says why', (tester) async {
    await pump(tester);
    await tester.tap(find.text('Add podcast'));
    await untilFound(tester, find.byType(TextField));
    await tester.enterText(find.byType(TextField), 'not a url');
    await tester.pump();
    await tester.tap(find.text('Subscribe'));
    await untilFound(tester, find.text("That isn't a web address."));
    await tester.enterText(find.byType(TextField), 'show.example/rss');
    await tester.pump();
    await tester.tap(find.text('Subscribe'));
    await untilFound(tester, find.text('Subscribed to "The Show & Co"'));
    expect(find.text('The Show & Co'), findsOneWidget);
    expect(find.text('Ann Host'), findsOneWidget);
    expect(find.text('2 unplayed'), findsOneWidget);
    await finish(tester);
  });

  testWidgets('POD-002 a show lists its episodes; marking one played '
      'changes the count', (tester) async {
    await pump(tester);
    await subscribe(tester);
    await openShow(tester);
    expect(find.text('Episode 2'), findsOneWidget);
    expect(find.text('Episode 1'), findsOneWidget);
    await tester.tap(find.byTooltip('More actions for Episode 2'));
    await untilFound(tester, find.text('Mark as played'));
    await tester.tap(find.text('Mark as played'));
    await untilFound(tester, find.text('Played'));
    await tester.tap(find.byTooltip('Podcast settings'));
    await untilFound(tester, find.text('Oldest first'));
    await tester.tap(find.text('Oldest first'));
    // Oldest first: episode 1 is the first row.
    await until(
      tester,
      () =>
          find.text('Episode 1').evaluate().isNotEmpty &&
          find.text('Episode 2').evaluate().isNotEmpty &&
          tester.getTopLeft(find.text('Episode 1')).dy <
              tester.getTopLeft(find.text('Episode 2')).dy,
      what: 'episode 1 above episode 2 (oldest first)',
    );
    await finish(tester);
  });

  testWidgets('POD-002 tapping an episode plays it: the player shows the '
      "show, the speed is the show's, and the place is kept", (tester) async {
    await pump(tester);
    await subscribe(tester);
    await openShow(tester);
    await tester.tap(find.text('Episode 2'));
    await untilFound(tester, find.text('Podcast'));
    expect(uriOf(engine.opened.last), 'https://cdn.example/ep2.mp3');
    expect(find.text('Episode 2'), findsWidgets);
    expect(find.text('The Show & Co'), findsWidgets);

    await tester.tap(find.byTooltip('Forward 30 seconds'));
    await until(
      tester,
      () => engine.current.position == const Duration(seconds: 30),
      what: 'the engine at 30 seconds',
    );

    await tester.tap(find.widgetWithText(ActionChip, '1×'));
    await untilFound(tester, find.text('1.5×'));
    await tester.tap(find.text('1.5×'));
    await until(
      tester,
      () =>
          engine.rates.isNotEmpty &&
          engine.rates.last == 1.5 &&
          find.text('Each show remembers its own speed.').evaluate().isNotEmpty,
      what: 'speed 1.5× and the note about it',
    );
    // The speed is saved with the show when it is chosen.
    final id = PodcastStore.idOf('https://show.example/rss');
    await until(
      tester,
      () async => (await store.show(id))?.speed == 1.5,
      what: 'the speed saved with the show',
    );
    await finish(tester);
  });

  testWidgets('POD-002 unsubscribing asks first and empties the list', (
    tester,
  ) async {
    await pump(tester);
    await subscribe(tester);
    await openShow(tester);
    await tester.tap(find.byTooltip('Podcast settings'));
    await untilFound(tester, find.text('Unsubscribe'));
    await tester.tap(find.text('Unsubscribe'));
    await untilFound(
      tester,
      find.textContaining('Its downloaded episodes are deleted'),
    );
    await tester.tap(find.text('Unsubscribe').last);
    await untilFound(tester, find.text('No podcasts yet'));
    expect(await tester.runAsync(service.shows), isEmpty);
    await finish(tester);
  });
}
