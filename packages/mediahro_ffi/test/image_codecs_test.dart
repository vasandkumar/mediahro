// FFI contract tests for the JPEG XL, AVIF and LibRaw wrappers (IMG-001,
// IMG-010): they run wherever the libraries load (the Android device batch)
// and are skipped elsewhere with the reason.
import 'dart:typed_data';

import 'package:mediahro_ffi/mediahro_ffi.dart';
import 'package:test/test.dart';

String? _skip(NativeLibrary lib) => NativeLibraries.isAvailable(lib)
    ? null
    : 'blocked: STATUS §3 — mediahro-deps lib${lib.baseName} for this '
          'platform (B4)';

Uint8List _gradient(int w, int h, {bool alpha = false}) {
  final b = Uint8List(w * h * 4);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final i = (y * w + x) * 4;
      b[i] = (x * 255) ~/ (w - 1);
      b[i + 1] = (y * 255) ~/ (h - 1);
      b[i + 2] = 90;
      b[i + 3] = alpha ? (x * 255) ~/ (w - 1) : 255;
    }
  }
  return b;
}

void main() {
  group('JPEG XL', () {
    final skip = _skip(NativeLibrary.jxl);

    test('IMG-001 a lossless encode decodes to the same pixels', () {
      final jxl = JxlCodec.open();
      final src = _gradient(64, 48);
      final bytes = jxl.encode(src, 64, 48, lossless: true);
      expect(bytes.length, greaterThan(20));
      final h = jxl.header(bytes);
      expect((h.width, h.height), (64, 48));
      expect(h.hasAlpha, isFalse);
      final img = jxl.decode(bytes);
      expect((img.width, img.height), (64, 48));
      expect(img.rgba, src);
    }, skip: skip);

    test('IMG-001 alpha survives', () {
      final jxl = JxlCodec.open();
      final src = _gradient(32, 32, alpha: true);
      final bytes = jxl.encode(src, 32, 32, lossless: true);
      expect(jxl.header(bytes).hasAlpha, isTrue);
      final img = jxl.decode(bytes);
      expect(img.rgba.sublist(3, 4), src.sublist(3, 4));
      expect(img.rgba[(31 * 32 + 31) * 4 + 3], 255);
    }, skip: skip);

    test('IMG-010 a lossy encode is smaller and close to the source', () {
      final jxl = JxlCodec.open();
      final src = _gradient(128, 96);
      final lossless = jxl.encode(src, 128, 96, lossless: true);
      final lossy = jxl.encode(src, 128, 96, quality: 80);
      expect(lossy.length, lessThan(lossless.length));
      final back = jxl.decode(lossy).rgba;
      var worst = 0;
      for (var i = 0; i < src.length; i += 4) {
        for (var c = 0; c < 3; c++) {
          final d = (src[i + c] - back[i + c]).abs();
          if (d > worst) worst = d;
        }
      }
      expect(worst, lessThan(24));
    }, skip: skip);

    test('IMG-001 garbage and truncated data raise JxlException', () {
      final jxl = JxlCodec.open();
      expect(
        () => jxl.header(Uint8List.fromList(List.generate(64, (i) => i))),
        throwsA(isA<JxlException>()),
      );
      final good = jxl.encode(_gradient(64, 64), 64, 64, lossless: true);
      expect(
        () => jxl.decode(Uint8List.sublistView(good, 0, good.length ~/ 2)),
        throwsA(isA<JxlException>()),
      );
    }, skip: skip);
  });

  group('AVIF', () {
    final skip = _skip(NativeLibrary.avif);

    test('IMG-001 libavif 1.x loads and rejects garbage cleanly', () {
      final avif = AvifCodec.open();
      expect(
        () => avif.header(Uint8List.fromList(List.generate(64, (i) => i))),
        throwsA(isA<AvifException>()),
      );
      expect(() => avif.decode(Uint8List(0)), throwsA(isA<AvifException>()));
    }, skip: skip);

    test(
      'IMG-001 an AVIF still decodes to RGBA of the header size',
      () {},
      skip:
          'blocked: B4a AV1 encoder for libavif (no AVIF sample can be made '
          'on the device until it lands; the corpus file decodes in the '
          'corpus harness)',
    );
  });

  group('LibRaw', () {
    final skip = _skip(NativeLibrary.raw);

    test('IMG-001 LibRaw loads and rejects garbage cleanly', () {
      final raw = RawCodec.open();
      final junk = Uint8List.fromList(List.generate(4096, (i) => i * 7));
      expect(() => raw.size(junk), throwsA(isA<RawException>()));
      expect(() => raw.develop(junk), throwsA(isA<RawException>()));
      expect(() => raw.thumbnail(junk), throwsA(isA<RawException>()));
    }, skip: skip);
  });
}
