import 'dart:typed_data';

import 'package:mediahro/images/pipeline/pixel_codec.dart';

/// Decoders for the small formats no native library in the app covers
/// (docs/05 §5: "QOI/TGA/PNM via small decoders"; PSD flattened and DDS
/// from IMG-001), written in plain Dart with hard limits on the sizes they
/// accept. Each returns RGBA8888 or throws [CodecUnsupported].
const int _maxPixels = 120 * 1000 * 1000;

/// Rejects sizes that are zero, too big, or impossible for [dataLength]
/// bytes of input (no format here packs more than 64 pixels into a byte), so
/// a forged header cannot ask for gigabytes.
void _limit(int w, int h, int dataLength) {
  if (w <= 0 ||
      h <= 0 ||
      w > _maxPixels ||
      h > _maxPixels ||
      w * h > _maxPixels ||
      w * h > dataLength * 64) {
    throw CodecUnsupported('image size $w×$h is not supported');
  }
}

int _u16be(Uint8List b, int o) => (b[o] << 8) | b[o + 1];
int _u32be(Uint8List b, int o) =>
    (b[o] << 24) | (b[o + 1] << 16) | (b[o + 2] << 8) | b[o + 3];
int _u16le(Uint8List b, int o) => b[o] | (b[o + 1] << 8);
int _u32le(Uint8List b, int o) =>
    b[o] | (b[o + 1] << 8) | (b[o + 2] << 16) | (b[o + 3] << 24);

/// Runs [body], mapping a read past the end of the data to the typed error.
T _bounded<T>(String what, T Function() body) {
  try {
    return body();
    // Truncated or hostile data indexes past the end; that is an expected
    // input here, reported as an unsupported file.
    // ignore: avoid_catching_errors
  } on RangeError {
    throw CodecUnsupported('$what data is truncated');
  }
}

// ---------------------------------------------------------------- QOI ----

/// Quite OK Image (qoiformat.org spec).
PixelFrame decodeQoi(Uint8List b) => _bounded('QOI', () {
  if (b.length < 22 || _u32be(b, 0) != 0x716F6966) {
    throw const CodecUnsupported('not a QOI file');
  }
  final w = _u32be(b, 4);
  final h = _u32be(b, 8);
  _limit(w, h, b.length);
  final out = Uint8List(w * h * 4);
  final index = Uint8List(64 * 4);
  var r = 0;
  var g = 0;
  var bl = 0;
  var a = 255;
  var run = 0;
  var p = 14;
  final end = b.length - 8;
  for (var i = 0; i < w * h; i++) {
    if (run > 0) {
      run--;
    } else if (p < end) {
      final b1 = b[p++];
      if (b1 == 0xFE) {
        r = b[p++];
        g = b[p++];
        bl = b[p++];
      } else if (b1 == 0xFF) {
        r = b[p++];
        g = b[p++];
        bl = b[p++];
        a = b[p++];
      } else {
        switch (b1 & 0xC0) {
          case 0x00:
            final k = (b1 & 0x3F) * 4;
            r = index[k];
            g = index[k + 1];
            bl = index[k + 2];
            a = index[k + 3];
          case 0x40:
            r = (r + ((b1 >> 4) & 3) - 2) & 0xFF;
            g = (g + ((b1 >> 2) & 3) - 2) & 0xFF;
            bl = (bl + (b1 & 3) - 2) & 0xFF;
          case 0x80:
            final b2 = b[p++];
            final dg = (b1 & 0x3F) - 32;
            r = (r + dg - 8 + ((b2 >> 4) & 0x0F)) & 0xFF;
            g = (g + dg) & 0xFF;
            bl = (bl + dg - 8 + (b2 & 0x0F)) & 0xFF;
          default:
            run = b1 & 0x3F;
        }
      }
      final k = ((r * 3 + g * 5 + bl * 7 + a * 11) % 64) * 4;
      index[k] = r;
      index[k + 1] = g;
      index[k + 2] = bl;
      index[k + 3] = a;
    }
    final o = i * 4;
    out[o] = r;
    out[o + 1] = g;
    out[o + 2] = bl;
    out[o + 3] = a;
  }
  return PixelFrame(width: w, height: h, rgba: out);
});

// ---------------------------------------------------------------- TGA ----

