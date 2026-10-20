import 'dart:collection';
import 'dart:convert';
import 'dart:typed_data';

import 'package:mediahro/images/metadata/bytes.dart';
import 'package:meta/meta.dart';

/// TIFF field types (TIFF 6.0 §2, plus IFD = 13 from TIFF-EP).
enum TiffType {
  byte(1, 1),
  ascii(2, 1),
  short(3, 2),
  long(4, 4),
  rational(5, 8),
  sbyte(6, 1),
  undefined(7, 1),
  sshort(8, 2),
  slong(9, 4),
  srational(10, 8),
  float(11, 4),
  double(12, 8),
  ifd(13, 4);

  const TiffType(this.code, this.size);
  final int code;
  final int size;

  static TiffType? of(int code) {
    for (final t in values) {
      if (t.code == code) return t;
    }
    return null;
  }
}

/// Which directory of an EXIF/TIFF structure a tag lives in.
enum IfdKind { ifd0, exif, gps, interop, ifd1 }

/// Pointer tags that link the sub-directories.
abstract final class TiffTag {
  static const exifIfd = 0x8769;
  static const gpsIfd = 0x8825;
  static const interopIfd = 0xA005;
  static const imageDescription = 0x010E;
  static const make = 0x010F;
  static const model = 0x0110;
  static const orientation = 0x0112;
  static const software = 0x0131;
  static const dateTime = 0x0132;
  static const artist = 0x013B;
  static const copyright = 0x8298;
  static const xmp = 0x02BC;
  static const iptc = 0x83BB;
  static const icc = 0x8773;
  static const rating = 0x4746;
  static const ratingPercent = 0x4749;
  static const xpTitle = 0x9C9B;
  static const xpComment = 0x9C9C;
  static const xpKeywords = 0x9C9E;
  static const xpSubject = 0x9C9F;
  static const thumbOffset = 0x0201;
  static const thumbLength = 0x0202;
  static const dateTimeOriginal = 0x9003;
  static const dateTimeDigitized = 0x9004;
  static const offsetTimeOriginal = 0x9011;
  static const subSecTimeOriginal = 0x9291;
  static const lensModel = 0xA434;
  static const lensMake = 0xA433;
  static const makerNote = 0x927C;
  static const userComment = 0x9286;
  static const cameraOwnerName = 0xA430;
  static const bodySerialNumber = 0xA431;
  static const lensSerialNumber = 0xA435;
  static const imageUniqueId = 0xA420;
  static const gpsVersion = 0x0000;
  static const gpsLatRef = 0x0001;
  static const gpsLat = 0x0002;
  static const gpsLonRef = 0x0003;
  static const gpsLon = 0x0004;
  static const gpsAltRef = 0x0005;
  static const gpsAlt = 0x0006;
  static const gpsTimeStamp = 0x0007;
  static const gpsDateStamp = 0x001D;
}

@immutable
final class TiffEntry {
  const TiffEntry(this.tag, this.type, this.count, this.raw, {this.offset});

  final int tag;
  final TiffType type;
  final int count;

  /// Value bytes in the structure's byte order.
  final Uint8List raw;

  /// Where the value lived out of line in the source, so an unchanged
  /// entry keeps pointing at it (MakerNote offsets stay valid).
  final int? offset;
}

final class TiffIfd {
  TiffIfd(this.offset);

  /// Offset of the directory in the source; -1 for a new one.
  final int offset;
  final LinkedHashMap<int, TiffEntry> entries = LinkedHashMap();
  int next = 0;
}

/// Limits for hostile files (PRIV-005).
const _maxEntries = 4096;
const _maxIfds = 64;

/// A parsed TIFF structure: an EXIF block (JPEG APP1, PNG eXIf, HEIC Exif
/// item) or a whole TIFF / TIFF-based RAW file.
final class TiffStructure {
  TiffStructure._(this.bytes, this.bigEndian, this.chain);

  final Uint8List bytes;
  final bool bigEndian;

  /// IFD0, IFD1, … (pages or thumbnail).
  final List<TiffIfd> chain;
  TiffIfd? exif;
  TiffIfd? gps;
  TiffIfd? interop;

