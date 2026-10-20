import 'dart:math' as math;
import 'dart:typed_data';

import 'package:mediahro/images/image_pipeline.dart';
import 'package:mediahro/images/pipeline/pixel_codec.dart';

/// Crops [f] to [region] given in source pixels and [scale] (frame size over
/// source size).
PixelFrame cropFrame(PixelFrame f, ImageRegion region, double scale) {
  final left = (region.left * scale).round().clamp(0, f.width - 1);
  final top = (region.top * scale).round().clamp(0, f.height - 1);
  final w = (region.width * scale).round().clamp(1, f.width - left);
  final h = (region.height * scale).round().clamp(1, f.height - top);
  final out = Uint8List(w * h * 4);
  for (var y = 0; y < h; y++) {
    final from = ((top + y) * f.width + left) * 4;
    out.setRange(y * w * 4, (y + 1) * w * 4, f.rgba, from);
  }
  return PixelFrame(
    width: w,
    height: h,
    rgba: out,
    sourceWidth: f.sourceWidth,
    sourceHeight: f.sourceHeight,
  );
}

/// Box-filter downscale so the longest edge is at most [edge].
PixelFrame downscaleToEdge(PixelFrame f, int edge) {
  final longest = math.max(f.width, f.height);
  if (longest <= edge) return f;
  final s = edge / longest;
  final w = math.max(1, (f.width * s).round());
  final h = math.max(1, (f.height * s).round());
  final out = Uint8List(w * h * 4);
  for (var y = 0; y < h; y++) {
    final y0 = (y * f.height) ~/ h;
    final y1 = math.max(y0 + 1, ((y + 1) * f.height) ~/ h);
    for (var x = 0; x < w; x++) {
      final x0 = (x * f.width) ~/ w;
      final x1 = math.max(x0 + 1, ((x + 1) * f.width) ~/ w);
      var r = 0;
      var g = 0;
      var b = 0;
      var a = 0;
      var n = 0;
      for (var yy = y0; yy < y1; yy++) {
        for (var xx = x0; xx < x1; xx++) {
          final i = (yy * f.width + xx) * 4;
          final al = f.rgba[i + 3];
          r += f.rgba[i] * al;
          g += f.rgba[i + 1] * al;
          b += f.rgba[i + 2] * al;
          a += al;
          n++;
        }
      }
      final o = (y * w + x) * 4;
      if (a > 0) {
        out[o] = r ~/ a;
        out[o + 1] = g ~/ a;
        out[o + 2] = b ~/ a;
      }
      out[o + 3] = a ~/ n;
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

/// [f] reduced by [scale] (< 1) with the box filter, or enlarged by nearest
/// neighbour when [scale] > 1 (full-resolution codecs serve tiles and
/// thumbnails by decoding, cropping and reducing).
PixelFrame scaleFrame(PixelFrame f, double scale) {
  if (scale == 1) return f;
  final w = math.max(1, (f.width * scale).round());
  final h = math.max(1, (f.height * scale).round());
  if (scale < 1) {
    return downscaleToEdge(f, math.max(w, h));
  }
  final out = Uint8List(w * h * 4);
  for (var y = 0; y < h; y++) {
    final sy = math.min(f.height - 1, (y / scale).floor());
    for (var x = 0; x < w; x++) {
      final sx = math.min(f.width - 1, (x / scale).floor());
      final o = (y * w + x) * 4;
      final i = (sy * f.width + sx) * 4;
      out.setRange(o, o + 4, f.rgba, i);
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

/// The decode contract for codecs that always produce the whole image:
/// crop to [region] (source pixels), then scale by [scale].
PixelFrame regionAndScale(PixelFrame f, ImageRegion? region, double scale) {
  var r = f;
  if (region != null) r = cropFrame(r, region, 1);
  return scaleFrame(r, scale);
}
