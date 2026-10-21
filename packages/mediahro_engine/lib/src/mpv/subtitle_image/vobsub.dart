import 'dart:typed_data';

import 'package:mediahro_engine/src/api/subtitle_image.dart';
import 'package:mediahro_engine/src/mpv/subtitle_image/matroska.dart';
import 'package:mediahro_engine/src/mpv/subtitle_image/pixels.dart';

/// The `palette:` (16 RGB colours) and `size:` lines of a VobSub `.idx`
/// header, which Matroska keeps as the track's codec private data.
({List<int> palette, int width, int height}) parseVobSubHeader(
  Uint8List? codecPrivate,
) {
  final palette = <int>[];
  var width = 720;
  var height = 576;
  if (codecPrivate != null) {
    final text = String.fromCharCodes(codecPrivate);
    for (final line in text.split(RegExp(r'\r?\n'))) {
      final l = line.trim().toLowerCase();
      if (l.startsWith('palette:')) {
        for (final part in l.substring(8).split(',')) {
          final v = int.tryParse(part.trim(), radix: 16);
          if (v == null) continue;
          // 0xRRGGBB to packed A=255, B, G, R.
          palette.add(
            0xFF000000 | ((v & 0xFF) << 16) | (v & 0xFF00) | ((v >> 16) & 0xFF),
          );
        }
      } else if (l.startsWith('size:')) {
        final m = RegExp(r'(\d+)\s*x\s*(\d+)').firstMatch(l);
        if (m != null) {
          width = int.parse(m[1]!);
          height = int.parse(m[2]!);
        }
      }
    }
  }
  // Without a palette the four pixel values read as grey.
  while (palette.length < 16) {
    final g = (palette.length * 17).clamp(0, 255);
    palette.add(0xFF000000 | (g << 16) | (g << 8) | g);
  }
  return (palette: palette, width: width, height: height);
}

/// DVD subpictures (`S_VOBSUB`): each packet is one SPU with its own
/// control sequences, so the packet's time plus the sequences' delays give
/// when the picture shows and hides.
Iterable<SubtitleImage> decodeVobSub(
  Iterable<MkvBlock> blocks,
  Uint8List? codecPrivate, {
  int maxImages = maxSubtitleImages,
}) sync* {
  final header = parseVobSubHeader(codecPrivate);
  var emitted = 0;
  for (final block in blocks) {
    if (emitted >= maxImages) return;
    final image = _decodeSpu(block, header);
    if (image != null) {
      emitted++;
      yield image;
    }
  }
}

// A delay in the control sequences is in units of 1024/90000 s.
Duration _delay(int date) => Duration(microseconds: (date << 10) * 1000 ~/ 90);

SubtitleImage? _decodeSpu(
  MkvBlock block,
  ({List<int> palette, int width, int height}) header,
) {
  final d = block.data;
  if (d.length < 6) return null;
  final size = (d[0] << 8) | d[1];
  final limit = size > 0 && size <= d.length ? size : d.length;
  var pos = (d[2] << 8) | d[3];
  var colors = 0x3210; // 4-bit indexes of the four pixel values
  var alphas = 0xFFF0;
  var x1 = 0;
  var x2 = -1;
  var y1 = 0;
  var y2 = -1;
  var top = 0;
  var bottom = 0;
  Duration? start;
  Duration? stop;
  var seen = 0;
  while (pos + 4 <= limit && seen++ < 64) {
    final date = (d[pos] << 8) | d[pos + 1];
    final next = (d[pos + 2] << 8) | d[pos + 3];
    var p = pos + 4;
    var done = false;
    while (p < limit && !done) {
      final cmd = d[p++];
      switch (cmd) {
        case 0x00: // forced display
        case 0x01: // start display
          start ??= _delay(date);
        case 0x02: // stop display
          // 0xFFFF means the end is not known.
          if (date != 0xFFFF) stop ??= _delay(date);
        case 0x03:
          if (p + 2 > limit) return null;
          colors = (d[p] << 8) | d[p + 1];
          p += 2;
        case 0x04:
          if (p + 2 > limit) return null;
          alphas = (d[p] << 8) | d[p + 1];
          p += 2;
        case 0x05:
          if (p + 6 > limit) return null;
          x1 = (d[p] << 4) | (d[p + 1] >> 4);
          x2 = ((d[p + 1] & 0xF) << 8) | d[p + 2];
          y1 = (d[p + 3] << 4) | (d[p + 4] >> 4);
          y2 = ((d[p + 4] & 0xF) << 8) | d[p + 5];
          p += 6;
        case 0x06:
          if (p + 4 > limit) return null;
          top = (d[p] << 8) | d[p + 1];
          bottom = (d[p + 2] << 8) | d[p + 3];
          p += 4;
        case 0xFF:
          done = true;
        default:
          return null;
      }
    }
    if (next == pos || next < pos) break;
    pos = next;
  }
  final w = x2 - x1 + 1;
  final h = y2 - y1 + 1;
  if (start == null || w <= 0 || h <= 0 || w * h > maxSubtitlePixels) {
    return null;
  }
  if (top >= limit || bottom >= limit) return null;
  final px = Uint8List(w * h);
  _field(d, top, bottom, w, h, 0, px);
  _field(d, bottom, limit, w, h, 1, px);
  final rgba = Uint8List(w * h * 4);
  final table = <int>[];
  for (var v = 0; v < 4; v++) {
    final c = header.palette[(colors >> (4 * v)) & 0xF];
    final a = ((alphas >> (4 * v)) & 0xF) * 17;
    table.add((a << 24) | (c & 0xFFFFFF));
  }
  for (var i = 0; i < w * h; i++) {
    final c = table[px[i]];
    rgba[i * 4] = c & 0xFF;
    rgba[i * 4 + 1] = (c >> 8) & 0xFF;
    rgba[i * 4 + 2] = (c >> 16) & 0xFF;
    rgba[i * 4 + 3] = c >> 24;
  }
  if (isTransparent(rgba)) return null;
  final from = block.pts + start;
  final until = stop != null
      ? block.pts + stop
      : from + (block.duration ?? defaultSubtitleDuration);
  return SubtitleImage(
    start: from,
    end: until > from ? until : from + defaultSubtitleDuration,
    x: x1,
    y: y1,
    width: w,
    height: h,
    frameWidth: header.width,
    frameHeight: header.height,
    rgba: rgba,
  );
}

// One field of 4-bit-nibble run lengths; [firstRow] 0 is the top field.
void _field(
  Uint8List d,
  int from,
  int to,
  int w,
  int h,
  int firstRow,
  Uint8List px,
) {
  var nib = from * 2;
  final end = to * 2;
  int next() =>
      nib < end ? (d[nib >> 1] >> ((nib++ & 1) == 0 ? 4 : 0)) & 0xF : 0;
  var x = 0;
  var y = firstRow;
  while (nib < end && y < h) {
    var v = 0;
    for (var t = 1; v < t && t <= 0x40; t <<= 2) {
      v = (v << 4) | next();
    }
    var run = v >> 2;
    final color = v & 3;
    if (run == 0 || run > w - x) run = w - x;
    for (var i = 0; i < run; i++) {
      px[y * w + x + i] = color;
    }
    x += run;
    if (x >= w) {
      x = 0;
      y += 2;
      // Each line starts on a byte.
      if (nib & 1 == 1) nib++;
    }
  }
}
