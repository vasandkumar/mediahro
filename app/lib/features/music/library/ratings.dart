import 'package:drift/drift.dart';
import 'package:mediahro/core/db/library_database.dart';
import 'package:mediahro/core/library/tags.dart';

/// Ratings (0…10, half stars) and favourites for songs (MUS-006). The
/// favourite is the user tag [favouriteTag], so smart playlists (MUS-008)
/// and search (LIB-005) find favourites like any other tag.
final class MusicRatings {
  MusicRatings(this.db, this.tags);

  final LibraryDatabase db;
  final TagRepository tags;

  static const favouriteTag = 'Favourites';

  Future<int?> rating(int itemId) async => (await (db.select(
    db.ratings,
  )..where((r) => r.itemId.equals(itemId))).getSingleOrNull())?.value;

  /// Sets the rating; 0 or null clears it.
  Future<void> setRating(int itemId, int? value) async {
    if (value == null || value <= 0) {
      await (db.delete(db.ratings)..where((r) => r.itemId.equals(itemId))).go();
      return;
    }
    await db
        .into(db.ratings)
        .insertOnConflictUpdate(
          RatingsCompanion.insert(
            itemId: Value(itemId),
            value: value.clamp(1, 10),
          ),
        );
  }

  Future<bool> isFavourite(int itemId) async =>
      (await tags.tagsOf(itemId))
          .any((t) => t.toLowerCase() == favouriteTag.toLowerCase());

  Future<void> setFavourite(int itemId, {required bool favourite}) => favourite
      ? tags.addTag([itemId], favouriteTag)
      : tags.removeTag([itemId], favouriteTag);
}
