import 'dart:typed_data';

import 'package:mediahro_engine/src/api/subtitle_image.dart';
import 'package:mediahro_engine/src/mpv/subtitle_image/matroska.dart';
import 'package:mediahro_engine/src/mpv/subtitle_image/pixels.dart';

/// Blu-ray PGS (`S_HDMV/PGS`) bitmap subtitles as Matroska stores them: each
/// packet is the segments of one display set, without the `PG` file header.
///
/// Objects and palettes persist through an epoch, so a display set that
/// only updates the palette redraws the objects it had.
Iterable<SubtitleImage> decodePgs(
  Iterable<MkvBlock> blocks, {
  int maxImages = maxSubtitleImages,
}) sync* {
  var emitted = 0;
  final palettes = <int, List<int>>{}; // id -> RGBA by entry
  final objects = <int, _Object>{};
  final pending = <int, _Partial>{};
  _Composition? comp;
  SubtitleImage? shown;

  for (final block in blocks) {
    final d = block.data;
    var p = 0;
    while (p + 3 <= d.length) {
      final type = d[p];
      final len = (d[p + 1] << 8) | d[p + 2];
      p += 3;
      if (p + len > d.length) break;
      final body = ByteData.sublistView(d, p, p + len);
      switch (type) {
        case 0x16: // presentation composition
          comp = _parseComposition(body);
          if (comp != null && comp.epochStart) {
            palettes.clear();
            objects.clear();
            pending.clear();
          }
        case 0x14: // palette definition
          _parsePalette(body, palettes, comp?.height ?? 1080);
        case 0x15: // object definition
          _parseObject(body, objects, pending);
        case 0x80: // end of the display set
          final c = comp;
          comp = null;
          if (c == null) break;
          // Whatever was on screen ends here.
          final s = shown;
          shown = null;
          if (s != null) {
            emitted++;
            yield s.end > block.pts ? s.withEnd(block.pts) : s;
          }
          if (emitted >= maxImages) return;
          shown = c.refs.isEmpty ? null : _compose(c, objects, palettes, block);
        default:
          break;
      }
      p += len;
    }
  }
  if (shown != null) yield shown;
}

final class _Object {
  _Object(this.width, this.height, this.pixels);
  final int width;
  final int height;
  final Uint8List pixels;
}

// An object spread over several definition segments.
final class _Partial {
  _Partial(this.width, this.height, this.expected);
  final int width;
  final int height;
  final int expected;
  final data = BytesBuilder(copy: false);
}

final class _Ref {
  const _Ref(this.id, this.x, this.y, this.crop);
  final int id;
  final int x;
  final int y;
  final ({int x, int y, int w, int h})? crop;
}

final class _Composition {
  const _Composition({
    required this.width,
    required this.height,
    required this.epochStart,
    required this.paletteId,
    required this.refs,
  });
  final int width;
  final int height;
  final bool epochStart;
  final int paletteId;
  final List<_Ref> refs;
}

_Composition? _parseComposition(ByteData b) {
  if (b.lengthInBytes < 11) return null;
  final width = b.getUint16(0);
  final height = b.getUint16(2);
  final state = b.getUint8(7);
  final paletteId = b.getUint8(9);
  final count = b.getUint8(10);
  final refs = <_Ref>[];
  var p = 11;
  for (var i = 0; i < count; i++) {
    if (p + 8 > b.lengthInBytes) break;
    final id = b.getUint16(p);
    final cropped = b.getUint8(p + 3) & 0x80 != 0;
    final x = b.getUint16(p + 4);
    final y = b.getUint16(p + 6);
    p += 8;
    ({int x, int y, int w, int h})? crop;
    if (cropped) {
      if (p + 8 > b.lengthInBytes) break;
      crop = (
        x: b.getUint16(p),
        y: b.getUint16(p + 2),
        w: b.getUint16(p + 4),
        h: b.getUint16(p + 6),
      );
      p += 8;
    }
    refs.add(_Ref(id, x, y, crop));
  }
  return _Composition(
    width: width,
    height: height,
    epochStart: state & 0x80 != 0,
    paletteId: paletteId,
    refs: refs,
  );
}

void _parsePalette(ByteData b, Map<int, List<int>> palettes, int height) {
  if (b.lengthInBytes < 2) return;
  final id = b.getUint8(0);
  final table = palettes[id] ?? List<int>.filled(256, 0);
  for (var p = 2; p + 5 <= b.lengthInBytes; p += 5) {
    final entry = b.getUint8(p);
    table[entry] = yCrCbToRgba(
      b.getUint8(p + 1),
      b.getUint8(p + 2),
      b.getUint8(p + 3),
      b.getUint8(p + 4),
      hd: height >= 720,
    );
  }
  palettes[id] = table;
}

