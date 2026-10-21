import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mediahro/core/db/library_database.dart';
import 'package:mediahro/core/library/queues.dart';
import 'package:mediahro/features/music/books/book_library.dart';
import 'package:mediahro/features/music/books/book_player.dart';
import 'package:mediahro/features/music/books/book_store.dart';
import 'package:mediahro/features/music/library/music_library.dart';
import 'package:mediahro/features/music/player/music_dsp.dart';
import 'package:mediahro/features/music/player/music_player.dart';
import 'package:mediahro/features/music/player/music_prefs.dart';
import 'package:mediahro/features/music/tags/tag_reader.dart';
import 'package:mediahro_engine/mediahro_engine.dart';

import '../test/features/music/music_test_support.dart';

/// Lane C2 on real devices (POD-001): a folder of files plays as a book with
/// libmpv: speed and skip silence reach the engine, a skip crosses into the
/// next file, and the book resumes where it was left.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('c2books');
  });
  tearDown(() async {
    try {
      await dir.delete(recursive: true);
    } on FileSystemException {
      // Best effort.
    }
  });

  /// [seconds] of a quiet 330 Hz tone, 8 kHz mono WAV.
  Uint8List tone(int seconds) {
    const rate = 8000;
    final frames = rate * seconds;
    final b = ByteData(44 + frames * 2);
    void str(int at, String s) {
      for (var i = 0; i < s.length; i++) {
        b.setUint8(at + i, s.codeUnitAt(i));
      }
    }

    str(0, 'RIFF');
    b.setUint32(4, 36 + frames * 2, Endian.little);
    str(8, 'WAVE');
    str(12, 'fmt ');
    b
      ..setUint32(16, 16, Endian.little)
      ..setUint16(20, 1, Endian.little)
      ..setUint16(22, 1, Endian.little)
      ..setUint32(24, rate, Endian.little)
      ..setUint32(28, rate * 2, Endian.little)
      ..setUint16(32, 2, Endian.little)
      ..setUint16(34, 16, Endian.little);
    str(36, 'data');
    b.setUint32(40, frames * 2, Endian.little);
    for (var i = 0; i < frames; i++) {
      final v = (math.sin(2 * math.pi * 330 * i / rate) * 3000).round();
      b.setInt16(44 + i * 2, v, Endian.little);
    }
    return b.buffer.asUint8List();
  }

  testWidgets('POD-001 a folder plays as a book: speed, silence, a skip '
      'across files, and resume', (tester) async {
    if (!MpvEngine.isAvailable) {
      return markTestSkipped('blocked: libmpv is not bundled in this build');
    }
    await tester.runAsync(() async {
      final db = LibraryDatabase.memory();
      final seed = MusicSeed(db);
      await seed.source(dir.uri.toString());
      for (var i = 1; i <= 2; i++) {
        File('${dir.path}/Book/0$i.wav')
          ..createSync(recursive: true)
          ..writeAsBytesSync(tone(20));
        await seed.song(
          'Book/0$i.wav',
          title: 'Part $i',
          artist: 'Narrator',
          album: 'The Book',
          genre: 'Audiobook',
          track: i,
          durationMs: 20000,
        );
      }
      final engine = MpvEngine(EngineRole.music);
      final player = MusicPlayer(
        engine: engine,
        queues: QueueRepository(db),
        library: MusicLibrary(db),
        files: localMusicFiles(db),
      );
      await player.init();
      final store = BookStore(MusicPrefs(db));
      final library = BookLibrary(
        library: MusicLibrary(db),
        store: store,
        files: localMusicFiles(db),
        readTags: readTagsOf,
      );
      final dsp = MusicDsp(engine: engine, prefs: MusicPrefs(db), db: db);
      BookPlayer newBook() => BookPlayer(
        player: player,
        engine: engine,
        dsp: dsp,
        library: library,
        store: store,
      );
      Future<void> until(bool Function() done) async {
        for (var i = 0; i < 100 && !done(); i++) {
          await Future<void>.delayed(const Duration(milliseconds: 50));
        }
      }

      final book = newBook();
      final b = (await library.books()).single;
      expect(b.title, 'The Book');
      await book.open(b);
      await until(() => engine.current.status == PlaybackStatus.playing);
      expect(engine.current.status, PlaybackStatus.playing);

      await book.setSpeed(1.5);
      await until(() => engine.current.rate == 1.5);
      expect(engine.current.rate, 1.5);
      await book.setSkipSilence(enabled: true);
      expect(book.state.skipSilence, isTrue);
      expect(engine.current.error, isNull);

      await book.skip(const Duration(seconds: 25));
      await until(() => player.state.index == 1);
      expect(player.state.index, 1);
      expect(book.state.chapterIndex, 1);
      await book.pause();
      await until(() => engine.current.status == PlaybackStatus.paused);
      final saved = (await store.progress(b.id))!;
      expect(saved.trackIndex, 1);
      expect(saved.speed, 1.5);
      expect(saved.skipSilence, isTrue);

      // A new player picks the book up where it was left, at its speed.
      await book.dispose();
      final again = newBook();
      await again.open(b, autoplay: false);
      expect(player.state.index, 1);
      expect(again.state.speed, 1.5);
      await until(() => engine.current.rate == 1.5);
      expect(engine.current.rate, 1.5);
      await again.dispose();
      await player.dispose();
      await engine.dispose();
      await db.close();
    });
  });
}
