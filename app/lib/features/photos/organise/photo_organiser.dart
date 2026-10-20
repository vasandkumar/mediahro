import 'package:drift/drift.dart';
import 'package:mediahro/core/db/library_database.dart';
import 'package:mediahro/core/library/playlists.dart';
import 'package:mediahro/core/library/tags.dart';
import 'package:mediahro/core/rules/smart_rule.dart';
import 'package:meta/meta.dart';

/// A photo album as the Albums tab lists it.
@immutable
final class PhotoAlbum {
  const PhotoAlbum({
    required this.id,
    required this.name,
    required this.count,
    required this.smart,
    this.coverItemId,
  });

  final int id;
  final String name;

  /// Photos in it now (smart albums count their rule's current result).
  final int count;
  final bool smart;
  final int? coverItemId;
}

/// Favourites, ratings, colour labels, tags and albums for photos (IMG-005),
/// over the library's shared tables (`image_meta.favourite`, `rating`,
/// `label`, `tag`, image playlists). Ratings are 1–5 stars, stored as half
/// stars (0–10) like every other mode.
final class PhotoOrganiser {
  PhotoOrganiser({
    required this.db,
    TagRepository? tags,
    PlaylistRepository? playlists,
  }) : tags = tags ?? TagRepository(db),
       playlists = playlists ?? PlaylistRepository(db);

  final LibraryDatabase db;
  final TagRepository tags;
  final PlaylistRepository playlists;

  static const String albumMode = 'image';

  // ---- favourites, ratings, labels, tags ------------------------------

  Future<void> setFavourite(
    Iterable<int> itemIds, {
    required bool value,
  }) async {
    final ids = itemIds.toList();
    if (ids.isEmpty) return;
    await db.transaction(() async {
      await db.batch((b) {
        // Rows exist for probed images; create the rest without touching
        // the columns the prober owns.
        b.insertAll(db.imageMeta, [
          for (final id in ids) ImageMetaCompanion.insert(itemId: Value(id)),
        ], mode: InsertMode.insertOrIgnore);
      });
      await (db.update(db.imageMeta)..where((m) => m.itemId.isIn(ids))).write(
        ImageMetaCompanion(favourite: Value(value)),
      );
    });
  }

  /// Marks the items as rejected (the XMP convention: rating -1) or clears
  /// the mark; a rejected photo is no longer a favourite. Star ratings are
  /// replaced by the mark.
  Future<void> setRejected(Iterable<int> itemIds, {required bool value}) async {
    final ids = itemIds.toList();
    if (ids.isEmpty) return;
    if (value) {
      await setFavourite(ids, value: false);
      await db.batch((b) {
        b.insertAllOnConflictUpdate(db.ratings, [
          for (final id in ids)
            RatingsCompanion.insert(itemId: Value(id), value: -1),
        ]);
      });
    } else {
      await (db.delete(
        db.ratings,
      )..where((r) => r.itemId.isIn(ids) & r.value.isSmallerThanValue(0))).go();
    }
  }

  /// Keeps the items: a favourite, and not rejected.
  Future<void> keep(Iterable<int> itemIds) async {
    final ids = itemIds.toList();
    await setRejected(ids, value: false);
    await setFavourite(ids, value: true);
  }

  /// Sets [stars] (0 clears) on every item.
  Future<void> setRating(Iterable<int> itemIds, int stars) async {
    final ids = itemIds.toList();
    if (ids.isEmpty) return;
    final v = stars.clamp(0, 5) * 2;
    await db.transaction(() async {
      if (v == 0) {
        await (db.delete(db.ratings)..where((r) => r.itemId.isIn(ids))).go();
        return;
      }
      await db.batch((b) {
        b.insertAllOnConflictUpdate(db.ratings, [
          for (final id in ids)
            RatingsCompanion.insert(itemId: Value(id), value: v),
        ]);
      });
    });
  }

  Future<void> setLabel(Iterable<int> itemIds, LabelColor? color) =>
      tags.setLabel(itemIds, color);

  Future<void> addTag(Iterable<int> itemIds, String name) =>
      tags.addTag(itemIds, name);

  Future<void> removeTag(Iterable<int> itemIds, String name) =>
      tags.removeTag(itemIds, name);

  Future<List<String>> tagsOf(int itemId) => tags.tagsOf(itemId);

  /// Tags present on every one of [itemIds] (what a multi-selection shows as
  /// applied).
  Future<Set<String>> commonTags(Iterable<int> itemIds) async {
    Set<String>? common;
    for (final id in itemIds) {
      final t = (await tags.tagsOf(id)).toSet();
      common = common == null ? t : common.intersection(t);
      if (common.isEmpty) break;
    }
    return common ?? {};
  }

  // ---- albums ---------------------------------------------------------

  Future<int> createAlbum(String name, {Iterable<int> items = const []}) async {
    final id = await playlists.createManual(name.trim(), mode: albumMode);
    final list = items.toList();
    if (list.isNotEmpty) await playlists.addItems(id, list);
    return id;
  }

  /// A smart album from [rule], limited to photos and videos of the library.
  Future<int> createSmartAlbum(String name, SmartRule rule) =>
      playlists.createSmart(
        name.trim(),
        SmartRule(
          root: rule.root,
          limit: rule.limit,
          limitUnit: rule.limitUnit,
          sort: rule.sort,
          kinds: const {'image', 'video'},
        ),
        mode: albumMode,
      );

  Future<void> renameAlbum(int id, String name) =>
      playlists.rename(id, name.trim());

  Future<void> deleteAlbum(int id) => playlists.delete(id);

  /// Adds [itemIds] to a manual album, skipping what it already has.
  Future<int> addToAlbum(int albumId, Iterable<int> itemIds) async {
    final have = await _memberIds(albumId);
    final fresh = [
      for (final id in itemIds.toSet())
        if (!have.contains(id)) id,
    ];
    if (fresh.isNotEmpty) await playlists.addItems(albumId, fresh);
    return fresh.length;
  }

  Future<void> removeFromAlbum(int albumId, Iterable<int> itemIds) async {
    final gone = itemIds.toSet();
    final rows =
        await (db.select(db.playlistItems)
              ..where((p) => p.playlistId.equals(albumId))
              ..orderBy([(p) => OrderingTerm.asc(p.position)]))
            .get();
    // Remove from the end so earlier positions stay valid.
    for (var i = rows.length - 1; i >= 0; i--) {
      if (gone.contains(rows[i].itemId)) {
        await playlists.removeAt(albumId, i);
      }
    }
  }

  Future<Set<int>> _memberIds(int albumId) async => {
    for (final r in await (db.select(
      db.playlistItems,
    )..where((p) => p.playlistId.equals(albumId))).get())
      if (r.itemId != null) r.itemId!,
  };

  /// Item ids of an album in display order (a smart album evaluates its rule
  /// now).
  Future<List<int>> albumItemIds(int albumId) async => [
    for (final t in await playlists.tracks(albumId))
      if (t.item != null) t.item!.id,
  ];

  /// Every photo album with its current size and a cover.
  Future<List<PhotoAlbum>> albums() async {
    final rows =
        await (db.select(db.playlists)
              ..where((p) => p.mode.equals(albumMode))
              ..orderBy([(p) => OrderingTerm.asc(p.name)]))
            .get();
    final out = <PhotoAlbum>[];
    for (final p in rows) {
      final ids = await albumItemIds(p.id);
      out.add(
        PhotoAlbum(
          id: p.id,
          name: p.name,
          count: ids.length,
          smart: p.rule != null,
          coverItemId: ids.isEmpty ? null : ids.first,
        ),
      );
    }
    return out;
  }
}
