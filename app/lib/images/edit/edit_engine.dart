import 'dart:math' as math;
import 'dart:typed_data';

import 'package:mediahro/images/edit/edit_recipe.dart';
import 'package:mediahro/images/image_pipeline.dart';
import 'package:mediahro/images/pipeline/pixel_codec.dart';

/// Applies [recipe] to [src] and returns a new frame; [src] is not changed.
/// Pure Dart on RGBA8888, so it runs in a worker isolate on every platform
/// (IMG-009). Cost is a few passes over the pixels; light and colour are
/// folded into lookup tables, so a recipe of exposure, contrast, white
/// balance and curves is three table reads per pixel.
PixelFrame applyRecipe(PixelFrame src, EditRecipe recipe) {
  if (recipe.isIdentity) return src;
  var f = recipe.hasGeometry ? _geometry(src, recipe) : src;
  if (_needsLight(recipe)) f = _light(f, recipe, copy: identical(f, src));
  final sharpen = recipe.amount(AdjustKind.sharpen);
  if (sharpen > 0.0005) f = _sharpen(f, sharpen);
  final vignette = recipe.amount(AdjustKind.vignette);
  if (vignette.abs() > 0.0005) {
    f = _vignette(f, vignette, copy: identical(f, src));
  }
  for (final b in recipe.blurs) {
    f = _blurRegion(f, b, copy: identical(f, src));
  }
  for (final s in recipe.strokes) {
    f = _stroke(f, s, copy: identical(f, src));
  }
  return f;
}

bool _needsLight(EditRecipe r) =>
    !r.curves.isIdentity ||
    r.adjust.entries.any(
      (e) =>
          e.key != AdjustKind.sharpen &&
          e.key != AdjustKind.vignette &&
          e.value.abs() > 0.0005,
    );

/// Size of the picture after the geometry of [recipe].
({int width, int height}) outputSize(int width, int height, EditRecipe recipe) {
  var w = width;
  var h = height;
  if (recipe.turns.isOdd) {
    w = height;
    h = width;
  }
  if (recipe.straighten.abs() > 0.005) {
    final k = _inscribedScale(w, h, recipe.straighten);
    w = math.max(1, (w * k).round());
    h = math.max(1, (h * k).round());
  }
  final c = recipe.crop;
  return (
    width: math.max(1, (c.width * w).round()),
    height: math.max(1, (c.height * h).round()),
  );
}

PixelFrame _copy(PixelFrame f) => PixelFrame(
  width: f.width,
  height: f.height,
  rgba: Uint8List.fromList(f.rgba),
  sourceWidth: f.sourceWidth,
  sourceHeight: f.sourceHeight,
);

// ---------------------------------------------------------------------------
// Geometry
// ---------------------------------------------------------------------------

/// The largest centred upright rectangle of the picture's own aspect that
/// fits inside it after turning by [degrees], as a fraction of its size.
double _inscribedScale(int w, int h, double degrees) {
  final t = degrees.abs() * math.pi / 180;
  final c = math.cos(t);
  final s = math.sin(t);
  return math.min(w / (w * c + h * s), h / (w * s + h * c));
}

PixelFrame _geometry(PixelFrame src, EditRecipe r) {
  var f = src;
  if (r.flipHorizontal || r.flipVertical) {
    f = _flip(f, r.flipHorizontal, r.flipVertical);
  }
  if (r.turns % 4 != 0) f = _turn(f, r.turns % 4);
  final angle = r.straighten.abs() > 0.005 ? r.straighten : 0.0;
  if (angle == 0 && r.crop.isFull) return f;
  if (angle == 0) return _cropRect(f, r.crop);
  return _straightenAndCrop(f, angle, r.crop);
}

PixelFrame _flip(PixelFrame f, bool horizontal, bool vertical) {
  final w = f.width;
  final h = f.height;
  final out = Uint8List(f.rgba.length);
  for (var y = 0; y < h; y++) {
    final sy = vertical ? h - 1 - y : y;
    for (var x = 0; x < w; x++) {
      final sx = horizontal ? w - 1 - x : x;
      final s = (sy * w + sx) * 4;
      final d = (y * w + x) * 4;
      out[d] = f.rgba[s];
      out[d + 1] = f.rgba[s + 1];
      out[d + 2] = f.rgba[s + 2];
      out[d + 3] = f.rgba[s + 3];
    }
  }
  return PixelFrame(
    width: w,
    height: h,
    rgba: out,
    sourceWidth: f.sourceWidth,
    sourceHeight: f.sourceHeight,
  );
}

