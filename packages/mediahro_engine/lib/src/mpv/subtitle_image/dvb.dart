import 'dart:math' as math;
import 'dart:typed_data';

import 'package:mediahro_engine/src/api/subtitle_image.dart';
import 'package:mediahro_engine/src/mpv/subtitle_image/matroska.dart';
import 'package:mediahro_engine/src/mpv/subtitle_image/pixels.dart';

/// DVB subtitles (`S_DVBSUB`, ETSI EN 300 743): each packet is the segments
/// of one display set. Regions persist between sets in the normal case, so
/// a set that only changes one region redraws the others.
Iterable<SubtitleImage> decodeDvb(
  Iterable<MkvBlock> blocks, {
  int maxImages = maxSubtitleImages,
}) sync* {
  var emitted = 0;
  final cluts = <int, List<int>>{};
  final regions = <int, _Region>{};
  final objects = <int, _DvbObject>{};
  var displayWidth = 720;
  var displayHeight = 576;
  var page = <({int id, int x, int y})>[];
  var timeout = const Duration(seconds: 5);
  SubtitleImage? shown;

  for (final block in blocks) {
    final d = block.data;
    var p = 0;
    // Some muxers keep the PES data_identifier and stream id.
    if (d.length > 2 && d[0] == 0x20 && d[1] == 0x00) p = 2;
    var sawPage = false;
    while (p + 6 <= d.length && d[p] == 0x0F) {
      final type = d[p + 1];
      final len = (d[p + 4] << 8) | d[p + 5];
      p += 6;
      if (p + len > d.length) break;
      final s = ByteData.sublistView(d, p, p + len);
      switch (type) {
        case 0x10: // page composition
          if (len < 2) break;
          sawPage = true;
          timeout = Duration(seconds: s.getUint8(0));
          final state = (s.getUint8(1) >> 2) & 3;
          if (state != 0) {
            // Acquisition point or mode change: start from nothing.
            regions.clear();
            objects.clear();
          }
          page = [
            for (var q = 2; q + 6 <= len; q += 6)
              (id: s.getUint8(q), x: s.getUint16(q + 2), y: s.getUint16(q + 4)),
          ];
        case 0x11:
          _parseRegion(s, regions);
        case 0x12:
          _parseClut(s, cluts);
        case 0x13:
          _parseObject(s, objects);
        case 0x14:
          if (len >= 5) {
            displayWidth = s.getUint16(1) + 1;
            displayHeight = s.getUint16(3) + 1;
          }
        case 0x80: // end of display set
          if (!sawPage) break;
          // Whatever was on screen ends here.
          final s0 = shown;
          shown = null;
          if (s0 != null) {
            emitted++;
            yield s0.end > block.pts ? s0.withEnd(block.pts) : s0;
          }
          if (emitted >= maxImages) return;
          final image = _compose(
            page,
            regions,
            objects,
            cluts,
            block.pts,
            timeout,
            displayWidth,
            displayHeight,
          );
          shown = image;
        default:
          break;
      }
      p += len;
    }
  }
  if (shown != null) yield shown;
}

final class _Region {
  _Region(this.id, this.width, this.height, this.depth, this.clut)
    : pixels = Uint8List(width * height);
  final int id;
  final int width;
  final int height;
  final int depth; // 2, 4 or 8 bits
  final int clut;
  final Uint8List pixels;
  List<({int id, int x, int y})> objects = [];
  bool filled = false;
}

final class _DvbObject {
  _DvbObject(this.top, this.bottom);
  final Uint8List top;
  final Uint8List bottom;
}

void _parseRegion(ByteData s, Map<int, _Region> regions) {
  if (s.lengthInBytes < 10) return;
  final id = s.getUint8(0);
  final fill = s.getUint8(1) & 0x08 != 0;
  final width = s.getUint16(2);
  final height = s.getUint16(4);
  if (width == 0 || height == 0 || width * height > maxSubtitlePixels) return;
  final depth = switch ((s.getUint8(6) >> 2) & 7) {
    1 => 2,
    2 => 4,
    _ => 8,
  };
  final r = _Region(id, width, height, depth, s.getUint8(7));
  if (fill) {
    final bg = switch (depth) {
      2 => (s.getUint8(9) >> 2) & 3,
      4 => s.getUint8(9) >> 4,
      _ => s.getUint8(8),
    };
    r.pixels.fillRange(0, r.pixels.length, bg);
    r.filled = true;
  }
  var p = 10;
  while (p + 6 <= s.lengthInBytes) {
    final obj = s.getUint16(p);
    final type = s.getUint8(p + 2) >> 6;
    final x = ((s.getUint8(p + 2) & 0x0F) << 8) | s.getUint8(p + 3);
    final y = ((s.getUint8(p + 4) & 0x0F) << 8) | s.getUint8(p + 5);
    r.objects.add((id: obj, x: x, y: y));
    // Character objects carry two more bytes: foreground and background.
    p += type == 0 ? 6 : 8;
  }
  regions[id] = r;
}

