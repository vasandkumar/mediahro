import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mediahro/images/image_format.dart';
import 'package:mediahro/images/raw_preview.dart';

/// A big-endian TIFF with the given directories, each a list of
/// (tag, type, count, value) entries. Directory `i` is at `offsets[i]`.
Uint8List tiff(
  List<int> offsets,
  List<List<(int, int, int, int)>> dirs, {
  int size = 20000,
  bool chained = true,
}) {
  final b = Uint8List(size);
  final v = ByteData.sublistView(b);
  b[0] = 0x4D;
  b[1] = 0x4D;
  v
    ..setUint16(2, 42)
    ..setUint32(4, offsets.first);
  for (var i = 0; i < dirs.length; i++) {
    var p = offsets[i];
    v.setUint16(p, dirs[i].length);
    p += 2;
    for (final (tag, type, count, value) in dirs[i]) {
      v
        ..setUint16(p, tag)
        ..setUint16(p + 2, type)
        ..setUint32(p + 4, count);
      if (type == 3 && count == 1) {
        v.setUint16(p + 8, value);
      } else {
        v.setUint32(p + 8, value);
      }
      p += 12;
    }
    v.setUint32(p, chained && i + 1 < dirs.length ? offsets[i + 1] : 0);
  }
  return b;
}

void main() {
  test('IMG-001 the thumbnail IFD1 JPEG is found', () {
    final raw = tiff(
      [8, 100],
      [
        [(0x0112, 3, 1, 1)],
        [(0x0201, 4, 1, 4000), (0x0202, 4, 1, 3000)],
      ],
    );
    final p = findRawPreviews(raw, raw.length);
    expect(p.map((e) => (e.offset, e.length)), [(4000, 3000)]);
  });

  test(
    'IMG-001 DNG-style SubIFD previews are found and sorted smallest first',
    () {
      // IFD0 has SubIFDs → two directories with JPEG strips.
      final raw = tiff(
        [8, 200, 400],
        [
          [(0x014A, 4, 2, 600)],
          [(0x0103, 3, 1, 7), (0x0111, 4, 1, 8000), (0x0117, 4, 1, 90000)],
          [(0x0103, 3, 1, 7), (0x0111, 4, 1, 12000), (0x0117, 4, 1, 5000)],
        ],
        size: 200000,
        chained: false,
      );
      // The SubIFD offsets array lives at 600.
      ByteData.sublistView(raw)
        ..setUint32(600, 200)
        ..setUint32(604, 400);
      final p = findRawPreviews(raw, raw.length);
      expect(p.map((e) => e.length), [5000, 90000]);
    },
  );

  test('IMG-001 previews outside the file are ignored', () {
    final raw = tiff(
      [8],
      [
        [(0x0201, 4, 1, 19000), (0x0202, 4, 1, 50000)],
      ],
    );
    expect(findRawPreviews(raw, raw.length), isEmpty);
  });

  test('IMG-001 a Fujifilm RAF header points at its JPEG', () {
    final b = Uint8List(100000)..setRange(0, 15, 'FUJIFILMCCD-RAW'.codeUnits);
    ByteData.sublistView(b)
      ..setUint32(84, 160)
      ..setUint32(88, 70000);
    final p = findRawPreviews(b, b.length);
    expect(p.single.offset, 160);
    expect(p.single.length, 70000);
  });

  test('IMG-001 garbage is not a RAW', () {
    expect(findRawPreviews(Uint8List(2000), 2000), isEmpty);
    expect(findRawPreviews(Uint8List(3), 3), isEmpty);
  });

  test('IMG-003 thumbnails take the smallest preview that is sharp enough', () {
    const small = RawPreview(100, 8000);
    const mid = RawPreview(200, 60000);
    const big = RawPreview(300, 4000000);
    expect(previewForThumbnail([small, mid, big], 256), mid);
    expect(previewForThumbnail([small, mid, big], 512), mid);
    expect(previewForThumbnail([small], 256), small);
    expect(previewForThumbnail([], 256), isNull);
    expect(previewForThumbnail([small, big], 512), big);
  });

  test('IMG-001 an MP4 or MOV is not mistaken for a HEIC', () {
    Uint8List ftyp(String brand) => Uint8List.fromList([
      0, 0, 0, 0x18, ...'ftyp'.codeUnits, ...brand.codeUnits, 0, 0, 0, 0, //
      ...'isom'.codeUnits,
    ]);
    expect(sniffImageFormat(ftyp('isom')), ImageFormat.unknown);
    expect(sniffImageFormat(ftyp('mp42')), ImageFormat.unknown);
    expect(sniffImageFormat(ftyp('qt  ')), ImageFormat.unknown);
    expect(sniffImageFormat(ftyp('heic')), ImageFormat.heic);
    expect(sniffImageFormat(ftyp('mif1')), ImageFormat.heic);
    expect(sniffImageFormat(ftyp('avif')), ImageFormat.avif);
    expect(sniffImageFormat(ftyp('crx ')), ImageFormat.raw);
  });
}
