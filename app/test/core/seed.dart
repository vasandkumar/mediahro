import 'package:drift/drift.dart';
import 'package:mediahro/core/db/library_database.dart';
import 'package:mediahro/core/index/index_writer.dart';
import 'package:mediahro/core/metadata/filename_parser.dart';

/// Test data builder for index-level tests.
final class Seed {
  Seed(this.db);

  final LibraryDatabase db;
  late final IndexWriter writer = IndexWriter(db);
  int? _source;

  Future<int> source({
    String name = 'Local',
    SourceKind kind = SourceKind.local,
    bool locked = false,
  }) => db
      .into(db.sources)
      .insert(
        SourcesCompanion.insert(
          kind: kind,
          name: name,
          rootUri: 'file:///$name/',
          addedAt: DateTime.utc(2026),
          locked: Value(locked),
        ),
      );

  Future<int> item(
    String relPath, {
    ItemKind kind = ItemKind.video,
    int? sourceId,
    String? title,
    int size = 1000,
    int? durationMs,
    int? height,
    String? videoCodec,
    String? audioCodec,
    String? hdrType,
    int playCount = 0,
    DateTime? addedAt,
    DateTime? lastPlayedAt,
    bool hidden = false,
    String? artist,
    String? album,
    String? genre,
    int? year,
  }) async {
    final sid = sourceId ?? (_source ??= await source());
    final name = relPath.split('/').last;
    final t = title ?? cleanTitle(name);
    final at = addedAt ?? DateTime.utc(2026);
    final id = await db
        .into(db.items)
        .insert(
          ItemsCompanion.insert(
            sourceId: sid,
            relPath: relPath,
            parentPath: relPath.contains('/')
                ? relPath.substring(0, relPath.lastIndexOf('/'))
                : '',
            name: name,
            ext: name.split('.').last,
            kind: kind,
            size: size,
            mtime: at,
            addedAt: at,
            scannedAt: at,
            title: t,
            sortTitle: sortTitle(t),
            durationMs: Value(durationMs),
            height: Value(height),
            width: Value(height == null ? null : height * 16 ~/ 9),
            videoCodec: Value(videoCodec),
            audioCodec: Value(audioCodec),
            hdrType: Value(hdrType),
            playCount: Value(playCount),
            lastPlayedAt: Value(lastPlayedAt),
            hidden: Value(hidden),
          ),
        );
    if (artist != null || album != null || genre != null || year != null) {
      await db
          .into(db.audioMeta)
          .insert(
            AudioMetaCompanion.insert(
              itemId: Value(id),
              artist: Value(artist),
              album: Value(album),
              genre: Value(genre),
              year: Value(year),
            ),
          );
    }
    await writer.refreshFts([id]);
    return id;
  }

  Future<void> tag(int itemId, String tag) async {
    final existing = await (db.select(
      db.tags,
    )..where((t) => t.name.equals(tag))).getSingleOrNull();
    final id =
        existing?.id ??
        await db.into(db.tags).insert(TagsCompanion.insert(name: tag));
    await db
        .into(db.itemTags)
        .insert(
          ItemTagsCompanion.insert(itemId: itemId, tagId: id),
          mode: InsertMode.insertOrIgnore,
        );
    await writer.refreshFts([itemId]);
  }

  Future<void> rate(int itemId, int value) => db
      .into(db.ratings)
      .insertOnConflictUpdate(
        RatingsCompanion.insert(itemId: Value(itemId), value: value),
      );
}
