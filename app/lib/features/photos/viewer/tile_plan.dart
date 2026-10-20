import 'dart:math' as math;
import 'dart:ui' show Rect, Size;

import 'package:meta/meta.dart';

/// Edge of a pyramid tile in pixels of its own level (IMG-004).
const int tileEdge = 512;

/// One tile of the on-demand pyramid: [level] 0 is full resolution, level k
/// is the image reduced by 2^k; [x] and [y] count tiles of [tileEdge].
@immutable
final class TileKey {
  const TileKey(this.level, this.x, this.y);

  final int level;
  final int x;
  final int y;

  @override
  bool operator ==(Object other) =>
      other is TileKey && other.level == level && other.x == x && other.y == y;

  @override
  int get hashCode => Object.hash(level, x, y);

  @override
  String toString() => 'Tile(L$level $x,$y)';

  /// Source-pixel rectangle the tile covers in an image of [image].
  Rect sourceRect(Size image) {
    final span = (tileEdge << level).toDouble();
    final left = x * span;
    final top = y * span;
    return Rect.fromLTRB(
      left,
      top,
      math.min(left + span, image.width),
      math.min(top + span, image.height),
    );
  }
}

/// Pyramid level whose resolution just meets the screen's: [scale] is
/// screen pixels per source pixel. Level 0 at 1:1 and beyond, level 3 when
/// one screen pixel covers 8–15 source pixels.
int levelFor(double scale, {int maxLevel = 8}) {
  if (scale >= 1 || scale <= 0) return 0;
  return math.min(maxLevel, (-math.log(scale) / math.ln2).floor());
}

/// The tiles of [level] that cover [visible] (source pixels), nearest to the
/// centre of the view first so the middle fills in before the edges.
List<TileKey> planTiles({
  required Size image,
  required Rect visible,
  required int level,
}) {
  final span = (tileEdge << level).toDouble();
  final area = visible.intersect(
    Rect.fromLTWH(0, 0, image.width, image.height),
  );
  if (area.isEmpty) return const [];
  final x0 = (area.left / span).floor();
  final x1 = ((area.right - 1e-6) / span).floor();
  final y0 = (area.top / span).floor();
  final y1 = ((area.bottom - 1e-6) / span).floor();
  final tiles = <TileKey>[
    for (var y = y0; y <= y1; y++)
      for (var x = x0; x <= x1; x++) TileKey(level, x, y),
  ];
  final c = visible.center;
  tiles.sort((a, b) {
    double d(TileKey t) {
      final r = t.sourceRect(image);
      return (r.center - c).distanceSquared;
    }

    return d(a).compareTo(d(b));
  });
  return tiles;
}

/// How the viewer shows an image: a single picture, or a 2048 px base with
/// tiles on top for big ones.
@immutable
final class ViewerPlan {
  const ViewerPlan._(this.baseScale, this.tiled);

  factory ViewerPlan.forSize(int width, int height) {
    if (width * height <= singleTextureLimit) {
      return const ViewerPlan._(1, false);
    }
    return ViewerPlan._(2048 / math.max(width, height), true);
  }

  /// Above 12 MP the full image is not held as one texture.
  static const int singleTextureLimit = 12 * 1000 * 1000;

  /// Decode scale of the base picture (1.0 = full resolution).
  final double baseScale;
  final bool tiled;
}
