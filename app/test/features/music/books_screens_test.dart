import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediahro/app/app.dart';
import 'package:mediahro/app/router.dart';
import 'package:mediahro/core/db/library_database.dart';
import 'package:mediahro/core/providers.dart';
import 'package:mediahro/engine/engine_pool.dart';
import 'package:mediahro/features/music/books/book.dart';
import 'package:mediahro/features/music/music_providers.dart';
import 'package:mediahro/features/music/music_wiring.dart';
import 'package:mediahro/features/settings/settings_providers.dart';

import '../../helpers.dart';
import 'music_test_support.dart';

/// POD-001 on screen: the Audiobooks tab, the book player, speed, bookmarks,
/// chapters and the sleep timer's end of chapter.
void main() {
  late LibraryDatabase db;
  late ScriptedMusicEngine engine;
  late Directory data;
  late ProviderContainer container;

  setUp(() async {
    db = LibraryDatabase.memory();
    engine = ScriptedMusicEngine();
    data = Directory.systemTemp.createTempSync('c2_books_ui');
    final seed = MusicSeed(db);
    for (var i = 1; i <= 3; i++) {
      await seed.song(
        'Emma/0$i.mp3',
        title: 'Part $i',
        artist: 'Jane Austen',
        album: 'Emma',
        albumArtist: 'Jane Austen',
        genre: 'Audiobook',
        track: i,
        durationMs: 600000,
      );
    }
    await seed.song(
      'x/1.mp3',
      title: 'Song',
      artist: 'Band',
      album: 'Loud',
      genre: 'Rock',
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

  Future<void> pump(WidgetTester tester) async {
    tester.view
      ..physicalSize = const Size(420, 900) * tester.view.devicePixelRatio
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
    container = ProviderScope.containerOf(
      tester.element(find.byType(MediahroApp)),
    );
    await settle(tester);
  }

  Future<void> openBook(WidgetTester tester) async {
    await pump(tester);
    await tester.ensureVisible(find.text('Audiobooks'));
    await tester.tap(find.text('Audiobooks'));
    await settle(tester);
    await tester.tap(find.text('Emma'));
    await settle(tester);
  }

  Future<void> finish(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await settle(tester);
  }

  testWidgets('POD-001 the Audiobooks tab lists books, not music; a book '
      'in progress shows what is left', (tester) async {
    await pump(tester);
    await tester.ensureVisible(find.text('Audiobooks'));
    await tester.tap(find.text('Audiobooks'));
    await settle(tester);
    expect(find.text('Emma'), findsOneWidget);
    expect(find.text('Jane Austen'), findsOneWidget);
    expect(find.text('Loud'), findsNothing);
    expect(find.text('Not started'), findsOneWidget);
    await tester.runAsync(
      () => container
          .read(bookStoreProvider)
          .saveProgress(
            'd:1:Emma',
            const BookProgress(trackIndex: 1, position: Duration(minutes: 5)),
          ),
    );
    container.invalidate(bookEntriesProvider);
    await settle(tester);
    // 10 + 5 of 30 minutes played.
    expect(find.text('15:00 left'), findsOneWidget);
    await finish(tester);
  });

  testWidgets('POD-001 an empty library explains where books come from', (
    tester,
  ) async {
    await db.customStatement("UPDATE item SET ext = 'mp3'");
    await db.customStatement("UPDATE audio_meta SET genre = 'Rock'");
    await pump(tester);
    await tester.ensureVisible(find.text('Audiobooks'));
    await tester.tap(find.text('Audiobooks'));
    await settle(tester);
    expect(find.textContaining('No audiobooks yet'), findsOneWidget);
    await finish(tester);
  });

  testWidgets('POD-001 tapping a book opens the player at the chapter; '
      'chapter and 30-second buttons move through it', (tester) async {
    await openBook(tester);
    expect(find.text('Audiobook'), findsOneWidget);
    expect(find.text('Emma'), findsOneWidget);
    expect(find.text('Part 1'), findsWidgets);
    expect(find.text('Chapter 1 of 3'), findsOneWidget);
    expect(uriOf(engine.opened.first), endsWith('Emma/01.mp3'));

    await tester.tap(find.byTooltip('Next chapter'));
    await settle(tester);
    expect(find.text('Chapter 2 of 3'), findsOneWidget);
    expect(uriOf(engine.opened.last), endsWith('Emma/02.mp3'));

    await tester.tap(find.byTooltip('Forward 30 seconds'));
    await settle(tester);
    expect(engine.current.position, const Duration(seconds: 30));
    await tester.tap(find.byTooltip('Pause'));
    await settle(tester);
    expect(engine.current.status.name, 'paused');
    await finish(tester);
  });

  testWidgets('POD-001 speed: the chip, the presets and the slider set the '
      "book's speed", (tester) async {
    await openBook(tester);
    expect(find.text('1×'), findsOneWidget);
    await tester.tap(find.widgetWithText(ActionChip, '1×'));
    await settle(tester);
    await tester.tap(find.text('1.5×'));
    await settle(tester);
    expect(engine.rates.last, 1.5);
    expect(
      (await tester.runAsync(
        () => container.read(bookStoreProvider).progress('d:1:Emma'),
      ))!.speed,
      1.5,
    );
    expect(find.text('Each book remembers its own speed.'), findsOneWidget);
    await finish(tester);
  });

  testWidgets('POD-001 bookmarks: add with a note, list, jump back, delete', (
    tester,
  ) async {
    await openBook(tester);
    await tester.tap(find.byTooltip('Forward 30 seconds'));
    await settle(tester);
    await tester.tap(find.text('Add bookmark'));
    await settle(tester);
    await tester.enterText(find.byType(TextField), 'Lovely line');
    // Let the caret callbacks run while the field is still attached.
    await tester.pump();
    await tester.tap(find.text('Save'));
    await settle(tester);
    expect(find.text('Bookmark added'), findsOneWidget);

    await tester.tap(find.byTooltip('Bookmarks'));
    await settle(tester);
    expect(find.text('0:30'), findsWidgets);
    expect(find.text('Lovely line'), findsOneWidget);
    await tester.tap(find.byTooltip('Bookmark actions'));
    await settle(tester);
    await tester.tap(find.text('Delete bookmark'));
    await settle(tester);
    expect(find.text('No bookmarks yet.'), findsOneWidget);
    await finish(tester);
  });

  testWidgets('POD-001 the chapter list jumps; the sleep sheet offers the '
      'end of this chapter in a book', (tester) async {
    await openBook(tester);
    await tester.tap(find.byTooltip('Chapters'));
    await settle(tester);
    expect(find.text('Part 3'), findsOneWidget);
    await tester.tap(find.text('Part 3'));
    await settle(tester);
    expect(find.text('Chapter 3 of 3'), findsOneWidget);

    await tester.tap(find.byTooltip('Sleep timer'));
    await settle(tester);
    await tester.tap(find.text('End of this chapter'));
    await settle(tester);
    expect(find.text('Pausing at the end of this chapter'), findsOneWidget);
    await finish(tester);
  });

  testWidgets('POD-001 a folder or a song can be made an audiobook', (
    tester,
  ) async {
    await pump(tester);
    await tester.runAsync(
      () => container.read(bookStoreProvider).setMark('d:1:x', 'book'),
    );
    container.invalidate(bookEntriesProvider);
    await settle(tester);
    await tester.ensureVisible(find.text('Audiobooks'));
    await tester.tap(find.text('Audiobooks'));
    await settle(tester);
    expect(find.text('Loud'), findsOneWidget);
    await finish(tester);
  });
}
