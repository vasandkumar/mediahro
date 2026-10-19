import 'package:drift/drift.dart';
import 'package:mediahro/core/db/library_database.dart';
import 'package:mediahro/core/index/index_writer.dart';

/// User tags on any item and colour labels, with bulk apply (LIB-009).
/// Tags are part of the search index (LIB-005).
final class TagRepository {
  TagRepository(this.db, {IndexWriter? writer})
    : _writer = writer ?? IndexWriter(db);

  final LibraryDatabase db;
  final IndexWriter _writer;

  /// Tag names are trimmed; matching is case-insensitive, the first spelling
  /// wins.
  Future<int> tagId(String name) async {
    final n = name.trim();
    if (n.isEmpty) throw ArgumentError.value(name, 'name', 'empty tag');
    final existing = await db
        .customSelect(
          'SELECT id FROM tag WHERE lower(name) = lower(?)',
          variables: [Variable.withString(n)],
        )
        .getSingleOrNull();
    if (existing != null) return existing.read<int>('id');
    return await db.into(db.tags).insert(TagsCompanion.insert(name: n));
  }

  Future<void> addTag(Iterable<int> itemIds, String name) =>
      db.transaction(() async {
        final id = await tagId(name);
        await db.batch((b) {
          b.insertAll(db.itemTags, [
            for (final i in itemIds)
              ItemTagsCompanion.insert(itemId: i, tagId: id),
          ], mode: InsertMode.insertOrIgnore);
        });
        await _writer.refreshFts(itemIds);
      });

  Future<void> removeTag(Iterable<int> itemIds, String name) =>
      db.transaction(() async {
        final id = await tagId(name);
        await (db.delete(
          db.itemTags,
        )..where((t) => t.tagId.equals(id) & t.itemId.isIn(itemIds))).go();
        await _writer.refreshFts(itemIds);
      });

  /// Batch tag edit (FILE-003): add and remove several tags at once.
  Future<void> editTags(
    Iterable<int> itemIds, {
    Set<String> add = const {},
    Set<String> remove = const {},
  }) => db.transaction(() async {
    for (final t in add) {
      await addTag(itemIds, t);
    }
    for (final t in remove) {
      await removeTag(itemIds, t);
    }
  });

  Future<void> renameTag(String from, String to) => db.transaction(() async {
    final id = await tagId(from);
    await (db.update(db.tags)..where((t) => t.id.equals(id))).write(
      TagsCompanion(name: Value(to.trim())),
    );
    final items = await (db.select(
      db.itemTags,
    )..where((t) => t.tagId.equals(id))).get();
    await _writer.refreshFts(items.map((e) => e.itemId));
  });

  Future<void> deleteTag(String name) => db.transaction(() async {
    final id = await tagId(name);
    final items = await (db.select(
      db.itemTags,
    )..where((t) => t.tagId.equals(id))).get();
    await (db.delete(db.tags)..where((t) => t.id.equals(id))).go();
    await _writer.refreshFts(items.map((e) => e.itemId));
  });

  Future<List<String>> tagsOf(int itemId) async {
    final rows =
        await (db.select(db.tags).join([
                innerJoin(db.itemTags, db.itemTags.tagId.equalsExp(db.tags.id)),
              ])
              ..where(db.itemTags.itemId.equals(itemId))
              ..orderBy([OrderingTerm.asc(db.tags.name)]))
            .get();
    return [for (final r in rows) r.readTable(db.tags).name];
  }

  /// All tags with usage counts, for the tag picker.
  Future<Map<String, int>> allTags() async {
    final rows = await db
        .customSelect(
          'SELECT t.name, count(it.item_id) AS n FROM tag t '
          'LEFT JOIN item_tag it ON it.tag_id = t.id GROUP BY t.id ORDER BY t.name',
        )
        .get();
    return {for (final r in rows) r.read<String>('name'): r.read<int>('n')};
  }

  /// Sets (or clears with null) the colour label of every item.
  Future<void> setLabel(Iterable<int> itemIds, LabelColor? color) =>
      db.transaction(() async {
        if (color == null) {
          await (db.delete(
            db.labels,
          )..where((l) => l.itemId.isIn(itemIds))).go();
          return;
        }
        await db.batch((b) {
          b.insertAllOnConflictUpdate(db.labels, [
            for (final i in itemIds)
              LabelsCompanion.insert(itemId: Value(i), color: color),
          ]);
        });
      });

  Future<LabelColor?> labelOf(int itemId) async => (await (db.select(
    db.labels,
  )..where((l) => l.itemId.equals(itemId))).getSingleOrNull())?.color;
}