  /// Magic 42 (TIFF), 0x4F52/0x5352 (ORF), 0x55 (RW2) are all accepted.
  static TiffStructure parse(Uint8List bytes) {
    if (bytes.length < 8) {
      throw const MetadataFormatException('TIFF header too short');
    }
    final bo = String.fromCharCodes(bytes.sublist(0, 2));
    final bigEndian = switch (bo) {
      'MM' => true,
      'II' => false,
      _ => throw const MetadataFormatException('bad TIFF byte order'),
    };
    final v = ByteView(bytes, bigEndian: bigEndian);
    final magic = v.u16(2);
    if (magic != 42 && magic != 0x4F52 && magic != 0x5352 && magic != 0x55) {
      throw MetadataFormatException('bad TIFF magic $magic');
    }
    final seen = <int>{};
    final chain = <TiffIfd>[];
    var off = v.u32(4);
    while (off != 0 && chain.length < _maxIfds && seen.add(off)) {
      final ifd = _readIfd(v, off);
      if (ifd == null) break;
      chain.add(ifd);
      off = ifd.next;
    }
    final s = TiffStructure._(bytes, bigEndian, chain);
    if (chain.isNotEmpty) {
      s
        ..exif = s._sub(v, chain.first, TiffTag.exifIfd, seen)
        ..gps = s._sub(v, chain.first, TiffTag.gpsIfd, seen);
      if (s.exif != null) {
        s.interop = s._sub(v, s.exif!, TiffTag.interopIfd, seen);
      }
    }
    return s;
  }

  TiffIfd? _sub(ByteView v, TiffIfd parent, int tag, Set<int> seen) {
    final e = parent.entries[tag];
    if (e == null || e.raw.length < 4) return null;
    final off = ByteView(e.raw, bigEndian: bigEndian).u32(0);
    if (!seen.add(off)) return null;
    return _readIfd(v, off);
  }

  static TiffIfd? _readIfd(ByteView v, int off) {
    if (off + 2 > v.length) return null;
    final n = v.u16(off);
    if (n > _maxEntries || off + 2 + n * 12 > v.length) return null;
    final ifd = TiffIfd(off);
    for (var i = 0; i < n; i++) {
      final p = off + 2 + i * 12;
      final tag = v.u16(p);
      final type = TiffType.of(v.u16(p + 2));
      final count = v.u32(p + 4);
      if (type == null) continue;
      final size = type.size * count;
      if (size > v.length) continue;
      if (size <= 4) {
        ifd.entries[tag] = TiffEntry(tag, type, count, v.slice(p + 8, size));
      } else {
        final at = v.u32(p + 8);
        if (at + size > v.length) continue;
        ifd.entries[tag] = TiffEntry(
          tag,
          type,
          count,
          v.slice(at, size),
          offset: at,
        );
      }
    }
    final nextAt = off + 2 + n * 12;
    ifd.next = nextAt + 4 <= v.length ? v.u32(nextAt) : 0;
    return ifd;
  }

  TiffIfd? ifd(IfdKind k) => switch (k) {
    IfdKind.ifd0 => chain.isEmpty ? null : chain.first,
    IfdKind.ifd1 => chain.length > 1 ? chain[1] : null,
    IfdKind.exif => exif,
    IfdKind.gps => gps,
    IfdKind.interop => interop,
  };

  TiffEntry? entry(IfdKind k, int tag) => ifd(k)?.entries[tag];

  // ---- typed value access ----

  List<int> ints(TiffEntry e) {
    final v = ByteView(e.raw, bigEndian: bigEndian);
    return [
      for (var i = 0; i < e.count && (i + 1) * e.type.size <= e.raw.length; i++)
        switch (e.type) {
          TiffType.byte || TiffType.undefined || TiffType.ascii => v.u8(i),
          TiffType.sbyte => v.u8(i).toSigned(8),
          TiffType.short => v.u16(i * 2),
          TiffType.sshort => v.i16(i * 2),
          TiffType.long || TiffType.ifd => v.u32(i * 4),
          TiffType.slong => v.i32(i * 4),
          _ => 0,
        },
    ];
  }

