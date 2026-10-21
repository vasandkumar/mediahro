import 'dart:typed_data';

/// Limits for bitmap subtitle parsing (CLAUDE.md §1.10): hostile or broken
/// tracks stop here instead of exhausting memory.
const int maxSubtitleImages = 20000;
const int maxSubtitlePixels = 4096 * 2304;
const int maxSubtitleRle = 8 << 20;

/// How long a bitmap shows when the track gives no end.
const Duration defaultSubtitleDuration = Duration(seconds: 4);

int _clamp(double v) => v < 0 ? 0 : (v > 255 ? 255 : v.round());

/// A colour packed as `A << 24 | B << 16 | G << 8 | R` from limited-range
/// YCrCb, with BT.709 for HD frames and BT.601 for SD ones.
int yCrCbToRgba(int y, int cr, int cb, int alpha, {required bool hd}) {
  final l = 1.164 * (y - 16);
  final u = (cb - 128).toDouble();
  final v = (cr - 128).toDouble();
  final r = hd ? l + 1.793 * v : l + 1.596 * v;
  final g = hd ? l - 0.213 * u - 0.533 * v : l - 0.392 * u - 0.813 * v;
  final b = hd ? l + 2.112 * u : l + 2.017 * u;
  return (alpha << 24) | (_clamp(b) << 16) | (_clamp(g) << 8) | _clamp(r);
}

/// Whether every pixel of straight RGBA [rgba] is fully transparent.
bool isTransparent(Uint8List rgba) {
  for (var i = 3; i < rgba.length; i += 4) {
    if (rgba[i] != 0) return false;
  }
  return true;
}
