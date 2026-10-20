import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mediahro/app/app.dart';
import 'package:mediahro/app/router.dart';
import 'package:mediahro/core/db/library_database.dart';
import 'package:mediahro/core/library/progress.dart';
import 'package:mediahro/core/library/queues.dart';
import 'package:mediahro/core/providers.dart';
import 'package:mediahro/core/scanner/scan_service.dart';
import 'package:mediahro/core/sources/source_access.dart';
import 'package:mediahro/features/music/library/artwork_store.dart';
import 'package:mediahro/features/music/library/music_files.dart';
import 'package:mediahro/features/music/library/music_indexer.dart';
import 'package:mediahro/features/music/library/music_library.dart';
import 'package:mediahro/features/music/music_wiring.dart';
import 'package:mediahro/features/music/player/music_player.dart';
import 'package:mediahro/features/music/tags/tag_reader.dart';
import 'package:mediahro/features/settings/settings_providers.dart';
import 'package:mediahro/features/settings/settings_store.dart';
import 'package:mediahro_design/mediahro_design.dart';
import 'package:mediahro_engine/mediahro_engine.dart';
import 'package:mediahro_ffi/mediahro_ffi.dart';

import '../test/features/music/tag_fixtures.dart';

/// Lane C2 on real devices: the tag reader in an isolate, scanning and
/// indexing music, cover art, gapless queue playback through libmpv, and the
/// music UI (MUS-001, MUS-002, MUS-004, MUS-006, MUS-007).
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final report = <String, Object>{};
  tearDownAll(() => binding.reportData = report);

  late Directory media;
  late Directory data;
  late LibraryDatabase db;

  setUp(() async {
    media = await Directory.systemTemp.createTemp('c2_media');
    data = await Directory.systemTemp.createTemp('c2_data');
    db = LibraryDatabase.open(data);
  });
  tearDown(() async {
    await db.close();
    for (final d in [media, data]) {
      try {
        await d.delete(recursive: true);
      } on FileSystemException {
        // Windows may still map a file; temp is cleaned by the OS.
      }
    }
  });

  Future<File> write(String rel, List<int> bytes) async {
    final f = File('${media.path}/$rel');
    await f.parent.create(recursive: true);
    return await f.writeAsBytes(bytes);
  }

  /// [seconds] of a quiet stereo sine as 16-bit WAV with tags in an `id3 `
  /// chunk (playable by libmpv everywhere).
  Uint8List tone(
    double seconds, {
    required String title,
    required String album,
    required int track,
    String artist = 'Mediahro Test',
    bool cover = false,
  }) {
    const rate = 44100;
    final frames = (seconds * rate).round();
    final pcm = ByteData(frames * 4);
    for (var i = 0; i < frames; i++) {
      final v = (math.sin(2 * math.pi * (330 + track * 110) * i / rate) * 600)
          .round();
      pcm
        ..setInt16(i * 4, v, Endian.little)
        ..setInt16(i * 4 + 2, v, Endian.little);
    }
    final tag = id3v2(4, [
      id3Text(4, 'TIT2', [title]),
      id3Text(4, 'TPE1', [artist]),
      id3Text(4, 'TPE2', [artist]),
      id3Text(4, 'TALB', [album]),
      id3Text(4, 'TRCK', ['$track']),
      if (cover) id3Apic(4, jpeg),
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

  Future<int> addSource() => db
      .into(db.sources)
      .insert(
        SourcesCompanion.insert(
          kind: SourceKind.local,
          name: 'Test music',
          rootUri: media.uri.toString(),
          addedAt: DateTime.now().toUtc(),
        ),
      );

  SourceResolver resolver() => DefaultSourceResolver(
    builders: {SourceKind.local: (_) => const LocalFileSystem()},
  );

  Future<(MusicLibrary, ArtworkStore)> scanAndIndex() async {
    final sid = await addSource();
    final scan = ScanService(db: db, resolver: resolver());
    final out = await scan.scan(sid);
    expect(out.state, ScanJobState.done, reason: '${out.error}');
    await scan.dispose();
    final art = ArtworkStore(db, Directory('${data.path}/art'));
    final files = MusicFiles(db, resolver());
    final indexer = MusicIndexer(db: db, files: files, art: art)..start();
    for (var i = 0; i < 100 && indexer.pending == 0; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    await indexer.idle();
    await indexer.dispose();
    return (MusicLibrary(db), art);
  }

  testWidgets('MUS-002 every tag container parses in an isolate on the '
      'device', (tester) async {
    final files = {
      'a.mp3': bytesOf([
        id3v2(3, [
          id3Text(3, 'TIT2', ['id3']),
        ]),
        mpegAudio,
      ]),
      'b.flac': flac(['TITLE=flac']),
      'c.ogg': oggVorbis(['TITLE=ogg']),
      'd.opus': oggOpus(['TITLE=opus']),
      'e.m4a': mp4(text: {'©nam': 'mp4'}),
      'f.wma': asf(title: 'asf', artist: 'x'),
      'g.wav': wav(info: {'INAM': 'wav'}),
      'h.aiff': aiff(name: 'aiff'),
      'i.ape': bytesOf([
        ascii('MAC '),
        List.filled(60, 0),
        apeTag({'Title': 'ape'}),
      ]),
    };
    final sw = Stopwatch()..start();
    for (final e in files.entries) {
      final f = await write(e.key, e.value);
      final t = await tester.runAsync(() => TagReader.readFile(f.path));
      expect(
        t!.title,
        e.key.split('.').last == 'mp3' ? 'id3' : _expected[e.key],
      );
    }
    report['mus002_read_ms'] = sw.elapsedMilliseconds;
  });

  testWidgets('MUS-001 MUS-004 scan, read tags and art, and build the music '
      'library on the device', (tester) async {
    await tester.runAsync(() async {
      await write(
        'Album A/01.wav',
        tone(1, title: 'One', album: 'A', track: 1, cover: true),
      );
      await write(
        'Album A/02.wav',
        tone(1, title: 'Two', album: 'A', track: 2),
      );
      await write(
        'Album B/01.wav',
        tone(1, title: 'Bee', album: 'B', track: 1, artist: 'Other'),
      );
      await write('Album B/folder.jpg', jpeg);
      final (lib, art) = await scanAndIndex();
      final albums = await lib.albums();
      expect(albums.map((a) => a.title), ['A', 'B']);
      expect(albums.first.trackCount, 2);
      expect(albums.first.displayArtist, 'Mediahro Test');
      final tracks = await lib.albumTracks(albums.first.groupKey);
      expect(tracks.map((t) => t.title), ['One', 'Two']);
      expect(tracks.first.duration!.inMilliseconds, closeTo(1000, 50));
      expect((await lib.groups(GroupField.artist)).map((g) => g.name), [
        'Mediahro Test',
        'Other',
      ]);
      // Embedded art on A; folder art on B.
      expect(await art.coverPath(tracks.first.itemId), isNotNull);
      final b = await lib.albumTracks(albums[1].groupKey);
      expect(await art.coverPath(b.single.itemId), isNotNull);
    });
  });

  testWidgets('MUS-007 gapless queue playback through libmpv on the device', (
    tester,
  ) async {
    if (!MpvEngine.isAvailable) {
      return markTestSkipped('blocked: libmpv is not bundled in this build');
    }
    await tester.runAsync(() async {
      for (var i = 1; i <= 3; i++) {
        await write(
          'Gapless/0$i.wav',
          tone(1.2, title: 'G$i', album: 'Gapless', track: i),
        );
      }
      final (lib, _) = await scanAndIndex();
      final album = await lib.albumTracks((await lib.albums()).single.groupKey);
      final engine = CrossfadingEngine(
        () => MpvEngine(
          EngineRole.music,
          config: MpvEngineConfig(audioBridge: AudioBridge()),
        ),
      );
      final player = MusicPlayer(
        engine: engine,
        queues: QueueRepository(db),
        library: lib,
        files: MusicFiles(db, resolver()),
        progress: ProgressRepository(db),
      );
      await player.init();
      final indices = <int>[];
      final sub = player.states.listen((s) {
        if (indices.isEmpty || indices.last != s.index) indices.add(s.index);
      });
      final sw = Stopwatch()..start();
      await player.playTracks(album);
      // Wait for the natural (gapless) advances to the last track.
      while (sw.elapsed < const Duration(seconds: 20) &&
          !(player.state.index == 2 &&
              player.state.playback.position >
                  const Duration(milliseconds: 200))) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      report['mus007_gapless_ms'] = sw.elapsedMilliseconds;
      report['mus007_indices'] = indices.join(',');
      expect(indices, [0, 1, 2]);
      expect(player.state.playback.error, isNull);
      // The first two tracks counted as played.
      final played = await (db.select(
        db.items,
      )..where((i) => i.playCount.isBiggerThanValue(0))).get();
      expect(played.length, 2);
      // Manual controls on the real engine.
      await player.previous();
      expect(player.state.index, anyOf(1, 2));
      await player.pause();
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(engine.current.status, PlaybackStatus.paused);
      await sub.cancel();
      await player.dispose();
      await engine.dispose();
    });
  });

  testWidgets('MUS-001 MUS-006 music screen, mini player and Now Playing on '
      'the device', (tester) async {
    await tester.runAsync(() async {
      await write('UI/01.wav', tone(3, title: 'Alpha', album: 'Ui', track: 1));
      await write('UI/02.wav', tone(3, title: 'Beta', album: 'Ui', track: 2));
      await scanAndIndex();
    });
    final settings = await tester.runAsync(
      () => SettingsStore.open(MemorySettingsPersistence(), null),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsStoreProvider.overrideWithValue(settings!),
          libraryDatabaseProvider.overrideWithValue(db),
          appDataDirectoryProvider.overrideWithValue(data),
          sourceResolverProvider.overrideWithValue(resolver()),
          ...musicOverrides,
        ],
        child: MediahroApp(router: buildRouter(initialLocation: '/music')),
      ),
    );
    await _pumpFor(tester, const Duration(seconds: 2));
    expect(find.text('Songs'), findsWidgets);
    expect(find.text('Alpha'), findsOneWidget);
    await tester.tap(find.text('Alpha'));
    await _pumpFor(tester, const Duration(seconds: 2));
    // Mini player shows the track; open Now Playing.
    expect(find.text('Alpha'), findsWidgets);
    await tester.tap(
      find.descendant(
        of: find.byType(KMiniPlayer),
        matching: find.text('Alpha'),
      ),
    );
    await _pumpFor(tester, const Duration(seconds: 1));
    expect(find.text('Now playing'), findsOneWidget);
    expect(find.byTooltip('Next track'), findsOneWidget);
    await tester.tap(find.byTooltip('Next track'));
    await _pumpFor(tester, const Duration(seconds: 2));
    expect(find.text('Beta'), findsWidgets);
    // Builds without libmpv show the engine error instead of playing.
    if (MpvEngine.isAvailable) {
      await tester.tap(find.byTooltip('Pause'));
      await _pumpFor(tester, const Duration(seconds: 1));
      expect(find.byTooltip('Play'), findsWidgets);
    }
    await tester.pumpWidget(const SizedBox());
    await _pumpFor(tester, const Duration(milliseconds: 500));
  });
}

const _expected = {
  'b.flac': 'flac',
  'c.ogg': 'ogg',
  'd.opus': 'opus',
  'e.m4a': 'mp4',
  'f.wma': 'asf',
  'g.wav': 'wav',
  'h.aiff': 'aiff',
  'i.ape': 'ape',
};

/// Pumps frames while real async work (isolates, the engine) runs.
Future<void> _pumpFor(WidgetTester tester, Duration d) async {
  final end = DateTime.now().add(d);
  while (DateTime.now().isBefore(end)) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump();
  }
}
