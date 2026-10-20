import 'dart:convert';
import 'dart:typed_data';

import 'package:mediahro/images/metadata/bytes.dart';

/// One ISO base media file box.
final class IsoBox {
  const IsoBox(this.type, this.start, this.headerLength, this.end);

  final String type;
  final int start;
  final int headerLength;
  final int end;

  int get dataStart => start + headerLength;
}

/// Reads the boxes in [from, to) of [bytes]. Stops at the first malformed
/// header; a size of 0 means "to the end of the enclosing range".
List<IsoBox> readIsoBoxes(Uint8List bytes, int from, int to) {
  final v = ByteView(bytes);
  final out = <IsoBox>[];
  var p = from;
  while (p + 8 <= to && out.length < 10000) {
    var size = v.u32(p);
    final type = v.fourCC(p + 4);
    var header = 8;
    if (size == 1) {
      if (p + 16 > to) break;
      size = v.u64(p + 8);
      header = 16;
    } else if (size == 0) {
      size = to - p;
    }
    if (type == 'uuid') header += 16;
    if (size < header || p + size > to) break;
    out.add(IsoBox(type, p, header, p + size));
    p += size;
  }
  return out;
}

/// One entry of the iloc box.
final class IsoItem {
  IsoItem(this.id, this.type);

  final int id;
  final String type;
  String contentType = '';

  /// 0 = file offset, 1 = idat, 2 = item offset.
  int constructionMethod = 0;
  int baseOffset = 0;

  /// (offset, length) pairs, offsets relative to [baseOffset].
  final List<(int, int)> extents = [];

  /// Position in the file of the single extent's offset and length fields,
  /// so the extent can be retargeted without moving any other byte.
  int? offsetFieldAt;
  int? lengthFieldAt;
  int offsetFieldSize = 0;
  int lengthFieldSize = 0;
}

/// HEIC / AVIF (and other HEIF) structure: items, dimensions, and the
/// Exif / XMP items. Writes retarget the existing items to data appended at
/// the end of the file, so no other offset moves (MakerNote-style safe).
final class IsoFile {
  IsoFile._(this.bytes, this.top, this.brand);

  factory IsoFile.parse(Uint8List bytes) {
    final top = readIsoBoxes(bytes, 0, bytes.length);
    if (top.isEmpty || top.first.type != 'ftyp') {
      throw const MetadataFormatException('not an ISO base media file');
    }
    final brand = ByteView(bytes).fourCC(top.first.dataStart);
    final f = IsoFile._(bytes, top, brand);
    for (final b in top) {
      if (b.type == 'meta') f._parseMeta(b);
    }
    return f;
  }

  final Uint8List bytes;
  final List<IsoBox> top;
  final String brand;
  final Map<int, IsoItem> items = {};
  int? primaryId;
  IsoBox? _idat;
  final Map<int, (int, int)> _dims = {};
  final List<(int, int)> _ispe = [];
  final Map<int, List<int>> _assoc = {};

  void _parseMeta(IsoBox meta) {
    // meta is a FullBox: 4 bytes of version and flags.
    final kids = readIsoBoxes(bytes, meta.dataStart + 4, meta.end);
    final v = ByteView(bytes);
    final infe = <int, IsoItem>{};
    for (final k in kids) {
      switch (k.type) {
        case 'pitm':
          final ver = bytes[k.dataStart];
          primaryId = ver == 0
              ? v.u16(k.dataStart + 4)
              : v.u32(k.dataStart + 4);
        case 'iinf':
          _parseIinf(k, infe);
        case 'idat':
          _idat = k;
        case 'iprp':
          _parseIprp(k);
      }
    }
    for (final k in kids) {
      if (k.type == 'iloc') _parseIloc(k, infe);
    }
    items.addAll(infe);
  }

  void _parseIinf(IsoBox b, Map<int, IsoItem> out) {
    final v = ByteView(bytes);
    final ver = bytes[b.dataStart];
    final start = b.dataStart + (ver == 0 ? 6 : 8);
    for (final e in readIsoBoxes(bytes, start, b.end)) {
      if (e.type != 'infe') continue;
      final ev = bytes[e.dataStart];
      if (ev < 2) continue;
      var p = e.dataStart + 4;
      final id = ev == 2 ? v.u16(p) : v.u32(p);
      p += ev == 2 ? 2 : 4;
      p += 2; // protection index
      final type = v.fourCC(p);
      p += 4;
      final item = IsoItem(id, type);
      // name\0, then content type\0 for mime items
      while (p < e.end && bytes[p] != 0) {
        p++;
      }
      p++;
      if (type == 'mime' && p < e.end) {
        final s = p;
        while (p < e.end && bytes[p] != 0) {
          p++;
        }
        item.contentType = utf8.decode(
          bytes.sublist(s, p),
          allowMalformed: true,
        );
      }
      out[id] = item;
    }
  }

