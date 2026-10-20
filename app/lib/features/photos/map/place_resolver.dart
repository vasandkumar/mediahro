import 'package:drift/drift.dart';
import 'package:mediahro/core/db/library_database.dart';
import 'package:mediahro/features/photos/map/gazetteer.dart';

/// Gives photos with a position a place (city, country) from the bundled
/// gazetteer, without any network request (IMG-007). Places live in the
/// shared `place` table; `image_meta.place_id` points at them.
final class PlaceResolver {
  PlaceResolver(this.db, this._gazetteer);

  final LibraryDatabase db;
  final Future<Gazetteer?> Function() _gazetteer;
  final Map<(String, String?), int> _ids = {};

  /// The place row for ([lat], [lon]), created on first use; null without a
  /// position, without the gazetteer, or when no city is within 100 km.
  Future<int?> resolve(double? lat, double? lon) async {
    if (lat == null || lon == null) return null;
    final g = await _gazetteer();
    final city = g?.nearest(lat, lon);
    if (city == null) return null;
    return await _placeId(city);
  }

  Future<int> _placeId(GazetteerPlace city) async {
    final key = (city.name, city.country);
    final known = _ids[key];
    if (known != null) return known;
    final existing =
        await (db.select(db.places)
              ..where(
                (p) =>
                    p.name.equals(city.name) & p.country.equals(city.country),
              )
              ..limit(1))
            .getSingleOrNull();
    final id =
        existing?.id ??
        await db
            .into(db.places)
            .insert(
              PlacesCompanion.insert(
                name: city.name,
                country: Value(city.country),
                latitude: Value(city.latitude),
                longitude: Value(city.longitude),
              ),
            );
    return _ids[key] = id;
  }

  /// Names the places of photos that have a position but no place yet
  /// (indexed before this existed, or while the gazetteer was missing).
  /// Returns how many photos got one.
  Future<int> backfill({int batch = 400}) async {
    if (await _gazetteer() == null) return 0;
    var resolved = 0;
    var after = 0;
    while (true) {
      final rows =
          await (db.select(db.imageMeta)
                ..where(
                  (m) =>
                      m.latitude.isNotNull() &
                      m.longitude.isNotNull() &
                      m.placeId.isNull() &
                      m.itemId.isBiggerThanValue(after),
                )
                ..orderBy([(m) => OrderingTerm.asc(m.itemId)])
                ..limit(batch))
              .get();
      if (rows.isEmpty) return resolved;
      final named = <(int, int)>[];
      for (final m in rows) {
        final id = await resolve(m.latitude, m.longitude);
        if (id != null) named.add((m.itemId, id));
      }
      await db.batch((b) {
        for (final (item, place) in named) {
          b.update(
            db.imageMeta,
            ImageMetaCompanion(placeId: Value(place)),
            where: (t) => t.itemId.equals(item),
          );
        }
      });
      resolved += named.length;
      after = rows.last.itemId;
    }
  }
}
