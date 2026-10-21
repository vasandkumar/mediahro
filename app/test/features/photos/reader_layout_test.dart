import 'dart:ui' show Offset, Size;

import 'package:flutter_test/flutter_test.dart';
import 'package:mediahro/features/photos/archive/reader_layout.dart';

const _portrait = Size(600, 900);
const _wide = Size(1800, 900);

void main() {
  group('IMG-017 spreads', () {
    test('IMG-017 one page at a time is one spread per page', () {
      expect(buildSpreads(3, const [null, null, null], PageMode.single), [
        const Spread(0),
        const Spread(1),
        const Spread(2),
      ]);
    });

    test('IMG-017 two pages pair them up and an odd last page is alone', () {
      expect(buildSpreads(5, List.filled(5, _portrait), PageMode.double), [
        const Spread(0, 1),
        const Spread(2, 3),
        const Spread(4),
      ]);
    });

    test('IMG-017 with the cover alone the pairs line up with the book', () {
      expect(
        buildSpreads(5, List.filled(5, _portrait), PageMode.doubleCoverAlone),
        [const Spread(0), const Spread(1, 2), const Spread(3, 4)],
      );
    });

    test('IMG-017 a wide picture stands alone', () {
      final sizes = <Size?>[_portrait, _portrait, _wide, _portrait, _portrait];
      expect(buildSpreads(5, sizes, PageMode.double), [
        const Spread(0, 1),
        const Spread(2),
        const Spread(3, 4),
      ]);
    });

    test('IMG-017 a page next to a wide one is left alone too', () {
      final sizes = <Size?>[_portrait, _wide, _portrait];
      expect(buildSpreads(3, sizes, PageMode.double), [
        const Spread(0),
        const Spread(1),
        const Spread(2),
      ]);
    });

    test('IMG-017 pages not looked at yet count as upright', () {
      expect(buildSpreads(4, const [null, null], PageMode.double), [
        const Spread(0, 1),
        const Spread(2, 3),
      ]);
    });

    test('IMG-017 an empty book has no spreads', () {
      expect(buildSpreads(0, const [], PageMode.double), isEmpty);
    });

    test('IMG-017 the spread that shows a page is found', () {
      final spreads = buildSpreads(
        5,
        List.filled(5, _portrait),
        PageMode.double,
      );
      expect(spreadOf(spreads, 0), 0);
      expect(spreadOf(spreads, 3), 1);
      expect(spreadOf(spreads, 4), 2);
      expect(spreadOf(spreads, 99), 2);
      expect(spreadOf(spreads, -1), 0);
      expect(spreadOf(const [], 3), 0);
    });
  });

  group('IMG-017 left and right', () {
    test('IMG-017 left to right puts the first page on the left', () {
      expect(const Spread(4, 5).sides(ReadingDirection.leftToRight), (4, 5));
    });

    test('IMG-017 right to left puts the first page on the right', () {
      expect(const Spread(4, 5).sides(ReadingDirection.rightToLeft), (5, 4));
    });

    test('IMG-017 a single page has nothing beside it', () {
      expect(const Spread(4).sides(ReadingDirection.rightToLeft), (4, null));
    });
  });

  group('IMG-017 fitting', () {
    const viewport = Size(400, 800);

    test('IMG-017 the whole page fits inside the screen', () {
      final s = fitted(viewport, _portrait, PageFit.page);
      expect(s.width, closeTo(400, 1e-9));
      expect(s.height, closeTo(600, 1e-9));
      final w = fitted(viewport, _wide, PageFit.page);
      expect(w.width, closeTo(400, 1e-9));
      expect(w.height, closeTo(200, 1e-9));
    });

    test('IMG-017 fitting the width can be taller than the screen', () {
      final s = fitted(viewport, const Size(600, 3000), PageFit.width);
      expect(s.width, closeTo(400, 1e-9));
      expect(s.height, closeTo(2000, 1e-9));
    });

    test('IMG-017 fitting the height can be wider than the screen', () {
      final s = fitted(viewport, _wide, PageFit.height);
      expect(s.height, closeTo(800, 1e-9));
      expect(s.width, closeTo(1600, 1e-9));
    });

    test('IMG-017 nothing to fit gives nothing', () {
      expect(fitted(Size.zero, _portrait, PageFit.page), Size.zero);
      expect(fitted(viewport, Size.zero, PageFit.page), Size.zero);
    });

    test('IMG-017 two pages side by side get the same height', () {
      final s = spreadSize(const Size(600, 900), const Size(500, 1000));
      expect(s.height, 1000);
      expect(s.width, closeTo(600 * 1000 / 900 + 500, 1e-9));
    });
  });

  group('IMG-017 taps', () {
    test('IMG-017 the middle shows or hides the controls', () {
      for (final d in ReadingDirection.values) {
        expect(
          tapAction(const Offset(200, 10), 600, d),
          TapAction.toggleControls,
        );
      }
    });

    test('IMG-017 left to right: right edge goes forward, left edge back', () {
      const d = ReadingDirection.leftToRight;
      expect(tapAction(const Offset(550, 0), 600, d), TapAction.next);
      expect(tapAction(const Offset(50, 0), 600, d), TapAction.previous);
    });

    test('IMG-017 right to left: left edge goes forward, right edge back', () {
      const d = ReadingDirection.rightToLeft;
      expect(tapAction(const Offset(50, 0), 600, d), TapAction.next);
      expect(tapAction(const Offset(550, 0), 600, d), TapAction.previous);
    });

    test('IMG-017 no width means only the controls', () {
      expect(
        tapAction(const Offset(1, 1), 0, ReadingDirection.leftToRight),
        TapAction.toggleControls,
      );
    });
  });

  test('IMG-017 settings compare by value', () {
    const a = ReaderSettings(mode: PageMode.double);
    expect(a, const ReaderSettings(mode: PageMode.double));
    expect(a.copyWith(fit: PageFit.width) == a, isFalse);
    expect(a.hashCode, const ReaderSettings(mode: PageMode.double).hashCode);
  });
}
