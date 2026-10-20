import 'dart:math' as math;
import 'dart:ui';

import 'package:meta/meta.dart';

/// Edge of one map tile in logical pixels at its own zoom level.
const double mapTileSize = 256;

/// The Web Mercator projection stops at this latitude.
const double maxMapLatitude = 85.0511287798;

/// The deepest tile level the tile server serves.
const int maxTileZoom = 19;

/// The deepest zoom the map goes to (tiles are scaled past [maxTileZoom]).
const double maxMapZoom = 20;

/// A position on Earth.
typedef GeoPoint = ({double lat, double lon});

/// Normalised Web Mercator: x and y in 0..1 over the whole world, y growing
/// southwards, as tile coordinates do.
(double, double) mercatorUnit(double lat, double lon) {
  final clamped = lat.clamp(-maxMapLatitude, maxMapLatitude);
  final s = math.sin(clamped * math.pi / 180);
  final x = (lon + 180) / 360;
  final y = 0.5 - math.log((1 + s) / (1 - s)) / (4 * math.pi);
  return (x, y);
}

/// Inverse of [mercatorUnit].
GeoPoint geoFromUnit(double x, double y) {
  final lon = x * 360 - 180;
  final n = math.pi - 2 * math.pi * y;
  final lat = 180 / math.pi * math.atan(0.5 * (math.exp(n) - math.exp(-n)));
  return (lat: lat, lon: lon);
}

/// A tile of the slippy-map grid.
@immutable
final class TileId {
  const TileId(this.z, this.x, this.y);

  final int z;
  final int x;
  final int y;

  @override
  bool operator ==(Object other) =>
      other is TileId && other.z == z && other.x == x && other.y == y;

  @override
  int get hashCode => Object.hash(z, x, y);

  @override
  String toString() => 'TileId($z/$x/$y)';
}

/// A tile to draw and where.
typedef PlacedTile = ({TileId id, Rect rect});

/// What part of the world a map widget shows: centre, zoom and size. All
/// projection between positions and screen points goes through it.
@immutable
final class MapCamera {
  const MapCamera({
    required this.center,
    required this.zoom,
    required this.size,
  });

  /// A camera whose view contains [bounds] with [padding] around, at most
  /// [maxZoom] deep.
  factory MapCamera.fit(
    GeoBounds bounds,
    Size size, {
    double padding = 48,
    double maxZoom = 15,
  }) {
    final (x1, y1) = mercatorUnit(bounds.north, bounds.west);
    final (x2, y2) = mercatorUnit(bounds.south, bounds.east);
    final w = math.max((x2 - x1).abs(), 1e-9);
    final h = math.max((y2 - y1).abs(), 1e-9);
    final availableW = math.max(size.width - 2 * padding, 1);
    final availableH = math.max(size.height - 2 * padding, 1);
    final zoom = math.min(
      math.log(availableW / (w * mapTileSize)) / math.ln2,
      math.log(availableH / (h * mapTileSize)) / math.ln2,
    );
    final c = geoFromUnit((x1 + x2) / 2, (y1 + y2) / 2);
    return MapCamera(
      center: c,
      zoom: zoom.clamp(0.0, maxZoom),
      size: size,
    ).constrained();
  }

  final GeoPoint center;
  final double zoom;
  final Size size;

  /// World size in pixels at the current zoom.
  double get worldPixels => mapTileSize * math.pow(2, zoom);

  /// The smallest zoom at which the world still fills [size].
  double get minZoom {
    final longest = math.max(size.width, size.height);
    return math.max(0, math.log(math.max(longest, 1) / mapTileSize) / math.ln2);
  }

  /// Screen point of a position (may be off screen).
  Offset toScreen(double lat, double lon) {
    final (x, y) = mercatorUnit(lat, lon);
    final (cx, cy) = mercatorUnit(center.lat, center.lon);
    final world = worldPixels;
    var dx = (x - cx) * world;
    // The shortest way round the globe.
    if (dx > world / 2) dx -= world;
    if (dx < -world / 2) dx += world;
    return Offset(size.width / 2 + dx, size.height / 2 + (y - cy) * world);
  }

  /// Position under a screen point.
  GeoPoint toGeo(Offset screen) {
    final (cx, cy) = mercatorUnit(center.lat, center.lon);
    final world = worldPixels;
    var x = cx + (screen.dx - size.width / 2) / world;
    final y = (cy + (screen.dy - size.height / 2) / world).clamp(0.0, 1.0);
    x -= x.floorToDouble();
    return geoFromUnit(x, y);
  }

  MapCamera copyWith({GeoPoint? center, double? zoom, Size? size}) => MapCamera(
    center: center ?? this.center,
    zoom: zoom ?? this.zoom,
    size: size ?? this.size,
  );