/// Truevision TGA: colour-mapped, true-colour and grey, raw or RLE.
PixelFrame decodeTga(Uint8List b) => _bounded('TGA', () {
  if (b.length < 18) throw const CodecUnsupported('not a TGA file');
  final idLen = b[0];
  final cmapType = b[1];
  final type = b[2];
  final cmapFirst = _u16le(b, 3);
  final cmapLen = _u16le(b, 5);
  final cmapBits = b[7];
  final w = _u16le(b, 12);
  final h = _u16le(b, 14);
  final bpp = b[16];
  final desc = b[17];
  final rle = type >= 9;
  final kind = rle ? type - 8 : type;
  if (kind != 1 && kind != 2 && kind != 3) {
    throw CodecUnsupported('TGA type $type');
  }
  if (cmapType > 1 || (kind == 1 && cmapType != 1)) {
    throw const CodecUnsupported('TGA colour map');
  }
  _limit(w, h, b.length);
  var p = 18 + idLen;
  Uint8List? palette;
  if (cmapType == 1) {
    final entry = (cmapBits + 7) ~/ 8;
    palette = Uint8List(cmapLen * 4);
    for (var i = 0; i < cmapLen; i++) {
      final px = _pixel(b, p, cmapBits);
      palette.setRange(i * 4, i * 4 + 4, px);
      p += entry;
    }
  }
  final bytesPerPixel = (bpp + 7) ~/ 8;
  if (bytesPerPixel == 0 || bytesPerPixel > 4) {
    throw CodecUnsupported('TGA $bpp bits per pixel');
  }
  final out = Uint8List(w * h * 4);
  final topLeft = desc & 0x20 != 0;
  void put(int i, Uint8List px) {
    final y = i ~/ w;
    final x = i % w;
    final row = topLeft ? y : h - 1 - y;
    out.setRange((row * w + x) * 4, (row * w + x) * 4 + 4, px);
  }

  Uint8List read(int at) {
    if (kind == 1) {
      final idx = b[at] - cmapFirst;
      if (palette == null || idx < 0 || idx * 4 + 4 > palette.length) {
        return Uint8List.fromList(const [0, 0, 0, 255]);
      }
      return Uint8List.sublistView(palette, idx * 4, idx * 4 + 4);
    }
    if (kind == 3) {
      return Uint8List.fromList([b[at], b[at], b[at], 255]);
    }
    return _pixel(b, at, bpp);
  }

  var i = 0;
  while (i < w * h) {
    if (rle) {
      final head = b[p++];
      final n = (head & 0x7F) + 1;
      if (head & 0x80 != 0) {
        final px = read(p);
        p += bytesPerPixel;
        for (var k = 0; k < n && i < w * h; k++) {
          put(i++, px);
        }
      } else {
        for (var k = 0; k < n && i < w * h; k++) {
          put(i++, read(p));
          p += bytesPerPixel;
        }
      }
    } else {
      put(i++, read(p));
      p += bytesPerPixel;
    }
  }
  return PixelFrame(width: w, height: h, rgba: out);
});

/// One TGA pixel (BGR(A), or 15/16-bit 5-5-5-1) as RGBA.
Uint8List _pixel(Uint8List b, int at, int bits) {
  switch (bits) {
    case 15 || 16:
      final v = _u16le(b, at);
      int c(int x) => (x << 3) | (x >> 2);
      return Uint8List.fromList([
        c((v >> 10) & 31),
        c((v >> 5) & 31),
        c(v & 31),
        255,
      ]);
    case 24:
      return Uint8List.fromList([b[at + 2], b[at + 1], b[at], 255]);
    case 32:
      return Uint8List.fromList([b[at + 2], b[at + 1], b[at], b[at + 3]]);
    case 8:
      return Uint8List.fromList([b[at], b[at], b[at], 255]);
    default:
      throw CodecUnsupported('TGA $bits-bit pixels');
  }
}

// ---------------------------------------------------------------- PNM ----