  List<double> doubles(TiffEntry e) {
    final v = ByteView(e.raw, bigEndian: bigEndian);
    return switch (e.type) {
      TiffType.rational || TiffType.srational => [
        for (var i = 0; i < e.count && i * 8 + 8 <= e.raw.length; i++)
          _ratio(
            e.type == TiffType.rational ? v.u32(i * 8) : v.i32(i * 8),
            e.type == TiffType.rational ? v.u32(i * 8 + 4) : v.i32(i * 8 + 4),
          ),
      ],
      TiffType.float => [
        for (var i = 0; i < e.count && i * 4 + 4 <= e.raw.length; i++)
          v.f32(i * 4),
      ],
      TiffType.double => [
        for (var i = 0; i < e.count && i * 8 + 8 <= e.raw.length; i++)
          v.f64(i * 8),
      ],
      _ => [for (final i in ints(e)) i.toDouble()],
    };
  }

  static double _ratio(int n, int d) => d == 0 ? 0 : n / d;

  String? string(IfdKind k, int tag) {
    final e = entry(k, tag);
    return e == null ? null : stringOf(e);
  }

  String stringOf(TiffEntry e) {
    if (e.tag >= 0x9C9B && e.tag <= 0x9C9F) {
      // Windows XP* tags: UCS-2 little-endian in BYTE.
      final units = <int>[
        for (var i = 0; i + 1 < e.raw.length; i += 2)
          e.raw[i] | (e.raw[i + 1] << 8),
      ];
      return String.fromCharCodes(units).replaceAll('\u0000', '').trim();
    }
    var end = e.raw.indexOf(0);
    if (end < 0) end = e.raw.length;
    final b = e.raw.sublist(0, end);
    try {
      return utf8.decode(b).trim();
    } on FormatException {
      return latin1.decode(b).trim();
    }
  }

  int? intValue(IfdKind k, int tag) {
    final e = entry(k, tag);
    if (e == null) return null;
    final v = ints(e);
    return v.isEmpty ? null : v.first;
  }

  List<double>? doublesOf(IfdKind k, int tag) {
    final e = entry(k, tag);
    return e == null ? null : doubles(e);
  }
}

/// Encodes values in [bigEndian] order for new entries.
final class TiffValues {
  TiffValues(this.bigEndian);

  final bool bigEndian;

  TiffEntry ascii(int tag, String s) {
    final b = Uint8List.fromList([...utf8.encode(s), 0]);
    return TiffEntry(tag, TiffType.ascii, b.length, b);
  }

  TiffEntry bytes(int tag, List<int> b, {TiffType type = TiffType.undefined}) =>
      TiffEntry(tag, type, b.length, Uint8List.fromList(b));

  TiffEntry shorts(int tag, List<int> v) {
    final s = ByteSink(bigEndian: bigEndian);
    v.forEach(s.u16);
    return TiffEntry(tag, TiffType.short, v.length, s.take());
  }

  TiffEntry longs(int tag, List<int> v, {TiffType type = TiffType.long}) {
    final s = ByteSink(bigEndian: bigEndian);
    v.forEach(s.u32);
    return TiffEntry(tag, type, v.length, s.take());
  }

  /// Unsigned rationals with [den] as the denominator.
  TiffEntry rationals(int tag, List<double> v, {int den = 10000}) {
    final s = ByteSink(bigEndian: bigEndian);
    for (final x in v) {
      s
        ..u32((x * den).round().clamp(0, 0xFFFFFFFF))
        ..u32(den);
    }
    return TiffEntry(tag, TiffType.rational, v.length, s.take());
  }

  /// Windows XP* tag: UCS-2 LE, NUL-terminated, type BYTE.
  TiffEntry xp(int tag, String s) {
    final b = <int>[];
    for (final c in s.codeUnits) {
      b
        ..add(c & 0xff)
        ..add(c >> 8);
    }
    b.addAll([0, 0]);
    return TiffEntry(tag, TiffType.byte, b.length, Uint8List.fromList(b));
  }
}

/// Edits a [TiffStructure] without moving any existing data: changed
/// directories and new values are appended and the header (or parent
/// pointer) is redirected. Unknown tags, MakerNotes and strip/tile data
/// keep their offsets, so nothing the editor does not understand breaks.
final class TiffEditor {
  TiffEditor(this.source) : values = TiffValues(source.bigEndian);

