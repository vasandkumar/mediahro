import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:mediahro/features/photos/edit/edit_geometry.dart';
import 'package:mediahro/images/edit/edit_recipe.dart';

double pixelRatio(NormRect r, double imageAspect) =>
    r.width * imageAspect / r.height;

void main() {
  group('IMG-009 crop handles', () {
    const box = Rect.fromLTWH(100, 100, 200, 120);

    test('IMG-009 corners, edges and the inside are told apart', () {
      expect(hitCropHandle(box, const Offset(102, 98)), CropHandle.topLeft);
      expect(hitCropHandle(box, const Offset(298, 101)), CropHandle.topRight);
      expect(hitCropHandle(box, const Offset(101, 219)), CropHandle.bottomLeft);
      expect(
        hitCropHandle(box, const Offset(299, 221)),
        CropHandle.bottomRight,
      );
      expect(hitCropHandle(box, const Offset(200, 99)), CropHandle.top);
      expect(hitCropHandle(box, const Offset(200, 222)), CropHandle.bottom);
      expect(hitCropHandle(box, const Offset(99, 160)), CropHandle.left);
      expect(hitCropHandle(box, const Offset(301, 160)), CropHandle.right);
      expect(hitCropHandle(box, const Offset(200, 160)), CropHandle.move);
      expect(hitCropHandle(box, const Offset(10, 10)), isNull);
    });
  });

  group('IMG-009 dragging the crop', () {
    const start = NormRect(0.2, 0.2, 0.5, 0.5);

    test('IMG-009 a free edge moves alone', () {
      final r = dragCrop(
        start,
        CropHandle.right,
        const Offset(0.1, 0.3),
        imageAspect: 1.5,
      );
      expect(r.left, 0.2);
      expect(r.right, closeTo(0.8, 1e-9));
      expect(r.top, 0.2);
      expect(r.bottom, 0.7);
    });

    test('IMG-009 a side cannot cross the other or leave the picture', () {
      final r = dragCrop(
        start,
        CropHandle.left,
        const Offset(5, 0),
        imageAspect: 1.5,
      );
      expect(r.width, closeTo(0.05, 1e-9));
      final out = dragCrop(
        start,
        CropHandle.bottomRight,
        const Offset(5, 5),
        imageAspect: 1.5,
      );
      expect(out.right, 1);
      expect(out.bottom, 1);
    });

    test('IMG-009 moving keeps the size and stays inside', () {
      final r = dragCrop(
        start,
        CropHandle.move,
        const Offset(0.9, -0.9),
        imageAspect: 1.5,
      );
      expect(r.width, 0.5);
      expect(r.height, 0.5);
      expect(r.right, 1);
      expect(r.top, 0);
    });

    for (final ratio in [1.0, 4 / 3, 16 / 9, 3 / 4, 2 / 3]) {
      test('IMG-009 a corner drag holds ${ratio.toStringAsFixed(2)}', () {
        const aspect = 1.5;
        final base = fitCropRatio(start, ratio, aspect);
        for (final h in [
          CropHandle.topLeft,
          CropHandle.topRight,
          CropHandle.bottomLeft,
          CropHandle.bottomRight,
        ]) {
          final r = dragCrop(
            base,
            h,
            const Offset(-0.07, 0.05),
            ratio: ratio,
            imageAspect: aspect,
          );
          expect(pixelRatio(r, aspect), closeTo(ratio, 0.01), reason: '$h');
          expect(r.left, greaterThanOrEqualTo(-1e-9), reason: '$h');
          expect(r.top, greaterThanOrEqualTo(-1e-9), reason: '$h');
          expect(r.right, lessThanOrEqualTo(1 + 1e-9), reason: '$h');
          expect(r.bottom, lessThanOrEqualTo(1 + 1e-9), reason: '$h');
        }
      });
    }

    test('IMG-009 an edge drag with a ratio resizes both ways', () {
      const aspect = 1.5;
      final base = fitCropRatio(start, 1, aspect);
      final narrower = dragCrop(
        base,
        CropHandle.right,
        const Offset(-0.1, 0),
        ratio: 1,
        imageAspect: aspect,
      );
      expect(pixelRatio(narrower, aspect), closeTo(1, 0.01));
      expect(narrower.width, lessThan(base.width));
      final shorter = dragCrop(
        base,
        CropHandle.bottom,
        const Offset(0, -0.1),
        ratio: 1,
        imageAspect: aspect,
      );
      expect(pixelRatio(shorter, aspect), closeTo(1, 0.01));
      expect(shorter.height, lessThan(base.height));
    });

    test('IMG-009 a corner pulled against the edge stops there', () {
      const aspect = 1.5;
      final base = fitCropRatio(start, 16 / 9, aspect);
      final r = dragCrop(
        base,
        CropHandle.bottomRight,
        const Offset(0.9, 0.9),
        ratio: 16 / 9,
        imageAspect: aspect,
      );
      expect(r.right, lessThanOrEqualTo(1 + 1e-9));
      expect(r.bottom, lessThanOrEqualTo(1 + 1e-9));
      expect(pixelRatio(r, aspect), closeTo(16 / 9, 0.01));
    });
  });

  group('IMG-009 choosing a ratio', () {
    test('IMG-009 the new box fits the picture and holds the ratio', () {
      for (final aspect in [1.5, 0.75, 1.0]) {
        for (final ratio in [1.0, 16 / 9, 9 / 16, 4 / 3]) {
          final r = fitCropRatio(NormRect.full, ratio, aspect);
          expect(pixelRatio(r, aspect), closeTo(ratio, 0.01));
          expect(r.left, greaterThanOrEqualTo(-1e-9));
          expect(r.right, lessThanOrEqualTo(1 + 1e-9));
          expect(r.top, greaterThanOrEqualTo(-1e-9));
          expect(r.bottom, lessThanOrEqualTo(1 + 1e-9));
        }
      }
    });

    test('IMG-009 the new box stays about where the old one was', () {
      const old = NormRect(0.05, 0.05, 0.3, 0.3);
      final r = fitCropRatio(old, 1, 1.5);
      expect((r.left + r.right) / 2, closeTo(0.2, 0.15));
      expect(r.width * r.height, greaterThan(0.05));
    });
  });

  group('IMG-009 drawing shapes', () {
    test('IMG-009 an arrow has a shaft and two equal wings', () {
      final pts = arrowPoints((0.1, 0.5), (0.7, 0.5), aspect: 1.5);
      expect(pts.first, (0.1, 0.5));
      expect(pts[1], (0.7, 0.5));
      expect(pts, hasLength(5));
      // Wings are the same length in the square space the head is drawn in.
      double len((double, double) p) {
        final dx = (p.$1 - 0.7) * 1.5;
        final dy = p.$2 - 0.5;
        return math.sqrt(dx * dx + dy * dy);
      }

      expect(len(pts[2]), closeTo(len(pts[4]), 1e-9));
      expect(len(pts[2]), closeTo(0.04, 1e-9));
      // They trail behind the tip, on both sides of the shaft.
      expect(pts[2].$1, lessThan(0.7));
      expect(pts[2].$2, isNot(closeTo(pts[4].$2, 1e-6)));
    });

    test('IMG-009 a tiny arrow is one point, not a mess', () {
      expect(arrowPoints((0.5, 0.5), (0.5, 0.5), aspect: 1), [(0.5, 0.5)]);
    });

    test('IMG-009 a box outline closes on itself', () {
      final pts = boxPoints((0.1, 0.2), (0.6, 0.7));
      expect(pts.first, pts.last);
      expect(pts, hasLength(5));
      expect(pts[2], (0.6, 0.7));
    });

    test('IMG-009 a rectangle between two corners is ordered', () {
      final r = rectBetween((0.8, 0.9), (0.2, 0.3));
      expect(r.left, 0.2);
      expect(r.top, 0.3);
      expect(r.width, closeTo(0.6, 1e-9));
      expect(r.height, closeTo(0.6, 1e-9));
    });
  });
}