void _parseObject(
  ByteData b,
  Map<int, _Object> objects,
  Map<int, _Partial> pending,
) {
  if (b.lengthInBytes < 4) return;
  final id = b.getUint16(0);
  final flags = b.getUint8(3);
  final first = flags & 0x80 != 0;
  final last = flags & 0x40 != 0;
  var p = 4;
  _Partial? part;
  if (first) {
    if (b.lengthInBytes < 11) return;
    final total = (b.getUint8(4) << 16) | b.getUint16(5);
    final w = b.getUint16(7);
    final h = b.getUint16(9);
    p = 11;
    if (w == 0 || h == 0 || w * h > maxSubtitlePixels) return;
    part = pending[id] = _Partial(w, h, total);
  } else {
    part = pending[id];
  }
  if (part == null) return;
  if (part.data.length + (b.lengthInBytes - p) > maxSubtitleRle) {
    pending.remove(id);
    return;
  }
  part.data.add(b.buffer.asUint8List(b.offsetInBytes + p, b.lengthInBytes - p));
  if (last) {
    pending.remove(id);
    objects[id] = _Object(
      part.width,
      part.height,
      _decodeRle(part.data.takeBytes(), part.width, part.height),
    );
  }
}

// PGS run-length coding: a colour byte is one pixel; a zero starts a run
// code (end of line, short or long run of colour 0 or of a given colour).
Uint8List _decodeRle(Uint8List d, int w, int h) {
  final px = Uint8List(w * h);
  var x = 0;
  var y = 0;
  var p = 0;
  while (p < d.length && y < h) {
    final c = d[p++];
    if (c != 0) {
      if (x < w) px[y * w + x++] = c;
      continue;
    }
    if (p >= d.length) break;
    final f = d[p++];
    if (f == 0) {
      x = 0;
      y++;
      continue;
    }
    int run;
    var color = 0;
    switch (f >> 6) {
      case 0:
        run = f & 0x3F;
      case 1:
        if (p >= d.length) return px;
        run = ((f & 0x3F) << 8) | d[p++];
      case 2:
        if (p >= d.length) return px;
        run = f & 0x3F;
        color = d[p++];
      default:
        if (p + 1 >= d.length) return px;
        run = ((f & 0x3F) << 8) | d[p++];
        color = d[p++];
    }
    for (var i = 0; i < run && x < w; i++) {
      px[y * w + x++] = color;
    }
  }
  return px;
}

SubtitleImage? _compose(
  _Composition c,
  Map<int, _Object> objects,
  Map<int, List<int>> palettes,
  MkvBlock block,
) {
  final palette = palettes[c.paletteId];
  if (palette == null) return null;
  final placed = <({_Ref ref, _Object obj, int w, int h})>[];
  for (final ref in c.refs) {
    final obj = objects[ref.id];
    if (obj == null) continue;
    final w = ref.crop?.w ?? obj.width;
    final h = ref.crop?.h ?? obj.height;
    if (w <= 0 || h <= 0) continue;
    placed.add((ref: ref, obj: obj, w: w, h: h));
  }
  if (placed.isEmpty) return null;
  var left = 1 << 30;
  var top = 1 << 30;
  var right = 0;
  var bottom = 0;
  for (final o in placed) {
    left = left < o.ref.x ? left : o.ref.x;
    top = top < o.ref.y ? top : o.ref.y;
    right = right > o.ref.x + o.w ? right : o.ref.x + o.w;
    bottom = bottom > o.ref.y + o.h ? bottom : o.ref.y + o.h;
  }
  final width = right - left;
  final height = bottom - top;
  if (width * height > maxSubtitlePixels) return null;
  final rgba = Uint8List(width * height * 4);
  for (final o in placed) {
    final cx = o.ref.crop?.x ?? 0;
    final cy = o.ref.crop?.y ?? 0;
    for (var yy = 0; yy < o.h; yy++) {
      final sy = cy + yy;
      if (sy >= o.obj.height) break;
      for (var xx = 0; xx < o.w; xx++) {
        final sx = cx + xx;
        if (sx >= o.obj.width) break;
        final color = palette[o.obj.pixels[sy * o.obj.width + sx]];
        if (color >> 24 == 0) continue;
        final at = ((o.ref.y - top + yy) * width + (o.ref.x - left + xx)) * 4;
        rgba[at] = color & 0xFF;
        rgba[at + 1] = (color >> 8) & 0xFF;
        rgba[at + 2] = (color >> 16) & 0xFF;
        rgba[at + 3] = color >> 24;
      }
    }
  }
  if (isTransparent(rgba)) return null;
  return SubtitleImage(
    start: block.pts,
    end: block.pts + (block.duration ?? defaultSubtitleDuration),
    x: left,
    y: top,
    width: width,
    height: height,
    frameWidth: c.width,
    frameHeight: c.height,
    rgba: rgba,
  );
}
