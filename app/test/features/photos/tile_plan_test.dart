import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:mediahro/features/photos/viewer/tile_plan.dart';

void main() {
  test(
    'IMG-004 pyramid level follows the zoom: full resolution at 1:1 and beyond',
    () {
      expect(levelFor(2), 0);
      expect(levelFor(1), 0);
      expect(levelFor(0.75), 0);
      expect(levelFor(0.5), 1);
      expect(levelFor(0.3), 1);
      expect(levelFor(0.125), 3);
      expect(levelFor(0.1), 3);
      expect(levelFor(0.0001), 8, reason: 'capped');
    },
  );

  test('IMG-004 tiles of 512 px cover exactly the visible rectangle', () {
    const image = Size(10000, 8000);
    final tiles = planTiles(
      image: image,
      visible: const Rect.fromLTWH(1000, 1000, 1200, 700),
      level: 0,
    );
    final xs = tiles.map((t) => t.x).toSet();
    final ys = tiles.map((t) => t.y).toSet();
    expect(xs, {1, 2, 3, 4});
    expect(ys, {1, 2, 3});
    expect(tiles, hasLength(12));
  });

  test('IMG-004 coarser levels cover more source pixels per tile', () {
    const image = Size(10000, 8000);
    const view = Rect.fromLTWH(0, 0, 10000, 8000);
    expect(
      planTiles(image: image, visible: view, level: 0),
      hasLength(20 * 16),
    );
    expect(planTiles(image: image, visible: view, level: 3), hasLength(3 * 2));
    final t = const TileKey(3, 2, 1).sourceRect(image);
    expect(t, const Rect.fromLTRB(8192, 4096, 10000, 8000));
  });

  test('IMG-004 tiles nearest the middle of the view come first', () {
    final tiles = planTiles(
      image: const Size(4096, 4096),
      visible: const Rect.fromLTWH(0, 0, 4096, 4096),
      level: 2,
    );
    expect(
      tiles.first,
      anyOf(
        const TileKey(2, 1, 1),
        const TileKey(2, 0, 0),
        const TileKey(2, 1, 0),
        const TileKey(2, 0, 1),
      ),
    );
    expect(tiles, hasLength(4));
  });

  test('IMG-004 a view outside the image needs no tiles', () {
    expect(
      planTiles(
        image: const Size(1000, 1000),
        visible: const Rect.fromLTWH(2000, 2000, 100, 100),
        level: 0,
      ),
      isEmpty,
    );
  });

  test(
    'IMG-004 a tile edge exactly on a boundary does not pull in the next tile',
    () {
      final tiles = planTiles(
        image: const Size(2048, 2048),
        visible: const Rect.fromLTWH(0, 0, 512, 512),
        level: 0,
      );
      expect(tiles, [const TileKey(0, 0, 0)]);
    },
  );

  test(
    'IMG-004 big images get a 2048 px base and tiles, small ones one texture',
    () {
      final small = ViewerPlan.forSize(4000, 3000);
      expect(small.tiled, isFalse);
      expect(small.baseScale, 1);
      final huge = ViewerPlan.forSize(12000, 9000); // 108 MP
      expect(huge.tiled, isTrue);
      expect(huge.baseScale, closeTo(2048 / 12000, 1e-9));
    },
  );
}
