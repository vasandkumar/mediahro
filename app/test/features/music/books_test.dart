import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mediahro/core/db/library_database.dart';
import 'package:mediahro/core/library/queues.dart';
import 'package:mediahro/features/music/books/book.dart';
import 'package:mediahro/features/music/books/book_library.dart';
import 'package:mediahro/features/music/books/book_player.dart';
import 'package:mediahro/features/music/books/book_store.dart';
import 'package:mediahro/features/music/books/cue_sheet.dart';
import 'package:mediahro/features/music/library/music_library.dart';
import 'package:mediahro/features/music/player/music_dsp.dart';
import 'package:mediahro/features/music/player/music_player.dart';
import 'package:mediahro/features/music/player/music_prefs.dart';
import 'package:mediahro/features/music/player/sleep_shake.dart';
import 'package:mediahro/features/music/player/sleep_timer.dart';
import 'package:mediahro/features/music/tags/tag_reader.dart';
import 'package:mediahro/platform/motion.dart';
import 'package:mediahro_engine/mediahro_engine.dart';

import 'music_test_support.dart';
import 'tag_fixtures.dart';

/// POD-001: audiobook mode: what is a book, its chapters, where the listener
/// stands, speed and silence per book, bookmarks, and the sleep timer's
/// shake and end-of-chapter.
void main() {
  group('POD-001 CUE sheets', () {
    test('POD-001 chapters come from TRACK, TITLE and INDEX 01 (75 frames '
        'a second)', () {
      const sheet = '''
﻿PERFORMER "Author"
TITLE "The Book"
FILE "book.mp3" MP3
  TRACK 01 AUDIO
    TITLE "Opening"
    INDEX 00 00:00:00
    INDEX 01 00:00:00
  TRACK 02 AUDIO
    TITLE "Chapter One"
    INDEX 01 05:30:37
  TRACK 03 AUDIO
    INDEX 01 1:02:03:00
  TRACK 04 AUDIO
    TITLE "Last"
    INDEX 01 120:00:00
''';
      final c = parseCueSheet(sheet);
      expect(c.map((e) => e.title), ['Opening', 'Chapter One', 'Last']);
      expect(
        c[1].start,
        const Duration(minutes: 5, seconds: 30, milliseconds: 493),
      );
      expect(c[2].start, const Duration(hours: 2));
    });

    test('POD-001 a sheet over several files, or without times, gives no '
        'chapters', () {
      expect(
        parseCueSheet(
          'FILE "a.mp3" MP3\nTRACK 01 AUDIO\nINDEX 01 00:00:00\n'
          'FILE "b.mp3" MP3\nTRACK 02 AUDIO\nINDEX 01 00:00:00\n',
        ),
        isEmpty,
      );
      expect(parseCueSheet('TRACK 01 AUDIO\nTITLE "x"\n'), isEmpty);
      expect(parseCueSheet(''), isEmpty);
    });
  });

  group('POD-001 positions', () {
    MusicTrack t(int id, int seconds) => MusicTrack(
      itemId: id,
      sourceId: 1,
      relPath: 'b/$id.mp3',
      parentPath: 'b',
      title: 'T$id',
      duration: Duration(seconds: seconds),
    );

    test('POD-001 a position across files maps to a file and a time inside '
        'it, and back', () {
      final b = Book(
        id: 'd:1:b',
        title: 'B',
        tracks: [t(1, 100), t(2, 50), t(3, 10)],
      );
      expect(b.duration, const Duration(seconds: 160));
      expect(b.locate(Duration.zero), (0, Duration.zero));
      expect(b.locate(const Duration(seconds: 99)), (
        0,
        const Duration(seconds: 99),
      ));
      expect(b.locate(const Duration(seconds: 100)), (1, Duration.zero));
      expect(b.locate(const Duration(seconds: 155)), (
        2,
        const Duration(seconds: 5),
      ));
      expect(
        b.globalOf(1, const Duration(seconds: 20)),
        const Duration(seconds: 120),
      );
      expect(b.singleFile, isFalse);
    });
  });

  group('POD-001 the library', () {
    late LibraryDatabase db;
    late MusicSeed seed;
    late MusicLibrary lib;
    late BookStore store;
    late BookLibrary books;

    setUp(() async {
      db = LibraryDatabase.memory();
      seed = MusicSeed(db);
      lib = MusicLibrary(db);
      store = BookStore(MusicPrefs(db));
      books = BookLibrary(
        library: lib,
        store: store,
        files: localMusicFiles(db),
        readTags: readTagsOf,
      );
      await seed.song(
        'dune.m4b',
        title: 'Dune',
        artist: 'Frank Herbert',
        album: 'Dune',
        composer: 'Scott Brick',
        durationMs: 3600000,
      );
      for (var i = 1; i <= 3; i++) {
        await seed.song(
          'Emma/0$i.mp3',
          title: 'Part $i',
          artist: 'Jane Austen',
          album: 'Emma',
          genre: 'Audiobook',
          track: i,
          durationMs: 60000,
        );
      }
      for (var i = 1; i <= 2; i++) {
        await seed.song(
          'Rock/0$i.mp3',
          title: 'Song $i',
          artist: 'Band',
          album: 'Loud',
          genre: 'Rock',
          track: i,
        );
      }
    });
    tearDown(() => db.close());

    test('POD-001 an M4B and a folder with a spoken-word genre are books; '
        'music is not', () async {
      final all = await books.books();
      expect(all.map((b) => b.title), ['Dune', 'Emma']);
      final dune = all.first;
      expect(dune.singleFile, isTrue);
      expect(dune.author, 'Frank Herbert');
      expect(dune.narrator, 'Scott Brick');
      expect(dune.id, startsWith('i:'));
      final emma = all.last;
      expect(emma.tracks.map((t) => t.title), ['Part 1', 'Part 2', 'Part 3']);
      expect(emma.id, 'd:1:Emma');
      expect(emma.duration, const Duration(minutes: 3));
    });

    test("POD-001 the listener's answer wins: a music folder can be made a "
        'book and a book can be made music', () async {
      await store.setMark('d:1:Rock', 'book');
      await store.setMark('d:1:Emma', 'music');
      final all = await books.books();
      expect(all.map((b) => b.title), ['Dune', 'Loud']);
      expect(all.last.tracks, hasLength(2));
      await store.setMark('d:1:Rock', null);
      await store.setMark('d:1:Emma', null);
      expect((await books.books()).map((b) => b.title), ['Dune', 'Emma']);
    });

    test('POD-001 the list puts books in progress first, newest first, '
        'finished ones last', () async {
      final all = await books.books();
      final dune = all.first;
      final emma = all.last;
      expect((await books.entries()).map((e) => e.book.title), [
        'Dune',
        'Emma',
      ]);
      await store.saveProgress(
        emma.id,
        const BookProgress(trackIndex: 1, position: Duration(seconds: 30)),
      );
      var e = await books.entries();
      expect(e.map((x) => x.book.title), ['Emma', 'Dune']);
      // 60 + 30 of 180 seconds.
      expect(e.first.fraction, closeTo(0.5, 0.001));
      await store.saveProgress(emma.id, const BookProgress(finished: true));
      e = await books.entries();
      expect(e.map((x) => x.book.title), ['Dune', 'Emma']);
      expect(e.last.fraction, 1);
      expect(e.last.finished, isTrue);
      await store.saveProgress(
        dune.id,
        const BookProgress(position: Duration(minutes: 1)),
      );
      expect((await books.entries()).first.book.title, 'Dune');
    });

    test('POD-001 a folder has one chapter per file', () async {
      final emma = (await books.books()).last;
      final c = await books.chapters(emma);
      expect(c.map((x) => x.title), ['Part 1', 'Part 2', 'Part 3']);
      expect(c.map((x) => x.start.inSeconds), [0, 60, 120]);
    });
  });

  group('POD-001 chapters of one file', () {
    late Directory dir;
    late LibraryDatabase db;
    late BookLibrary books;
    late MusicSeed seed;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('c2_book');
      db = LibraryDatabase.memory();
      seed = MusicSeed(db);
      await seed.source(dir.uri.toString());
      books = BookLibrary(
        library: MusicLibrary(db),
        store: BookStore(MusicPrefs(db)),
        files: localMusicFiles(db),
        readTags: readTagsOf,
      );
    });
    tearDown(() async {
      await db.close();
      try {
        await dir.delete(recursive: true);
      } on FileSystemException {
        // Windows may hold a handle briefly.
      }
    });

    test('POD-001 MP4 chapters are read from the file', () async {
      File('${dir.path}/a.m4b').writeAsBytesSync(
        mp4(
          text: {'©nam': 'A', '©alb': 'A', '©gen': 'Audiobook'},
          chapters: [(0, 'Intro'), (65000, ' One '), (400000, 'Past the end')],
        ),
      );
      await seed.song('a.m4b', title: 'A', album: 'A', durationMs: 300000);
      final b = (await books.books()).single;
      final c = await books.chapters(b);
      expect(c.map((x) => x.title), ['Intro', 'One']);
      expect(c[1].start, const Duration(seconds: 65));
    });

    test('POD-001 without marks in the file, a CUE sheet next to it '
        'supplies them', () async {
      File('${dir.path}/b.m4b').writeAsBytesSync(mp4(text: {'©nam': 'B'}));
      File('${dir.path}/b.cue').writeAsStringSync(
        'FILE "b.m4b" MP4\nTRACK 01 AUDIO\nTITLE "Start"\nINDEX 01 00:00:00\n'
        'TRACK 02 AUDIO\nTITLE "Middle"\nINDEX 01 02:00:00\n',
      );
      await seed.song('b.m4b', title: 'B', durationMs: 600000);
      final b = (await books.books()).single;
      final c = await books.chapters(b);
      expect(c.map((x) => x.title), ['Start', 'Middle']);
      expect(c[1].start, const Duration(minutes: 2));
    });

    test('POD-001 no marks anywhere is no chapters', () async {
      File('${dir.path}/c.m4b').writeAsBytesSync(mp4(text: {'©nam': 'C'}));
      await seed.song('c.m4b', title: 'C', durationMs: 600000);
      expect(await books.chapters((await books.books()).single), isEmpty);
    });
  });

  group('POD-001 the store', () {
    late LibraryDatabase db;
    late BookStore store;
    var now = DateTime.utc(2026, 10, 22, 12);

    setUp(() {
      db = LibraryDatabase.memory();
      now = DateTime.utc(2026, 10, 22, 12);
      store = BookStore(MusicPrefs(db), clock: () => now);
    });
    tearDown(() => db.close());

    test('POD-001 progress, speed and skip silence are remembered per book; '
        'a new book starts at the last speed used', () async {
      expect(await store.progress('i:1'), isNull);
      expect(await store.lastSpeed(), 1);
      await store.saveProgress(
        'i:1',
        const BookProgress(
          trackIndex: 2,
          position: Duration(seconds: 42),
          speed: 1.5,
          skipSilence: true,
        ),
      );
      final p = (await store.progress('i:1'))!;
      expect(p.trackIndex, 2);
      expect(p.position, const Duration(seconds: 42));
      expect(p.speed, 1.5);
      expect(p.skipSilence, isTrue);
      expect(p.updatedAt, now);
      expect(await store.progress('i:2'), isNull);
      expect(await store.lastSpeed(), 1.5);
      expect((await store.allProgress()).keys, ['i:1']);
    });

    test('POD-001 bookmarks keep their notes and stay in book order', () async {
      final late = await store.addBookmark(
        'i:1',
        const Duration(minutes: 30),
        note: 'Late',
      );
      now = now.add(const Duration(seconds: 1));
      final early = await store.addBookmark('i:1', const Duration(minutes: 2));
      expect((await store.bookmarks('i:1')).map((b) => b.at.inMinutes), [
        2,
        30,
      ]);
      await store.editBookmark('i:1', early.id, 'Quote about spice');
      await store.removeBookmark('i:1', late.id);
      final left = await store.bookmarks('i:1');
      expect(left.single.note, 'Quote about spice');
      expect(await store.bookmarks('i:2'), isEmpty);
    });
  });

  group('POD-001 the book player', () {
    late LibraryDatabase db;
    late ScriptedMusicEngine engine;
    late MusicPlayer player;
    late MusicDsp dsp;
    late BookStore store;
    late BookLibrary library;
    late BookPlayer book;
    late Book emma;
    late MusicTrack song;
    var now = DateTime.utc(2026, 10, 22, 12);

    Future<void> settle() async {
      for (var i = 0; i < 6; i++) {
        await Future<void>.delayed(Duration.zero);
      }
    }

    setUp(() async {
      now = DateTime.utc(2026, 10, 22, 12);
      db = LibraryDatabase.memory();
      engine = ScriptedMusicEngine();
      final seed = MusicSeed(db);
      for (var i = 1; i <= 3; i++) {
        await seed.song(
          'Emma/0$i.mp3',
          title: 'Part $i',
          artist: 'Jane Austen',
          album: 'Emma',
          genre: 'Audiobook',
          track: i,
          durationMs: 600000,
        );
      }
      await seed.song('x/1.mp3', title: 'Song', album: 'Music', genre: 'Rock');
      player = MusicPlayer(
        engine: engine,
        queues: QueueRepository(db),
        library: MusicLibrary(db),
        files: localMusicFiles(db),
        openTimeout: const Duration(milliseconds: 100),
      );
      await player.init();
      dsp = MusicDsp(engine: engine, prefs: MusicPrefs(db), db: db);
      store = BookStore(MusicPrefs(db), clock: () => now);
      library = BookLibrary(
        library: MusicLibrary(db),
        store: store,
        files: localMusicFiles(db),
        readTags: readTagsOf,
      );
      book = BookPlayer(
        player: player,
        engine: engine,
        dsp: dsp,
        library: library,
        store: store,
        clock: () => now,
      );
      emma = (await library.books()).single;
      song = (await MusicLibrary(
        db,
      ).songs()).firstWhere((t) => t.title == 'Song');
    });
    tearDown(() async {
      await book.dispose();
      await player.dispose();
      await db.close();
    });

    String opened(int i) => uriOf(engine.opened[i]).split('/').last;

    test('POD-001 a new book starts at the beginning at normal speed, '
        'as the queue of its files', () async {
      await book.open(emma);
      expect(opened(0), '01.mp3');
      expect(player.state.queue.map((t) => t.title), [
        'Part 1',
        'Part 2',
        'Part 3',
      ]);
      expect(book.state.book?.id, emma.id);
      expect(book.state.duration, const Duration(minutes: 30));
      expect(book.state.position, Duration.zero);
      expect(book.state.chapters, hasLength(3));
      expect(book.state.speed, 1);
      expect(engine.rates.last, 1);
      expect(player.state.shuffle, isFalse);
      expect(player.state.repeat, RepeatMode.off);
    });

    test('POD-001 it resumes where the listener left off, at the speed and '
        'silence setting of that book', () async {
      await store.saveProgress(
        emma.id,
        const BookProgress(
          trackIndex: 1,
          position: Duration(minutes: 4),
          speed: 1.75,
          skipSilence: true,
        ),
      );
      await book.open(emma);
      expect(opened(0), '02.mp3');
      expect(engine.current.position, const Duration(minutes: 4));
      expect(book.state.position, const Duration(minutes: 14));
      expect(book.state.speed, 1.75);
      expect(engine.rates.last, 1.75);
      expect(dsp.skipSilence, isTrue);
      expect(engine.dsp?.skipSilence, isTrue);
      expect(book.state.chapterIndex, 1);
    });

    test('POD-001 speed and skip silence are saved with the book; the next '
        'new book starts at the last speed', () async {
      await book.open(emma);
      await book.setSpeed(2.2);
      await book.setSkipSilence(enabled: true);
      final p = (await store.progress(emma.id))!;
      expect(p.speed, 2.2);
      expect(p.skipSilence, isTrue);
      await book.setSpeed(9);
      expect(book.state.speed, 3);
      expect(engine.rates.last, 3);
      await book.setSpeed(0.1);
      expect(book.state.speed, 0.5);
    });

    test('POD-001 chapter buttons: next, previous (restart after a few '
        'seconds), and seeking across files', () async {
      await book.open(emma);
      await book.nextChapter();
      expect(book.state.position, const Duration(minutes: 10));
      expect(opened(engine.opened.length - 1), '02.mp3');
      expect(book.state.chapterIndex, 1);
      engine.at(const Duration(seconds: 20));
      await settle();
      expect(book.state.position, const Duration(minutes: 10, seconds: 20));
      await book.previousChapter();
      expect(book.state.position, const Duration(minutes: 10));
      // Within three seconds of the start: the chapter before.
      engine.at(const Duration(seconds: 1));
      await settle();
      await book.previousChapter();
      expect(book.state.position, Duration.zero);
      expect(opened(engine.opened.length - 1), '01.mp3');
      await book.skip(const Duration(minutes: 25));
      expect(book.state.position, const Duration(minutes: 25));
      expect(book.state.chapterIndex, 2);
      await book.skip(const Duration(minutes: -30));
      expect(book.state.position, Duration.zero);
      await book.skip(const Duration(hours: 5));
      expect(book.state.position < book.state.duration, isTrue);
    });

    test('POD-001 progress is written while playing (every few seconds), '
        'on pause and on moving to the next file', () async {
      await book.open(emma);
      final base = (await store.progress(emma.id))!;
      expect(base.position, Duration.zero);
      engine.at(const Duration(seconds: 2));
      await settle();
      // Under five seconds since the last write: not yet.
      expect((await store.progress(emma.id))!.position, Duration.zero);
      now = now.add(const Duration(seconds: 6));
      engine.at(const Duration(seconds: 8));
      await settle();
      expect(
        (await store.progress(emma.id))!.position,
        const Duration(seconds: 8),
      );
      engine.at(const Duration(seconds: 9));
      await player.pause();
      await settle();
      expect(
        (await store.progress(emma.id))!.position,
        const Duration(seconds: 9),
      );
      // The gapless hand-off into file two.
      await player.play();
      engine
        ..at(const Duration(minutes: 10))
        ..finishTrack();
      await settle();
      final p = (await store.progress(emma.id))!;
      expect(p.trackIndex, 1);
      expect(p.position, Duration.zero);
    });

    test('POD-001 reaching the end marks the book finished; opening it '
        'again starts from the beginning', () async {
      await store.saveProgress(
        emma.id,
        const BookProgress(trackIndex: 2, position: Duration(minutes: 9)),
      );
      await book.open(emma);
      engine.finishTrack();
      await settle();
      expect(book.state.finished, isTrue);
      expect((await store.progress(emma.id))!.finished, isTrue);
      await book.dispose();
      book = BookPlayer(
        player: player,
        engine: engine,
        dsp: dsp,
        library: library,
        store: store,
        clock: () => now,
      );
      await book.open(emma);
      expect(book.state.finished, isFalse);
      expect(book.state.position, Duration.zero);
      expect(opened(engine.opened.length - 1), '01.mp3');
    });

    test(
      'POD-001 pause at the end of this chapter: once, then normal',
      () async {
        await book.open(emma);
        engine.at(const Duration(minutes: 3));
        await settle();
        await book.setStopAtChapterEnd(enabled: true);
        expect(book.state.stopAtChapterEnd, isTrue);
        engine.at(const Duration(minutes: 9, seconds: 30));
        await settle();
        expect(engine.current.status, PlaybackStatus.playing);
        engine.at(const Duration(minutes: 9, seconds: 59, milliseconds: 800));
        await settle();
        expect(engine.current.status, PlaybackStatus.paused);
        expect(book.state.stopAtChapterEnd, isFalse);
        expect(book.state.playing, isFalse);
      },
    );

    test('POD-001 bookmarks mark the current place with a note, jump back '
        'to it, and survive a reopen', () async {
      await book.open(emma);
      await book.seek(const Duration(minutes: 12, seconds: 30));
      final mark = await book.addBookmark(note: 'Remember this');
      expect(book.state.bookmarks.single.note, 'Remember this');
      expect(
        book.state.bookmarks.single.at,
        const Duration(minutes: 12, seconds: 30),
      );
      await book.seek(Duration.zero);
      await book.goToBookmark(mark!);
      expect(book.state.position, const Duration(minutes: 12, seconds: 30));
      await book.editBookmark(mark.id, 'Edited');
      expect(book.state.bookmarks.single.note, 'Edited');
      await book.open(emma);
      expect(book.state.bookmarks.single.note, 'Edited');
      await book.removeBookmark(mark.id);
      expect(book.state.bookmarks, isEmpty);
    });

    test('POD-001 playing something else ends book mode: progress saved, '
        'speed and silence back to normal', () async {
      await book.open(emma);
      await book.setSpeed(1.5);
      await book.setSkipSilence(enabled: true);
      engine.at(const Duration(minutes: 1));
      await settle();
      await player.playTracks([song]);
      await settle();
      expect(book.state.active, isFalse);
      expect(engine.rates.last, 1);
      expect(dsp.skipSilence, isFalse);
      expect(engine.dsp?.skipSilence, isFalse);
      final p = (await store.progress(emma.id))!;
      expect(p.speed, 1.5);
      expect(p.position, const Duration(minutes: 1));
    });

    test('POD-001 the speed belongs to the book: a new item that the '
        'engine played at normal speed is put back', () async {
      await book.open(emma);
      await book.setSpeed(1.5);
      await engine.setRate(1);
      await settle();
      expect(engine.current.rate, 1.5);
    });
  });

  group('POD-001 sleep timer', () {
    test('POD-001 a shake adds five minutes to a timer by time and a '
        'track to a timer by tracks', () async {
      final db = LibraryDatabase.memory();
      final engine = ScriptedMusicEngine();
      final player = MusicPlayer(
        engine: engine,
        queues: QueueRepository(db),
        library: MusicLibrary(db),
        files: localMusicFiles(db),
      );
      final timer = SleepTimer(player: player, engine: engine)
        ..startTime(const Duration(minutes: 10))
        ..shake();
      expect(timer.state.remaining! > const Duration(minutes: 14), isTrue);
      timer
        ..startTracks(2)
        ..shake();
      expect(timer.state.tracksLeft, 3);
      // The last track is no longer the one it stops after.
      timer
        ..startEndOfTrack()
        ..shake();
      expect(timer.state.tracksLeft, 2);
      expect(player.holdAtEnd, isFalse);
      timer
        ..cancel()
        ..shake();
      expect(timer.state.active, isFalse);
      await timer.dispose();
      await player.dispose();
      await db.close();
    });

    test('POD-001 a shake is quick swings back and forth; a slow turn or '
        'one fast move is not', () {
      var t = DateTime.utc(2026);
      final d = ShakeDetector(clock: () => t);
      bool feed(double yaw, [double pitch = 0]) {
        t = t.add(const Duration(milliseconds: 40));
        return d.add(MotionAttitude(yaw: yaw, pitch: pitch));
      }

      // A slow turn: 1 rad/s.
      for (var i = 0; i < 40; i++) {
        expect(feed(i * 0.04), isFalse);
      }
      d.reset();
      // One fast swing.
      expect(feed(0), isFalse);
      expect(feed(0.5), isFalse);
      expect(feed(1), isFalse);
      d.reset();
      // Back and forth, 0.5 rad every 40 ms.
      expect(feed(0), isFalse);
      var fired = false;
      for (final y in [0.5, 0.0, 0.5, 0.0, 0.5, 0.0]) {
        fired = fired || feed(y);
      }
      expect(fired, isTrue);
      // The heading wraps at half a turn without looking like a swing.
      d.reset();
      expect(feed(3.1), isFalse);
      expect(feed(-3.1), isFalse);
    });

    test('POD-001 while a timer runs, a shake reaches it; with no timer the '
        'sensor is not listened to', () async {
      final db = LibraryDatabase.memory();
      final engine = ScriptedMusicEngine();
      final player = MusicPlayer(
        engine: engine,
        queues: QueueRepository(db),
        library: MusicLibrary(db),
        files: localMusicFiles(db),
      );
      final timer = SleepTimer(player: player, engine: engine);
      final motion = _Motion();
      var t = DateTime.utc(2026);
      final extender = SleepShakeExtender(
        timer: timer,
        motion: motion,
        detector: ShakeDetector(
          clock: () => t = t.add(const Duration(milliseconds: 40)),
        ),
      )..start();
      await Future<void>.delayed(Duration.zero);
      expect(motion.listening, isFalse);
      timer.startTime(const Duration(minutes: 10));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(motion.listening, isTrue);
      expect(timer.state.remaining! < const Duration(minutes: 11), isTrue);
      for (final y in [0.0, 0.5, 0.0, 0.5, 0.0, 0.5, 0.0, 0.5]) {
        motion.send(MotionAttitude(yaw: y, pitch: 0));
      }
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(timer.state.remaining! > const Duration(minutes: 14), isTrue);
      timer.cancel();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(motion.listening, isFalse);
      await extender.dispose();
      await timer.dispose();
      await player.dispose();
      await db.close();
    });
  });
}

final class _Motion implements MotionFacade {
  final _c = StreamController<MotionAttitude>.broadcast();

  bool get listening => _c.hasListener;

  void send(MotionAttitude a) => _c.add(a);

  @override
  Stream<MotionAttitude> get attitude => _c.stream;

  @override
  Future<bool> get available async => true;
}