  void _parseIloc(IsoBox b, Map<int, IsoItem> infe) {
    final v = ByteView(bytes);
    var p = b.dataStart;
    final ver = bytes[p];
    p += 4;
    final sizes = v.u16(p);
    p += 2;
    final offSize = (sizes >> 12) & 0xF;
    final lenSize = (sizes >> 8) & 0xF;
    final baseSize = (sizes >> 4) & 0xF;
    final idxSize = ver >= 1 ? sizes & 0xF : 0;
    final count = ver < 2 ? v.u16(p) : v.u32(p);
    p += ver < 2 ? 2 : 4;
    int num(int size) {
      var r = 0;
      for (var i = 0; i < size; i++) {
        r = (r << 8) | bytes[p + i];
      }
      p += size;
      return r;
    }

    for (var i = 0; i < count && p < b.end; i++) {
      final id = ver < 2 ? num(2) : num(4);
      var method = 0;
      if (ver >= 1) method = num(2) & 0xF;
      num(2); // data reference index
      final base = num(baseSize);
      final extentCount = num(2);
      final item = infe[id] ?? IsoItem(id, '');
      infe[id] = item;
      item
        ..constructionMethod = method
        ..baseOffset = base;
      for (var e = 0; e < extentCount && p < b.end; e++) {
        if (ver >= 1 && idxSize > 0) num(idxSize);
        final offAt = p;
        final off = num(offSize);
        final lenAt = p;
        final len = num(lenSize);
        item.extents.add((off, len));
        if (extentCount == 1) {
          item
            ..offsetFieldAt = offAt
            ..lengthFieldAt = lenAt
            ..offsetFieldSize = offSize
            ..lengthFieldSize = lenSize;
        }
      }
    }
  }

  void _parseIprp(IsoBox b) {
    final v = ByteView(bytes);
    for (final k in readIsoBoxes(bytes, b.dataStart, b.end)) {
      if (k.type == 'ipco') {
        for (final p in readIsoBoxes(bytes, k.dataStart, k.end)) {
          if (p.type == 'ispe' && p.end - p.dataStart >= 12) {
            _ispe.add((v.u32(p.dataStart + 4), v.u32(p.dataStart + 8)));
          } else {
            _ispe.add((0, 0)); // keeps property indexes aligned
          }
        }
      } else if (k.type == 'ipma') {
        var p = k.dataStart;
        final ver = bytes[p];
        final flags = (bytes[p + 1] << 16) | (bytes[p + 2] << 8) | bytes[p + 3];
        p += 4;
        final n = v.u32(p);
        p += 4;
        for (var i = 0; i < n && p < k.end; i++) {
          final id = ver < 1 ? v.u16(p) : v.u32(p);
          p += ver < 1 ? 2 : 4;
          final c = bytes[p++];
          final list = <int>[];
          for (var a = 0; a < c; a++) {
            if (flags & 1 != 0) {
              list.add(v.u16(p) & 0x7FFF);
              p += 2;
            } else {
              list.add(bytes[p++] & 0x7F);
            }
          }
          _assoc[id] = list;
        }
      }
    }
    for (final e in _assoc.entries) {
      for (final idx in e.value) {
        if (idx >= 1 && idx <= _ispe.length && _ispe[idx - 1].$1 > 0) {
          _dims[e.key] = _ispe[idx - 1];
        }
      }
    }
  }

  /// Pixel size of the primary item (ispe), or (0, 0).
  (int, int) get size {
    final id = primaryId;
    if (id != null && _dims[id] != null) return _dims[id]!;
    return _dims.values.firstOrNull ?? (0, 0);
  }

  IsoItem? _byType(String type, {String? contentType}) {
    for (final i in items.values) {
      if (i.type == type &&
          (contentType == null || i.contentType == contentType)) {
        return i;
      }
    }
    return null;
  }

  Uint8List? _read(IsoItem item) {
    if (item.extents.isEmpty) return null;
    final b = BytesBuilder(copy: false);
    for (final (off, len) in item.extents) {
      int at;
      if (item.constructionMethod == 0) {
        at = item.baseOffset + off;
      } else if (item.constructionMethod == 1 && _idat != null) {
        at = _idat!.dataStart + item.baseOffset + off;
      } else {
        return null;
      }
      if (at < 0 || len < 0 || at + len > bytes.length) return null;
      b.add(Uint8List.sublistView(bytes, at, at + len));
    }
    return b.takeBytes();
  }

  /// The TIFF block of the Exif item.
  Uint8List? get exif {
    final item = _byType('Exif');
    final d = item == null ? null : _read(item);
    if (d == null || d.length < 8) return null;
    final skip = ByteView(d).u32(0);
    if (4 + skip >= d.length) return null;
    return Uint8List.sublistView(d, 4 + skip);
  }

  String? get xmp {
    final item = _byType('mime', contentType: 'application/rdf+xml');
    final d = item == null ? null : _read(item);
    return d == null ? null : utf8.decode(d, allowMalformed: true);
  }

  /// Whether the item can be retargeted in place (single extent, 4-byte
  /// capable offset and length fields).
  bool _patchable(IsoItem i) =>
      i.constructionMethod == 0 &&
      i.offsetFieldAt != null &&
      i.lengthFieldAt != null &&
      i.offsetFieldSize >= 4 &&
      i.lengthFieldSize >= 4 &&
      i.baseOffset == 0;

