import 'dart:io';

import 'package:drift/drift.dart';
import 'package:mediahro/core/db/library_database.dart';
import 'package:mediahro/core/index/index_writer.dart';
import 'package:mediahro/core/index/xxh3.dart';
import 'package:mediahro/core/metadata/filename_parser.dart';
import 'package:mediahro/core/metadata/metadata_clients.dart';
import 'package:mediahro/core/metadata/nfo.dart';
import 'package:mediahro/core/net/network_policy.dart';
import 'package:mediahro_servers/mediahro_servers.dart';

/// Reads a sidecar next to an item (`movie.nfo`, `<name>.nfo`) from its
/// source; null when absent.
typedef SidecarReader = Future<String?> Function(ItemRow item, String fileName);

enum ScrapeOutcome { matched, fromNfo, noMatch, skipped, unavailable }

/// Downloads artwork once into the cache directory so scraped libraries
/// work fully offline (LIB-011).
final class ArtworkCache {
  ArtworkCache(this.directory, this.http, {this.maxBytes = 8 << 20});

  final Directory directory;
  final HttpTransport http;
  final int maxBytes;

  Future<String?> fetch(String url) async {
    final name = xxh3Hex(Uint8List.fromList(url.codeUnits));
    final ext = url.toLowerCase().endsWith('.png') ? 'png' : 'jpg';
    final f = File('${directory.path}${Platform.pathSeparator}$name.$ext');
    if (f.existsSync()) return f.path;
    final res = await http.send(
      HttpRequestData(method: 'GET', uri: Uri.parse(url)),
    );
    if (res.statusCode != 200 ||
        res.body.isEmpty ||
        res.body.length > maxBytes) {
      return null;
    }
    await directory.create(recursive: true);
    final tmp = File('${f.path}.part');
    await tmp.writeAsBytes(res.body, flush: true);
    await tmp.rename(f.path);
    return f.path;
  }
}

/// TMDB/TVDB matching by the filename parser, with NFO sidecars first,
/// per-source opt-in, manual match/unmatch and offline cache (LIB-011).
final class MetadataScraper {
  MetadataScraper({
    required this.db,
    required this.providers,
    this.sidecars,
    this.artwork,
    IndexWriter? writer,
    DateTime Function()? clock,
  }) : _writer = writer ?? IndexWriter(db),
       _clock = clock ?? DateTime.now;

  final LibraryDatabase db;

  /// In preference order (TMDB first, TVDB as fallback for series).
  final List<MetadataProvider> providers;
  final SidecarReader? sidecars;
  final ArtworkCache? artwork;
  final IndexWriter _writer;
  final DateTime Function() _clock;
  final _seriesCache = <String, (int, MetadataMatch)>{};

  /// Scrapes every unscraped video of sources that opted in.
  Future<Map<ScrapeOutcome, int>> scrapePending({
    bool Function()? cancelled,
  }) async {
    final rows = await db
        .customSelect(
          'SELECT i.* FROM item i JOIN source s ON s.id = i.source_id '
          'LEFT JOIN video_meta v ON v.item_id = i.id '
          "WHERE s.scrape_metadata = 1 AND i.kind = 'video' AND i.missing = 0 "
          'AND coalesce(v.match_locked, 0) = 0 AND v.scraped_at IS NULL ORDER BY i.id',
          readsFrom: {db.items},
        )
        .get();
    final counts = <ScrapeOutcome, int>{};
    for (final r in rows) {
      if (cancelled?.call() ?? false) break;
      final o = await scrapeItem(db.items.map(r.data).id);
      counts[o] = (counts[o] ?? 0) + 1;
    }
    return counts;
  }

