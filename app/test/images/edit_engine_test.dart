import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mediahro/images/edit/edit_engine.dart';
import 'package:mediahro/images/edit/edit_recipe.dart';
import 'package:mediahro/images/image_pipeline.dart';
import 'package:mediahro/images/pipeline/pixel_codec.dart';

PixelFrame solid(int w, int h, int r, int g, int b, [int a = 255]) {
  final p = Uint8List(w * h * 4);
  for (var i = 0; i < w * h; i++) {
    p[i * 4] = r;
    p[i * 4 + 1] = g;
    p[i * 4 + 2] = b;
    p[i * 4 + 3] = a;
  }
  return PixelFrame(width: w, height: h, rgba: p);
}

/// Pixel (x, y) is (x, y, 7, 255), so every move is visible.
PixelFrame coordinates(int w, int h) {
  final p = Uint8List(w * h * 4);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final o = (y * w + x) * 4;
      p[o] = x;
      p[o + 1] = y;
      p[o + 2] = 7;
      p[o + 3] = 255;
    }
  }
  return PixelFrame(width: w, height: h, rgba: p);
}

List<int> px(PixelFrame f, int x, int y) {
  final o = (y * f.width + x) * 4;
  return [f.rgba[o], f.rgba[o + 1], f.rgba[o + 2], f.rgba[o + 3]];
}

EditRecipe adjust(AdjustKind k, double v) => EditRecipe.none.withAdjust(k, v);