/// Clockwise quarter turns.
PixelFrame _turn(PixelFrame f, int turns) {
  final w = f.width;
  final h = f.height;
  final swap = turns.isOdd;
  final ow = swap ? h : w;
  final oh = swap ? w : h;
  final out = Uint8List(f.rgba.length);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final int nx;
      final int ny;
      switch (turns) {
        case 1:
          nx = h - 1 - y;
          ny = x;
        case 2:
          nx = w - 1 - x;
          ny = h - 1 - y;
        default:
          nx = y;
          ny = w - 1 - x;
      }
      final s = (y * w + x) * 4;
      final d = (ny * ow + nx) * 4;
      out[d] = f.rgba[s];
      out[d + 1] = f.rgba[s + 1];
      out[d + 2] = f.rgba[s + 2];
      out[d + 3] = f.rgba[s + 3];
    }
  }
  return PixelFrame(
    width: ow,
    height: oh,
    rgba: out,
    sourceWidth: f.sourceWidth,
    sourceHeight: f.sourceHeight,
  );
}

PixelFrame _cropRect(PixelFrame f, NormRect c) {
  final left = (c.left * f.width).round().clamp(0, f.width - 1);
  final top = (c.top * f.height).round().clamp(0, f.height - 1);
  final w = math.max(1, (c.width * f.width).round()).clamp(1, f.width - left);
  final h = math.max(1, (c.height * f.height).round()).clamp(1, f.height - top);
  final out = Uint8List(w * h * 4);
  for (var y = 0; y < h; y++) {
    final s = ((top + y) * f.width + left) * 4;
    out.setRange(y * w * 4, (y + 1) * w * 4, f.rgba, s);
  }
  return PixelFrame(
    width: w,
    height: h,
    rgba: out,
    sourceWidth: f.sourceWidth,
    sourceHeight: f.sourceHeight,
  );
}

/// Turns the picture by [degrees] (clockwise), keeps the largest upright
/// rectangle, then cuts [crop] out of that: one bilinear pass.
PixelFrame _straightenAndCrop(PixelFrame f, double degrees, NormRect crop) {
  final w = f.width;
  final h = f.height;
  final k = _inscribedScale(w, h, degrees);
  final fullW = w * k;
  final fullH = h * k;
  final ow = math.max(1, (crop.width * fullW).round());
  final oh = math.max(1, (crop.height * fullH).round());
  final t = degrees * math.pi / 180;
  final cosT = math.cos(t);
  final sinT = math.sin(t);
  final out = Uint8List(ow * oh * 4);
  final src = f.rgba;
  final cx = w / 2;
  final cy = h / 2;
  for (var oy = 0; oy < oh; oy++) {
    final v = (crop.top + (oy + 0.5) / oh * crop.height) * fullH - fullH / 2;
    for (var ox = 0; ox < ow; ox++) {
      final u = (crop.left + (ox + 0.5) / ow * crop.width) * fullW - fullW / 2;
      // Back into the source picture: turn by −degrees.
      final sx = u * cosT + v * sinT + cx - 0.5;
      final sy = -u * sinT + v * cosT + cy - 0.5;
      final x0 = sx.floor();
      final y0 = sy.floor();
      final fx = sx - x0;
      final fy = sy - y0;
      final xa = x0.clamp(0, w - 1);
      final xb = (x0 + 1).clamp(0, w - 1);
      final ya = y0.clamp(0, h - 1);
      final yb = (y0 + 1).clamp(0, h - 1);
      final i00 = (ya * w + xa) * 4;
      final i10 = (ya * w + xb) * 4;
      final i01 = (yb * w + xa) * 4;
      final i11 = (yb * w + xb) * 4;
      final d = (oy * ow + ox) * 4;
      for (var c = 0; c < 4; c++) {
        final top = src[i00 + c] + (src[i10 + c] - src[i00 + c]) * fx;
        final bot = src[i01 + c] + (src[i11 + c] - src[i01 + c]) * fx;
        out[d + c] = (top + (bot - top) * fy + 0.5).toInt();
      }
    }
  }
  return PixelFrame(
    width: ow,
    height: oh,
    rgba: out,
    sourceWidth: f.sourceWidth,
    sourceHeight: f.sourceHeight,
  );
}