  Future<ScrapeOutcome> scrapeItem(int itemId, {bool force = false}) async {
    final item = await (db.select(
      db.items,
    )..where((i) => i.id.equals(itemId))).getSingle();
    final meta = await _meta(itemId);
    if (!force && (meta?.matchLocked ?? false)) return ScrapeOutcome.skipped;
    final source = await (db.select(
      db.sources,
    )..where((s) => s.id.equals(item.sourceId))).getSingle();
    if (!source.scrapeMetadata && !force) return ScrapeOutcome.skipped;

    final parts = item.relPath.split('/');
    final parsed = parseVideoFileName(
      parts.last,
      parentFolders: parts.reversed.skip(1).toList(),
    );
    final nfo = await _nfo(item);
    if (nfo != null &&
        nfo.title != null &&
        (nfo.tmdbId == null || providers.isEmpty)) {
      await _applyNfo(item, nfo, parsed);
      return ScrapeOutcome.fromNfo;
    }
    try {
      final series = parsed.isEpisode || (nfo?.isEpisode ?? false);
      final title =
          nfo?.showTitle ??
          (series ? parsed.title : nfo?.title ?? parsed.title);
      final match = await _find(
        title,
        year: nfo?.year ?? parsed.year,
        series: series,
        knownId: nfo?.tmdbId,
      );
      if (match == null) {
        await _markScraped(itemId);
        return ScrapeOutcome.noMatch;
      }
      EpisodeMetadata? ep;
      final season = nfo?.season ?? parsed.season;
      final episode = nfo?.episode ?? parsed.episode ?? parsed.absoluteEpisode;
      if (series && season != null && episode != null) {
        ep = await _provider(match.provider).episode(match.id, season, episode);
      }
      await _apply(
        item,
        match,
        ep,
        season: season,
        episode: episode,
        locked: false,
      );
      return ScrapeOutcome.matched;
    } on MetadataUnavailable {
      return ScrapeOutcome.unavailable;
    } on NetworkBlocked {
      // The TMDB/TVDB privacy toggle is off (PRIV-004).
      return ScrapeOutcome.unavailable;
    }
  }

  /// Manual match: pins [providerId]'s result and locks it against rescans.
  Future<void> match(
    int itemId,
    String provider,
    String providerId, {
    required bool series,
  }) async {
    final item = await (db.select(
      db.items,
    )..where((i) => i.id.equals(itemId))).getSingle();
    final m = await _provider(provider).details(providerId, series: series);
    final meta = await _meta(itemId);
    EpisodeMetadata? ep;
    if (series && meta?.seasonNumber != null && meta?.episodeNumber != null) {
      ep = await _provider(provider)
          .episode(providerId, meta!.seasonNumber!, meta.episodeNumber!);
    }
    await _apply(
      item,
      m,
      ep,
      season: meta?.seasonNumber,
      episode: meta?.episodeNumber,
      locked: true,
    );
  }

  /// Unmatch: drops scraped data, restores the file-name title and keeps
  /// the item unmatched on later scans.
  Future<void> unmatch(int itemId) => db.transaction(() async {
    final item = await (db.select(
      db.items,
    )..where((i) => i.id.equals(itemId))).getSingle();
    final parts = item.relPath.split('/');
    final parsed = parseVideoFileName(
      parts.last,
      parentFolders: parts.reversed.skip(1).toList(),
    );
    await (db.update(
      db.videoMeta,
    )..where((v) => v.itemId.equals(itemId))).write(
      const VideoMetaCompanion(
        tmdbId: Value(null),
        tvdbId: Value(null),
        imdbId: Value(null),
        overview: Value(null),
        episodeTitle: Value(null),
        communityRating: Value(null),
        seriesId: Value(null),
        seasonId: Value(null),
        collectionId: Value(null),
        matchLocked: Value(true),
      ),
    );
    await (db.delete(
      db.itemPeople,
    )..where((p) => p.itemId.equals(itemId))).go();
    await (db.delete(db.artworks)
          ..where((a) => a.ownerType.equals('item') & a.ownerId.equals(itemId)))
        .go();
    final title = parsed.title.isEmpty ? cleanTitle(item.name) : parsed.title;
    await (db.update(db.items)..where((i) => i.id.equals(itemId))).write(
      ItemsCompanion(title: Value(title), sortTitle: Value(sortTitle(title))),
    );
    await _writer.refreshFts([itemId]);
  });

  /// Candidates for the manual-match sheet.
  Future<List<MetadataMatch>> candidates(
    String title, {
    required bool series,
    int? year,
  }) async {
    final out = <MetadataMatch>[];
    for (final p in providers) {
      try {
        out.addAll(await p.search(title, year: year, series: series));
      } on MetadataUnavailable {
        continue;
      }
    }
    return out;
  }

  Future<MetadataMatch?> _find(
    String title, {
    required bool series,
    int? year,
    String? knownId,
  }) async {
    if (knownId != null && providers.any((p) => p.id == 'tmdb')) {
      return await _provider('tmdb').details(knownId, series: series);
    }
    if (series) {
      final cached = _seriesCache[_norm(title)];
      if (cached != null) return cached.$2;
    }
    for (final p in providers) {
      List<MetadataMatch> results;
      try {
        results = await p.search(
          title,
          year: series ? null : year,
          series: series,
        );
        if (results.isEmpty && year != null && !series) {
          results = await p.search(title, series: series);
        }
      } on MetadataUnavailable {
        continue;
      }
      final best = bestMatch(title, year, results);
      if (best == null) continue;
      final full = await p.details(best.id, series: series);
      return full;
    }
    return null;
  }

