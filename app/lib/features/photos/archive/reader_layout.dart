import 'dart:math' as math;
import 'dart:ui' show Offset, Size;

import 'package:meta/meta.dart';

/// The comic reading mode's layout maths (IMG-017): what shows together,
/// which side it is on, how big it is, and where a tap goes.
enum ReadingDirection { leftToRight, rightToLeft }

/// One page at a time, two pages side by side, or two with the first page
/// (the cover) alone so the spreads line up with the book.
enum PageMode { single, double, doubleCoverAlone }

/// How a page fits the screen: whole, to the width (scroll down), or to the
/// height (scroll sideways when wider).
enum PageFit { page, width, height }

@immutable
final class ReaderSettings {
  const ReaderSettings({
    this.direction = ReadingDirection.leftToRight,
    this.mode = PageMode.single,
    this.fit = PageFit.page,
  });

  final ReadingDirection direction;
  final PageMode mode;
  final PageFit fit;

  ReaderSettings copyWith({
    ReadingDirection? direction,
    PageMode? mode,
    PageFit? fit,
  }) => ReaderSettings(
    direction: direction ?? this.direction,
    mode: mode ?? this.mode,
    fit: fit ?? this.fit,
  );

  @override
  bool operator ==(Object other) =>
      other is ReaderSettings &&
      other.direction == direction &&
      other.mode == mode &&
      other.fit == fit;

  @override
  int get hashCode => Object.hash(direction, mode, fit);
}

/// What is shown at once: page [first] and, in a double spread, [second].
/// Both are indices in reading order.
@immutable
final class Spread {
  const Spread(this.first, [this.second]);

  final int first;
  final int? second;

  bool get isDouble => second != null;

  Iterable<int> get pages sync* {
    yield first;
    if (second != null) yield second!;
  }

  /// The page on the left of the screen and the page on the right, for
  /// [direction]: right to left puts the first page on the right.
  (int?, int?) sides(ReadingDirection direction) {
    final s = second;
    if (s == null) return (first, null);
    return direction == ReadingDirection.leftToRight ? (first, s) : (s, first);
  }

  @override
  bool operator ==(Object other) =>
      other is Spread && other.first == first && other.second == second;

  @override
  int get hashCode => Object.hash(first, second);

  @override
  String toString() => 'Spread($first${second == null ? '' : ', $second'})';
}

/// A page wider than this many times its height is a spread of its own (a
/// double-page picture) and is shown alone.
const double widePageRatio = 1.1;

bool isWidePage(Size? size) =>
    size != null && size.width > size.height * widePageRatio;

/// The spreads of a book of [count] pages. [sizes] holds each page's size
/// when it is known (null for a page not looked at yet, taken as upright).
/// In the double modes a wide page stands alone, and a page that would be
/// left with a wide neighbour is alone too.
List<Spread> buildSpreads(int count, List<Size?> sizes, PageMode mode) {
  if (count <= 0) return const [];
  if (mode == PageMode.single) {
    return [for (var i = 0; i < count; i++) Spread(i)];
  }
  final out = <Spread>[];
  var i = 0;
  if (mode == PageMode.doubleCoverAlone) {
    out.add(const Spread(0));
    i = 1;
  }
  while (i < count) {
    final here = i < sizes.length ? sizes[i] : null;
    if (isWidePage(here) || i + 1 >= count) {
      out.add(Spread(i));
      i++;
      continue;
    }
    final next = i + 1 < sizes.length ? sizes[i + 1] : null;
    if (isWidePage(next)) {
      out.add(Spread(i));
      i++;
      continue;
    }
    out.add(Spread(i, i + 1));
    i += 2;
  }
  return out;
}

/// The index in [spreads] that shows [page], or the nearest one.
int spreadOf(List<Spread> spreads, int page) {
  for (var i = 0; i < spreads.length; i++) {
    if (spreads[i].pages.contains(page)) return i;
  }
  return spreads.isEmpty ? 0 : (page < 0 ? 0 : spreads.length - 1);
}

/// The size a picture of [content] takes in [viewport] with [fit]. For
/// [PageFit.width] and [PageFit.height] it can be larger than the viewport
/// (the reader scrolls).
Size fitted(Size viewport, Size content, PageFit fit) {
  if (content.isEmpty || viewport.isEmpty) return Size.zero;
  final sx = viewport.width / content.width;
  final sy = viewport.height / content.height;
  final scale = switch (fit) {
    PageFit.page => math.min(sx, sy),
    PageFit.width => sx,
    PageFit.height => sy,
  };
  return Size(content.width * scale, content.height * scale);
}

/// The size of the two pages of a spread side by side, as one picture (their
/// heights made equal), for fitting to the viewport.
Size spreadSize(Size left, Size right) {
  if (left.isEmpty || right.isEmpty) return left.isEmpty ? right : left;
  final h = math.max(left.height, right.height);
  return Size(left.width * h / left.height + right.width * h / right.height, h);
}

/// What a tap at `at` in a viewer `width` wide does: the edges turn the page
/// (the left edge goes back in left-to-right reading, forward in right-to-left),
/// the middle third shows or hides the controls.
enum TapAction { previous, next, toggleControls }

TapAction tapAction(Offset at, double width, ReadingDirection direction) {
  if (width <= 0) return TapAction.toggleControls;
  final x = at.dx / width;
  if (x >= 1 / 3 && x <= 2 / 3) return TapAction.toggleControls;
  final left = x < 1 / 3;
  final forward = direction == ReadingDirection.leftToRight ? !left : left;
  return forward ? TapAction.next : TapAction.previous;
}