// ---------------------------------------------------------------------------
// Light and colour
// ---------------------------------------------------------------------------

double _toLinear(int i) {
  final v = i / 255;
  return v <= 0.04045
      ? v / 12.92
      : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
}

final Float64List _srgbToLinear = Float64List.fromList([
  for (var i = 0; i < 256; i++) _toLinear(i),
]);

double _linearToSrgb(double l) {
  if (l <= 0) return 0;
  if (l >= 1) return 1;
  return l <= 0.0031308
      ? l * 12.92
      : 1.055 * math.pow(l, 1 / 2.4).toDouble() - 0.055;
}

/// Control points to a 256-entry table (monotone cubic, so a curve never
/// overshoots between its points).
Float64List curveTable(List<(double, double)> points) {
  final t = Float64List(256);
  final pts = [...points]..sort((a, b) => a.$1.compareTo(b.$1));
  if (pts.length < 2) {
    for (var i = 0; i < 256; i++) {
      t[i] = i / 255;
    }
    return t;
  }
  final n = pts.length;
  final xs = [for (final p in pts) p.$1];
  final ys = [for (final p in pts) p.$2];
  final d = List<double>.filled(n - 1, 0);
  for (var i = 0; i < n - 1; i++) {
    final dx = xs[i + 1] - xs[i];
    d[i] = dx.abs() < 1e-9 ? 0 : (ys[i + 1] - ys[i]) / dx;
  }
  final m = List<double>.filled(n, 0);
  m[0] = d[0];
  m[n - 1] = d[n - 2];
  for (var i = 1; i < n - 1; i++) {
    m[i] = d[i - 1] * d[i] <= 0 ? 0 : (d[i - 1] + d[i]) / 2;
  }
  for (var i = 0; i < n - 1; i++) {
    if (d[i] == 0) {
      m[i] = 0;
      m[i + 1] = 0;
      continue;
    }
    final a = m[i] / d[i];
    final b = m[i + 1] / d[i];
    final s = a * a + b * b;
    if (s > 9) {
      final tau = 3 / math.sqrt(s);
      m[i] = tau * a * d[i];
      m[i + 1] = tau * b * d[i];
    }
  }
  var seg = 0;
  for (var i = 0; i < 256; i++) {
    final x = i / 255;
    if (x <= xs.first) {
      t[i] = ys.first;
      continue;
    }
    if (x >= xs.last) {
      t[i] = ys.last;
      continue;
    }
    while (seg < n - 2 && x > xs[seg + 1]) {
      seg++;
    }
    final h = xs[seg + 1] - xs[seg];
    final u = (x - xs[seg]) / h;
    final u2 = u * u;
    final u3 = u2 * u;
    t[i] =
        (2 * u3 - 3 * u2 + 1) * ys[seg] +
        (u3 - 2 * u2 + u) * h * m[seg] +
        (-2 * u3 + 3 * u2) * ys[seg + 1] +
        (u3 - u2) * h * m[seg + 1];
    t[i] = t[i].clamp(0.0, 1.0);
  }
  return t;
}

/// Per-channel tables for white balance, exposure, whites, blacks, contrast
/// and curves.
List<Uint8List> _lightTables(EditRecipe r) {
  final temp = r.amount(AdjustKind.temperature);
  final tint = r.amount(AdjustKind.tint);
  final gains = [
    1 + 0.35 * temp + 0.1 * tint,
    1 - 0.25 * tint,
    1 - 0.35 * temp + 0.1 * tint,
  ];
  final exposure = math.pow(2, 2 * r.amount(AdjustKind.exposure)).toDouble();
  final contrast = 1 + r.amount(AdjustKind.contrast);
  final blacks = -r.amount(AdjustKind.blacks) * 0.1;
  final whites = 1 - r.amount(AdjustKind.whites) * 0.15;
  final master = curveTable(r.curves.master);
  final channel = [
    curveTable(r.curves.red),
    curveTable(r.curves.green),
    curveTable(r.curves.blue),
  ];
  return [
    for (var c = 0; c < 3; c++)
      Uint8List.fromList([
        for (var i = 0; i < 256; i++)
          () {
            var y = _linearToSrgb(_srgbToLinear[i] * gains[c] * exposure);
            y = (y - blacks) / (1 - blacks);
            y = y / whites;
            y = 0.5 + (y - 0.5) * contrast;
            y = y.clamp(0.0, 1.0);
            final q = (y * 255).round();
            y = channel[c][(master[q] * 255).round()];
            return (y * 255).round().clamp(0, 255);
          }(),
      ]),
  ];
}

