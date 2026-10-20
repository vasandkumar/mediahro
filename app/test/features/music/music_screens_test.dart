import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediahro/app/app.dart';
import 'package:mediahro/app/router.dart';
import 'package:mediahro/core/db/library_database.dart';
import 'package:mediahro/core/providers.dart';
import 'package:mediahro/engine/engine_pool.dart';
import 'package:mediahro/features/music/music_home_screen.dart';
import 'package:mediahro/features/music/music_providers.dart';
import 'package:mediahro/features/music/music_wiring.dart';
import 'package:mediahro/features/music/ui/now_playing.dart';
import 'package:mediahro/features/settings/settings_providers.dart';

import 'package:mediahro_design/mediahro_design.dart';

import '../../helpers.dart';
import 'music_test_support.dart';

void main() {
  late LibraryDatabase db;
  late ScriptedMusicEngine engine;
  late Directory data;

  setUp(() async {
    db = LibraryDatabase.memory();
    engine = ScriptedMusicEngine();
    data = Directory.systemTemp.createTempSync('c2_ui');
  });
  tearDown(() async {
    await db.close();
    try {
      data.deleteSync(recursive: true);
    } on FileSystemException {
      // Best effort on Windows.
    }
  });

  Future<void> seedAlbum() async {
    final seed = MusicSeed(db);
    await seed.song(
      'a/1.flac',
      title: 'Alpha',
      artist: 'Amy',
      album: 'First',
      albumArtist: 'Amy',
      track: 1,
      year: 2001,
      genre: 'Pop',
    );
    await seed.song(
      'a/2.flac',
      title: 'Beta',
      artist: 'Amy',
      album: 'First',
      albumArtist: 'Amy',
      track: 2,
      year: 2001,
      genre: 'Pop',
    );
    await seed.song(
      'b/1.mp3',
      title: 'Gamma',
      artist: 'Bob',
      album: 'Second',
      albumArtist: 'Bob',
      genre: 'Rock',
    );
  }

  Future<void> pump(WidgetTester tester) async {
    tester.view
      ..physicalSize = const Size(420, 860) * tester.view.devicePixelRatio
      ..devicePixelRatio = tester.view.devicePixelRatio;
    addTearDown(tester.view.resetPhysicalSize);
    final store = await tester.runAsync(memoryStore);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsStoreProvider.overrideWithValue(store!),
          ...musicOverrides,
          libraryDatabaseProvider.overrideWithValue(db),
          appDataDirectoryProvider.overrideWithValue(data),
          sourceResolverProvider.overrideWithValue(
            localMusicFiles(db).resolver,
          ),
          playbackEngineFactoryProvider.overrideWithValue((_) => engine),
        ],
        child: MediahroApp(router: buildRouter(initialLocation: '/music')),
      ),
    );
    await settle(tester);
  }

  testWidgets('MUS-001 empty library shows the add-music state', (
    tester,
  ) async {
    await pump(tester);
    expect(find.text('No music yet'), findsOneWidget);
    expect(find.text('Add music'), findsOneWidget);
    await finish(tester);
  });

  testWidgets('MUS-001 tabs list songs, albums, artists and genres', (
    tester,
  ) async {
    await seedAlbum();
    await pump(tester);
    for (final t in ['Songs', 'Albums', 'Artists', 'Genres', 'Folders']) {
      expect(find.text(t), findsWidgets);
    }
    expect(find.text('Alpha'), findsOneWidget);
    expect(find.text('Gamma'), findsOneWidget);
    await tester.tap(find.text('Albums'));
    await settle(tester);
    expect(find.text('First'), findsOneWidget);
    expect(find.text('Amy · 2001'), findsOneWidget);
    await tester.tap(find.text('First'));
    await settle(tester);
    // Album screen: header, play/shuffle, tracks in order.
    expect(find.text('2 songs · 6:00'), findsOneWidget);
    expect(find.text('Play'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Alpha')).dy,
      lessThan(tester.getTopLeft(find.text('Beta')).dy),
    );
    await finish(tester);
  });

  testWidgets('MUS-006 MUS-007 tapping a song plays the list; mini player '
      'and Now Playing control it', (tester) async {
    await seedAlbum();
    await pump(tester);
    await tester.tap(find.text('Beta'));
    await settle(tester);
    expect(engine.calls, contains('open'));
    expect(uriOf(engine.opened.first), endsWith('a/2.flac'));
    // Mini player shows the track.
    expect(find.byType(MusicMiniPlayer), findsOneWidget);
    expect(find.text('Beta'), findsWidgets);
    await tester.tap(
      find.descendant(
        of: find.byType(KMiniPlayer),
        matching: find.byTooltip('Pause'),
      ),
    );
    await settle(tester);
    expect(engine.current.status.name, 'paused');

    // Now Playing.
    await tester.tap(
      find.descendant(
        of: find.byType(KMiniPlayer),
        matching: find.text('Beta'),
      ),
    );
    await settle(tester);
    expect(find.text('Now playing'), findsOneWidget);
    expect(find.text('First'), findsWidgets);
    await tester.tap(find.byTooltip('Next track'));
    await settle(tester);
    expect(find.text('Gamma'), findsWidgets);
    await tester.tap(find.byTooltip('Repeat is off'));
    await settle(tester);
    expect(find.byTooltip('Repeat all'), findsOneWidget);

    // Queue sheet.
    await tester.tap(find.byTooltip('Queue').last);
    await settle(tester);
    expect(find.text('Remove from queue'), findsNothing); // tooltip only
    expect(find.byTooltip('Remove from queue'), findsNWidgets(3));
    await finish(tester);
  });

  testWidgets('MUS-007 song menu: play next and add to queue', (tester) async {
    await seedAlbum();
    await pump(tester);
    await tester.tap(find.text('Alpha'));
    await settle(tester);
    await tester.tap(find.byTooltip('More actions for Gamma'));
    await settle(tester);
    await tester.tap(find.text('Play next'));
    await settle(tester);
    final player = ProviderScope.containerOf(
      tester.element(find.byType(MusicHomeScreen)),
    ).read(musicPlayerProvider);
    expect(player.state.queue.map((t) => t.title), [
      'Alpha',
      'Gamma',
      'Beta',
      'Gamma',
    ]);
    expect(find.text('Added 1 song to the queue'), findsOneWidget);
    await finish(tester);
  });

  testWidgets('MUS-006 Now Playing extras: favourite, rating, sound, sleep '
      'timer, info', (tester) async {
    await seedAlbum();
    await pump(tester);
    await tester.tap(find.text('Alpha'));
    await settle(tester);
    await tester.tap(
      find.descendant(
        of: find.byType(KMiniPlayer),
        matching: find.text('Alpha'),
      ),
    );
    await settle(tester);
    await tester.tap(find.byTooltip('Favourite'));
    await settle(tester);
    expect(find.byTooltip('Remove from favourites'), findsOneWidget);

    await tester.tap(find.byTooltip('Not rated'));
    await settle(tester);
    await tester.tap(find.byTooltip('Rate 4 stars'));
    await settle(tester);
    expect(find.text('4 of 5 stars'), findsOneWidget);
    await tester.tapAt(const Offset(10, 10));
    await settle(tester);

    await tester.tap(find.byTooltip('Sound'));
    await settle(tester);
    await tester.tap(find.text('Bass boost'));
    await settle(tester);
    expect(engine.dsp!.graphicEq.first, 6);
    await tester.tapAt(const Offset(10, 10));
    await settle(tester);

    await tester.tap(find.byTooltip('Sleep timer'));
    await settle(tester);
    await tester.tap(find.text('15 minutes'));
    await settle(tester);
    final stopsIn = find.byWidgetPredicate(
      (w) => w is Tooltip && (w.message ?? '').startsWith('Stops in 1'),
    );
    expect(stopsIn, findsOneWidget);
    await tester.tap(stopsIn);
    await settle(tester);
    await tester.tap(find.text('Turn off timer'));
    await settle(tester);
    expect(find.byTooltip('Sleep timer'), findsOneWidget);

    await tester.tap(find.byTooltip('Song info'));
    await settle(tester);
    expect(find.text('a/1.flac'), findsOneWidget);
    await tester.tapAt(const Offset(10, 10));
    await settle(tester);
    await finish(tester);
  });

  testWidgets('MUS-011 alarms screen without an alarm facade says so', (
    tester,
  ) async {
    await seedAlbum();
    await pump(tester);
    await tester.tap(find.byTooltip('More'));
    await settle(tester);
    await tester.tap(find.text('Alarms'));
    await settle(tester);
    expect(
      find.text("Alarms aren't available on this device yet."),
      findsOneWidget,
    );
    await finish(tester);
  });

  testWidgets('MUS-005 lyrics: empty state with the opt-in online prompt, '
      'then create synced lyrics by tapping along', (tester) async {
    await seedAlbum();
    await pump(tester);
    await tester.tap(find.text('Alpha'));
    await settle(tester);
    await tester.tap(
      find.descendant(
        of: find.byType(KMiniPlayer),
        matching: find.text('Alpha'),
      ),
    );
    await settle(tester);
    await tester.tap(find.byTooltip('Show lyrics'));
    await settle(tester);
    expect(find.text('No lyrics for this song.'), findsOneWidget);

    // Online lookup is off until the user agrees.
    await tester.tap(find.text('Search online (LRCLIB)'));
    await settle(tester);
    expect(find.textContaining('lrclib.net'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await settle(tester);

    // Create: paste text, stamp two lines, save.
    await tester.tap(find.byTooltip('Create synced lyrics'));
    await settle(tester);
    await tester.enterText(find.byType(TextField), 'First line\nSecond line');
    await tester.tap(find.text('Use this text'));
    await settle(tester);
    engine.at(const Duration(seconds: 2));
    await settle(tester);
    await tester.tap(find.text('Stamp line'));
    engine.at(const Duration(seconds: 9));
    await settle(tester);
    await tester.tap(find.text('Stamp line'));
    await settle(tester);
    expect(find.text('0:02'), findsOneWidget);
    expect(find.text('0:09'), findsWidgets);
    await tester.tap(find.text('Save'));
    await settle(tester);
    expect(find.text('Your lyrics'), findsOneWidget);
    expect(find.text('First line'), findsOneWidget);
    expect(find.text('Second line'), findsOneWidget);
    await finish(tester);
  });

  testWidgets('AUD-046 visualiser toggle; without an engine tap it says so', (
    tester,
  ) async {
    await seedAlbum();
    await pump(tester);
    await tester.tap(find.text('Alpha'));
    await settle(tester);
    await tester.tap(
      find.descendant(
        of: find.byType(KMiniPlayer),
        matching: find.text('Alpha'),
      ),
    );
    await settle(tester);
    await tester.tap(find.byTooltip('Show visualiser'));
    await settle(tester);
    expect(find.textContaining('live audio analysis'), findsOneWidget);
    await tester.tap(find.byTooltip('Show cover'));
    await settle(tester);
    expect(find.textContaining('live audio analysis'), findsNothing);
    await finish(tester);
  });
}

/// Unmounts the app and lets drift's stream-close timers run, so no timer
/// is pending when the test ends.
Future<void> finish(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await settle(tester);
}

/// Lets drift queries (real async) finish and frames settle without
/// waiting on looping skeleton animations.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 40; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 50));
  }
}