void _parseClut(ByteData s, Map<int, List<int>> cluts) {
  if (s.lengthInBytes < 2) return;
  final id = s.getUint8(0);
  final table = List<int>.filled(256, 0);
  var p = 2;
  while (p + 2 <= s.lengthInBytes) {
    final entry = s.getUint8(p);
    final flags = s.getUint8(p + 1);
    int y;
    int cr;
    int cb;
    int t;
    if (flags & 1 != 0) {
      if (p + 6 > s.lengthInBytes) break;
      y = s.getUint8(p + 2);
      cr = s.getUint8(p + 3);
      cb = s.getUint8(p + 4);
      t = s.getUint8(p + 5);
      p += 6;
    } else {
      if (p + 4 > s.lengthInBytes) break;
      final a = s.getUint8(p + 2);
      final b = s.getUint8(p + 3);
      y = (a >> 2) << 2;
      cr = (((a & 3) << 2) | (b >> 6)) << 4;
      cb = ((b >> 2) & 0xF) << 4;
      t = (b & 3) * 85;
      p += 4;
    }
    // Y of 0 means "fully transparent" whatever T says.
    table[entry] = y == 0 ? 0 : yCrCbToRgba(y, cr, cb, 255 - t, hd: false);
  }
  cluts[id] = table;
}

void _parseObject(ByteData s, Map<int, _DvbObject> objects) {
  if (s.lengthInBytes < 7) return;
  final id = s.getUint16(0);
  // Only pixel-coded objects; text objects are not bitmaps.
  if ((s.getUint8(2) >> 2) & 3 != 0) return;
  final topLen = s.getUint16(3);
  final bottomLen = s.getUint16(5);
  if (7 + topLen + bottomLen > s.lengthInBytes) return;
  final raw = s.buffer.asUint8List(s.offsetInBytes, s.lengthInBytes);
  final top = Uint8List.fromList(raw.sublist(7, 7 + topLen));
  final bottom = bottomLen == 0
      ? top
      : Uint8List.fromList(raw.sublist(7 + topLen, 7 + topLen + bottomLen));
  objects[id] = _DvbObject(top, bottom);
}

SubtitleImage? _compose(
  List<({int id, int x, int y})> page,
  Map<int, _Region> regions,
  Map<int, _DvbObject> objects,
  Map<int, List<int>> cluts,
  Duration at,
  Duration timeout,
  int frameWidth,
  int frameHeight,
) {
  final shown = <({_Region region, int x, int y})>[];
  for (final ref in page) {
    final r = regions[ref.id];
    if (r != null) shown.add((region: r, x: ref.x, y: ref.y));
  }
  if (shown.isEmpty) return null;
  // Draw each region's objects into its pixels.
  for (final s in shown) {
    final r = s.region;
    for (final o in r.objects) {
      final obj = objects[o.id];
      if (obj == null) continue;
      _drawObject(r, obj, o.x, o.y);
    }
  }
  var left = 1 << 30;
  var top = 1 << 30;
  var right = 0;
  var bottom = 0;
  for (final s in shown) {
    left = math.min(left, s.x);
    top = math.min(top, s.y);
    right = math.max(right, s.x + s.region.width);
    bottom = math.max(bottom, s.y + s.region.height);
  }
  final width = right - left;
  final height = bottom - top;
  if (width <= 0 || height <= 0 || width * height > maxSubtitlePixels) {
    return null;
  }
  final rgba = Uint8List(width * height * 4);
  for (final s in shown) {
    final r = s.region;
    final clut = cluts[r.clut];
    if (clut == null) continue;
    for (var y = 0; y < r.height; y++) {
      for (var x = 0; x < r.width; x++) {
        final color = clut[r.pixels[y * r.width + x]];
        if (color >> 24 == 0) continue;
        final i = ((s.y - top + y) * width + (s.x - left + x)) * 4;
        rgba[i] = color & 0xFF;
        rgba[i + 1] = (color >> 8) & 0xFF;
        rgba[i + 2] = (color >> 16) & 0xFF;
        rgba[i + 3] = color >> 24;
      }
    }
  }
  if (isTransparent(rgba)) return null;
  return SubtitleImage(
    start: at,
    end: at + timeout,
    x: left,
    y: top,
    width: width,
    height: height,
    frameWidth: frameWidth,
    frameHeight: frameHeight,
    rgba: rgba,
  );
}