PixelFrame _light(PixelFrame f, EditRecipe r, {required bool copy}) {
  final out = copy ? _copy(f) : f;
  final p = out.rgba;
  final n = out.width * out.height;
  final lut = _lightTables(r);
  final lr = lut[0];
  final lg = lut[1];
  final lb = lut[2];
  final shadows = r.amount(AdjustKind.shadows);
  final highlights = r.amount(AdjustKind.highlights);
  final saturation = r.amount(AdjustKind.saturation);
  final vibrance = r.amount(AdjustKind.vibrance);
  final tonal = shadows != 0 || highlights != 0;
  final colour = saturation != 0 || vibrance != 0;
  if (!tonal && !colour) {
    // Exposure, contrast, white balance and curves are all in the tables.
    for (var o = 0; o < n * 4; o += 4) {
      p[o] = lr[p[o]];
      p[o + 1] = lg[p[o + 1]];
      p[o + 2] = lb[p[o + 2]];
    }
    return out;
  }
  for (var i = 0, o = 0; i < n; i++, o += 4) {
    var red = lr[p[o]].toDouble();
    var green = lg[p[o + 1]].toDouble();
    var blue = lb[p[o + 2]].toDouble();
    if (tonal) {
      final l = (0.2126 * red + 0.7152 * green + 0.0722 * blue) / 255;
      final dark = (1 - l) * (1 - l);
      final delta = (shadows * 0.3 * dark + highlights * 0.3 * l * l) * 255;
      red += delta;
      green += delta;
      blue += delta;
    }
    if (colour) {
      final l = 0.2126 * red + 0.7152 * green + 0.0722 * blue;
      var factor = 1 + saturation;
      if (vibrance != 0) {
        final hi = math.max(red, math.max(green, blue));
        final lo = math.min(red, math.min(green, blue));
        final sat = hi <= 0 ? 0.0 : (hi - lo) / hi;
        factor += vibrance * (1 - sat);
      }
      red = l + (red - l) * factor;
      green = l + (green - l) * factor;
      blue = l + (blue - l) * factor;
    }
    p[o] = red < 0 ? 0 : (red > 255 ? 255 : (red + 0.5).toInt());
    p[o + 1] = green < 0 ? 0 : (green > 255 ? 255 : (green + 0.5).toInt());
    p[o + 2] = blue < 0 ? 0 : (blue > 255 ? 255 : (blue + 0.5).toInt());
  }
  return out;
}

// ---------------------------------------------------------------------------
// Detail and finishing
// ---------------------------------------------------------------------------

