import 'dart:convert';
import 'dart:io' show zlib;
import 'dart:typed_data';

import 'package:mediahro/images/metadata/bytes.dart';

const _signature = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
const _xmpKeyword = 'XML:com.adobe.xmp';
const _maxChunks = 100000;
const _textChunks = {'tEXt', 'zTXt', 'iTXt', 'tIME'};

final class PngChunk {
  const PngChunk(this.type, this.start, this.dataStart, this.dataLength);

  final String type;

  /// Offset of the length field.
  final int start;
  final int dataStart;
  final int dataLength;

  int get end => dataStart + dataLength + 4;
}

/// PNG chunk list with the metadata chunks (eXIf, iTXt XMP, iCCP) decoded and
/// a rewriter that touches only those chunks.
final class PngFile {
  PngFile._(this.bytes, this.chunks, this.width, this.height);

  factory PngFile.parse(Uint8List bytes) {
    for (var i = 0; i < 8; i++) {
      if (bytes.length < 8 || bytes[i] != _signature[i]) {
        throw const MetadataFormatException('not a PNG');
      }
    }
    final v = ByteView(bytes);
    final chunks = <PngChunk>[];
    var p = 8;
    var w = 0;
    var h = 0;
    while (p + 12 <= bytes.length && chunks.length < _maxChunks) {
      final len = v.u32(p);
      if (len > 0x7FFFFFFF || p + 12 + len > bytes.length) break;
      final type = v.fourCC(p + 4);
      chunks.add(PngChunk(type, p, p + 8, len));
      if (type == 'IHDR' && len >= 8) {
        w = v.u32(p + 8);
        h = v.u32(p + 12);
      }
      p += 12 + len;
      if (type == 'IEND') break;
    }
    return PngFile._(bytes, chunks, w, h);
  }

  final Uint8List bytes;
  final List<PngChunk> chunks;
  final int width;
  final int height;

  PngChunk? _first(String type) {
    for (final c in chunks) {
      if (c.type == type) return c;
    }
    return null;
  }

  Uint8List _data(PngChunk c) =>
      Uint8List.sublistView(bytes, c.dataStart, c.dataStart + c.dataLength);

  bool get isAnimated => _first('acTL') != null;

  /// The TIFF block of the eXIf chunk.
  Uint8List? get exif {
    final c = _first('eXIf');
    return c == null ? null : _data(c);
  }

  bool _isXmp(PngChunk c) {
    if (c.type != 'iTXt') return false;
    final d = _data(c);
    if (d.length <= _xmpKeyword.length) return false;
    for (var i = 0; i < _xmpKeyword.length; i++) {
      if (d[i] != _xmpKeyword.codeUnitAt(i)) return false;
    }
    return d[_xmpKeyword.length] == 0;
  }

  String? get xmp {
    for (final c in chunks) {
      if (!_isXmp(c)) continue;
      final d = _data(c);
      var p = _xmpKeyword.length + 1;
      if (p + 2 > d.length) return null;
      final compressed = d[p] == 1;
      p += 2; // flag + method
      // language tag and translated keyword, both NUL-terminated
      for (var i = 0; i < 2; i++) {
        while (p < d.length && d[p] != 0) {
          p++;
        }
        p++;
      }
      if (p > d.length) return null;
      final text = Uint8List.sublistView(d, p);
      return utf8.decode(
        compressed ? zlib.decode(text) : text,
        allowMalformed: true,
      );
    }
    return null;
  }

  /// Profile name from iCCP (the profile itself is zlib data).
  String? get iccName {
    final c = _first('iCCP');
    if (c == null) return null;
    final d = _data(c);
    final end = d.indexOf(0);
    return end <= 0 ? null : latin1.decode(d.sublist(0, end));
  }

  Uint8List? get icc {
    final c = _first('iCCP');
    if (c == null) return null;
    final d = _data(c);
    final end = d.indexOf(0);
    if (end < 0 || end + 2 > d.length) return null;
    try {
      return Uint8List.fromList(zlib.decode(Uint8List.sublistView(d, end + 2)));
    } on FormatException {
      return null;
    }
  }

  static Uint8List _chunk(String type, List<int> data) {
    final typeAndData = [...type.codeUnits, ...data];
    final s = ByteSink()
      ..u32(data.length)
      ..bytes(typeAndData)
      ..u32(crc32(typeAndData));
    return s.take();
  }

  /// A copy with the given blocks replaced or removed. New chunks go before
  /// the first IDAT. [dropText] also removes every free-text and date chunk
  /// (tEXt, zTXt, every iTXt including "Raw profile type" IPTC/EXIF dumps,
  /// and tIME), which tools use for titles, comments, GPS and authorship.
  Uint8List rewrite({
    Patch<Uint8List>? exif,
    Patch<String>? xmp,
    bool dropText = false,
  }) {
    final out = BytesBuilder(copy: false)..add(_signature);
    var emitted = false;
    void emitNew() {
      if (emitted) return;
      emitted = true;
      final e = exif?.value;
      if (e != null) out.add(_chunk('eXIf', e));
      final x = xmp?.value;
      if (x != null) {
        out.add(
          _chunk('iTXt', [
            ..._xmpKeyword.codeUnits,
            0, // keyword end
            0, // not compressed
            0, // method
            0, // empty language tag
            0, // empty translated keyword
            ...utf8.encode(x),
          ]),
        );
      }
    }

    for (final c in chunks) {
      if (c.type == 'IDAT' || c.type == 'IEND') emitNew();
      if (exif != null && c.type == 'eXIf') continue;
      if (xmp != null && _isXmp(c)) continue;
      if (dropText && _textChunks.contains(c.type)) continue;
      out.add(Uint8List.sublistView(bytes, c.start, c.end));
    }
    emitNew();
    if (chunks.isNotEmpty) {
      final tail = chunks.last.end;
      if (tail < bytes.length) out.add(Uint8List.sublistView(bytes, tail));
    }
    return out.takeBytes();
  }
}