// Pixel-data sub-blocks of an object, field by field: the top field
// fills rows 0, 2, 4…, the bottom field rows 1, 3, 5….
void _drawObject(_Region r, _DvbObject obj, int ox, int oy) {
  _drawField(r, obj.top, ox, oy);
  _drawField(r, obj.bottom, ox, oy + 1);
}

void _drawField(_Region r, Uint8List d, int ox, int firstRow) {
  var x = ox;
  var y = firstRow;
  var p = 0;
  // Pixel codes at the object's depth map to the region's depth.
  const map2to4 = [0, 7, 8, 15];
  const map2to8 = [0, 0x77, 0x88, 0xFF];
  void put(int code, int run, int depth) {
    final mapped = switch ((depth, r.depth)) {
      (2, 4) => map2to4[code],
      (2, 8) => map2to8[code],
      (4, 8) => code * 17,
      _ => code,
    };
    if (y >= 0 && y < r.height) {
      for (var i = 0; i < run; i++) {
        final xx = x + i;
        if (xx >= 0 && xx < r.width) r.pixels[y * r.width + xx] = mapped;
      }
    }
    x += run;
  }

  while (p < d.length) {
    final kind = d[p++];
    switch (kind) {
      case 0x10:
        final bits = _Bits(d, p);
        _twoBit(bits, put);
        p = bits.bytePosition;
      case 0x11:
        final bits = _Bits(d, p);
        _fourBit(bits, put);
        p = bits.bytePosition;
      case 0x12:
        final bits = _Bits(d, p);
        _eightBit(bits, put);
        p = bits.bytePosition;
      case 0x20:
        p += 2;
      case 0x21:
        p += 4;
      case 0x22:
        p += 16;
      case 0xF0:
        x = ox;
        y += 2;
      default:
        return;
    }
  }
}

final class _Bits {
  _Bits(this.d, int start) : _bit = start * 8;
  final Uint8List d;
  int _bit;

  bool get atEnd => _bit >= d.length * 8;

  int read(int n) {
    var v = 0;
    for (var i = 0; i < n; i++) {
      v <<= 1;
      if (_bit < d.length * 8) v |= (d[_bit >> 3] >> (7 - (_bit & 7))) & 1;
      _bit++;
    }
    return v;
  }

  int get bytePosition => (_bit + 7) >> 3;
}

typedef _Put = void Function(int code, int run, int depth);

void _twoBit(_Bits b, _Put put) {
  while (!b.atEnd) {
    final c = b.read(2);
    if (c != 0) {
      put(c, 1, 2);
      continue;
    }
    if (b.read(1) == 1) {
      final run = b.read(3) + 3;
      put(b.read(2), run, 2);
    } else if (b.read(1) == 1) {
      put(0, 1, 2);
    } else {
      switch (b.read(2)) {
        case 0:
          return;
        case 1:
          put(0, 2, 2);
        case 2:
          final run = b.read(4) + 12;
          put(b.read(2), run, 2);
        default:
          final run = b.read(8) + 29;
          put(b.read(2), run, 2);
      }
    }
  }
}

void _fourBit(_Bits b, _Put put) {
  while (!b.atEnd) {
    final c = b.read(4);
    if (c != 0) {
      put(c, 1, 4);
      continue;
    }
    if (b.read(1) == 0) {
      final n = b.read(3);
      if (n == 0) return;
      put(0, n + 2, 4);
    } else if (b.read(1) == 0) {
      final run = b.read(2) + 4;
      put(b.read(4), run, 4);
    } else {
      switch (b.read(2)) {
        case 0:
          put(0, 1, 4);
        case 1:
          put(0, 2, 4);
        case 2:
          final run = b.read(4) + 9;
          put(b.read(4), run, 4);
        default:
          final run = b.read(8) + 25;
          put(b.read(4), run, 4);
      }
    }
  }
}

void _eightBit(_Bits b, _Put put) {
  while (!b.atEnd) {
    final c = b.read(8);
    if (c != 0) {
      put(c, 1, 8);
      continue;
    }
    if (b.read(1) == 0) {
      final n = b.read(7);
      if (n == 0) return;
      put(0, n, 8);
    } else {
      final run = b.read(7);
      put(b.read(8), run, 8);
    }
  }
}