  /// True when an Exif edit can be written into this file.
  bool get canWriteExif {
    final i = _byType('Exif');
    return i != null && _patchable(i);
  }

  bool get hasXmpItem =>
      _byType('mime', contentType: 'application/rdf+xml') != null;

  bool get canWriteXmp {
    final i = _byType('mime', contentType: 'application/rdf+xml');
    return i != null && _patchable(i);
  }

  /// Returns the file with the Exif and XMP items pointing at new data
  /// appended in a trailing `mdat`, or null when an edit does not fit
  /// (no such item, extents not patchable): the caller falls back to a sidecar.
  Uint8List? rewrite({Uint8List? exif, String? xmp}) {
    final jobs = <(IsoItem, List<int>)>[];
    if (exif != null) {
      final item = _byType('Exif');
      if (item == null || !_patchable(item)) return null;
      jobs.add((item, [0, 0, 0, 0, ...exif]));
    }
    if (xmp != null) {
      final item = _byType('mime', contentType: 'application/rdf+xml');
      if (item == null || !_patchable(item)) return null;
      jobs.add((item, utf8.encode(xmp)));
    }
    if (jobs.isEmpty) return bytes;
    final out = Uint8List.fromList(bytes);
    var total = 0;
    for (final (_, d) in jobs) {
      total += d.length;
    }
    final tail = ByteSink()
      ..u32(8 + total)
      ..ascii('mdat');
    var at = bytes.length + 8;
    for (final (item, d) in jobs) {
      _putSized(out, item.offsetFieldAt!, item.offsetFieldSize, at);
      _putSized(out, item.lengthFieldAt!, item.lengthFieldSize, d.length);
      tail.bytes(d);
      at += d.length;
    }
    return (BytesBuilder(copy: false)
          ..add(out)
          ..add(tail.take()))
        .takeBytes();
  }

  static void _putSized(Uint8List b, int at, int size, int value) {
    var v = value;
    for (var i = size - 1; i >= 0; i--) {
      b[at + i] = v & 0xFF;
      v >>= 8;
    }
  }
}

/// JPEG XL container (ISO box layout) metadata: Exif and xml boxes.
final class JxlFile {
  JxlFile._(this.bytes, this.boxes, this.isContainer);

  factory JxlFile.parse(Uint8List bytes) {
    final isContainer =
        bytes.length >= 12 &&
        Iterable<int>.generate(12).every((i) => bytes[i] == _signature[i]);
    if (!isContainer &&
        !(bytes.length >= 2 && bytes[0] == 0xFF && bytes[1] == 0x0A)) {
      throw const MetadataFormatException('not a JPEG XL file');
    }
    return JxlFile._(
      bytes,
      isContainer ? readIsoBoxes(bytes, 0, bytes.length) : const [],
      isContainer,
    );
  }

  static const _signature = [
    0, 0, 0, 0x0C, 0x4A, 0x58, 0x4C, 0x20, 0x0D, 0x0A, 0x87, 0x0A, //
  ];

  final Uint8List bytes;
  final List<IsoBox> boxes;
  final bool isContainer;

  IsoBox? _box(String t) {
    for (final b in boxes) {
      if (b.type == t) return b;
    }
    return null;
  }

  /// TIFF block of the Exif box (4-byte offset prefix honoured).
  Uint8List? get exif {
    final b = _box('Exif');
    if (b == null || b.end - b.dataStart < 8) return null;
    final skip = ByteView(bytes).u32(b.dataStart);
    final at = b.dataStart + 4 + skip;
    return at >= b.end ? null : Uint8List.sublistView(bytes, at, b.end);
  }

  String? get xmp {
    final b = _box('xml ');
    return b == null
        ? null
        : utf8.decode(
            Uint8List.sublistView(bytes, b.dataStart, b.end),
            allowMalformed: true,
          );
  }

  static Uint8List _box1(String type, List<int> data) {
    final s = ByteSink()
      ..u32(8 + data.length)
      ..ascii(type)
      ..bytes(data);
    return s.take();
  }

  /// A container with Exif / xml replaced or removed; a bare codestream is
  /// wrapped first.
  Uint8List rewrite({Patch<Uint8List>? exif, Patch<String>? xmp}) {
    final out = BytesBuilder(copy: false);
    if (!isContainer) {
      out
        ..add(_signature)
        ..add(
          _box1('ftyp', [...'jxl '.codeUnits, 0, 0, 0, 0, ...'jxl '.codeUnits]),
        )
        ..add(_box1('jxlc', bytes));
    } else {
      for (final b in boxes) {
        if (exif != null && b.type == 'Exif') continue;
        if (xmp != null && b.type == 'xml ') continue;
        out.add(Uint8List.sublistView(bytes, b.start, b.end));
      }
    }
    final e = exif?.value;
    if (e != null) out.add(_box1('Exif', [0, 0, 0, 0, ...e]));
    final x = xmp?.value;
    if (x != null) out.add(_box1('xml ', utf8.encode(x)));
    return out.takeBytes();
  }
}