void main() {
  group('IMG-009 recipe', () {
    test('IMG-009 an empty recipe is the identity', () {
      expect(EditRecipe.none.isIdentity, isTrue);
      expect(const EditRecipe(turns: 4).isIdentity, isTrue);
      expect(adjust(AdjustKind.exposure, 0.3).isIdentity, isFalse);
      expect(adjust(AdjustKind.exposure, 0.0001).isIdentity, isTrue);
    });

    test('IMG-009 setting an adjustment to zero removes it', () {
      final r = adjust(AdjustKind.contrast, 0.4);
      expect(r.amount(AdjustKind.contrast), 0.4);
      expect(r.withAdjust(AdjustKind.contrast, 0).adjust, isEmpty);
      expect(
        r.withAdjust(AdjustKind.contrast, 9).amount(AdjustKind.contrast),
        1,
      );
    });

    test('IMG-009 a recipe survives JSON', () {
      const r = EditRecipe(
        flipHorizontal: true,
        turns: 3,
        straighten: -4.5,
        crop: NormRect(0.1, 0.2, 0.5, 0.6),
        adjust: {AdjustKind.exposure: 0.25, AdjustKind.vignette: -0.5},
        curves: CurveSet(
          master: [(0, 0), (0.5, 0.7), (1, 1)],
          blue: [(0, 0.1), (1, 0.9)],
        ),
        blurs: [BlurSpec(NormRect(0.1, 0.1, 0.2, 0.2), radius: 0.05)],
        strokes: [
          StrokeSpec(
            [(0.1, 0.1), (0.9, 0.9)],
            colorArgb: 0xFFFF0000,
            width: 0.02,
          ),
        ],
      );
      final back = EditRecipe.fromJson(jsonDecode(jsonEncode(r.toJson())));
      expect(back.flipHorizontal, isTrue);
      expect(back.flipVertical, isFalse);
      expect(back.turns, 3);
      expect(back.straighten, -4.5);
      expect(back.crop, r.crop);
      expect(back.adjust, r.adjust);
      expect(back.curves.master, r.curves.master);
      expect(back.curves.blue, r.curves.blue);
      expect(back.blurs.single.rect, r.blurs.single.rect);
      expect(back.blurs.single.radius, 0.05);
      expect(back.strokes.single.points, r.strokes.single.points);
      expect(back.strokes.single.colorArgb, 0xFFFF0000);
    });

    test('IMG-009 damaged saved data is dropped, not fatal', () {
      expect(EditRecipe.fromJson('nope').isIdentity, isTrue);
      expect(EditRecipe.fromJson(null).isIdentity, isTrue);
      final r = EditRecipe.fromJson(const {
        'turns': 'x',
        'straighten': 99,
        'crop': {'l': 'a'},
        'adjust': {'exposure': 'big', 'contrast': 7},
        'curves': 3,
        'blurs': [
          1,
          {'r': 2},
        ],
        'strokes': [
          {'p': <Object>[], 'c': 1, 'w': 1},
          {
            'p': [
              [0, 0],
              'x',
              [1],
            ],
            'c': 0xFF000000,
            'w': 0.1,
          },
        ],
      });
      expect(r.turns, 0);
      expect(r.straighten, 45);
      expect(r.crop.isFull, isTrue);
      expect(r.amount(AdjustKind.exposure), 0);
      expect(r.amount(AdjustKind.contrast), 1);
      expect(r.blurs, isEmpty);
      expect(r.strokes.single.points, [(0.0, 0.0)]);
    });

    test('IMG-009 the look keeps adjustments and curves only', () {
      const r = EditRecipe(
        turns: 1,
        straighten: 3,
        crop: NormRect(0, 0, 0.5, 0.5),
        adjust: {AdjustKind.saturation: 0.2},
        curves: CurveSet(master: [(0, 0), (0.5, 0.6), (1, 1)]),
        blurs: [BlurSpec(NormRect(0, 0, 0.1, 0.1))],
      );
      final look = r.look();
      expect(look.hasGeometry, isFalse);
      expect(look.hasAnnotations, isFalse);
      expect(look.amount(AdjustKind.saturation), 0.2);
      expect(look.curves.isIdentity, isFalse);
    });

    test('IMG-009 edit operations convert to a recipe', () {
      final r = EditRecipe.fromOps(
        const [
          CropOp(ImageRegion(100, 50, 400, 200)),
          RotateOp(95),
          FlipOp(horizontal: true),
          AdjustOp(AdjustKind.exposure, 0.5),
          CurvesOp([(0, 0), (1, 1)]),
          BlurRegionOp(ImageRegion(0, 0, 100, 100), radius: 20),
          StrokeOp(
            [(0.1, 0.1), (0.2, 0.2)],
            colorArgb: 0xFF00FF00,
            width: 0.01,
          ),
        ],
        1000,
        500,
      );
      expect(r.crop, const NormRect(0.1, 0.1, 0.4, 0.4));
      expect(r.turns, 1);
      expect(r.straighten, 5);
      expect(r.flipHorizontal, isTrue);
      expect(r.amount(AdjustKind.exposure), 0.5);
      expect(r.blurs.single.radius, closeTo(20 / 500, 1e-9));
      expect(r.strokes, hasLength(1));
    });

    test('IMG-009 a crop is kept inside the picture', () {
      final c = const NormRect(0.9, 0.9, 0.5, 0.5).clamped();
      expect(c.right, lessThanOrEqualTo(1));
      expect(c.bottom, lessThanOrEqualTo(1));
      expect(const NormRect(0, 0, 0, 0).clamped().width, 0.02);
    });
  });

  group('IMG-009 geometry', () {
    test('IMG-009 the identity returns the very same frame', () {
      final f = solid(4, 4, 1, 2, 3);
      expect(identical(applyRecipe(f, EditRecipe.none), f), isTrue);
    });

    test('IMG-009 flips mirror the picture', () {
      final f = coordinates(5, 3);
      final h = applyRecipe(f, const EditRecipe(flipHorizontal: true));
      expect(px(h, 0, 0).sublist(0, 2), [4, 0]);
      final v = applyRecipe(f, const EditRecipe(flipVertical: true));
      expect(px(v, 0, 0).sublist(0, 2), [0, 2]);
      final both = applyRecipe(
        f,
        const EditRecipe(flipHorizontal: true, flipVertical: true),
      );
      expect(px(both, 0, 0).sublist(0, 2), [4, 2]);
    });

    test('IMG-009 quarter turns go clockwise', () {
      final f = coordinates(4, 2);
      final once = applyRecipe(f, const EditRecipe(turns: 1));
      expect((once.width, once.height), (2, 4));
      // The old top-left corner is now top-right.
      expect(px(once, 1, 0).sublist(0, 2), [0, 0]);
      // The old bottom-left corner is now top-left.
      expect(px(once, 0, 0).sublist(0, 2), [0, 1]);
      final twice = applyRecipe(f, const EditRecipe(turns: 2));
      expect((twice.width, twice.height), (4, 2));
      expect(px(twice, 0, 0).sublist(0, 2), [3, 1]);
      final thrice = applyRecipe(f, const EditRecipe(turns: 3));
      expect(px(thrice, 0, 0).sublist(0, 2), [3, 0]);
    });

    test('IMG-009 a crop cuts the right pixels', () {
      final f = coordinates(10, 8);
      final c = applyRecipe(
        f,
        const EditRecipe(crop: NormRect(0.2, 0.25, 0.5, 0.5)),
      );
      expect((c.width, c.height), (5, 4));
      expect(px(c, 0, 0).sublist(0, 2), [2, 2]);
      expect(px(c, 4, 3).sublist(0, 2), [6, 5]);
    });

    test('IMG-009 straightening keeps the aspect and loses no corners', () {
      final f = solid(200, 100, 40, 90, 200);
      final r = applyRecipe(f, const EditRecipe(straighten: 10));
      expect(r.width / r.height, closeTo(2, 0.05));
      expect(r.width, lessThan(200));
      for (final p in [
        [0, 0],
        [r.width - 1, 0],
        [0, r.height - 1],
        [r.width - 1, r.height - 1],
      ]) {
        expect(px(r, p[0], p[1]), [40, 90, 200, 255], reason: '$p');
      }
    });

    test('IMG-009 a forty-five degree turn of a square shrinks it to 71 %', () {
      final r = applyRecipe(
        solid(100, 100, 1, 1, 1),
        const EditRecipe(straighten: 45),
      );
      expect(r.width, 71);
      expect(r.height, 71);
    });

    test('IMG-009 straightening turns clockwise around the centre', () {
      // A bright horizontal bar along the top; rotating by +20 degrees
      // clockwise tilts its right end downwards.
      const w = 200;
      const h = 100;
      final p = Uint8List(w * h * 4);
      for (var y = 0; y < h; y++) {
        for (var x = 0; x < w; x++) {
          final o = (y * w + x) * 4;
          final v = (y - 50).abs() < 4 ? 255 : 0;
          p[o] = v;
          p[o + 1] = v;
          p[o + 2] = v;
          p[o + 3] = 255;
        }
      }
      final r = applyRecipe(
        PixelFrame(width: w, height: h, rgba: p),
        const EditRecipe(straighten: 10),
      );
      int barRow(int x) {
        var best = 0;
        var row = 0;
        for (var y = 0; y < r.height; y++) {
          final v = px(r, x, y)[0];
          if (v > best) {
            best = v;
            row = y;
          }
        }
        return row;
      }

      // Rotating clockwise moves the left end up and the right end down.
      expect(barRow(r.width - 5), greaterThan(barRow(5)));
    });

    test('IMG-009 straighten and crop together give the cropped size', () {
      const recipe = EditRecipe(
        straighten: -7,
        crop: NormRect(0.1, 0.1, 0.5, 0.4),
      );
      final r = applyRecipe(solid(300, 200, 9, 9, 9), recipe);
      final size = outputSize(300, 200, recipe);
      expect((r.width, r.height), (size.width, size.height));
    });

    test('IMG-009 output size follows turns, straightening and crop', () {
      expect(outputSize(400, 300, const EditRecipe(turns: 1)), (
        width: 300,
        height: 400,
      ));
      expect(
        outputSize(400, 300, const EditRecipe(crop: NormRect(0, 0, 0.5, 0.5))),
        (width: 200, height: 150),
      );
      expect(outputSize(400, 300, EditRecipe.none), (width: 400, height: 300));
    });

    test('IMG-009 the source frame is left alone', () {
      final f = coordinates(6, 6);
      final before = Uint8List.fromList(f.rgba);
      applyRecipe(
        f,
        const EditRecipe(
          flipHorizontal: true,
          turns: 1,
          adjust: {
            AdjustKind.exposure: 0.5,
            AdjustKind.sharpen: 0.5,
            AdjustKind.vignette: 0.5,
          },
          blurs: [BlurSpec(NormRect(0, 0, 0.5, 0.5))],
          strokes: [
            StrokeSpec([(0, 0), (1, 1)], colorArgb: 0xFFFF0000),
          ],
        ),
      );
      expect(f.rgba, before);
    });
  });

  group('IMG-009 light and colour', () {
    final grey = solid(4, 4, 128, 128, 128);

    int mid(PixelFrame f) => f.rgba[0];

    test('IMG-009 exposure brightens and darkens', () {
      expect(
        mid(applyRecipe(grey, adjust(AdjustKind.exposure, 0.5))),
        greaterThan(150),
      );
      expect(
        mid(applyRecipe(grey, adjust(AdjustKind.exposure, -0.5))),
        lessThan(100),
      );
    });

    test('IMG-009 exposure is measured in stops of linear light', () {
      // +0.5 is one stop: sRGB 128 doubles in linear light, about 176.
      final up = mid(applyRecipe(grey, adjust(AdjustKind.exposure, 0.5)));
      expect(up, closeTo(176, 3));
    });

    test('IMG-009 contrast spreads tones around the middle', () {
      final f = PixelFrame(
        width: 2,
        height: 1,
        rgba: Uint8List.fromList([100, 100, 100, 255, 160, 160, 160, 255]),
      );
      final out = applyRecipe(f, adjust(AdjustKind.contrast, 0.5));
      expect(out.rgba[0], lessThan(100));
      expect(out.rgba[4], greaterThan(160));
      final flat = applyRecipe(f, adjust(AdjustKind.contrast, -0.5));
      expect(flat.rgba[4] - flat.rgba[0], lessThan(60));
    });

    test('IMG-009 whites lift the top, blacks lift the bottom', () {
      final bright = solid(2, 2, 230, 230, 230);
      expect(
        mid(applyRecipe(bright, adjust(AdjustKind.whites, 0.8))),
        greaterThan(240),
      );
      final dark = solid(2, 2, 10, 10, 10);
      expect(
        mid(applyRecipe(dark, adjust(AdjustKind.blacks, 0.8))),
        greaterThan(20),
      );
      expect(
        mid(applyRecipe(dark, adjust(AdjustKind.blacks, -0.8))),
        lessThan(5),
      );
    });

    test('IMG-009 shadows lift dark areas far more than light ones', () {
      final dark = solid(2, 2, 40, 40, 40);
      final light = solid(2, 2, 220, 220, 220);
      final r = adjust(AdjustKind.shadows, 1);
      final liftDark = mid(applyRecipe(dark, r)) - 40;
      final liftLight = mid(applyRecipe(light, r)) - 220;
      expect(liftDark, greaterThan(40));
      expect(liftDark, greaterThan(liftLight * 4));
    });

    test('IMG-009 negative highlights pull bright areas down', () {
      final light = solid(2, 2, 230, 230, 230);
      final dark = solid(2, 2, 40, 40, 40);
      final r = adjust(AdjustKind.highlights, -1);
      expect(mid(applyRecipe(light, r)), lessThan(200));
      expect(mid(applyRecipe(dark, r)), closeTo(40, 6));
    });

    test('IMG-009 warm temperature adds red and takes blue away', () {
      final out = applyRecipe(grey, adjust(AdjustKind.temperature, 0.6));
      expect(out.rgba[0], greaterThan(128));
      expect(out.rgba[2], lessThan(128));
      final cool = applyRecipe(grey, adjust(AdjustKind.temperature, -0.6));
      expect(cool.rgba[0], lessThan(128));
      expect(cool.rgba[2], greaterThan(128));
    });

    test('IMG-009 tint moves between green and magenta', () {
      final magenta = applyRecipe(grey, adjust(AdjustKind.tint, 0.6));
      expect(magenta.rgba[1], lessThan(128));
      final green = applyRecipe(grey, adjust(AdjustKind.tint, -0.6));
      expect(green.rgba[1], greaterThan(128));
    });

    test('IMG-009 no saturation is grey, more saturation is more colour', () {
      final colour = solid(2, 2, 200, 100, 50);
      final none = applyRecipe(colour, adjust(AdjustKind.saturation, -1));
      expect(none.rgba[0], none.rgba[1]);
      expect(none.rgba[1], none.rgba[2]);
      final more = applyRecipe(colour, adjust(AdjustKind.saturation, 0.5));
      expect(more.rgba[0] - more.rgba[2], greaterThan(150));
    });

    test('IMG-009 vibrance lifts muted colours more than vivid ones', () {
      final muted = solid(2, 2, 140, 120, 110);
      final vivid = solid(2, 2, 250, 20, 20);
      final r = adjust(AdjustKind.vibrance, 0.8);
      final dm =
          (applyRecipe(muted, r).rgba[0] - applyRecipe(muted, r).rgba[2]) -
          (140 - 110);
      final dv =
          (applyRecipe(vivid, r).rgba[0] - applyRecipe(vivid, r).rgba[2]) -
          (250 - 20);
      expect(dm, greaterThan(10));
      expect(dm / (140 - 110), greaterThan(dv / (250 - 20)));
    });

    test('IMG-009 alpha is never touched by light and colour', () {
      final f = solid(2, 2, 100, 100, 100, 77);
      final out = applyRecipe(
        f,
        const EditRecipe(
          adjust: {AdjustKind.exposure: 0.4, AdjustKind.saturation: 0.3},
          curves: CurveSet(master: [(0, 0.1), (1, 0.9)]),
        ),
      );
      expect(out.rgba[3], 77);
    });
  });

  group('IMG-009 curves', () {
    test('IMG-009 an inverted curve inverts the picture', () {
      final out = applyRecipe(
        solid(2, 2, 30, 128, 250),
        const EditRecipe(curves: CurveSet(master: [(0, 1), (1, 0)])),
      );
      expect(out.rgba[0], closeTo(225, 2));
      expect(out.rgba[1], closeTo(127, 2));
      expect(out.rgba[2], closeTo(5, 2));
    });

    test('IMG-009 a point above the line lifts the middle', () {
      final t = curveTable(const [(0, 0), (0.5, 0.8), (1, 1)]);
      expect(t[128], closeTo(0.8, 0.02));
      expect(t[0], 0);
      expect(t[255], 1);
    });

    test('IMG-009 curves never overshoot or run backwards', () {
      final t = curveTable(const [(0, 0), (0.2, 0.6), (0.4, 0.62), (1, 1)]);
      for (var i = 1; i < 256; i++) {
        expect(t[i], greaterThanOrEqualTo(t[i - 1] - 1e-9));
        expect(t[i], inInclusiveRange(0, 1));
      }
    });

    test('IMG-009 fewer than two points is a straight line', () {
      final t = curveTable(const [(0.5, 0.9)]);
      expect(t[100], closeTo(100 / 255, 1e-9));
    });

    test('IMG-009 a channel curve changes only that channel', () {
      final out = applyRecipe(
        solid(2, 2, 100, 100, 100),
        const EditRecipe(curves: CurveSet(blue: [(0, 0.3), (1, 1)])),
      );
      expect(out.rgba[0], closeTo(100, 1));
      expect(out.rgba[2], closeTo(146, 3));
    });

    test('IMG-009 a straight curve changes nothing', () {
      const r = EditRecipe(curves: CurveSet(master: [(0, 0), (1, 1)]));
      expect(r.isIdentity, isTrue);
    });
  });

  group('IMG-009 detail', () {
    PixelFrame edge() {
      const w = 40;
      const h = 8;
      final p = Uint8List(w * h * 4);
      for (var y = 0; y < h; y++) {
        for (var x = 0; x < w; x++) {
          final o = (y * w + x) * 4;
          final v = x < w ~/ 2 ? 80 : 170;
          p[o] = v;
          p[o + 1] = v;
          p[o + 2] = v;
          p[o + 3] = 255;
        }
      }
      return PixelFrame(width: w, height: h, rgba: p);
    }

    test('IMG-009 sharpening makes an edge overshoot, flat areas stay', () {
      final out = applyRecipe(edge(), adjust(AdjustKind.sharpen, 0.8));
      expect(px(out, 19, 4)[0], lessThan(80));
      expect(px(out, 20, 4)[0], greaterThan(170));
      expect(px(out, 2, 4)[0], 80);
      expect(px(out, 37, 4)[0], 170);
    });

    test('IMG-009 vignette darkens the corners and spares the centre', () {
      final out = applyRecipe(
        solid(60, 40, 200, 200, 200),
        adjust(AdjustKind.vignette, 0.8),
      );
      expect(px(out, 0, 0)[0], lessThan(140));
      expect(px(out, 30, 20)[0], 200);
    });

    test('IMG-009 a negative vignette lightens the corners', () {
      final out = applyRecipe(
        solid(60, 40, 100, 100, 100),
        adjust(AdjustKind.vignette, -0.8),
      );
      expect(px(out, 0, 0)[0], greaterThan(150));
      expect(px(out, 30, 20)[0], 100);
    });
  });

  group('IMG-009 drawing and blur', () {
    test('IMG-009 a blurred area smooths detail inside, not outside', () {
      const w = 40;
      final p = Uint8List(w * w * 4);
      for (var i = 0; i < w * w; i++) {
        final v = ((i % w) + (i ~/ w)).isEven ? 255 : 0;
        p[i * 4] = v;
        p[i * 4 + 1] = v;
        p[i * 4 + 2] = v;
        p[i * 4 + 3] = 255;
      }
      final f = PixelFrame(width: w, height: w, rgba: p);
      final out = applyRecipe(
        f,
        const EditRecipe(
          blurs: [BlurSpec(NormRect(0.25, 0.25, 0.5, 0.5), radius: 0.05)],
        ),
      );
      final inside = px(out, 20, 20)[0];
      expect(inside, inInclusiveRange(90, 165));
      expect(px(out, 2, 2)[0], px(f, 2, 2)[0]);
      expect(px(out, 3, 2)[0], px(f, 3, 2)[0]);
    });

    test('IMG-009 a stroke paints along its line only', () {
      final f = solid(50, 50, 255, 255, 255);
      final out = applyRecipe(
        f,
        const EditRecipe(
          strokes: [
            StrokeSpec(
              [(0.1, 0.5), (0.9, 0.5)],
              colorArgb: 0xFFFF0000,
              width: 0.1,
            ),
          ],
        ),
      );
      expect(px(out, 25, 25), [255, 0, 0, 255]);
      expect(px(out, 25, 2), [255, 255, 255, 255]);
      expect(px(out, 1, 25), [255, 255, 255, 255]);
    });

    test('IMG-009 a half-transparent stroke blends with the picture', () {
      final out = applyRecipe(
        solid(50, 50, 0, 0, 0),
        const EditRecipe(
          strokes: [
            StrokeSpec(
              [(0.2, 0.5), (0.8, 0.5)],
              colorArgb: 0x80FFFFFF,
              width: 0.2,
            ),
          ],
        ),
      );
      expect(px(out, 25, 25)[0], closeTo(128, 3));
    });

    test('IMG-009 a single point is a dot', () {
      final out = applyRecipe(
        solid(40, 40, 0, 0, 0),
        const EditRecipe(
          strokes: [
            StrokeSpec([(0.5, 0.5)], colorArgb: 0xFF00FF00, width: 0.2),
          ],
        ),
      );
      expect(px(out, 20, 20), [0, 255, 0, 255]);
      expect(px(out, 2, 2), [0, 0, 0, 255]);
    });

    test('IMG-009 drawings land on the cropped picture', () {
      final out = applyRecipe(
        solid(100, 100, 0, 0, 0),
        const EditRecipe(
          crop: NormRect(0.5, 0.5, 0.5, 0.5),
          strokes: [
            StrokeSpec([(0.5, 0.5)], colorArgb: 0xFFFFFFFF, width: 0.5),
          ],
        ),
      );
      expect((out.width, out.height), (50, 50));
      expect(px(out, 25, 25)[0], 255);
    });
  });

  group('IMG-009 speed', () {
    test('IMG-009 a typical recipe on a megapixel photo stays fast', () {
      final f = solid(1200, 900, 120, 110, 100);
      const r = EditRecipe(
        straighten: 2,
        adjust: {
          AdjustKind.exposure: 0.2,
          AdjustKind.contrast: 0.2,
          AdjustKind.shadows: 0.3,
          AdjustKind.saturation: 0.2,
          AdjustKind.sharpen: 0.4,
          AdjustKind.vignette: 0.3,
        },
        curves: CurveSet(master: [(0, 0), (0.5, 0.55), (1, 1)]),
      );
      final sw = Stopwatch()..start();
      final out = applyRecipe(f, r);
      sw.stop();
      expect(out.width, lessThan(1200));
      // Debug-mode Dart in a test run; the app runs compiled code.
      expect(sw.elapsedMilliseconds, lessThan(6000));
    });
  });
}