  /// Zoom and latitude kept inside what the world can show, longitude
  /// wrapped to -180..180.
  MapCamera constrained() {
    final z = zoom.clamp(minZoom, maxMapZoom);
    final world = mapTileSize * math.pow(2, z);
    final (cx, cy) = mercatorUnit(center.lat, center.lon);
    final halfH = size.height / 2 / world;
    final y = halfH >= 0.5 ? 0.5 : cy.clamp(halfH, 1 - halfH);
    final x = cx - cx.floorToDouble();
    return MapCamera(center: geoFromUnit(x, y), zoom: z, size: size);
  }

  /// Moves the view by [delta] screen pixels (a drag to the right moves the
  /// map right, so the centre moves left).
  MapCamera panned(Offset delta) {
    final (cx, cy) = mercatorUnit(center.lat, center.lon);
    final world = worldPixels;
    return MapCamera(
      center: geoFromUnit(cx - delta.dx / world, cy - delta.dy / world),
      zoom: zoom,
      size: size,
    ).constrained();
  }

  /// Changes the zoom keeping the position under [focal] where it is.
  MapCamera zoomedAt(Offset focal, double newZoom) {
    final z = newZoom.clamp(minZoom, maxMapZoom);
    final before = toGeo(focal);
    final (bx, by) = mercatorUnit(before.lat, before.lon);
    final world = mapTileSize * math.pow(2, z);
    final cx = bx - (focal.dx - size.width / 2) / world;
    final cy = by - (focal.dy - size.height / 2) / world;
    return MapCamera(
      center: geoFromUnit(cx, cy.clamp(0.0, 1.0)),
      zoom: z,
      size: size,
    ).constrained();
  }

  /// The geographic box on screen, [margin] pixels beyond the edges.
  GeoBounds visibleBounds({double margin = 0}) {
    final nw = toGeo(Offset(-margin, -margin));
    final se = toGeo(Offset(size.width + margin, size.height + margin));
    return GeoBounds(north: nw.lat, south: se.lat, west: nw.lon, east: se.lon);
  }

  /// The tiles that cover the screen at the nearest tile level, with the
  /// screen rectangle each one is drawn into (scaled between levels).
  List<PlacedTile> tiles() {
    final level = zoom.round().clamp(0, maxTileZoom);
    final count = 1 << level;
    final scale = math.pow(2, zoom - level).toDouble();
    final px = mapTileSize * scale;
    final (cx, cy) = mercatorUnit(center.lat, center.lon);
    // Tile coordinates (fractional) of the screen's top left corner.
    final left = cx * count - size.width / 2 / px;
    final top = cy * count - size.height / 2 / px;
    final right = left + size.width / px;
    final bottom = top + size.height / px;
    final out = <PlacedTile>[];
    for (var ty = top.floor(); ty <= bottom.floor(); ty++) {
      if (ty < 0 || ty >= count) continue;
      for (var tx = left.floor(); tx <= right.floor(); tx++) {
        out.add((
          id: TileId(
            level,
            tx % count < 0 ? tx % count + count : tx % count,
            ty,
          ),
          rect: Rect.fromLTWH((tx - left) * px, (ty - top) * px, px, px),
        ));
      }
    }
    // Centre first: the tiles the eye is on load first.
    final middle = Offset(size.width / 2, size.height / 2);
    out.sort(
      (a, b) => (a.rect.center - middle).distanceSquared.compareTo(
        (b.rect.center - middle).distanceSquared,
      ),
    );
    return out;
  }

  @override
  bool operator ==(Object other) =>
      other is MapCamera &&
      other.center == center &&
      other.zoom == zoom &&
      other.size == size;

  @override
  int get hashCode => Object.hash(center, zoom, size);
}

/// A box of latitude and longitude; [west] may exceed [east] across the
/// antimeridian only for boxes made by `MapCamera.visibleBounds`.
@immutable
final class GeoBounds {
  const GeoBounds({
    required this.north,
    required this.south,
    required this.west,
    required this.east,
  });

  /// The smallest box around [points] (not across the antimeridian).
  factory GeoBounds.around(Iterable<GeoPoint> points) {
    var n = -90.0;
    var s = 90.0;
    var w = 180.0;
    var e = -180.0;
    for (final p in points) {
      n = math.max(n, p.lat);
      s = math.min(s, p.lat);
      w = math.min(w, p.lon);
      e = math.max(e, p.lon);
    }
    return GeoBounds(north: n, south: s, west: w, east: e);
  }

  final double north;
  final double south;
  final double west;
  final double east;

  bool contains(double lat, double lon) =>
      lat <= north &&
      lat >= south &&
      (west <= east ? lon >= west && lon <= east : lon >= west || lon <= east);
}