  /// An empty EXIF block in big-endian order.
  factory TiffEditor.empty() {
    final s = ByteSink()
      ..ascii('MM')
      ..u16(42)
      ..u32(8)
      ..u16(0)
      ..u32(0);
    return TiffEditor(TiffStructure.parse(s.take()));
  }

  final TiffStructure source;
  final TiffValues values;
  final Map<IfdKind, Map<int, TiffEntry?>> _changes = {};
  final Set<IfdKind> _dropped = {};

  bool get hasChanges => _changes.isNotEmpty || _dropped.isNotEmpty;

  void set(IfdKind k, TiffEntry e) => (_changes[k] ??= {})[e.tag] = e;
  void remove(IfdKind k, int tag) => (_changes[k] ??= {})[tag] = null;

  /// Removes a whole sub-directory (GPS on strip, for example).
  void drop(IfdKind k) {
    assert(k != IfdKind.ifd0, 'IFD0 cannot be dropped');
    _dropped.add(k);
    _changes.remove(k);
  }

  Map<int, TiffEntry> _merged(IfdKind k) {
    final base = _dropped.contains(k) ? null : source.ifd(k);
    final m = <int, TiffEntry>{...?base?.entries};
    for (final c in (_changes[k] ?? const <int, TiffEntry?>{}).entries) {
      if (c.value == null) {
        m.remove(c.key);
      } else {
        m[c.key] = c.value!;
      }
    }
    return m;
  }

  bool _touched(IfdKind k) =>
      _dropped.contains(k) || (_changes[k]?.isNotEmpty ?? false);

  /// The edited structure: the source bytes followed by appended data.
  Uint8List build() {
    if (!hasChanges) return source.bytes;
    final be = source.bigEndian;
    final out = BytesBuilder(copy: false)..add(source.bytes);
    if (out.length.isOdd) out.addByte(0);

    int append(List<int> b) {
      final at = out.length;
      out.add(b);
      if (out.length.isOdd) out.addByte(0);
      return at;
    }

    // Writes one directory after its out-of-line values; returns its offset.
    int writeIfd(Map<int, TiffEntry> entries, int next) {
      final tags = entries.keys.toList()..sort();
      final placed = <int, int>{};
      for (final t in tags) {
        final e = entries[t]!;
        if (e.raw.length > 4) placed[t] = e.offset ?? append(e.raw);
      }
      final s = ByteSink(bigEndian: be)..u16(tags.length);
      for (final t in tags) {
        final e = entries[t]!;
        s
          ..u16(t)
          ..u16(e.type.code)
          ..u32(e.count);
        if (e.raw.length > 4) {
          s.u32(placed[t]!);
        } else {
          s
            ..bytes(e.raw)
            ..bytes(List.filled(4 - e.raw.length, 0));
        }
      }
      s.u32(next);
      return append(s.take());
    }

    TiffEntry pointer(int tag, int at) => values.longs(tag, [at]);

    final exifTouched = _touched(IfdKind.exif) || _touched(IfdKind.interop);
    final gpsTouched = _touched(IfdKind.gps);
    final ifd0 = _merged(IfdKind.ifd0);

    if (_touched(IfdKind.interop) && !_dropped.contains(IfdKind.exif)) {
      final m = _merged(IfdKind.interop);
      final exif = _changes[IfdKind.exif] ??= {};
      if (m.isEmpty || _dropped.contains(IfdKind.interop)) {
        exif[TiffTag.interopIfd] = null;
      } else {
        exif[TiffTag.interopIfd] = pointer(
          TiffTag.interopIfd,
          writeIfd(m, 0),
        );
      }
    }
    if (exifTouched) {
      final m = _merged(IfdKind.exif);
      if (m.isEmpty || _dropped.contains(IfdKind.exif)) {
        ifd0.remove(TiffTag.exifIfd);
      } else {
        ifd0[TiffTag.exifIfd] = pointer(TiffTag.exifIfd, writeIfd(m, 0));
      }
    }
    if (gpsTouched) {
      final m = _merged(IfdKind.gps);
      if (m.isEmpty || _dropped.contains(IfdKind.gps)) {
        ifd0.remove(TiffTag.gpsIfd);
      } else {
        ifd0[TiffTag.gpsIfd] = pointer(TiffTag.gpsIfd, writeIfd(m, 0));
      }
    }
    var next = source.chain.isEmpty ? 0 : source.chain.first.next;
    if (_dropped.contains(IfdKind.ifd1)) {
      next = source.chain.length > 2 ? source.chain[2].offset : 0;
    }
    final ifd0At = writeIfd(ifd0, next);
    final bytes = out.takeBytes();
    putU32(bytes, 4, ifd0At, bigEndian: be);
    return bytes;
  }