/// Unsharp mask with a five-tap blur whose tap spacing grows with the
/// picture, so the same amount looks the same at preview and full size.
PixelFrame _sharpen(PixelFrame f, double amount) {
  final w = f.width;
  final h = f.height;
  final step = math.max(1, (math.max(w, h) / 1800).round());
  final src = f.rgba;
  final row = w * 4;
  final s4 = step * 4;
  final tmp = Uint8List(src.length);
  // Taps 1 4 6 4 1 at spacing [step]. The blur runs over all four bytes of
  // a pixel alike (the alpha result is thrown away), so the inner loops are
  // flat walks over the rows with no per-pixel bounds handling in the
  // interior.
  final lo = math.min(2 * step, w);
  final hi = math.max(w - 2 * step, lo);
  for (var y = 0; y < h; y++) {
    final base = y * row;
    // Edge pixels read clamped neighbours.
    for (var x = 0; x < w; x++) {
      if (x == lo && hi > lo) x = hi;
      final o = base + x * 4;
      for (var c = 0; c < 3; c++) {
        final a = base + _clampIndex(x - 2 * step, w) * 4 + c;
        final b = base + _clampIndex(x - step, w) * 4 + c;
        final d = base + _clampIndex(x + step, w) * 4 + c;
        final e = base + _clampIndex(x + 2 * step, w) * 4 + c;
        tmp[o + c] =
            (src[a] + 4 * src[b] + 6 * src[o + c] + 4 * src[d] + src[e]) >> 4;
      }
    }
    final end = base + hi * 4;
    for (var i = base + lo * 4; i < end; i++) {
      tmp[i] =
          (src[i - 2 * s4] +
              4 * src[i - s4] +
              6 * src[i] +
              4 * src[i + s4] +
              src[i + 2 * s4]) >>
          4;
    }
  }
  final out = Uint8List(src.length);
  final gain = amount * 2;
  for (var y = 0; y < h; y++) {
    final o = y * row;
    final r0 = _clampIndex(y - 2 * step, h) * row;
    final r1 = _clampIndex(y - step, h) * row;
    final r3 = _clampIndex(y + step, h) * row;
    final r4 = _clampIndex(y + 2 * step, h) * row;
    for (var i = 0; i < row; i++) {
      final blur =
          (tmp[r0 + i] +
              4 * tmp[r1 + i] +
              6 * tmp[o + i] +
              4 * tmp[r3 + i] +
              tmp[r4 + i]) >>
          4;
      final s = src[o + i];
      final v = s + (s - blur) * gain;
      out[o + i] = v < 0 ? 0 : (v > 255 ? 255 : v.round());
    }
  }
  // Alpha is carried over, not sharpened.
  for (var i = 3; i < out.length; i += 4) {
    out[i] = src[i];
  }
  return PixelFrame(
    width: w,
    height: h,
    rgba: out,
    sourceWidth: f.sourceWidth,
    sourceHeight: f.sourceHeight,
  );
}

int _clampIndex(int v, int n) => v < 0 ? 0 : (v >= n ? n - 1 : v);

double _smoothstep(double a, double b, double x) {
  final t = ((x - a) / (b - a)).clamp(0.0, 1.0);
  return t * t * (3 - 2 * t);
}

/// Positive darkens the corners, negative lightens them.
PixelFrame _vignette(PixelFrame f, double amount, {required bool copy}) {
  final out = copy ? _copy(f) : f;
  final p = out.rgba;
  final w = out.width;
  final h = out.height;
  final cx = (w - 1) / 2;
  final cy = (h - 1) / 2;
  for (var y = 0; y < h; y++) {
    final dy = cy == 0 ? 0 : (y - cy) / cy;
    for (var x = 0; x < w; x++) {
      final dx = cx == 0 ? 0 : (x - cx) / cx;
      final r = math.sqrt(dx * dx + dy * dy) / math.sqrt2;
      final weight = _smoothstep(0.35, 1, r);
      if (weight == 0) continue;
      final o = (y * w + x) * 4;
      for (var c = 0; c < 3; c++) {
        final v = p[o + c];
        final nv = amount > 0
            ? v * (1 - amount * weight * 0.8)
            : v + (255 - v) * (-amount) * weight * 0.7;
        p[o + c] = nv < 0 ? 0 : (nv > 255 ? 255 : nv.round());
      }
    }
  }
  return out;
}

// ---------------------------------------------------------------------------
// Annotations
// ---------------------------------------------------------------------------

PixelFrame _blurRegion(PixelFrame f, BlurSpec b, {required bool copy}) {
  final out = copy ? _copy(f) : f;
  final w = out.width;
  final h = out.height;
  final left = (b.rect.left * w).floor().clamp(0, w - 1);
  final top = (b.rect.top * h).floor().clamp(0, h - 1);
  final right = (b.rect.right * w).ceil().clamp(left + 1, w);
  final bottom = (b.rect.bottom * h).ceil().clamp(top + 1, h);
  final rw = right - left;
  final rh = bottom - top;
  final radius = math.max(1, (b.radius * math.min(w, h)).round());
  final region = Uint8List(rw * rh * 3);
  for (var y = 0; y < rh; y++) {
    for (var x = 0; x < rw; x++) {
      final s = ((top + y) * w + left + x) * 4;
      final d = (y * rw + x) * 3;
      region[d] = out.rgba[s];
      region[d + 1] = out.rgba[s + 1];
      region[d + 2] = out.rgba[s + 2];
    }
  }
  var a = region;
  for (var pass = 0; pass < 3; pass++) {
    a = _boxBlur(a, rw, rh, radius, horizontal: true);
    a = _boxBlur(a, rw, rh, radius, horizontal: false);
  }
  for (var y = 0; y < rh; y++) {
    for (var x = 0; x < rw; x++) {
      final s = (y * rw + x) * 3;
      final d = ((top + y) * w + left + x) * 4;
      out.rgba[d] = a[s];
      out.rgba[d + 1] = a[s + 1];
      out.rgba[d + 2] = a[s + 2];
    }
  }
  return out;
}

