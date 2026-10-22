import 'package:drift/drift.dart';
import 'package:mediahro/core/db/library_database.dart';
import 'package:mediahro/core/index/index_writer.dart';
import 'package:mediahro/core/metadata/filename_parser.dart';
import 'package:mediahro/core/metadata/nfo.dart';

/// Reads a sidecar next to an item (`movie.nfo`, `<name>.nfo`) from its
/// source; null when absent.
typedef SidecarReader = Future<String?> Function(ItemRow item, String fileName);

enum ScrapeOutcome { fromNfo, noMatch, skipped }

/// Local metadata for videos (LIB-011, ADR-048): NFO sidecars first, else the
/// file-name parser. Nothing is looked up online: no film database needs a
/// key the publisher would have to hold, so there is no remote matching.
/// Per-source opt-in, unmatch (back to the file-name title) and a pinned
/// state that later scans leave alone.
final class MetadataScraper {
  MetadataScraper({
    required this.db,
    this.sidecars,
    IndexWriter? writer,
    DateTime Function()? clock,
  }) : _writer = writer ?? IndexWriter(db),
       _clock = clock ?? DateTime.now;

  final LibraryDatabase db;
  final SidecarReader? sidecars;
  final IndexWriter _writer;
  final DateTime Function() _clock;

  /// Reads the sidecars of every unscanned video of sources that opted in.
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
    if (nfo != null && nfo.title != null) {
      await _applyNfo(item, nfo, parsed);
      return ScrapeOutcome.fromNfo;
    }
    await _markScraped(itemId);
    return ScrapeOutcome.noMatch;
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
