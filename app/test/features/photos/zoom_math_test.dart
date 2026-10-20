import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:mediahro/features/photos/viewer/zoom_math.dart';

ZoomGeometry geo({
  Size image = const Size(4000, 3000),
  Size viewport = const Size(400, 800),
  double dpr = 2,
  FitMode mode = FitMode.fit,
}) => ZoomGeometry(
  image: image,
  viewport: viewport,
  devicePixelRatio: dpr,
  mode: mode,
);

void main() {
  test('IMG-004 fit shows the whole picture, fill covers the viewport', () {
    final fit = geo();
    expect(fit.fitScale, closeTo(0.1, 1e-9)); // 400 / 4000
    final fill = geo(mode: FitMode.fill);
    expect(fill.fitScale, closeTo(800 / 3000, 1e-9));
  });

  test(
    'IMG-004 the readout is percent of one source pixel per device pixel',
    () {
      final g = geo();
      expect(g.percent(g.initial), 20); // 0.1 × dpr 2 × 100
      expect(g.percent(ZoomState(0.5, g.centreOfImage)), 100);
      expect(g.percent(ZoomState(4, g.centreOfImage)), 800);
    },
  );

  test('IMG-004 zoom is limited to 8 device pixels per source pixel', () {
    final g = geo();
    final z = g.clamp(ZoomState(100, g.centreOfImage));
    expect(z.scale, 4); // 8 / dpr 2
    expect(
      g.clamp(ZoomState(0.0001, g.centreOfImage)).scale,
      closeTo(0.1, 1e-9),
    );
  });

  test('IMG-004 the picture cannot be panned away from the viewport', () {
    final g = geo();
    final z = g.clamp(const ZoomState(1, Offset(-500, 99999)));
    final v = g.visibleRect(z);
    expect(v.left, greaterThanOrEqualTo(-1e-9));
    expect(v.bottom, lessThanOrEqualTo(3000 + 1e-9));
  });

  test('IMG-004 a picture smaller than the viewport stays centred', () {
    final g = geo(image: const Size(100, 100));
    final z = g.clamp(ZoomState(g.fitScale, const Offset(10, 10)));
    expect(z.centre, const Offset(50, 50));
  });

  test('IMG-004 pinch zoom keeps the point under the fingers fixed', () {
    final g = geo();
    var s = g.zoomAt(g.initial, 5, const Offset(300, 400));
    // The source point that was under (300, 200) must still be there.
    final before =
        g.initial.centre +
        (const Offset(300, 400) - const Offset(200, 400)) / g.initial.scale;
    final after =
        s.centre + (const Offset(300, 400) - const Offset(200, 400)) / s.scale;
    expect(after.dx, closeTo(before.dx, 1e-6));
    expect(after.dy, closeTo(before.dy, 1e-6));
    s = g.zoomAt(s, 1 / 5, const Offset(300, 400));
    expect(s.scale, closeTo(g.fitScale, 1e-9));
  });

  test('IMG-004 pan moves the picture with the finger', () {
    final g = geo();
    final zoomed = g.zoomAt(g.initial, 5, const Offset(200, 400));
    final panned = g.pan(zoomed, const Offset(50, 0)); // finger right
    expect(
      panned.centre.dx,
      lessThan(zoomed.centre.dx),
      reason: 'view moves left',
    );
    expect(
      panned.centre.dx,
      closeTo(zoomed.centre.dx - 50 / zoomed.scale, 1e-9),
    );
  });

  test('IMG-004 double tap cycles fit → 1:1 → 4× → fit', () {
    final g = geo();
    const tap = Offset(200, 400);
    var s = g.initial;
    final seen = <int>[g.percent(s)];
    for (var i = 0; i < 3; i++) {
      s = g.nextStop(s, tap);
      seen.add(g.percent(s));
    }
    expect(seen.first, 20);
    expect(seen[1], 100, reason: 'second stop is 1:1');
    expect(seen[2], greaterThan(100));
    expect(seen.last, 20, reason: 'and back to fit');
    expect(g.isAtFit(s), isTrue);
  });

  test('IMG-004 double tap on a small picture zooms in twice then returns', () {
    final g = geo(image: const Size(200, 150), dpr: 1);
    final a = g.nextStop(g.initial, const Offset(200, 400));
    expect(a.scale, closeTo(g.fitScale * 2, 1e-9));
    final b = g.nextStop(a, const Offset(200, 400));
    expect(b.scale, greaterThan(a.scale));
    expect(g.nextStop(b, const Offset(200, 400)), g.initial);
  });

  test('IMG-004 swipes belong to the page view only at fit', () {
    final g = geo();
    expect(g.isAtFit(g.initial), isTrue);
    expect(g.isAtFit(g.zoomAt(g.initial, 3, const Offset(100, 100))), isFalse);
  });
}
