import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mediahro/core/db/library_database.dart';
import 'package:mediahro/core/scanner/scan_service.dart';
import 'package:mediahro/core/sources/source_access.dart';
import 'package:mediahro/features/music/library/artwork_store.dart';
import 'package:mediahro/features/music/library/music_files.dart';
import 'package:mediahro/features/music/library/music_indexer.dart';
import 'package:mediahro/features/music/library/music_library.dart';
import 'package:mediahro/features/music/lyrics/lrc.dart';
import 'package:mediahro/features/music/lyrics/lyrics_service.dart';
import 'package:mediahro/features/music/tags/tag_reader.dart';
import 'package:mediahro/features/music/visualizer/analysis.dart';
import 'package:mediahro_ffi/mediahro_ffi.dart';

import '../test/features/music/tag_fixtures.dart';

/// Lane C2, lyrics and the visualiser's analysis on real devices
/// (MUS-005, AUD-046): embedded, sidecar and edited lyrics through the
/// device's file system and tag isolate; the FFT on the device's CPU.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late Directory media;
  late Directory data;
  late LibraryDatabase db;

  setUp(() async {
    media = await Directory.systemTemp.createTemp('c2ly_media');
    data = await Directory.systemTemp.createTemp('c2ly_data');
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

  SourceResolver resolver() => DefaultSourceResolver(
    builders: {SourceKind.local: (_) => const LocalFileSystem()},
  );

  testWidgets('MUS-005 embedded, sidecar and edited lyrics on the device', (
    tester,
  ) async {
    await tester.runAsync(() async {
      await File('${media.path}/a.mp3').writeAsBytes(
        bytesOf([
          id3v2(4, [
            id3Text(4, 'TIT2', ['Song A']),
            id3Text(4, 'TPE1', ['Amy']),
            id3Sylt(4, [(1000, 'One'), (2500, 'Two')]),
          ]),
          mpegAudio,
        ]),
      );
      await File('${media.path}/b.mp3').writeAsBytes(
        bytesOf([
          id3v2(4, [
            id3Text(4, 'TIT2', ['Song B']),
          ]),
          mpegAudio,
        ]),
      );
      await File('${media.path}/b.lrc')
          .writeAsString('[00:01.00]<00:01.00>Side <00:01.40>car');
      final sid = await db
          .into(db.sources)
          .insert(
            SourcesCompanion.insert(
              kind: SourceKind.local,
              name: 'Lyrics',
              rootUri: media.uri.toString(),
              addedAt: DateTime.now().toUtc(),
            ),
          );
      final scan = ScanService(db: db, resolver: resolver());
      await scan.scan(sid);
      await scan.dispose();
      final files = MusicFiles(db, resolver());
      final indexer = MusicIndexer(
        db: db,
        files: files,
        art: ArtworkStore(db, Directory('${data.path}/art')),
      )..start();
      for (var i = 0; i < 100 && indexer.pending == 0; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      await indexer.idle();
      await indexer.dispose();
      final songs = await MusicLibrary(db).songs();
      final a = songs.firstWhere((t) => t.title == 'Song A');
      final b = songs.firstWhere((t) => t.title == 'Song B');
      final service = LyricsService(
        files: files,
        cacheDir: Directory('${data.path}/lyrics'),
        readTags: readTagsOf,
      );
      final la = await service.forTrack(a);
      expect(la!.synced, isTrue);
      expect(la.lines.map((l) => l.text), ['One', 'Two']);
      final lb = await service.forTrack(b);
      expect(lb!.origin, LyricsOrigin.sidecar);
      expect(lb.wordSynced, isTrue);
      await service.saveEdited(
        a,
        const Lyrics([LyricLine('Mine', time: Duration(seconds: 3))]),
      );
      expect((await service.forTrack(a))!.origin, LyricsOrigin.edited);
    });
  });

  testWidgets('AUD-046 spectrum analysis runs within a frame on the device', (
    tester,
  ) async {
    final a = SpectrumAnalyzer();
    final input = VisualizerInput(
      samples: Float32List.fromList([
        for (var i = 0; i < 2048; i++) (i % 64) / 64 - 0.5,
      ]),
    );
    final sw = Stopwatch()..start();
    for (var i = 0; i < 60; i++) {
      a.process(input);
    }
    sw.stop();
    // 60 frames of 2048-point analysis well under a second of CPU.
    expect(sw.elapsedMilliseconds, lessThan(1000));
  });
}
