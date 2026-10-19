import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediahro/core/db/library_database.dart';
import 'package:mediahro/core/rules/rule_sql.dart';
import 'package:mediahro/core/search/library_search.dart';

import '../seed.dart';

void main() {
  late LibraryDatabase db;
  late Seed seed;
  late LibrarySearch search;

  setUp(() {
    db = LibraryDatabase.memory();
    seed = Seed(db);
    search = LibrarySearch(db);
  });
  tearDown(() => db.close());

  Future<List<String>> titles(String q, [SearchFilters? f]) async => [
    for (final i in await search.search(
      SearchRequest(q, filters: f ?? const SearchFilters()),
    ))
      i.title,
  ];

  test(
    'LIB-005 prefix search across titles, file names, tags, artists and albums',
    () async {
      await seed.item('Films/blade_runner.mkv', title: 'Blade Runner');
      final song = await seed.item(
        'Music/track01.flac',
        kind: ItemKind.audio,
        title: 'Teardrop',
        artist: 'Massive Attack',
        album: 'Mezzanine',
      );
      await seed.item(
        'Photos/IMG_2001.jpg',
        kind: ItemKind.image,
        title: 'IMG 2001',
      );
      await seed.tag(song, 'trip-hop');

      expect(await titles('bla'), ['Blade Runner']);
      expect(await titles('runner'), ['Blade Runner']);
      expect(await titles('track01'), ['Teardrop']);
      expect(await titles('massiv'), ['Teardrop']);
      expect(await titles('mezz'), ['Teardrop']);
      expect(await titles('trip'), ['Teardrop']);
      expect(await titles('IMG_20'), ['IMG 2001']);
      expect(await titles('blade nothing'), isEmpty);
      expect(await titles('   '), isEmpty);
    },
  );

  test(
    'LIB-005 search is accent-insensitive and treats FTS syntax as text',
    () async {
      await seed.item('a.mkv', title: 'Amélie');
      expect(await titles('ame'), ['Amélie']);
      expect(await titles('"ame*'), ['Amélie']);
      expect(await titles('ame) OR (x'), isEmpty);
      expect(await titles('NEAR(ame'), isEmpty);
    },
  );

  test('LIB-005 filters by type, source, resolution, codec, HDR, duration, date, rating and unplayed', () async {
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

    expect(await titles('film', const SearchFilters(kinds: {ItemKind.audio})), [
      'Film Score',
    ]);
    expect(await titles('film', SearchFilters(sourceIds: {nas})), ['Film HD']);
    expect(
      await titles(
        'film',
        const SearchFilters(resolutions: {ResolutionClass.uhd}),
      ),
      ['Film UHD'],
    );
    expect(await titles('film', const SearchFilters(videoCodecs: {'h264'})), [
      'Film HD',
    ]);
    expect(
      await titles('film', const SearchFilters(hdrTypes: {'dolbyVision'})),
      ['Film UHD'],
    );
    expect(
      await titles(
        'film',
        const SearchFilters(minDuration: Duration(hours: 1)),
      ),
      ['Film UHD'],
    );
    expect(
      await titles('film', SearchFilters(addedAfter: DateTime.utc(2026))),
      ['Film UHD'],
    );
    expect(await titles('film', const SearchFilters(minRating: 8)), [
      'Film UHD',
    ]);
    expect(
      (await titles('film', const SearchFilters(unplayedOnly: true)))..sort(),
      ['Film Score', 'Film UHD'],
    );
    // Filters alone, no text: browse by facet.
    expect(await titles('', const SearchFilters(videoCodecs: {'hevc'})), [
      'Film UHD',
    ]);
  });

  test('LIB-013 hidden items and PIN-gated sources/folders are excluded from search', () async {
    final kids = await seed.source(name: 'Kids');
    final locked = await seed.source(name: 'Private', locked: true);
    await seed.item('a.mkv', title: 'Alpha visible', sourceId: kids);
    await seed.item(
      'b.mkv',
      title: 'Alpha hidden',
      sourceId: kids,
      hidden: true,
    );
    await seed.item('c.mkv', title: 'Alpha locked source', sourceId: locked);
    await seed.item(
      'Adult/d.mkv',
      title: 'Alpha locked folder',
      sourceId: kids,
    );
    await seed.item(
      'Adulthood/e.mkv',
      title: 'Alpha sibling folder',
      sourceId: kids,
    );
    await db
        .into(db.lockedFolders)
        .insert(
          LockedFoldersCompanion.insert(sourceId: kids, relPath: 'Adult'),
        );
    expect((await titles('alpha'))..sort(), [
      'Alpha sibling folder',
      'Alpha visible',
    ]);
    final open = await search.search(
      const SearchRequest('alpha', visibility: Visibility(unlocked: true)),
    );
    expect(open.map((i) => i.title), hasLength(4));
  });

  test(
    'LIB-005 search over 50 k items answers within the desktop budget (30 ms)',
    () async {
      final sid = await seed.source();
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
              mtime: DateTime.utc(2026),
              addedAt: DateTime.utc(2026),
              scannedAt: DateTime.utc(2026),
              title: '${words[i % 8]} ${words[(i ~/ 8) % 8]} $i',
              sortTitle: '${words[i % 8]} $i',
              height: Value(i.isEven ? 1080 : 2160),
            ),
        ]);
      });
      await seed.writer.rebuildFts();
      // Warm up the statement cache, then take the median of 21 runs.
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
      final median = Duration(microseconds: times[times.length ~/ 2]);
      // Reported in CI logs for the perf trend (docs/11 §5).
      // ignore: avoid_print
      print('LIB-005 perf: median ${median.inMicroseconds} µs over 50 k items');
      expect(median, lessThanOrEqualTo(const Duration(milliseconds: 30)));
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
