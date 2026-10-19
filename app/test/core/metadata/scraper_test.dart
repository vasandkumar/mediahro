import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:mediahro/core/db/library_database.dart';
import 'package:mediahro/core/metadata/metadata_clients.dart';
import 'package:mediahro/core/metadata/nfo.dart';
import 'package:mediahro/core/metadata/scraper.dart';
import 'package:mediahro/core/net/network_policy.dart';
import 'package:mediahro/core/search/library_search.dart';
import 'package:mediahro_servers/mediahro_servers.dart';

import '../seed.dart';

/// Canned TMDB responses keyed by path.
final class _FakeTmdb implements HttpTransport {
  final requests = <Uri>[];
  bool offline = false;

  @override
  Future<HttpResponseData> send(HttpRequestData r) async {
    requests.add(r.uri);
    if (offline) throw const SocketException('offline');
    final p = r.uri.path;
    Object? body;
    if (r.uri.host == 'image.tmdb.org') {
      return const HttpResponseData(statusCode: 200, body: [1, 2, 3]);
    }
    if (p == '/3/search/movie') {
      body = {
        'results': [
          {
            'id': 1,
            'title': 'The Matrix Revisited',
            'release_date': '2001-11-20',
          },
          {'id': 603, 'title': 'The Matrix', 'release_date': '1999-03-30'},
        ],
      };
    } else if (p == '/3/movie/603') {
      body = {
        'id': 603,
        'title': 'The Matrix',
        'release_date': '1999-03-30',
        'overview': 'A hacker learns the truth.',
        'poster_path': '/poster.jpg',
        'backdrop_path': '/back.jpg',
        'vote_average': 8.2,
        'imdb_id': 'tt0133093',
        'belongs_to_collection': {'id': 2344, 'name': 'The Matrix Collection'},
        'credits': {
          'cast': [
            {'name': 'Keanu Reeves', 'character': 'Neo'},
          ],
          'crew': [
            {'name': 'Lana Wachowski', 'job': 'Director'},
            {'name': 'Someone', 'job': 'Editor'},
          ],
        },
      };
    } else if (p == '/3/search/tv') {
      body = {
        'results': [
          {'id': 1396, 'name': 'Breaking Bad', 'first_air_date': '2008-01-20'},
        ],
      };
    } else if (p == '/3/tv/1396') {
      body = {
        'id': 1396,
        'name': 'Breaking Bad',
        'first_air_date': '2008-01-20',
      };
    } else if (p == '/3/tv/1396/season/1/episode/2') {
      body = {'name': "Cat's in the Bag...", 'overview': 'Ep two.'};
    } else {
      return const HttpResponseData(statusCode: 404);
    }
    return HttpResponseData(
      statusCode: 200,
      body: utf8.encode(jsonEncode(body)),
    );
  }
}

