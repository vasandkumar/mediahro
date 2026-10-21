import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show FutureProviderFamily;
import 'package:mediahro/core/providers.dart';
import 'package:mediahro/features/photos/map/gazetteer.dart';
import 'package:mediahro/features/photos/map/geo_point.dart';
import 'package:mediahro/features/photos/map/place_resolver.dart';

/// Where the bundled gazetteer lives (declared in `pubspec.yaml`).
const gazetteerAsset = 'assets/gazetteer/places.bin';

/// The offline gazetteer, or null when the build does not carry it (photos then get no place names).
final gazetteerProvider = FutureProvider<Gazetteer?>((ref) async {
  try {
    final data = await rootBundle.load(gazetteerAsset);
    return Gazetteer.parse(
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
    );
  } on Object {
    // No asset in this build, or a damaged one.
    return null;
  }
});

/// The city nearest to a position, for labels (details sheet); null without
/// the gazetteer or near no city.
final FutureProviderFamily<GazetteerPlace?, GeoPoint> nearestPlaceProvider =
    FutureProvider.autoDispose.family<GazetteerPlace?, GeoPoint>((
      ref,
      at,
    ) async {
      final g = await ref.watch(gazetteerProvider.future);
      return g?.nearest(at.lat, at.lon);
    });

final placeResolverProvider = Provider<PlaceResolver>(
  (ref) => PlaceResolver(
    ref.watch(libraryDatabaseProvider),
    () => ref.read(gazetteerProvider.future),
  ),
);