  MetadataProvider _provider(String id) =>
      providers.firstWhere((p) => p.id == id);

  Future<VideoMetaRow?> _meta(int itemId) => (db.select(
    db.videoMeta,
  )..where((v) => v.itemId.equals(itemId))).getSingleOrNull();

  Future<NfoInfo?> _nfo(ItemRow item) async {
    final read = sidecars;
    if (read == null) return null;
    final base = item.name.contains('.')
        ? item.name.substring(0, item.name.lastIndexOf('.'))
        : item.name;
    for (final n in ['$base.nfo', 'movie.nfo']) {
      final text = await read(item, n);
      if (text != null) {
        final info = parseNfo(text);
        if (info != null) return info;
      }
    }
    return null;
  }

  Future<void> _applyNfo(ItemRow item, NfoInfo nfo, ParsedName parsed) =>
      db.transaction(() async {
        await db
            .into(db.videoMeta)
            .insertOnConflictUpdate(
              VideoMetaCompanion.insert(
                itemId: Value(item.id),
                parsedTitle: Value(parsed.title),
                year: Value(nfo.year ?? parsed.year),
                seasonNumber: Value(nfo.season ?? parsed.season),
                episodeNumber: Value(nfo.episode ?? parsed.episode),
                overview: Value(nfo.plot),
                communityRating: Value(nfo.rating),
                tmdbId: Value(nfo.tmdbId),
                tvdbId: Value(nfo.tvdbId),
                imdbId: Value(nfo.imdbId),
                episodeTitle: Value(nfo.isEpisode ? nfo.title : null),
                scrapedAt: Value(_clock()),
              ),
            );
        final title = nfo.isEpisode
            ? (nfo.showTitle ?? parsed.title)
            : nfo.title!;
        await _setTitle(item.id, title);
        await _people(item.id, nfo.actors, nfo.directors);
        await _writer.refreshFts([item.id]);
      });

  Future<void> _apply(
    ItemRow item,
    MetadataMatch m,
    EpisodeMetadata? ep, {
    required int? season,
    required int? episode,
    required bool locked,
  }) => db.transaction(() async {
    int? seriesId;
    int? seasonId;
    int? collectionId;
    if (m.isSeries) {
      seriesId = await _series(m);
      if (season != null) seasonId = await _season(seriesId, season);
    } else if (m.collectionId != null) {
      collectionId = await _collection(m);
    }
    await db
        .into(db.videoMeta)
        .insertOnConflictUpdate(
          VideoMetaCompanion.insert(
            itemId: Value(item.id),
            year: Value(m.year),
            seasonNumber: Value(season),
            episodeNumber: Value(episode),
            seriesId: Value(seriesId),
            seasonId: Value(seasonId),
            collectionId: Value(collectionId),
            tmdbId: Value(m.provider == 'tmdb' ? m.id : null),
            tvdbId: Value(m.provider == 'tvdb' ? m.id : null),
            imdbId: Value(m.imdbId),
            overview: Value(ep?.overview ?? m.overview),
            episodeTitle: Value(ep?.title),
            communityRating: Value(ep?.rating ?? m.rating),
            matchLocked: Value(locked),
            scrapedAt: Value(_clock()),
          ),
        );
    await _setTitle(item.id, m.title);
    await _people(item.id, m.cast, m.directors);
    await (db.delete(
          db.artworks,
        )..where((a) => a.ownerType.equals('item') & a.ownerId.equals(item.id)))
        .go();
    for (final (role, url) in [
      ('poster', m.posterUrl),
      ('backdrop', m.backdropUrl),
      ('thumb', ep?.stillUrl),
    ]) {
      if (url == null) continue;
      String? cached;
      try {
        cached = await artwork?.fetch(url);
      } on Object {
        cached = null;
      }
      await db
          .into(db.artworks)
          .insert(
            ArtworksCompanion.insert(
              ownerType: 'item',
              ownerId: item.id,
              role: role,
              uri: url,
              cachePath: Value(cached),
            ),
          );
    }
    await _writer.refreshFts([item.id]);
  });

  Future<void> _setTitle(int itemId, String title) =>
      (db.update(db.items)..where((i) => i.id.equals(itemId))).write(
        ItemsCompanion(title: Value(title), sortTitle: Value(sortTitle(title))),
      );