  /// A fresh, compact block with every value copied (used when an EXIF
  /// block must fit a 64 KiB JPEG segment). Drops IFD1 when [dropThumbnail].
  Uint8List compact({bool dropThumbnail = false}) {
    final be = source.bigEndian;
    final s = ByteSink(bigEndian: be)
      ..ascii(be ? 'MM' : 'II')
      ..u16(42)
      ..u32(8);
    final body = BytesBuilder(copy: false)..add(s.take());

    int append(List<int> b) {
      final at = body.length;
      body.add(b);
      if (body.length.isOdd) body.addByte(0);
      return at;
    }

    int writeIfd(Map<int, TiffEntry> entries, int next) {
      final tags = entries.keys.toList()..sort();
      final placed = <int, int>{};
      for (final t in tags) {
        final e = entries[t]!;
        if (e.raw.length > 4) placed[t] = append(e.raw);
      }
      final w = ByteSink(bigEndian: be)..u16(tags.length);
      for (final t in tags) {
        final e = entries[t]!;
        w
          ..u16(t)
          ..u16(e.type.code)
          ..u32(e.count);
        if (e.raw.length > 4) {
          w.u32(placed[t]!);
        } else {
          w
            ..bytes(e.raw)
            ..bytes(List.filled(4 - e.raw.length, 0));
        }
      }
      w.u32(next);
      return append(w.take());
    }

    final ifd0 = _merged(IfdKind.ifd0)
      ..remove(TiffTag.exifIfd)
      ..remove(TiffTag.gpsIfd);
    final exif = _dropped.contains(IfdKind.exif)
        ? <int, TiffEntry>{}
        : (_merged(IfdKind.exif)..remove(TiffTag.interopIfd));
    final interop = _dropped.contains(IfdKind.interop)
        ? <int, TiffEntry>{}
        : _merged(IfdKind.interop);
    final gps = _dropped.contains(IfdKind.gps)
        ? <int, TiffEntry>{}
        : _merged(IfdKind.gps);
    if (interop.isNotEmpty && exif.isNotEmpty) {
      exif[TiffTag.interopIfd] = values.longs(TiffTag.interopIfd, [
        writeIfd(interop, 0),
      ]);
    }
    if (exif.isNotEmpty) {
      ifd0[TiffTag.exifIfd] = values.longs(TiffTag.exifIfd, [
        writeIfd(exif, 0),
      ]);
    }
    if (gps.isNotEmpty) {
      ifd0[TiffTag.gpsIfd] = values.longs(TiffTag.gpsIfd, [writeIfd(gps, 0)]);
    }
    var ifd1At = 0;
    final ifd1 = source.ifd(IfdKind.ifd1);
    if (!dropThumbnail && !_dropped.contains(IfdKind.ifd1) && ifd1 != null) {
      final m = <int, TiffEntry>{...ifd1.entries};
      final off = m[TiffTag.thumbOffset];
      final len = m[TiffTag.thumbLength];
      if (off != null && len != null) {
        final o = source.ints(off).firstOrNull ?? 0;
        final l = source.ints(len).firstOrNull ?? 0;
        if (o + l <= source.bytes.length && l > 0) {
          final at = append(source.bytes.sublist(o, o + l));
          m[TiffTag.thumbOffset] = values.longs(TiffTag.thumbOffset, [at]);
        } else {
          m
            ..remove(TiffTag.thumbOffset)
            ..remove(TiffTag.thumbLength);
        }
      }
      ifd1At = writeIfd(m, 0);
    }
    final ifd0At = writeIfd(ifd0, ifd1At);
    final bytes = body.takeBytes();
    putU32(bytes, 4, ifd0At, bigEndian: be);
    return bytes;
  }
}