/// Netpbm P1–P6 (bitmap, grey, RGB; ASCII and binary).
PixelFrame decodePnm(Uint8List b) => _bounded('PNM', () {
  if (b.length < 3 || b[0] != 0x50) throw const CodecUnsupported('not PNM');
  final kind = b[1] - 0x30;
  if (kind < 1 || kind > 6) throw CodecUnsupported('PNM type P$kind');
  var p = 2;
  int token() {
    // Skip whitespace and # comments.
    while (true) {
      while (p < b.length && (b[p] == 0x20 || (b[p] >= 9 && b[p] <= 13))) {
        p++;
      }
      if (p < b.length && b[p] == 0x23) {
        while (p < b.length && b[p] != 10) {
          p++;
        }
      } else {
        break;
      }
    }
    var v = 0;
    var any = false;
    while (p < b.length && b[p] >= 0x30 && b[p] <= 0x39) {
      v = v * 10 + b[p++] - 0x30;
      any = true;
    }
    if (!any) throw const CodecUnsupported('PNM header');
    return v;
  }

  final w = token();
  final h = token();
  _limit(w, h, b.length);
  final bitmap = kind == 1 || kind == 4;
  final maxval = bitmap ? 1 : token();
  if (maxval < 1 || maxval > 65535) {
    throw const CodecUnsupported('PNM maxval');
  }
  final ascii = kind <= 3;
  if (!ascii) p++; // exactly one whitespace byte after the header
  final channels = (kind == 3 || kind == 6) ? 3 : 1;
  final out = Uint8List(w * h * 4);
  int scale(int v) => bitmap ? (v == 0 ? 255 : 0) : (v * 255 ~/ maxval);
  final wide = maxval > 255;
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final o = (y * w + x) * 4;
      final v = [0, 0, 0];
      for (var c = 0; c < channels; c++) {
        int s;
        if (kind == 1) {
          // ASCII bitmaps may run the digits together ("0101").
          while (p < b.length && (b[p] == 0x20 || (b[p] >= 9 && b[p] <= 13))) {
            p++;
          }
          s = b[p++] - 0x30;
        } else if (ascii) {
          s = token();
        } else if (kind == 4) {
          // Packed bits, rows padded to a byte.
          s = (b[p + x ~/ 8] >> (7 - (x % 8))) & 1;
        } else if (wide) {
          s = _u16be(b, p);
          p += 2;
        } else {
          s = b[p++];
        }
        v[c] = scale(s);
      }
      if (channels == 1) {
        v[1] = v[0];
        v[2] = v[0];
      }
      out[o] = v[0];
      out[o + 1] = v[1];
      out[o + 2] = v[2];
      out[o + 3] = 255;
    }
    if (kind == 4) p += (w + 7) ~/ 8;
  }
  return PixelFrame(width: w, height: h, rgba: out);
});

// ---------------------------------------------------------------- PSD ----

