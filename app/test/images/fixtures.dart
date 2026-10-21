import 'dart:convert';
import 'dart:typed_data';

import 'package:mediahro/images/metadata/bytes.dart';
import 'package:mediahro/images/metadata/tiff.dart';

/// Synthetic image files for the metadata tests: just enough structure for
/// the container readers and writers; the pixel data is filler.

const scanData = [0x12, 0x34, 0x56, 0x78, 0x9A];

/// A TIFF/EXIF block with the camera, lens, time, GPS and orientation tags.
Uint8List sampleExif({int orientation = 6, bool bigEndian = true}) {
  final b = ByteSink(bigEndian: bigEndian)
    ..ascii(bigEndian ? 'MM' : 'II')
    ..u16(42)
    ..u32(8)
    ..u16(0)
    ..u32(0);
  final e = TiffEditor(TiffStructure.parse(b.take()));
  final v = e.values;
  e
    ..set(IfdKind.ifd0, v.ascii(TiffTag.make, 'Samsung'))
    ..set(IfdKind.ifd0, v.ascii(TiffTag.model, 'SM-M176B'))
    ..set(IfdKind.ifd0, v.shorts(TiffTag.orientation, [orientation]))
    ..set(
      IfdKind.exif,
      v.ascii(TiffTag.dateTimeOriginal, '2024:05:01 10:20:30'),
    )
    ..set(IfdKind.exif, v.ascii(TiffTag.lensModel, 'Main 5.4mm f/1.8'))
    ..set(IfdKind.exif, v.bytes(TiffTag.makerNote, List.generate(40, (i) => i)))
    ..set(IfdKind.gps, v.ascii(TiffTag.gpsLatRef, 'N'))
    ..set(IfdKind.gps, v.rationals(TiffTag.gpsLat, [12, 58, 30], den: 1))
    ..set(IfdKind.gps, v.ascii(TiffTag.gpsLonRef, 'E'))
    ..set(IfdKind.gps, v.rationals(TiffTag.gpsLon, [77, 35, 45], den: 1));
  return e.build();
}

Uint8List _seg(int marker, List<int> data) =>
    (ByteSink()
          ..u8(0xFF)
          ..u8(marker)
          ..u16(data.length + 2)
          ..bytes(data))
        .take();

/// A 4×2 baseline JPEG skeleton with a JFIF header.
Uint8List sampleJpeg({
  Uint8List? exif,
  String? xmp,
  Uint8List? photoshop,
  bool jfif = true,
  List<String> comments = const [],
  List<int> trailer = const [],
}) {
  final b = BytesBuilder()..add([0xFF, 0xD8]);
  if (jfif) {
    b.add(
      _seg(0xE0, [
        ...'JFIF'.codeUnits, 0, 1, 1, 0, 0, 1, 0, 1, 0, 0, //
      ]),
    );
  }
  if (exif != null) b.add(_seg(0xE1, [...'Exif'.codeUnits, 0, 0, ...exif]));
  if (xmp != null) {
    b.add(
      _seg(0xE1, [
        ...'http://ns.adobe.com/xap/1.0/'.codeUnits,
        0,
        ...utf8.encode(xmp),
      ]),
    );
  }
  if (photoshop != null) {
    b.add(_seg(0xED, [...'Photoshop 3.0'.codeUnits, 0, ...photoshop]));
  }
  for (final c in comments) {
    b.add(_seg(0xFE, c.codeUnits));
  }
  b
    ..add(_seg(0xDB, [0, ...List.filled(64, 8)]))
    ..add(_seg(0xC0, [8, 0, 2, 0, 4, 3, 1, 0x22, 0, 2, 0x11, 1, 3, 0x11, 1]))
    ..add(_seg(0xDA, [3, 1, 0, 2, 0x11, 3, 0x11, 0, 0x3F, 0]))
    ..add(scanData)
    ..add([0xFF, 0xD9])
    ..add(trailer);
  return b.takeBytes();
}

Uint8List _pngChunk(String type, List<int> data) {
  final td = [...type.codeUnits, ...data];
  return (ByteSink()
        ..u32(data.length)
        ..bytes(td)
        ..u32(crc32(td)))
      .take();
}

