import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:mediahro/features/photos/map/clustering.dart';
import 'package:mediahro/features/photos/map/web_mercator.dart';

const _size = Size(400, 800);

MapCamera _camera(double lat, double lon, double zoom) =>
    MapCamera(center: (lat: lat, lon: lon), zoom: zoom, size: _size);

void main() {
  group('Web Mercator', () {
    test('IMG-007 the world is one unit square', () {
      expect(mercatorUnit(0, 0), (0.5, 0.5));
      expect(mercatorUnit(0, -180).$1, 0);
      expect(mercatorUnit(0, 180).$1, 1);
      expect(mercatorUnit(maxMapLatitude, 0).$2, closeTo(0, 1e-9));
      expect(mercatorUnit(-maxMapLatitude, 0).$2, closeTo(1, 1e-9));
    });

    test('IMG-007 positions survive a round trip', () {
      for (final (lat, lon) in [
        (12.97, 77.59),
        (-33.9, 151.2),
        (64.1, -21.9),
      ]) {
        final (x, y) = mercatorUnit(lat, lon);
        final back = geoFromUnit(x, y);
        expect(back.lat, closeTo(lat, 1e-9));
        expect(back.lon, closeTo(lon, 1e-9));
      }
    });

    test('IMG-007 latitudes beyond the projection are clamped', () {
      expect(mercatorUnit(90, 0).$2, closeTo(0, 1e-9));
      expect(mercatorUnit(-90, 0).$2, closeTo(1, 1e-9));
    });
  });

  group('MapCamera', () {
    test('IMG-007 the centre is the middle of the screen', () {
      final c = _camera(48.85, 2.35, 10);
      final p = c.toScreen(48.85, 2.35);
      expect(p.dx, closeTo(200, 1e-6));
      expect(p.dy, closeTo(400, 1e-6));
      final g = c.toGeo(const Offset(200, 400));
      expect(g.lat, closeTo(48.85, 1e-9));
      expect(g.lon, closeTo(2.35, 1e-9));
    });

    test('IMG-007 north is up and east is right', () {
      final c = _camera(0, 0, 8);
      expect(c.toScreen(1, 0).dy, lessThan(400));
      expect(c.toScreen(0, 1).dx, greaterThan(200));
    });

    test('IMG-007 screen and position convert both ways', () {
      final c = _camera(35.68, 139.65, 12.4);
      final g = c.toGeo(const Offset(90, 610));
      final back = c.toScreen(g.lat, g.lon);
      expect(back.dx, closeTo(90, 1e-6));
      expect(back.dy, closeTo(610, 1e-6));
    });

    test('IMG-007 dragging moves the map with the finger', () {
      final c = _camera(10, 20, 9);
      final spot = c.toScreen(10.1, 20.1);
      final moved = c.panned(const Offset(50, -30));
      final after = moved.toScreen(10.1, 20.1);
      expect(after.dx, closeTo(spot.dx + 50, 1e-6));
      expect(after.dy, closeTo(spot.dy - 30, 1e-6));
    });

    test('IMG-007 zooming keeps the point under the fingers', () {
      final c = _camera(40, -3, 7);
      const focal = Offset(120, 250);
      final before = c.toGeo(focal);
      final z = c.zoomedAt(focal, 9.5);
      expect(z.zoom, 9.5);
      final at = z.toScreen(before.lat, before.lon);
      expect(at.dx, closeTo(focal.dx, 1e-6));
      expect(at.dy, closeTo(focal.dy, 1e-6));
    });

    test('IMG-007 zoom stays between the world and the deepest level', () {
      final c = _camera(0, 0, 5);
      expect(c.zoomedAt(Offset.zero, 99).zoom, maxMapZoom);
      expect(c.zoomedAt(Offset.zero, -3).zoom, closeTo(c.minZoom, 1e-9));
      // 800 px tall: the world (256 px at zoom 0) must cover it.
      expect(c.minZoom, closeTo(math.log(800 / 256) / math.ln2, 1e-9));
    });

    test('IMG-007 the view never leaves the world vertically', () {
      final c = _camera(80, 0, 6).panned(const Offset(0, 5000));
      final top = c.toGeo(Offset.zero);
      expect(top.lat, lessThanOrEqualTo(maxMapLatitude + 1e-6));
      expect(c.toScreen(maxMapLatitude, 0).dy, greaterThanOrEqualTo(-1e-6));
    });

    test('IMG-007 dragging past the antimeridian wraps the longitude', () {
      final c = _camera(0, 179, 4).panned(const Offset(-300, 0));
      expect(c.center.lon, inInclusiveRange(-180, 180));
      expect(c.center.lon, lessThan(0));
      final fiji = c.toScreen(-17, 179);
      final tonga = c.toScreen(-17, -179);
      expect((tonga.dx - fiji.dx).abs(), lessThan(40));
    });

    test('IMG-007 fit shows every corner of the box', () {
      const box = GeoBounds(north: 52, south: 48, west: 2, east: 12);
      final c = MapCamera.fit(box, _size);
      for (final (lat, lon) in [(52.0, 2.0), (48.0, 12.0)]) {
        final p = c.toScreen(lat, lon);
        expect(p.dx, inInclusiveRange(0, _size.width));
        expect(p.dy, inInclusiveRange(0, _size.height));
      }
    });

    test('IMG-007 fit of one spot stops at the depth limit', () {
      const box = GeoBounds(north: 10, south: 10, west: 20, east: 20);
      expect(MapCamera.fit(box, _size).zoom, 15);
    });

    test('IMG-007 visible bounds contain the centre and not the far side', () {
      final c = _camera(10, 20, 8);
      final b = c.visibleBounds();
      expect(b.contains(10, 20), isTrue);
      expect(b.contains(-10, 20), isFalse);
      expect(b.contains(10, 90), isFalse);
    });
  });

  group('tiles', () {
    test('IMG-007 tiles cover the screen without gaps', () {
      final c = _camera(48.85, 2.35, 10.3);
      final tiles = c.tiles();
      expect(tiles, isNotEmpty);
      var minX = double.infinity;
      var minY = double.infinity;
      var maxX = -double.infinity;
      var maxY = -double.infinity;
      for (final t in tiles) {
        minX = math.min(minX, t.rect.left);
        minY = math.min(minY, t.rect.top);
        maxX = math.max(maxX, t.rect.right);
        maxY = math.max(maxY, t.rect.bottom);
        expect(t.id.z, 10);
      }
      final covered = Rect.fromLTRB(minX, minY, maxX, maxY);
      expect(covered.left, lessThanOrEqualTo(0));
      expect(covered.top, lessThanOrEqualTo(0));
      expect(covered.right, greaterThanOrEqualTo(_size.width));
      expect(covered.bottom, greaterThanOrEqualTo(_size.height));
      // Whole tiles only: area equals the number of tiles.
      final area = tiles.fold<double>(
        0,
        (a, t) => a + t.rect.width * t.rect.height,
      );
      expect(area, closeTo(covered.width * covered.height, 1));
    });

    test('IMG-007 the tile under the centre comes first', () {
      final c = _camera(48.85, 2.35, 10);
      final first = c.tiles().first;
      expect(
        first.rect.contains(Offset(_size.width / 2, _size.height / 2)),
        isTrue,
      );
      // Paris is tile 10/518/352.
      expect(first.id, const TileId(10, 518, 352));
    });

    test('IMG-007 tiles scale between levels', () {
      final c = _camera(0, 0, 10.4); // tile level 10, drawn 1.32x
      final t = c.tiles().first;
      expect(t.rect.width, closeTo(256 * math.pow(2, 0.4), 1e-6));
    });

    test('IMG-007 tiles wrap around the world horizontally', () {
      const c = MapCamera(
        center: (lat: 0, lon: 179.9),
        zoom: 3,
        size: Size(800, 800),
      );
      final xs = {for (final t in c.tiles()) t.id.x};
      expect(xs, containsAll([7, 0]));
      expect(xs.every((x) => x >= 0 && x < 8), isTrue);
    });

    test('IMG-007 no tile is asked for above the poles', () {
      final c = _camera(80, 10, 3);
      expect(c.tiles().every((t) => t.id.y >= 0 && t.id.y < 8), isTrue);
    });
  });

  group('clustering', () {
    GeoPhoto photo(int id, double lat, double lon, [int time = 0]) =>
        GeoPhoto(id: id, lat: lat, lon: lon, time: time);

    test(
      'IMG-007 photos on one spot are one cluster with the newest cover',
      () {
        final photos = [
          photo(1, 48.85, 2.35, 10),
          photo(2, 48.85, 2.35, 30),
          photo(3, 48.85, 2.35, 20),
        ];
        final out = clusterPhotos(photos, _camera(48.85, 2.35, 14));
        expect(out, hasLength(1));
        expect(out.single.count, 3);
        expect(out.single.cover.id, 2);
        expect(out.single.coincident, isTrue);
      },
    );

    test('IMG-007 far apart photos stay single', () {
      final photos = [photo(1, 48.85, 2.35), photo(2, 48.95, 2.55)];
      final out = clusterPhotos(photos, _camera(48.9, 2.45, 11));
      expect(out, hasLength(2));
      expect(out.every((c) => c.count == 1), isTrue);
    });

    test('IMG-007 zooming out merges neighbours', () {
      final photos = [photo(1, 48.85, 2.35), photo(2, 48.86, 2.36)];
      expect(clusterPhotos(photos, _camera(48.855, 2.355, 14)), hasLength(2));
      final far = clusterPhotos(photos, _camera(48.85, 2.35, 8));
      expect(far, hasLength(1));
      expect(far.single.coincident, isFalse);
    });

    test('IMG-007 a cluster sits at the centre of its photos', () {
      final photos = [photo(1, 10, 20), photo(2, 10.02, 20.02)];
      final c = clusterPhotos(photos, _camera(10, 20, 6)).single;
      expect(c.lat, closeTo(10.01, 1e-3));
      expect(c.lon, closeTo(20.01, 1e-3));
    });

    test('IMG-007 photos off screen are left out', () {
      final photos = [photo(1, 48.85, 2.35), photo(2, -33.9, 151.2)];
      final out = clusterPhotos(photos, _camera(48.85, 2.35, 8));
      expect(out.expand((c) => c.photos).map((p) => p.id), [1]);
    });

    test('IMG-007 photos just across the antimeridian share the view', () {
      final photos = [photo(1, -17, 179.9), photo(2, -17, -179.9)];
      final out = clusterPhotos(
        photos,
        const MapCamera(center: (lat: -17, lon: 179.95), zoom: 7, size: _size),
      );
      expect(out.fold<int>(0, (a, c) => a + c.count), 2);
    });

    test('IMG-007 large clusters are drawn before single photos', () {
      final photos = [
        photo(1, 10, 20),
        for (var i = 0; i < 5; i++) photo(10 + i, 10.5, 20.5),
      ];
      final out = clusterPhotos(photos, _camera(10.25, 20.25, 9));
      expect(out.first.count, 5);
    });

    test('IMG-007 zoom to split goes deeper but never past the limit', () {
      final photos = [photo(1, 48.85, 2.35), photo(2, 48.86, 2.36)];
      final cam = _camera(48.85, 2.35, 8);
      final cluster = clusterPhotos(photos, cam).single;
      final z = zoomToSplit(cluster, cam);
      expect(z, greaterThan(cam.zoom));
      expect(z, lessThanOrEqualTo(18));
      final same = clusterPhotos([
        photo(1, 1, 1),
        photo(2, 1, 1),
      ], _camera(1, 1, 8));
      expect(zoomToSplit(same.single, cam), cam.zoom);
    });

    test('IMG-007 100 000 photos cluster within a frame', () {
      final rnd = math.Random(7);
      final photos = [
        for (var i = 0; i < 100000; i++)
          photo(i, 40 + rnd.nextDouble() * 20, rnd.nextDouble() * 40),
      ];
      final cam = _camera(50, 20, 5);
      final sw = Stopwatch()..start();
      final out = clusterPhotos(photos, cam);
      sw.stop();
      expect(out.fold<int>(0, (a, c) => a + c.count), greaterThan(1000));
      expect(sw.elapsedMilliseconds, lessThan(150));
    });
  });
}
