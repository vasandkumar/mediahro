import 'package:drift/drift.dart' show Variable;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show StreamProviderFamily;
import 'package:mediahro/core/providers.dart';
import 'package:mediahro/core/rules/rule_sql.dart' as rules;
import 'package:mediahro/features/photos/map/map_providers.dart';
import 'package:mediahro/features/photos/photos_providers.dart';
import 'package:mediahro/features/photos/timeline/timeline_model.dart';
import 'package:meta/meta.dart';

/// A city (or the nearest large one) with the photos taken there.
@immutable
final class PlaceGroup {
  const PlaceGroup({
    required this.id,
    required this.name,
    required this.country,
    required this.count,
    required this.coverId,
  });

  final int id;
  final String name;

  /// Null for a place without a country.
  final String? country;
  final int count;

  /// The newest photo, shown as the place's picture.
  final int coverId;
}

/// The places of the library, countries A to Z and the busiest city first
/// (IMG-007). Photos indexed before the gazetteer was there are named on the
/// first run.
final photoPlacesProvider = StreamProvider<List<PlaceGroup>>((ref) async* {
  final db = ref.watch(libraryDatabaseProvider);
  final unlocked = ref.watch(visibilityProvider).value ?? false;
  final vis = rules.Visibility(unlocked: unlocked);
  await ref.watch(placeResolverProvider).backfill();
  final query = db.customSelect(
    'SELECT p.id, p.name, p.country, count(*) AS n, '
    'max(coalesce(i.taken_at, i.mtime) * 10000000 + i.id) AS newest '
    'FROM item i JOIN image_meta im ON im.item_id = i.id '
    'JOIN place p ON p.id = im.place_id '
    "WHERE ${vis.sql} AND i.kind = 'image' "
    'GROUP BY p.id',
    readsFrom: {db.items, db.imageMeta, db.places, db.sources},
  );
  await for (final _ in query.watch().map((_) {})) {
    final rows = await query.get();
    final out =
        [
          for (final r in rows)
            PlaceGroup(
              id: r.read<int>('id'),
              name: r.read<String>('name'),
              country: r.readNullable<String>('country'),
              count: r.read<int>('n'),
              coverId: r.read<int>('newest') % 10000000,
            ),
        ]..sort((a, b) {
          final c = (a.country ?? '').compareTo(b.country ?? '');
          return c != 0 ? c : b.count.compareTo(a.count);
        });
    yield out;
  }
});

/// The photos of one place, newest first.
final StreamProviderFamily<List<PhotoEntry>, int> placeEntriesProvider =
    StreamProvider.family<List<PhotoEntry>, int>((ref, placeId) async* {
      final db = ref.watch(libraryDatabaseProvider);
      final entries =
          ref.watch(photoEntriesProvider).value ?? const <PhotoEntry>[];
      final query = db.customSelect(
        'SELECT item_id FROM image_meta WHERE place_id = ?1',
        variables: [Variable.withInt(placeId)],
        readsFrom: {db.imageMeta},
      );
      await for (final _ in query.watch().map((_) {})) {
        final ids = {for (final r in await query.get()) r.read<int>('item_id')};
        yield [
          for (final e in entries)
            if (ids.contains(e.id)) e,
        ];
      }
    });
