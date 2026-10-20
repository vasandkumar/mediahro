import 'dart:convert';
import 'dart:typed_data';

import 'package:mediahro/images/metadata/bytes.dart';

const _exifHeader = [0x45, 0x78, 0x69, 0x66, 0, 0]; // "Exif\0\0"
final Uint8List _xmpHeader = Uint8List.fromList(
  utf8.encode('http://ns.adobe.com/xap/1.0/\u0000'),
);
final List<int> _extXmpHeader = utf8.encode(
  'http://ns.adobe.com/xmp/extension/\u0000',
);
const _psHeader = [
  0x50, 0x68, 0x6F, 0x74, 0x6F, 0x73, 0x68, 0x6F, 0x70, 0x20, 0x33, 0x2E, //
  0x30, 0,
]; // "Photoshop 3.0\0"
const _iccHeader = [
  0x49,
  0x43,
  0x43,
  0x5F,
  0x50,
  0x52,
  0x4F,
  0x46,
  0x49,
  0x4C,
  0x45,
  0,
]; // "ICC_PROFILE\0"
const _mpfHeader = [0x4D, 0x50, 0x46, 0]; // "MPF\0"

/// Largest payload of one marker segment (the length field counts itself).
const jpegMaxSegmentData = 65533;

/// One marker segment before the scan data.
final class JpegSegment {
  const JpegSegment(this.marker, this.start, this.dataStart, this.end);

  /// The byte after 0xFF.
  final int marker;

  /// Offset of the 0xFF byte.
  final int start;

  /// First payload byte (after the length field).
  final int dataStart;

  /// One past the last byte of the segment.
  final int end;

  int get dataLength => end - dataStart;
}

/// The header part of a JPEG file: every marker segment up to the first scan.
/// Everything from [scanStart] on (entropy data, further images such as
/// an MPF gain map, a trailing Motion Photo video) is never touched.
final class JpegFile {
  JpegFile._(
    this.bytes,
    this.segments,
    this.scanStart,
    this.width,
    this.height,
  );

  /// Throws [MetadataFormatException] for anything that is not a JPEG.
  factory JpegFile.parse(Uint8List bytes) {
    if (bytes.length < 4 || bytes[0] != 0xFF || bytes[1] != 0xD8) {
      throw const MetadataFormatException('not a JPEG');
    }
    final segments = <JpegSegment>[];
    var p = 2;
    var scanStart = bytes.length;
    var width = 0;
    var height = 0;
    while (p + 1 < bytes.length) {
      if (bytes[p] != 0xFF) {
        // Garbage between segments: stop at what we have.
        scanStart = p;
        break;
      }
      final m = bytes[p + 1];
      if (m == 0xFF) {
        p++; // fill byte
        continue;
      }
      if (m == 0xD9 || m == 0xDA) {
        scanStart = p;
        break;
      }
      if (m == 0x01 || (m >= 0xD0 && m <= 0xD8)) {
        p += 2;
        continue;
      }
      if (p + 4 > bytes.length) {
        scanStart = p;
        break;
      }
      final len = (bytes[p + 2] << 8) | bytes[p + 3];
      if (len < 2 || p + 2 + len > bytes.length) {
        throw const MetadataFormatException('truncated JPEG segment');
      }
      final seg = JpegSegment(m, p, p + 4, p + 2 + len);
      segments.add(seg);
      if (m >= 0xC0 && m <= 0xCF && m != 0xC4 && m != 0xC8 && m != 0xCC) {
        if (seg.dataLength >= 5) {
          height = (bytes[seg.dataStart + 1] << 8) | bytes[seg.dataStart + 2];
          width = (bytes[seg.dataStart + 3] << 8) | bytes[seg.dataStart + 4];
        }
      }
      p += 2 + len;
    }
    return JpegFile._(bytes, segments, scanStart, width, height);
  }

  final Uint8List bytes;
  final List<JpegSegment> segments;

  /// Offset of the SOS (or EOI) marker.
  final int scanStart;
  final int width;
  final int height;

  bool _starts(JpegSegment s, List<int> header) {
    if (s.dataLength < header.length) return false;
    for (var i = 0; i < header.length; i++) {
      if (bytes[s.dataStart + i] != header[i]) return false;
    }
    return true;
  }

