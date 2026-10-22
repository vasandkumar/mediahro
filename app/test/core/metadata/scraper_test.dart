import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:mediahro/core/db/library_database.dart';
import 'package:mediahro/core/metadata/nfo.dart';
import 'package:mediahro/core/metadata/scraper.dart';
import 'package:mediahro/core/search/library_search.dart';

import '../seed.dart';

const _movieNfo =
    '<movie><title>Summer 2019</title><year>2019</year><plot>Beach.</plot> '
    '<actor><name>Ana</name><role>Herself</role></actor> '
    '<director>Ben</director></movie>';

/// LIB-011 after ADR-048: details come from NFO files next to the videos and
/// from the file name; nothing is looked up online.
void main() {
  late LibraryDatabase db;
  late Seed seed;

  setUp(() {
    db = LibraryDatabase.memory();
    seed = Seed(db);
  });
  tearDown(() => db.close());

  Future<int> optInSource() async {
    final sid = await seed.source(name: 'Films');
    await (db.update(db.sources)..where((s) => s.id.equals(sid))).write(
      const SourcesCompanion(scrapeMetadata: Value(true)),
    );
    return sid;
  }

  MetadataScraper scraper({SidecarReader? sidecars}) =>
      MetadataScraper(db: db, sidecars: sidecars);

  SidecarReader nfo(String fileName, String text) =>
      (item, name) async => name == fileName ? text : null;

  test('LIB-011 an NFO next to the video gives title, year, plot and the '
      'cast, which is searchable', () async {
    final sid = await optInSource();
    final id = await seed.item('Home Movie.mkv', sourceId: sid);
    final s = scraper(sidecars: nfo('Home Movie.nfo', _movieNfo));
    expect(await s.scrapePending(), {ScrapeOutcome.fromNfo: 1});
    final item = await (db.select(
      db.items,
    )..where((i) => i.id.equals(id))).getSingle();
    expect(item.title, 'Summer 2019');
    final meta = await (db.select(
      db.videoMeta,
    )..where((v) => v.itemId.equals(id))).getSingle();
    expect(meta.overview, 'Beach.');
    expect(meta.year, 2019);
    expect(meta.scrapedAt, isNotNull);
    expect(
      await LibrarySearch(db).search(const SearchRequest('ana')),
      hasLength(1),
    );
    // Done: a second pass has nothing to do.
    expect(await s.scrapePending(), isEmpty);
  });

  test(
    'LIB-011 movie.nfo in the folder serves as the fallback sidecar',
    () async {
      final sid = await optInSource();
      final id = await seed.item('Film/Part.mkv', sourceId: sid);
      expect(
        await scraper(sidecars: nfo('movie.nfo', _movieNfo)).scrapeItem(id),
        ScrapeOutcome.fromNfo,
      );
    },
  );

  test('LIB-011 a video with no NFO is only marked as read: its title stays '
      'the one the file name gives, and nothing is fetched', () async {
    final sid = await optInSource();
    final id = await seed.item('The.Matrix.1999.1080p.mkv', sourceId: sid);
    final s = scraper(sidecars: (item, name) async => null);
    expect(await s.scrapePending(), {ScrapeOutcome.noMatch: 1});
    final meta = await (db.select(
      db.videoMeta,
    )..where((v) => v.itemId.equals(id))).getSingle();
    expect(meta.scrapedAt, isNotNull);
    expect(meta.overview, isNull);
    expect(await s.scrapePending(), isEmpty);
  });

  test(
    'LIB-011 reading sidecars is per-folder opt-in; unmatch sticks',
    () async {
      final off = await seed.source(name: 'Home');
      final home = await seed.item('Home Movie.mkv', sourceId: off);
      final s = scraper(sidecars: nfo('Home Movie.nfo', _movieNfo));
      expect(await s.scrapeItem(home), ScrapeOutcome.skipped);

      final on = await optInSource();
      final id = await seed.item('Home Movie.mkv', sourceId: on);
      expect(await s.scrapeItem(id), ScrapeOutcome.fromNfo);
      await s.unmatch(id);
      final meta = await (db.select(
        db.videoMeta,
      )..where((v) => v.itemId.equals(id))).getSingle();
      expect(meta.overview, isNull);
      expect(meta.matchLocked, isTrue);
      final item = await (db.select(
        db.items,
      )..where((i) => i.id.equals(id))).getSingle();
      expect(item.title, isNot('Summer 2019'));
      expect(await s.scrapeItem(id), ScrapeOutcome.skipped);
      // Forcing it reads the NFO again.
      expect(await s.scrapeItem(id, force: true), ScrapeOutcome.fromNfo);
    },
  );

  test('LIB-011 NFO parser reads Kodi uniqueids and episodes', () {
    final n = parseNfo(
      '<episodedetails><title>Pilot</title><showtitle>Show</showtitle><season>1</season>'
      '<episode>1</episode><uniqueid type="tmdb">55</uniqueid><aired>2010-02-03</aired></episodedetails>',
    )!;
    expect(
      (n.isEpisode, n.showTitle, n.season, n.episode, n.tmdbId, n.year),
      (true, 'Show', 1, 1, '55', 2010),
    );
    expect(parseNfo('https://www.imdb.com/title/tt0133093/'), isNull);
  });
}
