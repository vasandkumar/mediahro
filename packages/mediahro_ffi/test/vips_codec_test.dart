// FFI contract tests for the libvips wrapper (IMG-001, IMG-003, IMG-004):
// they run wherever libvips can be loaded and are skipped elsewhere with the
// reason, like the other native contract tests.
import 'dart:io';
import 'dart:typed_data';

import 'package:mediahro_ffi/mediahro_ffi.dart';
import 'package:test/test.dart';

final String? _skip = NativeLibraries.isAvailable(NativeLibrary.vips)
    ? null
    : 'blocked: STATUS §3 — mediahro-deps libvips for this platform (B4)';

/// A [w]×[h] gradient: red grows left to right, green top to bottom.
VipsPixels _gradient(int w, int h) {
  final b = Uint8List(w * h * 4);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final i = (y * w + x) * 4;
      b[i] = (x * 255) ~/ (w - 1);
      b[i + 1] = (y * 255) ~/ (h - 1);
      b[i + 2] = 40;
      b[i + 3] = 255;
    }
  }
  return VipsPixels(w, h, b);
}

void main() {
  late VipsCodec vips;
  setUpAll(() {
    if (_skip == null) vips = VipsCodec.open();
  });

  test('IMG-001 PNG round-trips losslessly through encode and decode', () {
    final src = _gradient(64, 32);
    final png = vips.encode(src, VipsSaveFormat.png);
    final h = vips.header(VipsInput.bytes(png));
    expect((h.width, h.height), (64, 32));
    final back = vips.decode(VipsInput.bytes(png));
    expect(back.rgba, src.rgba);
  }, skip: _skip);

  test('IMG-001 JPEG and WebP decode close to the source', () {
    final src = _gradient(64, 32);
    for (final f in [VipsSaveFormat.jpeg, VipsSaveFormat.webp]) {
      final enc = vips.encode(src, f, quality: 95);
      final back = vips.decode(VipsInput.bytes(enc));
      expect((back.width, back.height), (64, 32));
      var worst = 0;
      for (var i = 0; i < src.rgba.length; i += 4) {
        for (var c = 0; c < 3; c++) {
          final d = (src.rgba[i + c] - back.rgba[i + c]).abs();
          if (d > worst) worst = d;
        }
      }
      expect(worst, lessThan(24), reason: '$f');
    }
  }, skip: _skip);

  test('IMG-003 thumbnails keep the aspect ratio and fit the edge', () {
    final png = vips.encode(_gradient(400, 200), VipsSaveFormat.png);
    final t = vips.thumbnail(VipsInput.bytes(png), 100);
    expect((t.width, t.height), (100, 50));
    expect(t.rgba, hasLength(100 * 50 * 4));
  }, skip: _skip);

  test('IMG-003 thumbnails never upscale', () {
    final png = vips.encode(_gradient(40, 20), VipsSaveFormat.png);
    final t = vips.thumbnail(VipsInput.bytes(png), 256);
    expect((t.width, t.height), (40, 20));
  }, skip: _skip);

  test('IMG-004 a region decodes at 1:1 and at a reduced scale', () {
    final src = _gradient(200, 100);
    final png = vips.encode(src, VipsSaveFormat.png);
    final tile = vips.decode(
      VipsInput.bytes(png),
      region: (left: 100, top: 50, width: 50, height: 25),
    );
    expect((tile.width, tile.height), (50, 25));
    // The tile's first pixel is the source pixel at (100, 50).
    const i = (50 * 200 + 100) * 4;
    expect(tile.rgba.sublist(0, 4), src.rgba.sublist(i, i + 4));
    final half = vips.decode(
      VipsInput.bytes(png),
      region: (left: 0, top: 0, width: 200, height: 100),
      scale: 0.5,
    );
    expect((half.width, half.height), (100, 50));
  }, skip: _skip);

  test('IMG-003 local files are streamed from disk (thumbnail and header)', () {
    final dir = Directory.systemTemp.createTempSync('vips-codec');
    addTearDown(() => dir.deleteSync(recursive: true));
    final f = File('${dir.path}${Platform.pathSeparator}big.png')
      ..writeAsBytesSync(vips.encode(_gradient(300, 300), VipsSaveFormat.png));
    final h = vips.header(VipsInput.file(f.path));
    expect((h.width, h.height), (300, 300));
    final t = vips.thumbnail(VipsInput.file(f.path), 60);
    expect((t.width, t.height), (60, 60));
  }, skip: _skip);

  test('IMG-001 garbage is reported, not crashed on', () {
    final junk = Uint8List.fromList(List.generate(200, (i) => i));
    expect(vips.canLoad(VipsInput.bytes(junk)), isFalse);
    expect(
      () => vips.header(VipsInput.bytes(junk)),
      throwsA(isA<VipsException>()),
    );
    expect(
      () => vips.thumbnail(VipsInput.bytes(junk), 64),
      throwsA(isA<VipsException>()),
    );
  }, skip: _skip);
}
