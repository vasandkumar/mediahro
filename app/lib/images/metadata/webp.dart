import 'dart:convert';
import 'dart:typed_data';

import 'package:mediahro/images/metadata/bytes.dart';

final class WebpChunk {
  const WebpChunk(this.type, this.start, this.dataStart, this.dataLength);

  final String type;

  /// Offset of the FourCC.
  final int start;
  final int dataStart;
  final int dataLength;

  int get end => dataStart + dataLength + (dataLength.isOdd ? 1 : 0);
}

/// RIFF WebP chunk list with EXIF / XMP / ICCP access and a rewriter that
/// converts a simple file to the extended layout when metadata is added.
final class WebpFile {
  WebpFile._(this.bytes, this.chunks);

  factory WebpFile.parse(Uint8List bytes) {
    if (bytes.length < 20 ||
        String.fromCharCodes(bytes.sublist(0, 4)) != 'RIFF' ||
        String.fromCharCodes(bytes.sublist(8, 12)) != 'WEBP') {
      throw const MetadataFormatException('not a WebP');
    }
    final v = ByteView(bytes, bigEndian: false);
    final chunks = <WebpChunk>[];
    var p = 12;
    while (p + 8 <= bytes.length && chunks.length < 100000) {
      final len = v.u32(p + 4);
      final c = WebpChunk(v.fourCC(p), p, p + 8, len);
      if (c.dataStart + len > bytes.length) {
        // A truncated last chunk: keep what is there.
        break;
      }
      chunks.add(c);
      p = c.end;
    }
    return WebpFile._(bytes, chunks);
  }

  final Uint8List bytes;
  final List<WebpChunk> chunks;

  WebpChunk? _first(String type) {
    for (final c in chunks) {
      if (c.type == type) return c;
    }
    return null;
  }

  Uint8List _data(WebpChunk c) =>
      Uint8List.sublistView(bytes, c.dataStart, c.dataStart + c.dataLength);

  bool get isAnimated => _first('ANIM') != null;

  bool get hasAlpha {
    final x = _first('VP8X');
    if (x != null && x.dataLength >= 1) return bytes[x.dataStart] & 0x10 != 0;
    if (_first('ALPH') != null) return true;
    final l = _first('VP8L');
    return l != null &&
        l.dataLength >= 5 &&
        (bytes[l.dataStart + 4] >> 4) & 1 == 1;
  }

  /// Canvas size from VP8X, or the bitstream header of a simple file.
  (int, int) get size {
    final v = ByteView(bytes, bigEndian: false);
    final x = _first('VP8X');
    if (x != null && x.dataLength >= 10) {
      final d = x.dataStart;
      final w = (bytes[d + 4] | (bytes[d + 5] << 8) | (bytes[d + 6] << 16)) + 1;
      final h = (bytes[d + 7] | (bytes[d + 8] << 8) | (bytes[d + 9] << 16)) + 1;
      return (w, h);
    }
    final l = _first('VP8L');
    if (l != null && l.dataLength >= 5 && bytes[l.dataStart] == 0x2F) {
      final b = l.dataStart + 1;
      final w = (bytes[b] | ((bytes[b + 1] & 0x3F) << 8)) + 1;
      final h =
          ((bytes[b + 1] >> 6) |
              (bytes[b + 2] << 2) |
              ((bytes[b + 3] & 0x0F) << 10)) +
          1;
      return (w, h);
    }
    final k = _first('VP8 ');
    if (k != null && k.dataLength >= 10) {
      final b = k.dataStart + 6;
      if (bytes[b - 3] == 0x9D &&
          bytes[b - 2] == 0x01 &&
          bytes[b - 1] == 0x2A) {
        return (v.u16(b) & 0x3FFF, v.u16(b + 2) & 0x3FFF);
      }
    }
    return (0, 0);
  }

  /// The TIFF block of the EXIF chunk (an optional "Exif\0\0" prefix removed).
  Uint8List? get exif {
    final c = _first('EXIF');
    if (c == null) return null;
    final d = _data(c);
    if (d.length > 6 && d[0] == 0x45 && d[1] == 0x78 && d[2] == 0x69) {
      return Uint8List.sublistView(d, 6);
    }
    return d;
  }

  String? get xmp {
    final c = _first('XMP ');
    return c == null ? null : utf8.decode(_data(c), allowMalformed: true);
  }

  Uint8List? get icc {
    final c = _first('ICCP');
    return c == null ? null : _data(c);
  }

  static void _writeChunk(BytesBuilder out, String type, List<int> data) {
    final s = ByteSink(bigEndian: false)
      ..ascii(type)
      ..u32(data.length)
      ..bytes(data);
    if (data.length.isOdd) s.u8(0);
    out.add(s.take());
  }

  /// A copy with EXIF / XMP replaced or removed. Simple files (bare VP8 or
  /// VP8L) gain a VP8X header when anything is added.
  Uint8List rewrite({Patch<Uint8List>? exif, Patch<String>? xmp}) {
    final newExif = exif != null ? exif.value : this.exif;
    final newXmp = xmp != null ? xmp.value : this.xmp;
    final (w, h) = size;
    final old = _first('VP8X');
    var flags = old != null && old.dataLength >= 1 ? bytes[old.dataStart] : 0;
    flags &= ~0x0C; // exif, xmp
    if (newExif != null) flags |= 0x08;
    if (newXmp != null) flags |= 0x04;
    if (old == null) {
      if (_first('ICCP') != null) flags |= 0x20;
      if (hasAlpha) flags |= 0x10;
      if (isAnimated) flags |= 0x02;
    }
    final body = BytesBuilder(copy: false);
    final head = ByteSink(bigEndian: false)
      ..u8(flags)
      ..bytes(const [0, 0, 0])
      ..u8((w - 1) & 0xFF)
      ..u8(((w - 1) >> 8) & 0xFF)
      ..u8(((w - 1) >> 16) & 0xFF)
      ..u8((h - 1) & 0xFF)
      ..u8(((h - 1) >> 8) & 0xFF)
      ..u8(((h - 1) >> 16) & 0xFF);
    var vp8x = head.take();
    if (old != null && old.dataLength >= 10) {
      // Keep the canvas bytes the file already had.
      vp8x = Uint8List.fromList(_data(old))..[0] = flags;
    }
    _writeChunk(body, 'VP8X', vp8x);
    for (final t in const ['ICCP', 'ANIM']) {
      final c = _first(t);
      if (c != null) body.add(Uint8List.sublistView(bytes, c.start, c.end));
    }
    const lead = {'VP8X', 'ICCP', 'ANIM', 'EXIF', 'XMP '};
    for (final c in chunks) {
      if (lead.contains(c.type)) continue;
      body.add(Uint8List.sublistView(bytes, c.start, c.end));
    }
    if (newExif != null) _writeChunk(body, 'EXIF', newExif);
    if (newXmp != null) _writeChunk(body, 'XMP ', utf8.encode(newXmp));
    final payload = body.takeBytes();
    final out = ByteSink(bigEndian: false)
      ..ascii('RIFF')
      ..u32(payload.length + 4)
      ..ascii('WEBP')
      ..bytes(payload);
    return out.take();
  }
}
