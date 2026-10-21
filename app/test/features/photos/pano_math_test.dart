import 'dart:math' as math;
import 'dart:ui' show Offset, Size;

import 'package:flutter_test/flutter_test.dart';
import 'package:mediahro/features/photos/pano/pano_math.dart';
import 'package:mediahro/images/metadata/pano_meta.dart';
import 'package:mediahro/images/metadata/xmp.dart';

const _viewport = Size(400, 300);

PanoCamera _whole({double aspect = 4 / 3}) =>
    PanoCamera(PanoGeometry.whole, aspect: aspect);

void main() {
  group('IMG-001 GPano metadata', () {
    PanoramaMeta? read(String body) => PanoramaMeta.fromXmp(
      XmpPacket.parse(
        '<x:xmpmeta xmlns:x="adobe:ns:meta/"> '
        '<rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#"> '
        '<rdf:Description xmlns:GPano="http://ns.google.com/photos/1.0/panorama/">'
        '$body</rdf:Description></rdf:RDF></x:xmpmeta>',
      ),
    );

    test('IMG-001 an equirectangular projection can be looked around in', () {
      final m = read(
        '<GPano:ProjectionType>equirectangular</GPano:ProjectionType>',
      );
      expect(m!.isEquirectangular, isTrue);
    });

    test('IMG-001 another projection is not looked around in', () {
      final m = read(
        '<GPano:ProjectionType>cylindrical</GPano:ProjectionType>'
        '<GPano:FullPanoWidthPixels>8000</GPano:FullPanoWidthPixels>'
        '<GPano:FullPanoHeightPixels>4000</GPano:FullPanoHeightPixels>',
      );
      expect(m!.isEquirectangular, isFalse);
    });

    test('IMG-001 without a projection a 2 to 1 sphere counts', () {
      final m = read(
        '<GPano:FullPanoWidthPixels>8000</GPano:FullPanoWidthPixels>'
        '<GPano:FullPanoHeightPixels>4000</GPano:FullPanoHeightPixels>',
      );
      expect(m!.isEquirectangular, isTrue);
      final wide = read(
        '<GPano:FullPanoWidthPixels>9000</GPano:FullPanoWidthPixels>'
        '<GPano:FullPanoHeightPixels>3000</GPano:FullPanoHeightPixels>',
      );
      expect(wide!.isEquirectangular, isFalse);
    });

    test('IMG-001 a photo with no GPano says nothing', () {
      expect(read('<xmp:Rating>3</xmp:Rating>'), isNull);
    });

    test('IMG-001 the crop and the first view are read as numbers', () {
      final m = read(
        '<GPano:ProjectionType>equirectangular</GPano:ProjectionType>'
        '<GPano:FullPanoWidthPixels>8000</GPano:FullPanoWidthPixels>'
        '<GPano:FullPanoHeightPixels>4000</GPano:FullPanoHeightPixels>'
        '<GPano:CroppedAreaImageWidthPixels>4000</GPano:CroppedAreaImageWidthPixels>'
        '<GPano:CroppedAreaImageHeightPixels>1000</GPano:CroppedAreaImageHeightPixels>'
        '<GPano:CroppedAreaLeftPixels>2000</GPano:CroppedAreaLeftPixels>'
        '<GPano:CroppedAreaTopPixels>1500</GPano:CroppedAreaTopPixels>'
        '<GPano:InitialViewHeadingDegrees>120</GPano:InitialViewHeadingDegrees>'
        '<GPano:InitialViewPitchDegrees>-5</GPano:InitialViewPitchDegrees>',
      )!;
      expect(m.croppedLeft, 2000);
      expect(m.croppedTop, 1500);
      expect(m.initialHeading, 120);
      expect(m.initialPitch, -5);
    });
  });

  group('IMG-001 where a picture sits on the sphere', () {
    test('IMG-001 a whole sphere maps 360 by 180 degrees onto 0 to 1', () {
      const g = PanoGeometry.whole;
      expect(g.uv(-math.pi, math.pi / 2), Offset.zero);
      final mid = g.uv(0, 0);
      expect(mid.dx, closeTo(0.5, 1e-9));
      expect(mid.dy, closeTo(0.5, 1e-9));
      expect(g.uv(math.pi / 2, -math.pi / 4).dx, closeTo(0.75, 1e-9));
      expect(g.uv(math.pi / 2, -math.pi / 4).dy, closeTo(0.75, 1e-9));
    });

    test('IMG-001 longitudes beyond a turn wrap round a whole sphere', () {
      const g = PanoGeometry.whole;
      final a = g.uv(0.3, 0.1);
      final b = g.uv(0.3 + 2 * math.pi, 0.1);
      final c = g.uv(0.3 - 4 * math.pi, 0.1);
      expect(b.dx, closeTo(a.dx, 1e-9));
      expect(c.dx, closeTo(a.dx, 1e-9));
    });

    test('IMG-001 a cropped panorama maps only its window', () {
      const meta = PanoramaMeta(
        projection: 'equirectangular',
        fullWidth: 8000,
        fullHeight: 4000,
        croppedWidth: 4000,
        croppedHeight: 1000,
        croppedLeft: 2000,
        croppedTop: 1500,
      );
      final g = PanoGeometry.from(meta);
      expect(g.wrapsAround, isFalse);
      expect(g.lonSpan, closeTo(math.pi, 1e-9));
      expect(g.latSpan, closeTo(math.pi / 4, 1e-9));
      // The window's middle is at -0 degrees longitude (2000 + 2000 of 8000
      // is the centre of the sphere) and on the horizon.
      expect(g.lonCentre, closeTo(0, 1e-9));
      expect(g.latCentre, closeTo(0, 1e-9));
      final corner = g.uv(g.lonMin, g.latMax);
      expect(corner.dx, closeTo(0, 1e-9));
      expect(corner.dy, closeTo(0, 1e-9));
      expect(g.covers(0, 0), isTrue);
      expect(g.covers(2.5, 0), isFalse);
      expect(g.covers(0, 0.6), isFalse);
    });

    test('IMG-001 a window off to one side keeps its own longitude', () {
      const meta = PanoramaMeta(
        fullWidth: 8000,
        fullHeight: 4000,
        croppedWidth: 2000,
        croppedHeight: 2000,
        croppedLeft: 6000,
        croppedTop: 1000,
      );
      final g = PanoGeometry.from(meta);
      // Right quarter of the sphere: 90 to 180 degrees.
      expect(g.lonMin, closeTo(math.pi / 2, 1e-9));
      expect(g.lonMax, closeTo(math.pi, 1e-9));
      // A direction just past the seam is reached as the same place minus a
      // turn, and stays outside the window.
      expect(g.covers(-math.pi + 0.1, 0), isFalse);
      expect(g.covers(math.pi * 0.75, 0), isTrue);
    });

    test('IMG-001 missing numbers mean the whole sphere', () {
      expect(PanoGeometry.from(null), PanoGeometry.whole);
      expect(
        PanoGeometry.from(const PanoramaMeta(projection: 'equirectangular')),
        PanoGeometry.whole,
      );
      expect(
        PanoGeometry.from(const PanoramaMeta(fullWidth: 0, fullHeight: 0)),
        PanoGeometry.whole,
      );
    });
  });

  group('IMG-001 what the camera sees', () {
    test('IMG-001 the middle of the screen is where the camera looks', () {
      final cam = _whole();
      for (final (yaw, pitch) in [
        (0.0, 0.0),
        (1.0, 0.4),
        (-2.5, -0.9),
        (3.0, 1.0),
      ]) {
        final v = PanoView(yaw: yaw, pitch: pitch, fov: 1.2);
        final (lon, lat) = cam.direction(
          Offset(_viewport.width / 2, _viewport.height / 2),
          _viewport,
          v,
        );
        expect(wrapAngle(lon - yaw), closeTo(0, 1e-9));
        expect(lat, closeTo(pitch, 1e-9));
      }
    });

    test('IMG-001 the top of the screen sees fov/2 above the middle', () {
      final cam = _whole();
      final v = PanoView(yaw: 0, pitch: 0, fov: degToRad(80));
      final (_, lat) = cam.direction(const Offset(200, 0), _viewport, v);
      expect(radToDeg(lat), closeTo(40, 1e-6));
      final (lon, lat2) = cam.direction(const Offset(400, 150), _viewport, v);
      // The right edge sees atan(tan(40°) * 4/3) to the right, on the horizon.
      expect(lat2, closeTo(0, 1e-9));
      expect(lon, closeTo(math.atan(math.tan(degToRad(40)) * 4 / 3), 1e-9));
    });

    test('IMG-001 straight lines stay straight: columns are meridians at the horizon only', () {
      // A rectilinear view of a level horizon is a horizontal line.
      final cam = _whole();
      const v = PanoView(yaw: 0.7, pitch: 0, fov: 1);
      for (final x in [0.0, 100.0, 300.0, 400.0]) {
        final (_, lat) = cam.direction(Offset(x, 150), _viewport, v);
        expect(lat, closeTo(0, 1e-9));
      }
    });

    test(
      'IMG-001 looking up, a screen row curves: edges see more longitude',
      () {
        final cam = _whole();
        final v = PanoView(yaw: 0, pitch: degToRad(50), fov: degToRad(60));
        final (lonMid, _) = cam.direction(const Offset(200, 20), _viewport, v);
        final (lonEdge, _) = cam.direction(const Offset(400, 20), _viewport, v);
        expect((lonEdge - lonMid).abs() > 0.3, isTrue);
      },
    );

    test('IMG-001 the texture seam is continuous across a screen', () {
      final cam = _whole();
      // Looking at the seam (longitude 180): u must not jump across the view
      // by more than the view covers.
      const v = PanoView(yaw: math.pi - 0.05, pitch: 0, fov: 1);
      double? last;
      for (var x = 0.0; x <= 400; x += 10) {
        final (lon, _) = cam.direction(Offset(x, 150), _viewport, v);
        if (last != null) expect((lon - last).abs() < 0.2, isTrue);
        last = lon;
      }
    });
  });

  group('IMG-001 keeping the camera inside the picture', () {
    test('IMG-001 a whole sphere lets the camera turn all the way round', () {
      final cam = _whole();
      final v = cam.clamp(const PanoView(yaw: 7, pitch: 0, fov: 1));
      expect(v.yaw, closeTo(7 - 2 * math.pi, 1e-9));
    });

    test('IMG-001 the camera cannot look past the poles', () {
      final cam = _whole();
      final v = cam.clamp(PanoView(yaw: 0, pitch: 3, fov: degToRad(60)));
      expect(v.pitch, closeTo(math.pi / 2 - degToRad(30), 1e-9));
      final w = cam.clamp(PanoView(yaw: 0, pitch: -3, fov: degToRad(60)));
      expect(w.pitch, closeTo(-(math.pi / 2 - degToRad(30)), 1e-9));
    });

    test('IMG-001 the field of view stays between 20 and 100 degrees', () {
      final cam = _whole();
      expect(
        radToDeg(cam.clamp(const PanoView(yaw: 0, pitch: 0, fov: 0.01)).fov),
        closeTo(20, 1e-6),
      );
      expect(
        radToDeg(cam.clamp(const PanoView(yaw: 0, pitch: 0, fov: 3)).fov),
        closeTo(100, 1e-6),
      );
    });

    test('IMG-001 a cropped panorama keeps the screen inside the window', () {
      const meta = PanoramaMeta(
        projection: 'equirectangular',
        fullWidth: 8000,
        fullHeight: 4000,
        croppedWidth: 2000,
        croppedHeight: 800,
        croppedLeft: 3000,
        croppedTop: 1600,
      );
      final g = PanoGeometry.from(meta);
      final cam = PanoCamera(g, aspect: 16 / 9);
      for (final start in [
        const PanoView(yaw: 3, pitch: 1, fov: 1.5),
        const PanoView(yaw: -3, pitch: -1, fov: 0.5),
        const PanoView(yaw: 0, pitch: 0, fov: 1.7),
      ]) {
        final v = cam.clamp(start);
        // The four corners and edge middles of the screen see only picture.
        for (final p in const [
          Offset.zero,
          Offset(400, 0),
          Offset(0, 300),
          Offset(400, 300),
          Offset(200, 0),
          Offset(200, 300),
          Offset(0, 150),
          Offset(400, 150),
        ]) {
          final (lon, lat) = cam.direction(p, _viewport, v);
          final uv = g.uv(lon, lat);
          expect(uv.dx, inInclusiveRange(-0.02, 1.02), reason: '$v $p');
          expect(uv.dy, inInclusiveRange(-0.02, 1.02), reason: '$v $p');
        }
      }
    });

    test(
      'IMG-001 a window narrower than the screen is shown whole, centred',
      () {
        const meta = PanoramaMeta(
          fullWidth: 8000,
          fullHeight: 4000,
          croppedWidth: 400,
          croppedHeight: 4000,
          croppedLeft: 1000,
          croppedTop: 0,
        );
        final g = PanoGeometry.from(meta);
        final cam = PanoCamera(g);
        final v = cam.clamp(const PanoView(yaw: 2, pitch: 0, fov: 1.5));
        // 400 of 8000 is 18 degrees across: the field of view shrinks to fit
        // and the camera sits in the window's middle.
        expect(cam.horizontalFov(v.fov) <= g.lonSpan + 1e-9, isTrue);
        expect(v.yaw, closeTo(g.lonCentre, 1e-9));
      },
    );

    test('IMG-001 the first view follows GPano, else the middle', () {
      final cam = _whole();
      final plain = cam.initial(null);
      expect(plain.yaw, closeTo(0, 1e-9));
      expect(plain.pitch, closeTo(0, 1e-9));
      expect(radToDeg(plain.fov), closeTo(75, 1e-6));
      final set = cam.initial(
        const PanoramaMeta(
          initialHeading: 90,
          initialPitch: 10,
          initialFov: 90,
        ),
      );
      expect(radToDeg(set.yaw), closeTo(-90, 1e-6));
      expect(radToDeg(set.pitch), closeTo(10, 1e-6));
    });
  });

  group('IMG-001 touch', () {
    test(
      'IMG-001 dragging right turns the camera left, the picture follows',
      () {
        final cam = _whole();
        final v = PanoView(yaw: 0, pitch: 0, fov: degToRad(60));
        final right = cam.dragged(v, const Offset(100, 0), 300);
        expect(right.yaw < 0, isTrue);
        final down = cam.dragged(v, const Offset(0, 100), 300);
        expect(down.pitch > 0, isTrue);
        // A drag of the viewport's whole height turns by the field of view.
        final full = cam.dragged(v, const Offset(0, 30), 300);
        expect(radToDeg(full.pitch), closeTo(6, 1e-6));
      },
    );

    test(
      'IMG-001 pinching changes the field of view and stops at the limits',
      () {
        final cam = _whole();
        final v = PanoView(yaw: 0, pitch: 0, fov: degToRad(60));
        expect(radToDeg(cam.zoomed(v, 2).fov), closeTo(30, 1e-6));
        expect(radToDeg(cam.zoomed(v, 100).fov), closeTo(20, 1e-6));
        expect(radToDeg(cam.zoomed(v, 0.01).fov), closeTo(100, 1e-6));
        expect(cam.zoomed(v, 0), v);
      },
    );

    test('IMG-001 coasting slows down and stops', () {
      var s = degToRad(200);
      var steps = 0;
      while (s != 0 && steps < 1000) {
        s = coast(s, 1 / 60);
        steps++;
      }
      expect(s, 0);
      expect(steps > 20 && steps < 400, isTrue);
      expect(coast(degToRad(100), 0.35), closeTo(degToRad(50), 1e-9));
    });
  });

  group("IMG-001 the phone's own motion", () {
    test('IMG-001 the view stays put until the phone moves', () {
      final cam = _whole();
      final f = MotionFollower(smoothing: 1)
        ..start(const PanoView(yaw: 0.5, pitch: 0.1, fov: 1));
      final first = f.update(const PanoAttitude(yaw: 2, pitch: 0.3), cam)!;
      expect(first.yaw, closeTo(0.5, 1e-9));
      expect(first.pitch, closeTo(0.1, 1e-9));
    });

    test('IMG-001 turning the phone turns the camera by as much', () {
      final cam = _whole();
      final f = MotionFollower(smoothing: 1)
        ..start(const PanoView(yaw: 0.5, pitch: 0, fov: 1))
        ..update(const PanoAttitude(yaw: 2, pitch: 0), cam);
      final v = f.update(const PanoAttitude(yaw: 2.4, pitch: 0.2), cam)!;
      expect(v.yaw, closeTo(0.9, 1e-9));
      expect(v.pitch, closeTo(0.2, 1e-9));
    });

    test('IMG-001 the shortest way round is taken across the compass seam', () {
      final cam = _whole();
      final f = MotionFollower(smoothing: 1)
        ..start(const PanoView(yaw: 0, pitch: 0, fov: 1))
        ..update(const PanoAttitude(yaw: 3, pitch: 0), cam);
      final v = f.update(const PanoAttitude(yaw: -3, pitch: 0), cam)!;
      expect(v.yaw, closeTo(2 * math.pi - 6.0, 1e-9));
    });

    test('IMG-001 readings are smoothed', () {
      final cam = _whole();
      final f = MotionFollower()
        ..start(const PanoView(yaw: 0, pitch: 0, fov: 1))
        ..update(const PanoAttitude(yaw: 0, pitch: 0), cam);
      final v = f.update(const PanoAttitude(yaw: 1, pitch: 0), cam)!;
      expect(v.yaw > 0 && v.yaw < 0.5, isTrue);
    });

    test('IMG-001 the camera stays inside a cropped panorama', () {
      const meta = PanoramaMeta(
        fullWidth: 8000,
        fullHeight: 4000,
        croppedWidth: 2000,
        croppedHeight: 1000,
        croppedLeft: 3000,
        croppedTop: 1500,
      );
      final cam = PanoCamera(PanoGeometry.from(meta));
      final f = MotionFollower(smoothing: 1)
        ..start(cam.initial(meta))
        ..update(const PanoAttitude(yaw: 0, pitch: 0), cam);
      final v = f.update(const PanoAttitude(yaw: 2, pitch: 1), cam)!;
      expect(v, cam.clamp(v));
    });

    test("IMG-001 after a drag the phone's present aim is the new zero", () {
      final cam = _whole();
      final f = MotionFollower(smoothing: 1)
        ..start(const PanoView(yaw: 0, pitch: 0, fov: 1))
        ..update(const PanoAttitude(yaw: 1, pitch: 0), cam)
        ..rebase(const PanoView(yaw: 1, pitch: 0, fov: 1));
      final first = f.update(const PanoAttitude(yaw: 1.5, pitch: 0), cam)!;
      expect(first.yaw, closeTo(1, 1e-9));
      final next = f.update(const PanoAttitude(yaw: 1.7, pitch: 0), cam)!;
      expect(next.yaw, closeTo(1.2, 1e-9));
    });

    test('IMG-001 stopped means no view', () {
      final f = MotionFollower()
        ..start(const PanoView(yaw: 0, pitch: 0, fov: 1))
        ..stop();
      expect(f.following, isFalse);
      expect(f.update(const PanoAttitude(yaw: 1, pitch: 0), _whole()), isNull);
    });
  });
}