/// The flattened composite of a Photoshop PSD/PSB (the merged image Photoshop
/// stores when "Maximise compatibility" is on): RGB, grey, indexed and CMYK,
/// 8 or 16 bits, raw or RLE.
PixelFrame decodePsd(Uint8List b) => _bounded('PSD', () {
  if (b.length < 26 || _u32be(b, 0) != 0x38425053) {
    throw const CodecUnsupported('not a PSD file');
  }
  final version = _u16be(b, 4);
  if (version != 1 && version != 2) {
    throw CodecUnsupported('PSD version $version');
  }
  final channels = _u16be(b, 12);
  final h = _u32be(b, 14);
  final w = _u32be(b, 18);
  final depth = _u16be(b, 22);
  final mode = _u16be(b, 24);
  _limit(w, h, b.length);
  if (depth != 8 && depth != 16) {
    throw CodecUnsupported('PSD $depth-bit channels');
  }
  var p = 26;
  final modeLen = _u32be(b, p);
  final modeData = Uint8List.sublistView(b, p + 4, p + 4 + modeLen);
  p += 4 + modeLen;
  p += 4 + _u32be(b, p); // image resources
  if (version == 1) {
    p += 4 + _u32be(b, p); // layer and mask info
  } else {
    p += 8 + (_u32be(b, p) << 32 | _u32be(b, p + 4));
  }
  final compression = _u16be(b, p);
  p += 2;
  final bytes = depth ~/ 8;
  final plane = w * h * bytes;
  final data = Uint8List(plane * channels);
  if (compression == 0) {
    data.setRange(0, data.length, b, p);
  } else if (compression == 1) {
    final lenSize = version == 1 ? 2 : 4;
    final rows = h * channels;
    var src = p + rows * lenSize;
    var dst = 0;
    final rowBytes = w * bytes;
    for (var r = 0; r < rows; r++) {
      final len = lenSize == 2 ? _u16be(b, p + r * 2) : _u32be(b, p + r * 4);
      final end = src + len;
      var got = 0;
      while (src < end && got < rowBytes) {
        final n = b[src++];
        if (n < 128) {
          final c = n + 1;
          for (var k = 0; k < c && got < rowBytes; k++) {
            data[dst + got++] = b[src++];
          }
        } else if (n > 128) {
          final c = 257 - n;
          final v = b[src++];
          for (var k = 0; k < c && got < rowBytes; k++) {
            data[dst + got++] = v;
          }
        }
      }
      src = end;
      dst += rowBytes;
    }
  } else {
    throw const CodecUnsupported('PSD with ZIP-compressed composite');
  }
  // Planar → 8-bit sample (the high byte of 16-bit channels).
  int sample(int c, int i) => data[c * plane + i * bytes];
  final out = Uint8List(w * h * 4);
  for (var i = 0; i < w * h; i++) {
    final o = i * 4;
    switch (mode) {
      case 1: // grey
        final v = sample(0, i);
        out[o] = v;
        out[o + 1] = v;
        out[o + 2] = v;
        out[o + 3] = channels > 1 ? sample(1, i) : 255;
      case 2: // indexed
        final k = sample(0, i);
        if (modeData.length >= 768) {
          out[o] = modeData[k];
          out[o + 1] = modeData[256 + k];
          out[o + 2] = modeData[512 + k];
        }
        out[o + 3] = 255;
      case 3: // RGB
        if (channels < 3) throw const CodecUnsupported('PSD channels');
        out[o] = sample(0, i);
        out[o + 1] = sample(1, i);
        out[o + 2] = sample(2, i);
        out[o + 3] = channels > 3 ? sample(3, i) : 255;
      case 4: // CMYK, stored inverted
        if (channels < 4) throw const CodecUnsupported('PSD channels');
        final k = sample(3, i);
        out[o] = sample(0, i) * k ~/ 255;
        out[o + 1] = sample(1, i) * k ~/ 255;
        out[o + 2] = sample(2, i) * k ~/ 255;
        out[o + 3] = channels > 4 ? sample(4, i) : 255;
      default:
        throw CodecUnsupported('PSD colour mode $mode');
    }
  }
  return PixelFrame(width: w, height: h, rgba: out);
});

// ---------------------------------------------------------------- DDS ----

/// DirectDraw Surface: uncompressed RGB(A) and BC1/BC2/BC3 (DXT1/3/5), top
/// mip level only.
PixelFrame decodeDds(Uint8List b) => _bounded('DDS', () {
  if (b.length < 128 || _u32le(b, 0) != 0x20534444) {
    throw const CodecUnsupported('not a DDS file');
  }
  final h = _u32le(b, 12);
  final w = _u32le(b, 16);
  _limit(w, h, b.length);
  final pfFlags = _u32le(b, 80);
  final fourCC = String.fromCharCodes(b.sublist(84, 88));
  final bits = _u32le(b, 88);
  var p = 128;
  final out = Uint8List(w * h * 4);
  if (pfFlags & 0x4 != 0) {
    if (fourCC == 'DX10') {
      throw const CodecUnsupported('DDS with a DX10 header');
    }
    final bc = switch (fourCC) {
      'DXT1' => 1,
      'DXT3' => 2,
      'DXT5' => 3,
      _ => throw CodecUnsupported('DDS format $fourCC'),
    };
    final blockSize = bc == 1 ? 8 : 16;
    for (var by = 0; by < (h + 3) ~/ 4; by++) {
      for (var bx = 0; bx < (w + 3) ~/ 4; bx++) {
        final block = _bcBlock(b, p, bc);
        p += blockSize;
        for (var y = 0; y < 4; y++) {
          for (var x = 0; x < 4; x++) {
            final px = bx * 4 + x;
            final py = by * 4 + y;
            if (px >= w || py >= h) continue;
            out.setRange(
              (py * w + px) * 4,
              (py * w + px) * 4 + 4,
              block,
              (y * 4 + x) * 4,
            );
          }
        }
      }
    }
  } else if (pfFlags & 0x40 != 0 && (bits == 32 || bits == 24)) {
    final rMask = _u32le(b, 92);
    final gMask = _u32le(b, 96);
    final bMask = _u32le(b, 100);
    final aMask = _u32le(b, 104);
    final bpp = bits ~/ 8;
    int channel(int v, int mask) {
      if (mask == 0) return 255;
      var shift = 0;
      while ((mask >> shift) & 1 == 0) {
        shift++;
      }
      final max = mask >> shift;
      return ((v & mask) >> shift) * 255 ~/ max;
    }

    for (var i = 0; i < w * h; i++) {
      var v = b[p] | (b[p + 1] << 8) | (b[p + 2] << 16);
      if (bpp == 4) v |= b[p + 3] << 24;
      p += bpp;
      out[i * 4] = channel(v, rMask);
      out[i * 4 + 1] = channel(v, gMask);
      out[i * 4 + 2] = channel(v, bMask);
      out[i * 4 + 3] = aMask == 0 ? 255 : channel(v, aMask);
    }
  } else {
    throw const CodecUnsupported('DDS pixel format');
  }
  return PixelFrame(width: w, height: h, rgba: out);
});

