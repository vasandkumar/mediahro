import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show FutureProviderFamily;
import 'package:mediahro/core/net/network_policy.dart';
import 'package:mediahro/core/providers.dart';
import 'package:mediahro/core/rules/rule_sql.dart' as rules;
import 'package:mediahro/features/photos/map/clustering.dart';
import 'package:mediahro/features/photos/map/gazetteer.dart';
import 'package:mediahro/features/photos/map/map_tiles.dart';
import 'package:mediahro/features/photos/map/place_resolver.dart';
import 'package:mediahro/features/photos/map/web_mercator.dart' show GeoPoint;
import 'package:mediahro_servers/mediahro_servers.dart';

/// Where the bundled gazetteer lives (declared in `pubspec.yaml`).
const gazetteerAsset = 'assets/gazetteer/places.bin';

/// The offline gazetteer, or null when the build does not carry it (the map
/// still works; photos just get no place names).
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

/// Whether the map-tile switch of the privacy dashboard is on; follows the
/// switch live.
final mapTilesEnabledProvider = StreamProvider<bool>((ref) async* {
  final policy = ref.watch(networkPolicyProvider);
  yield policy.isEnabled(Endpoints.mapTiles);
  await for (final _ in policy.changes) {
    yield policy.isEnabled(Endpoints.mapTiles);
  }
});

/// Map pictures: the disk cache, then (only when the privacy switch is on)
/// the tile server through the network gateway.
final mapTileSourceProvider = Provider<MapTileSource>((ref) {
  final gateway = ref.watch(networkGatewayProvider);
  final policy = ref.watch(networkPolicyProvider);
  final root = ref.watch(appDataDirectoryProvider).path;
  return NetworkMapTileSource(
    directory: Directory('$root${Platform.pathSeparator}maptiles'),
    isEnabled: () => policy.isEnabled(Endpoints.mapTiles),
    fetch: (uri) async {
      final res = await gateway.send(HttpRequestData(method: 'GET', uri: uri));
      return res.statusCode == 200 ? Uint8List.fromList(res.body) : null;
    },
  );
});

/// Photos with a position, for the map.
final geoPhotosProvider = StreamProvider<List<GeoPhoto>>((ref) async* {
  final db = ref.watch(libraryDatabaseProvider);
  final unlocked = ref.watch(visibilityProvider).value ?? false;
  final vis = rules.Visibility(unlocked: unlocked);
  final query = db.customSelect(
    'SELECT i.id, im.latitude AS lat, im.longitude AS lon, '
    'coalesce(i.taken_at, i.mtime) AS t '
    'FROM item i JOIN image_meta im ON im.item_id = i.id '
    "WHERE ${vis.sql} AND i.kind = 'image' "
    'AND im.latitude IS NOT NULL AND im.longitude IS NOT NULL',
    readsFrom: {db.items, db.imageMeta, db.sources},
  );
  var first = true;
  await for (final _ in query.watch().map((_) {})) {
    if (!first) await Future<void>.delayed(const Duration(milliseconds: 600));
    first = false;
    final rows = await query.get();
    yield [
      for (final r in rows)
        if (_valid(r.read<double>('lat'), r.read<double>('lon')))
          GeoPhoto(
            id: r.read<int>('id'),
            lat: r.read<double>('lat'),
            lon: r.read<double>('lon'),
            time: r.read<int>('t') * 1000,
          ),
    ];
  }
});

// A (0, 0) fix is a camera that had no GPS lock, not a photo of the Atlantic.
bool _valid(double lat, double lon) =>
    lat.abs() <= 90 && lon.abs() <= 180 && !(lat == 0 && lon == 0);