  Future<void> _people(
    int itemId,
    List<(String, String?)> cast,
    List<String> directors,
  ) async {
    await (db.delete(
      db.itemPeople,
    )..where((p) => p.itemId.equals(itemId))).go();
    Future<int> person(String name) async {
      final existing = await (db.select(
        db.people,
      )..where((p) => p.name.equals(name))).getSingleOrNull();
      return existing?.id ??
          await db.into(db.people).insert(PeopleCompanion.insert(name: name));
    }

    for (final (name, character) in cast) {
      await db
          .into(db.itemPeople)
          .insert(
            ItemPeopleCompanion.insert(
              itemId: itemId,
              personId: await person(name),
              role: 'actor',
              character: Value(character),
            ),
            mode: InsertMode.insertOrIgnore,
          );
    }
    for (final d in directors) {
      await db
          .into(db.itemPeople)
          .insert(
            ItemPeopleCompanion.insert(
              itemId: itemId,
              personId: await person(d),
              role: 'director',
            ),
            mode: InsertMode.insertOrIgnore,
          );
    }
  }

  Future<int> _series(MetadataMatch m) async {
    final key = _norm(m.title);
    final cached = _seriesCache[key];
    if (cached != null) return cached.$1;
    final existing =
        await (db.select(db.seriesTable)..where(
              (s) => m.provider == 'tmdb'
                  ? s.tmdbId.equals(m.id)
                  : s.tvdbId.equals(m.id),
            ))
            .getSingleOrNull();
    final id =
        existing?.id ??
        await db
            .into(db.seriesTable)
            .insert(
              SeriesTableCompanion.insert(
                title: m.title,
                year: Value(m.year),
                overview: Value(m.overview),
                tmdbId: Value(m.provider == 'tmdb' ? m.id : null),
                tvdbId: Value(m.provider == 'tvdb' ? m.id : null),
              ),
            );
    _seriesCache[key] = (id, m);
    return id;
  }

  Future<int> _season(int seriesId, int number) async {
    final existing =
        await (db.select(db.seasons)..where(
              (s) => s.seriesId.equals(seriesId) & s.number.equals(number),
            ))
            .getSingleOrNull();
    return existing?.id ??
        await db
            .into(db.seasons)
            .insert(
              SeasonsCompanion.insert(seriesId: seriesId, number: number),
            );
  }

  Future<int> _collection(MetadataMatch m) async {
    final existing =
        await (db.select(db.collections)..where(
              (c) =>
                  c.type.equals('tmdb') & c.externalId.equals(m.collectionId!),
            ))
            .getSingleOrNull();
    return existing?.id ??
        await db
            .into(db.collections)
            .insert(
              CollectionsCompanion.insert(
                name: m.collectionName ?? m.title,
                type: 'tmdb',
                externalId: Value(m.collectionId),
              ),
            );
  }

  Future<void> _markScraped(int itemId) => db
      .into(db.videoMeta)
      .insert(
        VideoMetaCompanion.insert(
          itemId: Value(itemId),
          scrapedAt: Value(_clock()),
        ),
        onConflict: DoUpdate(
          (_) => VideoMetaCompanion(scrapedAt: Value(_clock())),
        ),
      );
}

/// Picks the candidate whose normalised title matches best, preferring
/// the parsed year; null when nothing is similar enough.
MetadataMatch? bestMatch(String title, int? year, List<MetadataMatch> results) {
  final want = _tokens(title);
  MetadataMatch? best;
  var bestScore = 0.0;
  for (final (i, r) in results.indexed) {
    final got = _tokens(r.title);
    final inter = want.intersection(got).length;
    final union = want.union(got).length;
    var score = union == 0 ? 0.0 : inter / union;
    if (_norm(r.title) == _norm(title)) score += 1;
    if (year != null && r.year != null) {
      if (r.year == year) {
        score += 0.6;
      } else if ((r.year! - year).abs() == 1) {
        score += 0.2;
      } else {
        score -= 0.4;
      }
    }
    score -= i * 0.01;
    if (score > bestScore) {
      bestScore = score;
      best = r;
    }
  }
  return bestScore >= 0.6 ? best : null;
}

String _norm(String s) =>
    s.toLowerCase().replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), '');

Set<String> _tokens(String s) => s
    .toLowerCase()
    .split(RegExp(r'[^\p{L}\p{N}]+', unicode: true))
    .where((t) => t.isNotEmpty && t != 'the' && t != 'a')
    .toSet();