void main() {
  late LibraryDatabase db;
  late Seed seed;
  late _FakeTmdb http;
  late Directory cache;

  setUp(() async {
    db = LibraryDatabase.memory();
    seed = Seed(db);
    http = _FakeTmdb();
    cache = await Directory.systemTemp.createTemp('mediahro_art');
  });
  tearDown(() async {
    await db.close();
    await cache.delete(recursive: true);
  });

  Future<int> optInSource() async {
    final sid = await seed.source(name: 'Films');
    await (db.update(db.sources)..where((s) => s.id.equals(sid))).write(
      const SourcesCompanion(scrapeMetadata: Value(true)),
    );
    return sid;
  }

  MetadataScraper scraper({SidecarReader? sidecars}) => MetadataScraper(
    db: db,
    providers: [TmdbClient(http, apiKey: 'user-key')],
    sidecars: sidecars,
    artwork: ArtworkCache(cache, http),
  );

  test('LIB-011 movie matched by parsed title and year; poster, cast, collection cached', () async {
    final sid = await optInSource();
    final id = await seed.item(
      'The.Matrix.1999.1080p.BluRay.x264-GRP.mkv',
      sourceId: sid,
    );
    final s = scraper();
    expect(await s.scrapePending(), {ScrapeOutcome.matched: 1});
    final search = http.requests.firstWhere((u) => u.path == '/3/search/movie');
    expect(search.queryParameters['query'], 'The Matrix');
    expect(search.queryParameters['year'], '1999');
    final meta = await (db.select(
      db.videoMeta,
    )..where((v) => v.itemId.equals(id))).getSingle();
    expect(meta.tmdbId, '603');
    expect(meta.overview, contains('hacker'));
    expect(meta.collectionId, isNotNull);
    final item = await (db.select(
      db.items,
    )..where((i) => i.id.equals(id))).getSingle();
    expect(item.title, 'The Matrix');
    final art = await db.select(db.artworks).get();
    expect(art.map((a) => a.role).toSet(), {'poster', 'backdrop'});
    expect(
      art.every((a) => a.cachePath != null && File(a.cachePath!).existsSync()),
      isTrue,
    );
    // Cast is searchable (people column).
    expect(
      await LibrarySearch(db).search(const SearchRequest('keanu')),
      hasLength(1),
    );

    // Offline afterwards: nothing is fetched again, data stays.
    http.offline = true;
    expect(await s.scrapePending(), isEmpty);
  });

  test('LIB-011 episodes: series, season and episode names', () async {
    final sid = await optInSource();
    final id = await seed.item('Breaking.Bad.S01E02.720p.mkv', sourceId: sid);
    expect(await scraper().scrapeItem(id), ScrapeOutcome.matched);
    final meta = await (db.select(
      db.videoMeta,
    )..where((v) => v.itemId.equals(id))).getSingle();
    expect(meta.episodeTitle, "Cat's in the Bag...");
    expect(meta.seriesId, isNotNull);
    expect(meta.seasonId, isNotNull);
  });

  test(
    'LIB-011 scraping is per-folder opt-in; manual unmatch sticks',
    () async {
      final off = await seed.source(name: 'Home');
      final home = await seed.item('The.Matrix.1999.mkv', sourceId: off);
      final s = scraper();
      expect(await s.scrapeItem(home), ScrapeOutcome.skipped);
      expect(http.requests, isEmpty);

      final on = await optInSource();
      final id = await seed.item('The.Matrix.1999.mkv', sourceId: on);
      await s.scrapeItem(id);
      await s.unmatch(id);
      final meta = await (db.select(
        db.videoMeta,
      )..where((v) => v.itemId.equals(id))).getSingle();
      expect(meta.tmdbId, isNull);
      expect(meta.matchLocked, isTrue);
      expect(await s.scrapeItem(id), ScrapeOutcome.skipped);
      await s.match(id, 'tmdb', '603', series: false);
      final again = await (db.select(
        db.videoMeta,
      )..where((v) => v.itemId.equals(id))).getSingle();
      expect(again.tmdbId, '603');
      expect(again.matchLocked, isTrue);
    },
  );

  test('LIB-011 NFO sidecars are used before any online lookup', () async {
    final sid = await optInSource();
    final id = await seed.item('Home Movie.mkv', sourceId: sid);
    final s = MetadataScraper(
      db: db,
      providers: const [],
      sidecars: (item, name) async => name == 'Home Movie.nfo'
          ? '<movie><title>Summer 2019</title><year>2019</year><plot>Beach.</plot> '
                '<actor><name>Ana</name><role>Herself</role></actor></movie>'
          : null,
    );
    expect(await s.scrapeItem(id), ScrapeOutcome.fromNfo);
    final item = await (db.select(
      db.items,
    )..where((i) => i.id.equals(id))).getSingle();
    expect(item.title, 'Summer 2019');
    expect(http.requests, isEmpty);
  });

  test(
    'PRIV-004 scraping stops when the TMDB endpoint is turned off',
    () async {
      final sid = await optInSource();
      final id = await seed.item('The.Matrix.1999.mkv', sourceId: sid);
      final gateway = NetworkGateway(_Off());
      addTearDown(gateway.close);
      final s = MetadataScraper(
        db: db,
        providers: [TmdbClient(gateway, apiKey: 'k')],
      );
      expect(await s.scrapeItem(id), ScrapeOutcome.unavailable);
    },
  );

  test('LIB-011 best match prefers the exact title and year', () {
    const results = [
      MetadataMatch(
        provider: 'tmdb',
        id: '1',
        title: 'Dune',
        isSeries: false,
        year: 1984,
      ),
      MetadataMatch(
        provider: 'tmdb',
        id: '2',
        title: 'Dune',
        isSeries: false,
        year: 2021,
      ),
      MetadataMatch(
        provider: 'tmdb',
        id: '3',
        title: 'Dune: Part Two',
        isSeries: false,
        year: 2024,
      ),
    ];
    expect(bestMatch('Dune', 2021, results)!.id, '2');
    expect(bestMatch('Dune', null, results)!.id, '1');
    expect(bestMatch('Completely Different', null, results), isNull);
  });

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

final class _Off implements NetworkPolicy {
  @override
  bool isEnabled(NetworkEndpoint endpoint) => false;

  @override
  bool isUserConfiguredHost(String host) => false;

  @override
  void recordUse(NetworkEndpoint endpoint, DateTime at) {}
}
