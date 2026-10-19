import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mediahro/app/l10n/gen/app_localizations.dart';
import 'package:mediahro/core/backup/backup_service.dart';
import 'package:mediahro/core/db/library_database.dart';
import 'package:mediahro/core/files/file_operations.dart';
import 'package:mediahro/core/files/file_systems.dart';
import 'package:mediahro/core/index/index_writer.dart';
import 'package:mediahro/core/library/library_views.dart';
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
import 'package:mediahro_ffi/mediahro_ffi.dart';

/// Lane B2 on real devices (Android emulator, iOS simulator, macOS,
/// Windows): the platform's SQLite with FTS5, isolates, the local file
/// system and the crypto stack. Native storage grants (SAF, bookmarks) are
/// lane C4's and are faked in the unit tests.
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

  testWidgets('LIB-005 FTS5 prefix search runs on the platform SQLite', (
    tester,
  ) async {
    await write('Films/Blade Runner (1982).mkv');
    await write('Films/Alien (1979).mkv');
    final sid = await addLocal();
    await scanner().scan(sid);
    final hits = await LibrarySearch(db).search(const SearchRequest('bla'));
    expect(hits.map((h) => h.relPath), ['Films/Blade Runner (1982).mkv']);
  });

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
    'LIB-003 10 k files: initial scan and incremental rescan budgets',
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
      // docs/11 §5: 10 s desktop; the 30 s phone budget is measured on the
      // reference device (device lab), not on CI emulators.
      if (!Platform.isAndroid && !Platform.isIOS) {
        expect(initial, lessThanOrEqualTo(const Duration(seconds: 10)));
      }
      expect(incremental, lessThanOrEqualTo(const Duration(seconds: 2)));
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
    // Budgets apply to profile/release builds (docs/11 §5); JIT debug runs only report.
    if (!kDebugMode) {
      expect(median, lessThanOrEqualTo(const Duration(milliseconds: 50)));
    }
  }, timeout: const Timeout(Duration(minutes: 5)));

  testWidgets(
    'LIB-008/LIB-009/LIB-015 queues, tags and statistics persist in the device database',
    (tester) async {
      await write('Music/a.flac');
      await write('Music/b.flac');
      final sid = await addLocal();
      await scanner().scan(sid);
      final ids = [for (final i in await db.select(db.items).get()) i.id];

      final queues = QueueRepository(db);
      final gym = await queues.createAudioQueue('Gym');
      await queues.replace(gym, ids);
      await queues.activate(gym);
      expect([for (final e in (await queues.load(gym)).entries) e.itemId], ids);
      expect((await queues.active(QueueMode.audio))?.id, gym);

      final tags = TagRepository(db);
      await tags.addTag(ids, 'workout');
      await tags.setLabel(ids, LabelColor.green);
      expect(await tags.tagsOf(ids.first), ['workout']);
      expect(await tags.labelOf(ids.last), LabelColor.green);

      await ProgressRepository(db)
          .recordPlay(ids.first, const Duration(minutes: 3));
      final stats = await LibraryViews(db).stats();
      expect(stats.playCount, 1);
      expect(stats.timePlayed, const Duration(minutes: 3));
      expect(stats.countByKind[ItemKind.audio], 2);
    },
  );
}
