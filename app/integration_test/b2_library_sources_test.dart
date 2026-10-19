import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderListenable;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mediahro/app/l10n/gen/app_localizations.dart';
import 'package:mediahro/core/backup/backup_service.dart';
import 'package:mediahro/core/db/library_database.dart';
import 'package:mediahro/core/db/sqlite_support.dart';
import 'package:mediahro/core/files/file_operations.dart';
import 'package:mediahro/core/files/file_systems.dart';
import 'package:mediahro/core/index/index_writer.dart';
import 'package:mediahro/core/library/library_views.dart';
import 'package:mediahro/core/library/parental_gate.dart';
import 'package:mediahro/core/library/progress.dart';
import 'package:mediahro/core/library/queues.dart';
import 'package:mediahro/core/library/tags.dart';
import 'package:mediahro/core/net/persistent_network_policy.dart';
import 'package:mediahro/core/parsers/playlist_parser.dart';
import 'package:mediahro/core/providers.dart';
import 'package:mediahro/core/scanner/scan_service.dart';
import 'package:mediahro/core/search/library_search.dart';
import 'package:mediahro/core/sources/source_access.dart';
import 'package:mediahro/features/sources/sources_screen.dart';
import 'package:mediahro/platform/platform_facades.dart';
import 'package:mediahro_ffi/mediahro_ffi.dart';

import '../test/core/seed.dart';