int _expand565(int v) {
  final r = (v >> 11) & 31;
  final g = (v >> 5) & 63;
  final b = v & 31;
  return ((r << 3 | r >> 2) << 16) |
      ((g << 2 | g >> 4) << 8) |
      (b << 3 | b >> 2);
}

/// One 4×4 block as 16 RGBA pixels.
Uint8List _bcBlock(Uint8List b, int at, int bc) {
  final out = Uint8List(64);
  final colourAt = bc == 1 ? at : at + 8;
  final c0 = _u16le(b, colourAt);
  final c1 = _u16le(b, colourAt + 2);
  final e0 = _expand565(c0);
  final e1 = _expand565(c1);
  List<int> rgb(int e) => [(e >> 16) & 255, (e >> 8) & 255, e & 255];
  final p0 = rgb(e0);
  final p1 = rgb(e1);
  final palette = <List<int>>[p0, p1];
  final fourColour = bc != 1 || c0 > c1;
  if (fourColour) {
    palette
      ..add([for (var i = 0; i < 3; i++) (2 * p0[i] + p1[i]) ~/ 3])
      ..add([for (var i = 0; i < 3; i++) (p0[i] + 2 * p1[i]) ~/ 3]);
  } else {
    palette
      ..add([for (var i = 0; i < 3; i++) (p0[i] + p1[i]) ~/ 2])
      ..add(const [0, 0, 0]);
  }
  final bitsC = _u32le(b, colourAt + 4);
  // Alpha.
  final alpha = Uint8List(16)..fillRange(0, 16, 255);
  if (bc == 2) {
    for (var i = 0; i < 16; i++) {
      final v = (b[at + i ~/ 2] >> (4 * (i % 2))) & 15;
      alpha[i] = v * 17;
    }
  } else if (bc == 3) {
    final a0 = b[at];
    final a1 = b[at + 1];
    final table = <int>[a0, a1];
    if (a0 > a1) {
      for (var i = 1; i <= 6; i++) {
        table.add(((7 - i) * a0 + i * a1) ~/ 7);
      }
    } else {
      for (var i = 1; i <= 4; i++) {
        table.add(((5 - i) * a0 + i * a1) ~/ 5);
      }
      table
        ..add(0)
        ..add(255);
    }
    var bitsA = 0;
    for (var i = 0; i < 6; i++) {
      bitsA |= b[at + 2 + i] << (8 * i);
    }
    for (var i = 0; i < 16; i++) {
      alpha[i] = table[(bitsA >> (3 * i)) & 7];
    }
  }
  for (var i = 0; i < 16; i++) {
    final idx = (bitsC >> (2 * i)) & 3;
    final c = palette[idx];
    out[i * 4] = c[0];
    out[i * 4 + 1] = c[1];
    out[i * 4 + 2] = c[2];
    out[i * 4 + 3] = (bc == 1 && !fourColour && idx == 3) ? 0 : alpha[i];
  }
  return out;
}