/// A 4×2 RGBA PNG skeleton.
Uint8List samplePng({
  Uint8List? exif,
  String? xmp,
  List<(String, List<int>)> extra = const [],
}) {
  final b = BytesBuilder()
    ..add([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
    ..add(
      _pngChunk(
        'IHDR',
        (ByteSink()
              ..u32(4)
              ..u32(2)
              ..bytes([8, 6, 0, 0, 0]))
            .take(),
      ),
    );
  if (exif != null) b.add(_pngChunk('eXIf', exif));
  if (xmp != null) {
    b.add(
      _pngChunk('iTXt', [
        ...'XML:com.adobe.xmp'.codeUnits,
        0,
        0,
        0,
        0,
        0,
        ...utf8.encode(xmp),
      ]),
    );
  }
  for (final (type, data) in extra) {
    b.add(_pngChunk(type, data));
  }
  b
    ..add(_pngChunk('IDAT', scanData))
    ..add(_pngChunk('IEND', const []));
  return b.takeBytes();
}

Uint8List _riff(String type, List<int> data) {
  final s = ByteSink(bigEndian: false)
    ..ascii(type)
    ..u32(data.length)
    ..bytes(data);
  if (data.length.isOdd) s.u8(0);
  return s.take();
}

/// A 4×2 lossless WebP (simple layout, no metadata) or, with [exif] / [xmp],
/// the extended layout.
Uint8List sampleWebp({Uint8List? exif, String? xmp}) {
  const bits = 3 | (1 << 14);
  final vp8l = [
    0x2F,
    bits & 0xFF,
    (bits >> 8) & 0xFF,
    (bits >> 16) & 0xFF,
    (bits >> 24) & 0xFF,
    ...scanData,
  ];
  final body = BytesBuilder();
  if (exif != null || xmp != null) {
    final flags = (exif != null ? 0x08 : 0) | (xmp != null ? 0x04 : 0);
    body.add(_riff('VP8X', [flags, 0, 0, 0, 3, 0, 0, 1, 0, 0]));
  }
  body.add(_riff('VP8L', vp8l));
  if (exif != null) body.add(_riff('EXIF', exif));
  if (xmp != null) body.add(_riff('XMP ', utf8.encode(xmp)));
  final payload = body.takeBytes();
  return (ByteSink(bigEndian: false)
        ..ascii('RIFF')
        ..u32(payload.length + 4)
        ..ascii('WEBP')
        ..bytes(payload))
      .take();
}

Uint8List _box(String type, List<int> data) =>
    (ByteSink()
          ..u32(8 + data.length)
          ..ascii(type)
          ..bytes(data))
        .take();

Uint8List _fullBox(String type, int version, List<int> data) =>
    _box(type, [version, 0, 0, 0, ...data]);

/// A HEIC skeleton: primary `hvc1` item (4×2), an Exif item, and an XMP item
/// when [xmp] is given. iloc uses 4-byte offset and length fields.
Uint8List sampleHeic({Uint8List? exif, String? xmp}) {
  Uint8List infe(int id, String type, {String name = '', String? content}) =>
      _fullBox('infe', 2, [
        id >> 8, id & 0xFF, 0, 0, //
        ...type.codeUnits, ...name.codeUnits, 0,
        if (content != null) ...[...content.codeUnits, 0],
      ]);
  final items = <(int, Uint8List)>[];
  final infes = <Uint8List>[infe(1, 'hvc1')];
  if (exif != null) {
    items.add((2, Uint8List.fromList([0, 0, 0, 0, ...exif])));
    infes.add(infe(2, 'Exif'));
  }
  if (xmp != null) {
    items.add((3, Uint8List.fromList(utf8.encode(xmp))));
    infes.add(infe(3, 'mime', content: 'application/rdf+xml'));
  }
  final ftyp = _box('ftyp', [
    ...'heic'.codeUnits,
    0,
    0,
    0,
    0,
    ...'mif1'.codeUnits,
  ]);

  Uint8List meta(List<int> offsets) {
    // item 1: no data in the skeleton (extent of length 0)
    final iloc = <int>[
      ...[0x44, 0x00, 0, items.length + 1],
      ...[0, 1, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0],
    ];
    for (var i = 0; i < items.length; i++) {
      final (id, data) = items[i];
      final o = offsets[i];
      iloc.addAll([
        id >> 8, id & 0xFF, 0, 0, 0, 1, //
        (o >> 24) & 0xFF, (o >> 16) & 0xFF, (o >> 8) & 0xFF, o & 0xFF,
        (data.length >> 24) & 0xFF, (data.length >> 16) & 0xFF,
        (data.length >> 8) & 0xFF, data.length & 0xFF,
      ]);
    }
    final ispe = _fullBox('ispe', 0, [0, 0, 0, 4, 0, 0, 0, 2]);
    return _fullBox('meta', 0, [
      ..._fullBox('pitm', 0, [0, 1]),
      ..._fullBox('iinf', 0, [0, infes.length, ...infes.expand((e) => e)]),
      ..._fullBox('iloc', 0, iloc),
      ..._box('iprp', [
        ..._box('ipco', ispe),
        ..._fullBox('ipma', 0, [0, 0, 0, 1, 0, 1, 1, 1]),
      ]),
    ]);
  }

  final metaLen = meta(List.filled(items.length, 0)).length;
  var at = ftyp.length + metaLen + 8; // after the mdat header
  final offsets = <int>[];
  for (final (_, d) in items) {
    offsets.add(at);
    at += d.length;
  }
  final mdat = _box('mdat', [for (final (_, d) in items) ...d]);
  return Uint8List.fromList([...ftyp, ...meta(offsets), ...mdat]);
}

/// A TIFF file (little-endian, 1×1) with extra IFD0 entries from [edit].
Uint8List sampleTiff({void Function(TiffEditor e)? edit}) {
  final b = ByteSink(bigEndian: false)
    ..ascii('II')
    ..u16(42)
    ..u32(8)
    ..u16(0)
    ..u32(0);
  final e = TiffEditor(TiffStructure.parse(b.take()));
  e
    ..set(IfdKind.ifd0, e.values.longs(0x0100, [1]))
    ..set(IfdKind.ifd0, e.values.longs(0x0101, [1]));
  edit?.call(e);
  return e.build();
}

String xmpDoc(String body) =>
    '<x:xmpmeta xmlns:x="adobe:ns:meta/"><rdf:RDF '
    'xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">'
    '<rdf:Description rdf:about="" '
    'xmlns:dc="http://purl.org/dc/elements/1.1/" '
    'xmlns:xmp="http://ns.adobe.com/xap/1.0/" '
    'xmlns:exif="http://ns.adobe.com/exif/1.0/" '
    'xmlns:GPano="http://ns.google.com/photos/1.0/panorama/" '
    'xmlns:hdrgm="http://ns.adobe.com/hdr-gain-map/1.0/" '
    'xmlns:GCamera="http://ns.google.com/photos/1.0/camera/" '
    'xmlns:Container="http://ns.google.com/photos/1.0/container/" '
    'xmlns:Item="http://ns.google.com/photos/1.0/container/item/">'
    '$body</rdf:Description></rdf:RDF></x:xmpmeta>';