/// One sliding-window box blur pass over RGB, edges clamped.
Uint8List _boxBlur(
  Uint8List src,
  int w,
  int h,
  int radius, {
  required bool horizontal,
}) {
  final out = Uint8List(src.length);
  final lines = horizontal ? h : w;
  final length = horizontal ? w : h;
  final stepAlong = horizontal ? 3 : w * 3;
  final stepAcross = horizontal ? w * 3 : 3;
  final size = 2 * radius + 1;
  for (var line = 0; line < lines; line++) {
    final base = line * stepAcross;
    for (var c = 0; c < 3; c++) {
      var sum = 0;
      for (var t = -radius; t <= radius; t++) {
        sum += src[base + t.clamp(0, length - 1) * stepAlong + c];
      }
      for (var i = 0; i < length; i++) {
        out[base + i * stepAlong + c] = sum ~/ size;
        final add = (i + radius + 1).clamp(0, length - 1);
        final drop = (i - radius).clamp(0, length - 1);
        sum +=
            src[base + add * stepAlong + c] - src[base + drop * stepAlong + c];
      }
    }
  }
  return out;
}

PixelFrame _stroke(PixelFrame f, StrokeSpec s, {required bool copy}) {
  final out = copy ? _copy(f) : f;
  final w = out.width;
  final h = out.height;
  final radius = math.max(0.5, s.width * math.min(w, h) / 2);
  final alpha = ((s.colorArgb >> 24) & 0xff) / 255;
  final cr = (s.colorArgb >> 16) & 0xff;
  final cg = (s.colorArgb >> 8) & 0xff;
  final cb = s.colorArgb & 0xff;
  final pts = [for (final (x, y) in s.points) (x * w, y * h)];
  void segment(double x0, double y0, double x1, double y1) {
    final minX = (math.min(x0, x1) - radius - 1).floor().clamp(0, w - 1);
    final maxX = (math.max(x0, x1) + radius + 1).ceil().clamp(0, w - 1);
    final minY = (math.min(y0, y1) - radius - 1).floor().clamp(0, h - 1);
    final maxY = (math.max(y0, y1) + radius + 1).ceil().clamp(0, h - 1);
    final dx = x1 - x0;
    final dy = y1 - y0;
    final len2 = dx * dx + dy * dy;
    for (var y = minY; y <= maxY; y++) {
      for (var x = minX; x <= maxX; x++) {
        final px = x + 0.5;
        final py = y + 0.5;
        final t = len2 == 0
            ? 0.0
            : (((px - x0) * dx + (py - y0) * dy) / len2).clamp(0.0, 1.0);
        final ex = px - (x0 + t * dx);
        final ey = py - (y0 + t * dy);
        final coverage = (radius + 0.5 - math.sqrt(ex * ex + ey * ey)).clamp(
          0.0,
          1.0,
        );
        if (coverage == 0) continue;
        final a = coverage * alpha;
        final o = (y * w + x) * 4;
        out.rgba[o] = (out.rgba[o] + (cr - out.rgba[o]) * a).round();
        out.rgba[o + 1] = (out.rgba[o + 1] + (cg - out.rgba[o + 1]) * a)
            .round();
        out.rgba[o + 2] = (out.rgba[o + 2] + (cb - out.rgba[o + 2]) * a)
            .round();
      }
    }
  }

  if (pts.length == 1) {
    segment(pts[0].$1, pts[0].$2, pts[0].$1, pts[0].$2);
  }
  for (var i = 0; i + 1 < pts.length; i++) {
    segment(pts[i].$1, pts[i].$2, pts[i + 1].$1, pts[i + 1].$2);
  }
  return out;
}