  JpegSegment? _find(int marker, List<int> header) {
    for (final s in segments) {
      if (s.marker == marker && _starts(s, header)) return s;
    }
    return null;
  }

  /// The TIFF block of the first Exif APP1.
  Uint8List? get exif {
    final s = _find(0xE1, _exifHeader);
    return s == null
        ? null
        : Uint8List.sublistView(bytes, s.dataStart + 6, s.end);
  }

  /// The standard XMP packet (extended XMP is ignored).
  String? get xmp {
    final s = _find(0xE1, _xmpHeader);
    if (s == null) return null;
    return utf8.decode(
      Uint8List.sublistView(bytes, s.dataStart + _xmpHeader.length, s.end),
      allowMalformed: true,
    );
  }

  /// The Photoshop image-resource block of APP13 (IPTC lives in it).
  Uint8List? get photoshop {
    final s = _find(0xED, _psHeader);
    return s == null
        ? null
        : Uint8List.sublistView(bytes, s.dataStart + _psHeader.length, s.end);
  }

  /// The ICC profile, reassembled from its APP2 chunks.
  Uint8List? get icc {
    final chunks = <int, Uint8List>{};
    for (final s in segments) {
      if (s.marker == 0xE2 && _starts(s, _iccHeader) && s.dataLength > 14) {
        chunks[bytes[s.dataStart + 12]] = Uint8List.sublistView(
          bytes,
          s.dataStart + 14,
          s.end,
        );
      }
    }
    if (chunks.isEmpty) return null;
    final b = BytesBuilder(copy: false);
    for (final k in chunks.keys.toList()..sort()) {
      b.add(chunks[k]!);
    }
    return b.takeBytes();
  }

  /// A Multi-Picture Format directory is present (Ultra HDR / gain map files
  /// carry the secondary image after the primary one).
  bool get hasMpf => _find(0xE2, _mpfHeader) != null;

  /// An extended-XMP segment exists (its content is not read).
  bool get hasExtendedXmp => _find(0xE1, _extXmpHeader) != null;

  /// A copy with the given blocks replaced or removed; the scan data and
  /// everything after it is copied untouched.
  ///
  /// Throws [MetadataFormatException] when a block does not fit one segment.
  Uint8List rewrite({
    Patch<Uint8List>? exif,
    Patch<String>? xmp,
    Patch<Uint8List>? photoshop,
  }) {
    final out = BytesBuilder(copy: false)..add(const [0xFF, 0xD8]);

    void put(int marker, List<int> header, List<int> data) {
      final len = header.length + data.length;
      if (len > jpegMaxSegmentData) {
        throw const MetadataFormatException(
          'metadata block too large for JPEG',
        );
      }
      out
        ..add([0xFF, marker, (len + 2) >> 8, (len + 2) & 0xFF])
        ..add(header)
        ..add(data);
    }

    bool drop(JpegSegment s) =>
        (exif != null && s.marker == 0xE1 && _starts(s, _exifHeader)) ||
        (xmp != null &&
            s.marker == 0xE1 &&
            (_starts(s, _xmpHeader) || _starts(s, _extXmpHeader))) ||
        (photoshop != null && s.marker == 0xED && _starts(s, _psHeader));

    void emitNew() {
      final e = exif?.value;
      if (e != null) put(0xE1, _exifHeader, e);
      final x = xmp?.value;
      if (x != null) put(0xE1, _xmpHeader, utf8.encode(x));
      final ps = photoshop?.value;
      if (ps != null) put(0xED, _psHeader, ps);
    }

    // JFIF stays first when present; the new blocks follow it.
    var emitted = false;
    for (final s in segments) {
      if (drop(s)) continue;
      out.add(Uint8List.sublistView(bytes, s.start, s.end));
      if (!emitted && s.marker == 0xE0) {
        emitNew();
        emitted = true;
      }
    }
    if (!emitted) {
      // No JFIF: new blocks lead, so Exif is right after SOI.
      final rest = out.takeBytes();
      out.add(const [0xFF, 0xD8]);
      emitNew();
      out.add(Uint8List.sublistView(rest, 2));
    }
    out.add(Uint8List.sublistView(bytes, scanStart));
    return out.takeBytes();
  }
}
