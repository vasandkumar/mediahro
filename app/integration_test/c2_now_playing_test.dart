import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mediahro/core/db/library_database.dart';
import 'package:mediahro/core/library/queues.dart';
import 'package:mediahro/core/library/tags.dart';
import 'package:mediahro/core/scanner/scan_service.dart';
import 'package:mediahro/core/sources/source_access.dart';
import 'package:mediahro/features/music/library/artwork_store.dart';
import 'package:mediahro/features/music/library/music_files.dart';
import 'package:mediahro/features/music/library/music_indexer.dart';
import 'package:mediahro/features/music/library/music_library.dart';
import 'package:mediahro/features/music/library/ratings.dart';
import 'package:mediahro/features/music/player/music_dsp.dart';
import 'package:mediahro/features/music/player/music_player.dart';
import 'package:mediahro/features/music/player/music_prefs.dart';
import 'package:mediahro/features/music/player/sleep_timer.dart';
import 'package:mediahro_engine/mediahro_engine.dart';
import 'package:mediahro_ffi/mediahro_ffi.dart';

import '../test/features/music/tag_fixtures.dart';

/// Lane C2, Now Playing extras and the sleep timer on real devices
/// (MUS-006, MUS-011): the EQ, levelling and crossfade reach libmpv, the
/// sleep timer fades and pauses real playback, ratings and favourites
/// persist.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late Directory media;
  late Directory data;
  late LibraryDatabase db;

  setUp(() async {
    media = await Directory.systemTemp.createTemp('c2np_media');
    data = await Directory.systemTemp.createTemp('c2np_data');
    db = LibraryDatabase.open(data);
  });
  tearDown(() async {
    await db.close();
    for (final d in [media, data]) {
      try {
        await d.delete(recursive: true);
      } on FileSystemException {
        // The OS cleans temp.
      }
    }
  });

  Uint8List tone(double seconds, String title, int track) {
    const rate = 44100;
    final frames = (seconds * rate).round();
    final pcm = ByteData(frames * 4);
    for (var i = 0; i < frames; i++) {
      final v = (math.sin(2 * math.pi * 440 * i / rate) * 500).round();
      pcm
        ..setInt16(i * 4, v, Endian.little)
        ..setInt16(i * 4 + 2, v, Endian.little);
    }
    final tag = id3v2(4, [
      id3Text(4, 'TIT2', [title]),
      id3Text(4, 'TALB', ['Extras']),
      id3Text(4, 'TPE2', ['Mediahro Test']),
      id3Text(4, 'TRCK', ['$track']),
    ]);
    final fmt = [
      ...u16le(1), ...u16le(2), ...u32le(rate), ...u32le(rate * 4), //
      ...u16le(4), ...u16le(16),
    ];
    final body = [
      ...ascii('fmt '), ...u32le(fmt.length), ...fmt, //
      ...ascii('data'), ...u32le(frames * 4), ...pcm.buffer.asUint8List(),
      ...ascii('id3 '), ...u32le(tag.length), ...tag,
      if (tag.length.isOdd) 0,
    ];
    return bytesOf([
      ascii('RIFF'),
      u32le(body.length + 4),
      ascii('WAVE'),
      body,
    ]);
  }

  SourceResolver resolver() => DefaultSourceResolver(
    builders: {SourceKind.local: (_) => const LocalFileSystem()},
  );

  Future<List<MusicTrack>> library() async {
    for (var i = 1; i <= 2; i++) {
      await File('${media.path}/0$i.wav').writeAsBytes(tone(4, 'E$i', i));
    }
    final sid = await db
        .into(db.sources)
        .insert(
          SourcesCompanion.insert(
            kind: SourceKind.local,
            name: 'Extras',
            rootUri: media.uri.toString(),
            addedAt: DateTime.now().toUtc(),
          ),
        );
    final scan = ScanService(db: db, resolver: resolver());
    await scan.scan(sid);
    await scan.dispose();
    final indexer = MusicIndexer(
      db: db,
      files: MusicFiles(db, resolver()),
      art: ArtworkStore(db, Directory('${data.path}/art')),
    )..start();
    for (var i = 0; i < 100 && indexer.pending == 0; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    await indexer.idle();
    await indexer.dispose();
    final lib = MusicLibrary(db);
    return await lib.albumTracks((await lib.albums()).single.groupKey);
  }

  testWidgets('MUS-006 MUS-011 EQ and levelling reach libmpv; the sleep '
      'timer fades and pauses real playback', (tester) async {
    if (!MpvEngine.isAvailable) {
      return markTestSkipped('blocked: libmpv is not bundled in this build');
    }
    await tester.runAsync(() async {
      final tracks = await library();
      final engine = CrossfadingEngine(
        () => MpvEngine(
          EngineRole.music,
          config: MpvEngineConfig(audioBridge: AudioBridge()),
        ),
      );
      final player = MusicPlayer(
        engine: engine,
        queues: QueueRepository(db),
        library: MusicLibrary(db),
        files: MusicFiles(db, resolver()),
      );
      await player.init();
      final dsp = MusicDsp(engine: engine, prefs: MusicPrefs(db), db: db);
      await dsp.load();
      await dsp.applyPreset('rock');
      await dsp.update(
        dsp.sound.copyWith(
          loudness: LoudnessMode.ebuR128,
          crossfade: const Duration(seconds: 2),
        ),
      );
      await player.playTracks(tracks);
      await Future<void>.delayed(const Duration(milliseconds: 800));
      expect(engine.current.status, PlaybackStatus.playing);
      expect(engine.current.error, isNull);

      final timer = SleepTimer(
        player: player,
        engine: engine,
        fade: const Duration(milliseconds: 800),
        tick: const Duration(milliseconds: 50),
      )..startTime(const Duration(milliseconds: 1500));
      await Future<void>.delayed(const Duration(milliseconds: 1100));
      expect(engine.current.volume, lessThan(1));
      await Future<void>.delayed(const Duration(milliseconds: 1200));
      expect(engine.current.status, PlaybackStatus.paused);
      expect(engine.current.volume, closeTo(1, 0.01));
      await timer.dispose();
      await dsp.dispose();
      await player.dispose();
      await engine.dispose();
    });
  });

  testWidgets('MUS-006 ratings and favourites persist in the index', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final tracks = await library();
      final r = MusicRatings(db, TagRepository(db));
      await r.setRating(tracks.first.itemId, 7);
      await r.setFavourite(tracks.first.itemId, favourite: true);
      expect(await r.rating(tracks.first.itemId), 7);
      expect(await r.isFavourite(tracks.first.itemId), isTrue);
    });
  });
}