/// Lane B2 on real devices (Android emulator, iOS simulator, macOS,
/// Windows): the platform's SQLite with FTS5, isolates, the local file
/// system and the crypto stack. Cells that need lane C4's facades (folder
/// grants, OS trash, secure storage) run here once C4 provides them and are
/// skipped with `pending: C4 …` until then (docs/lanes rule 7).
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final report = <String, Object>{};
  tearDownAll(() => binding.reportData = report);

  late Directory media;
  late Directory dbDir;
  late LibraryDatabase db;

  setUp(() async {
    media = await Directory.systemTemp.createTemp('mediahro_b2_media');
    dbDir = await Directory.systemTemp.createTemp('mediahro_b2_db');
    db = LibraryDatabase.open(dbDir);
  });
  tearDown(() async {
    await db.close();
    await media.delete(recursive: true);
    await dbDir.delete(recursive: true);
  });

  Future<int> addLocal() => db
      .into(db.sources)
      .insert(
        SourcesCompanion.insert(
          kind: SourceKind.local,
          name: 'Device',
          rootUri: media.uri.toString(),
          addedAt: DateTime.now().toUtc(),
        ),
      );

  ScanService scanner() => ScanService(
    db: db,
    resolver: DefaultSourceResolver(
      builders: {SourceKind.local: (_) => const LocalFileSystem()},
    ),
  );

  Future<void> write(String rel, [List<int> bytes = const [1, 2, 3]]) async {
    final f = File('${media.path}/$rel');
    await f.parent.create(recursive: true);
    await f.writeAsBytes(bytes);
  }

  testWidgets('LIB-001/LIB-003 scan on an isolate, then rescan incrementally', (
    tester,
  ) async {
    for (var i = 0; i < 300; i++) {
      await write('Show/Season 1/Show.S01E${i.toString().padLeft(3, '0')}.mkv');
    }
    await write('Music/Artist - Song.flac');
    await write('Photos/IMG_0001.jpg');
    final sid = await addLocal();
    final svc = scanner();
    final first = await svc.scan(sid);
    expect(first.state, ScanJobState.done, reason: '${first.error}');
    expect(first.result.added, 302);

    await File('${media.path}/Photos/IMG_0001.jpg').delete();
    await write('Photos/IMG_0002.jpg', [9, 9]);
    final second = await svc.scan(sid);
    expect(second.state, ScanJobState.done, reason: '${second.error}');
    expect(second.result.added, 1);
    final kinds = {
      for (final i in await db.select(db.items).get())
        i.relPath.split('/').first: i.kind,
    };
    expect(kinds, {
      'Show': ItemKind.video,
      'Music': ItemKind.audio,
      'Photos': ItemKind.image,
    });
  });

  testWidgets(
    'LIB-001/LIB-005 the platform SQLite runs the index (FTS5, JSON, >= 3.30)',
    (tester) async {
      // iOS/macOS use the system SQLite (ADR-020); Android/Windows bundle it.
      final r = await inspectSqlite(db);
      debugPrint(
        'LIB-001 sqlite: ${r.version} on ${Platform.operatingSystem}'
        '${Platform.isIOS || Platform.isMacOS ? ' (system)' : ' (bundled)'}',
      );
      report['sqlite_version'] = r.version;
      expect(r.missing, isEmpty, reason: r.compileOptions.join(' '));
      if (!Platform.isIOS && !Platform.isMacOS) {
        expect(r.compileOptions, contains('ENABLE_FTS5'));
      }
    },
  );

  testWidgets(
    'LIB-005 prefix search across every field and every filter on the device',
    (tester) async {
      final seed = Seed(db);
      final search = LibrarySearch(db);
      Future<List<String?>> titles(
        String q, [
        SearchFilters f = const SearchFilters(),
      ]) async => [
        for (final i in await search.search(SearchRequest(q, filters: f)))
          i.title,
      ];

      await seed.item('Films/Blade.Runner.1982.mkv', title: 'Blade Runner');
      final song = await seed.item(
        'Music/track01.flac',
        title: 'Teardrop',
        kind: ItemKind.audio,
        artist: 'Massive Attack',
        album: 'Mezzanine',
      );
      await seed.tag(song, 'trip-hop');
      final photo = await seed.item(
        'Photos/IMG_2001.jpg',
        title: 'Beach day',
        kind: ItemKind.image,
      );
      // People and places come from the photo pipeline (C3).
      final person = await db
          .into(db.people)
          .insert(PeopleCompanion.insert(name: 'Grace Hopper'));
      await db
          .into(db.itemPeople)
          .insert(
            ItemPeopleCompanion.insert(
              itemId: photo,
              personId: person,
              role: 'face',
            ),
          );
      final place = await db
          .into(db.places)
          .insert(
            PlacesCompanion.insert(
              name: 'Lisbon',
              country: const Value('Portugal'),
            ),
          );
      await db
          .into(db.imageMeta)
          .insert(
            ImageMetaCompanion.insert(
              itemId: Value(photo),
              placeId: Value(place),
            ),
          );
      await IndexWriter(db).refreshFts([photo]);

      expect(await titles('bla'), ['Blade Runner'], reason: 'title prefix');
      expect(await titles('track01'), ['Teardrop'], reason: 'file name');
      expect(await titles('trip'), ['Teardrop'], reason: 'tag');
      expect(await titles('massiv'), ['Teardrop'], reason: 'artist');
      expect(await titles('mezz'), ['Teardrop'], reason: 'album');
      expect(await titles('hopp'), ['Beach day'], reason: 'people');
      expect(await titles('lisb'), ['Beach day'], reason: 'places');
      expect(await titles('portu'), ['Beach day'], reason: 'country');

      final nas = await seed.source(name: 'NAS', kind: SourceKind.smb);
      final uhd = await seed.item(
        'uhd.mkv',
        title: 'Film UHD',
        height: 2160,
        videoCodec: 'hevc',
        hdrType: 'dolbyVision',
        durationMs: 7200000,
        addedAt: DateTime.utc(2026, 5),
      );
      await seed.item(
        'hd.mkv',
        title: 'Film HD',
        height: 720,
        videoCodec: 'h264',
        durationMs: 1800000,
        playCount: 3,
        addedAt: DateTime.utc(2025),
        sourceId: nas,
      );
      await seed.item('song.flac', title: 'Film Score', kind: ItemKind.audio);
      await seed.rate(uhd, 9);
      expect(
        await titles('film', const SearchFilters(kinds: {ItemKind.audio})),
        ['Film Score'],
        reason: 'type',
      );
      expect(await titles('film', SearchFilters(sourceIds: {nas})), [
        'Film HD',
      ], reason: 'source');
      expect(
        await titles(
          'film',
          const SearchFilters(resolutions: {ResolutionClass.uhd}),
        ),
        ['Film UHD'],
        reason: 'resolution',
      );
      expect(await titles('film', const SearchFilters(videoCodecs: {'h264'})), [
        'Film HD',
      ], reason: 'codec');
      expect(
        await titles('film', const SearchFilters(hdrTypes: {'dolbyVision'})),
        ['Film UHD'],
        reason: 'HDR',
      );
      expect(
        await titles(
          'film',
          const SearchFilters(minDuration: Duration(hours: 1)),
        ),
        ['Film UHD'],
        reason: 'duration',
      );
      expect(
        await titles('film', SearchFilters(addedAfter: DateTime.utc(2026))),
        ['Film UHD'],
        reason: 'date',
      );
      expect(await titles('film', const SearchFilters(minRating: 8)), [
        'Film UHD',
      ], reason: 'rating');
      expect(
        (await titles('film', const SearchFilters(unplayedOnly: true)))..sort(),
        ['Film Score', 'Film UHD'],
        reason: 'unplayed',
      );
    },
  );

  testWidgets(
    'FILE-002/FILE-006 rename carries sidecars on the device file system',
    (tester) async {
      await write('Clip.mkv');
      await write('Clip.en.srt');
      final ops = FileOperations(fileSystems: MountedFileSystems(), db: db);
      final renamed = await ops.rename(
        Uri.file('${media.path}/Clip.mkv'),
        'Holiday.mkv',
      );
      expect(File.fromUri(renamed).existsSync(), isTrue);
      expect(File('${media.path}/Holiday.en.srt').existsSync(), isTrue);
      expect(File('${media.path}/Clip.en.srt').existsSync(), isFalse);
    },
  );

  testWidgets('LIB-007 playlists parse on an isolate and round-trip', (
    tester,
  ) async {
    const m3u =
        '#EXTM3U\n#EXTINF:215,Artist - One\none.flac\n#EXTINF:-1,Radio\nhttps://example.org/live\n';
    final parsed = await parsePlaylistIsolated(
      Uint8List.fromList(utf8.encode(m3u)),
      PlaylistFormat.m3u,
    );
    expect(parsed.entries.map((e) => (e.artist, e.title)), [
      ('Artist', 'One'),
      (null, 'Radio'),
    ]);
    final again = parsePlaylist(writeM3u(parsed.entries), PlaylistFormat.m3u);
    expect(again.entries.length, 2);
  });

  testWidgets('CORE-014 encrypted backup round-trips with the device crypto', (
    tester,
  ) async {
    await addLocal();
    final backup = BackupService(db);
    final file = await backup.export('correct horse', iterations: 100000);
    await db.delete(db.sources).go();
    final report = await backup.restore(file, 'correct horse');
    expect(report.sources, 1);
    expect((await db.select(db.sources).get()).single.name, 'Device');
  });

  testWidgets('LIB-001 Sources screen lists the device folder with its count', (
    tester,
  ) async {
    final sid = await addLocal();
    await write('a.mkv');
    await scanner().scan(sid);
    final policy = await PersistentNetworkPolicy.load(db);
    addTearDown(policy.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          libraryDatabaseProvider.overrideWithValue(db),
          networkPolicyProvider.overrideWithValue(policy),
          appDataDirectoryProvider.overrideWithValue(dbDir),
        ],
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: SourcesScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Device'), findsOneWidget);
    expect(find.textContaining('1 item'), findsOneWidget);
  });

  testWidgets(
    'LIB-003 10 k files scan and rescan incrementally (budgets in profile builds)',
    (tester) async {
      for (var d = 0; d < 100; d++) {
        final sub = Directory('${media.path}/Folder $d')..createSync();
        for (var i = 0; i < 100; i++) {
          File('${sub.path}/Episode.S01E${i.toString().padLeft(2, '0')}.mkv')
              .writeAsBytesSync(const [1, 2, 3]);
        }
      }
      final sid = await addLocal();
      final svc = scanner();
      final sw = Stopwatch()..start();
      final first = await svc.scan(sid);
      final initial = sw.elapsed;
      expect(first.state, ScanJobState.done, reason: '${first.error}');
      expect(first.result.added, 10000);
      sw.reset();
      final second = await svc.scan(sid);
      final incremental = sw.elapsed;
      expect(second.result.added + second.result.updated, 0);
      report['lib003_initial_ms'] = initial.inMilliseconds;
      report['lib003_incremental_ms'] = incremental.inMilliseconds;
      debugPrint(
        'LIB-003 perf: initial ${initial.inMilliseconds} ms, '
        'incremental ${incremental.inMilliseconds} ms',
      );
      // docs/11 §5: budgets apply to profile/release builds on reference
      // devices (10 s desktop, 30 s mid-range phone, 2 s incremental); CI's
      // JIT debug runs only report them, as for CORE-001.
      if (!kDebugMode) {
        if (!Platform.isAndroid && !Platform.isIOS) {
          expect(initial, lessThanOrEqualTo(const Duration(seconds: 10)));
        }
        expect(incremental, lessThanOrEqualTo(const Duration(seconds: 2)));
      }
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );

  testWidgets('LIB-005 search over 50 k items on the device', (tester) async {
    final sid = await addLocal();
    const words = [
      'alpha',
      'bravo',
      'charlie',
      'delta',
      'echo',
      'foxtrot',
      'golf',
      'hotel',
    ];
    final now = DateTime.utc(2026);
    await db.batch((b) {
      b.insertAll(db.items, [
        for (var i = 0; i < 50000; i++)
          ItemsCompanion.insert(
            sourceId: sid,
            relPath: 'd${i ~/ 500}/file_$i.mkv',
            parentPath: 'd${i ~/ 500}',
            name: 'file_$i.mkv',
            ext: 'mkv',
            kind: ItemKind.video,
            size: i,
            mtime: now,
            addedAt: now,
            scannedAt: now,
            title: '${words[i % 8]} ${words[(i ~/ 8) % 8]} $i',
            sortTitle: '${words[i % 8]} $i',
            height: Value(i.isEven ? 1080 : 2160),
          ),
      ]);
    });
    await IndexWriter(db).rebuildFts();
    final search = LibrarySearch(db);
    await search.search(const SearchRequest('alp'));
    final times = <int>[];
    for (var i = 0; i < 21; i++) {
      final sw = Stopwatch()..start();
      final r = await search.search(
        SearchRequest(
          i.isEven ? 'char del' : 'ho',
          filters: const SearchFilters(resolutions: {ResolutionClass.uhd}),
        ),
      );
      times.add(sw.elapsedMicroseconds);
      expect(r, isNotEmpty);
    }
    times.sort();
    final median = Duration(microseconds: times[10]);
    report['lib005_median_us'] = median.inMicroseconds;
    debugPrint(
      'LIB-005 perf: median ${median.inMicroseconds} µs over 50 k items',
    );
    // doc 04 LIB-005 / ADR-020: ≤ 50 ms on mobile, ≤ 30 ms on desktop. The
    // time is spent in SQLite, not in Dart, so it is asserted in debug too.
    final budget = Platform.isAndroid || Platform.isIOS
        ? const Duration(milliseconds: 50)
        : const Duration(milliseconds: 30);
    expect(median, lessThanOrEqualTo(budget));
  }, timeout: const Timeout(Duration(minutes: 5)));

  testWidgets(
    'LIB-008/LIB-009/LIB-015 queues, tags, labels and statistics survive a restart',
    (tester) async {
      await write('Music/a.flac', List.filled(300, 1));
      await write('Music/b.flac', List.filled(200, 1));
      await write('Films/c.mkv', List.filled(1000, 1));
      final sid = await addLocal();
      await scanner().scan(sid);
      final items = await db.select(db.items).get();
      final audio = [
        for (final i in items)
          if (i.kind == ItemKind.audio) i.id,
      ]..sort();
      final film = items.firstWhere((i) => i.kind == ItemKind.video).id;

      var queues = QueueRepository(db);
      final gym = await queues.createAudioQueue('Gym');
      final car = await queues.createAudioQueue('Car');
      await queues.replace(gym, audio);
      await queues.replace(car, audio.reversed.toList());
      await queues.activate(car);
      final video = await queues.videoQueue();
      expect(await queues.videoQueue(), video, reason: 'one video queue');
      await queues.replace(video, [film]);

      var tags = TagRepository(db);
      await tags.addTag([...audio, film], 'favourites');
      await tags.setLabel(audio, LabelColor.green);

      final progress = ProgressRepository(db);
      await progress.recordPlay(audio.first, const Duration(minutes: 3));
      await progress.recordPlay(audio.first, const Duration(minutes: 2));
      await progress.recordPlay(film, const Duration(minutes: 40));

      // Restart: a fresh connection to the same database file.
      await db.close();
      db = LibraryDatabase.open(dbDir);
      queues = QueueRepository(db);
      tags = TagRepository(db);

      expect(
        (await queues.audioQueues()).map((q) => q.name),
        containsAll(['Gym', 'Car']),
      );
      expect((await queues.active(QueueMode.audio))?.id, car);
      expect([
        for (final e in (await queues.load(gym)).entries) e.itemId,
      ], audio);
      expect(
        [for (final e in (await queues.load(video)).entries) e.itemId],
        [film],
      );
      expect(await tags.tagsOf(film), ['favourites']);
      expect(await tags.labelOf(audio.last), LabelColor.green);
      expect(await tags.labelOf(film), isNull, reason: 'bulk apply only');

      final stats = await LibraryViews(db).stats();
      expect(stats.playCount, 3);
      expect(stats.timePlayed, const Duration(minutes: 45));
      expect(stats.topItems.first.$1.id, audio.first);
      expect(stats.topItems.first.$2, 2);
      expect(stats.bytesByKind[ItemKind.audio], 500);
      expect(stats.bytesByKind[ItemKind.video], 1000);
      expect(stats.bytesBySource[sid], 1500);
      expect(stats.countByKind[ItemKind.audio], 2);
    },
  );

  // Cells that need lane C4's facades: skipped until C4 provides them.
  T? facade<T>(ProviderListenable<T> p) {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    try {
      return c.read(p);
    } on Object {
      return null;
    }
  }

  testWidgets('LIB-002/FILE-002 OS trash with restore through StorageFacade', (
    tester,
  ) async {
    final storage = facade<StorageFacade>(storageProvider);
    if (storage == null) return markTestSkipped('pending: C4 StorageFacade');
    await write('Trash me/a.mkv');
    final uri = File('${media.path}/Trash me/a.mkv').uri;
    final r = await storage.moveToTrash([uri]);
    expect(File.fromUri(uri).existsSync(), isFalse);
    await storage.restoreFromTrash(r);
    expect(File.fromUri(uri).existsSync(), isTrue);
  });

  testWidgets('LIB-013 parental PIN in the OS secure storage', (tester) async {
    final secure = facade<SecureStorageFacade>(secureStorageProvider);
    if (secure == null) {
      return markTestSkipped('pending: C4 SecureStorageFacade');
    }
    final gate = ParentalGate(db: db, secureStorage: secure);
    addTearDown(gate.dispose);
    await gate.setPin('4711');
    gate.lock();
    expect(
      await gate.unlock(pin: '0000', preferBiometrics: false),
      UnlockResult.wrongPin,
    );
    expect(
      await gate.unlock(pin: '4711', preferBiometrics: false),
      UnlockResult.unlocked,
    );
    await gate.removePin();
  });
}
