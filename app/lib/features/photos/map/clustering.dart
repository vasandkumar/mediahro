import 'dart:math' as math;
import 'dart:ui';

import 'package:mediahro/features/photos/map/web_mercator.dart';

/// A geotagged photo on the map.
final class GeoPhoto {
  GeoPhoto({
    required this.id,
    required this.lat,
    required this.lon,
    required this.time,
  }) {
    final (x, y) = mercatorUnit(lat, lon);
    unitX = x;
    unitY = y;
  }

  final int id;
  final double lat;
  final double lon;

  /// Capture time, milliseconds since the epoch.
  final int time;

  /// Position in normalised Web Mercator, computed once so panning a map of
  /// 100 000 photos does no trigonometry.
  late final double unitX;
  late final double unitY;
}

/// Photos that fall in the same screen cell, drawn as one marker.
final class PhotoCluster {
  PhotoCluster(this.photos, this.lat, this.lon, this.cover);

  final List<GeoPhoto> photos;

  /// Centre of the photos.
  final double lat;
  final double lon;

  /// The newest photo, shown as the marker's picture.
  final GeoPhoto cover;

  int get count => photos.length;

  /// Whether every photo is at the same spot (zooming in cannot split them).
  bool get coincident {
    final p = photos.first;
    return photos.every((o) => o.lat == p.lat && o.lon == p.lon);
  }

  GeoBounds get bounds =>
      GeoBounds.around([for (final p in photos) (lat: p.lat, lon: p.lon)]);
}

/// Groups the photos in view into screen cells of [cellPx] pixels at the
/// camera's zoom. Photos further than a cell beyond the screen are skipped.
List<PhotoCluster> clusterPhotos(
  Iterable<GeoPhoto> photos,
  MapCamera camera, {
  double cellPx = 72,
}) {
  final world = camera.worldPixels;
  final (cx, cy) = mercatorUnit(camera.center.lat, camera.center.lon);
  final half = Size(
    camera.size.width / 2 + cellPx,
    camera.size.height / 2 + cellPx,
  );
  final cells = <int, List<GeoPhoto>>{};
  for (final p in photos) {
    var dx = (p.unitX - cx) * world;
    if (dx > world / 2) dx -= world;
    if (dx < -world / 2) dx += world;
    final dy = (p.unitY - cy) * world;
    if (dx.abs() > half.width || dy.abs() > half.height) continue;
    final col = ((dx + half.width) / cellPx).floor();
    final row = ((dy + half.height) / cellPx).floor();
    (cells[col * 100000 + row] ??= []).add(p);
  }
  final out = <PhotoCluster>[];
  for (final group in cells.values) {
    var sx = 0.0;
    var sy = 0.0;
    var cover = group.first;
    for (final p in group) {
      sx += p.unitX;
      sy += p.unitY;
      if (p.time > cover.time) cover = p;
    }
    final c = geoFromUnit(sx / group.length, sy / group.length);
    out.add(PhotoCluster(group, c.lat, c.lon, cover));
  }
  // Large clusters underneath, single photos on top where they overlap.
  out.sort((a, b) => b.count.compareTo(a.count));
  return out;
}

/// The zoom to open a cluster at: far enough in to split it, never past
/// [maxZoom].
double zoomToSplit(
  PhotoCluster cluster,
  MapCamera camera, {
  double maxZoom = 18,
}) {
  if (cluster.coincident) return camera.zoom;
  final fit = MapCamera.fit(
    cluster.bounds,
    camera.size,
    padding: 64,
    maxZoom: maxZoom,
  );
  return math.max(fit.zoom, camera.zoom + 1).clamp(0, maxZoom);
}
