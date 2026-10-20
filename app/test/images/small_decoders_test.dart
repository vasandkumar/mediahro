import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mediahro/images/pipeline/pixel_codec.dart';
import 'package:mediahro/images/pipeline/small_decoders.dart';

Uint8List u8(List<int> l) => Uint8List.fromList(l);

List<int> u32be(int v) => [v >> 24, (v >> 16) & 255, (v >> 8) & 255, v & 255];
List<int> u16be(int v) => [v >> 8, v & 255];
List<int> u32le(int v) => [v & 255, (v >> 8) & 255, (v >> 16) & 255, v >> 24];
List<int> u16le(int v) => [v & 255, v >> 8];

List<int> px(PixelFrame f, int i) => f.rgba.sublist(i * 4, i * 4 + 4);

void main() {
  group('IMG-001 QOI', () {
    List<int> qoi(int w, int h, List<int> chunks) => [
      ...'qoif'.codeUnits,
      ...u32be(w),
      ...u32be(h),
      4,
      0,
      ...chunks,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      1,
    ];

    test('IMG-001 RGB, RGBA and run chunks', () {
      final f = decodeQoi(
        u8(qoi(2, 2, [0xFE, 255, 0, 0, 0xC1, 0xFF, 0, 255, 0, 128])),
      );
      expect((f.width, f.height), (2, 2));
      expect(px(f, 0), [255, 0, 0, 255]);
      expect(px(f, 1), [255, 0, 0, 255]);
      expect(px(f, 2), [255, 0, 0, 255]);
      expect(px(f, 3), [0, 255, 0, 128]);
    });

    test('IMG-001 diff, luma and index chunks', () {
      final f = decodeQoi(
        u8(qoi(2, 2, [0xFE, 100, 100, 100, 0x79, 0xAA, 0xB6, 0x11])),
      );
      expect(px(f, 0), [100, 100, 100, 255]);
      expect(px(f, 1), [101, 100, 99, 255]);
      expect(px(f, 2), [114, 110, 107, 255]);
      expect(px(f, 3), [
        100,
        100,
        100,
        255,
      ], reason: 'index of the first pixel');
    });

    test('IMG-001 truncated and oversized files are rejected', () {
      expect(
        () => decodeQoi(u8(qoi(1000, 1000, [0xFE, 1, 2, 3]).sublist(0, 20))),
        throwsA(isA<CodecUnsupported>()),
      );
      expect(
        () => decodeQoi(u8(qoi(70000, 70000, const []))),
        throwsA(isA<CodecUnsupported>()),
      );
      expect(() => decodeQoi(u8([1, 2, 3])), throwsA(isA<CodecUnsupported>()));
    });
  });

  group('IMG-001 TGA', () {
    List<int> header(int type, int w, int h, int bpp, {int desc = 0}) => [
      0, 0, type, 0, 0, 0, 0, 0, 0, 0, 0, 0, //
      ...u16le(w), ...u16le(h), bpp, desc,
    ];

    test('IMG-001 24-bit truecolour, bottom-left origin', () {
      final f = decodeTga(
        u8([...header(2, 2, 2, 24), 0, 0, 255, 0, 255, 0, 255, 0, 0, 0, 0, 0]),
      );
      // Rows are stored bottom first: the first stored row is the bottom one.
      expect(px(f, 2), [255, 0, 0, 255]);
      expect(px(f, 3), [0, 255, 0, 255]);
      expect(px(f, 0), [0, 0, 255, 255]);
    });

    test('IMG-001 top-left origin and 32-bit alpha', () {
      final f = decodeTga(
        u8([...header(2, 1, 1, 32, desc: 0x28), 10, 20, 30, 40]),
      );
      expect(px(f, 0), [30, 20, 10, 40]);
    });

    test('IMG-001 RLE runs expand', () {
      final f = decodeTga(u8([...header(10, 4, 1, 24), 0x83, 255, 0, 0]));
      for (var i = 0; i < 4; i++) {
        expect(px(f, i), [0, 0, 255, 255]);
      }
    });

    test('IMG-001 8-bit grey', () {
      final f = decodeTga(u8([...header(3, 2, 1, 8), 10, 200]));
      expect(px(f, 1), [200, 200, 200, 255]);
    });

    test('IMG-001 colour-mapped', () {
      final b = [
        0, 1, 1, ...u16le(0), ...u16le(2), 24, 0, 0, 0, 0, //
        ...u16le(2), ...u16le(1), 8, 0,
        0, 0, 255, 0, 255, 0, // palette: red, green (BGR)
        1, 0,
      ];
      final f = decodeTga(u8(b));
      expect(px(f, 0), [0, 255, 0, 255]);
      expect(px(f, 1), [255, 0, 0, 255]);
    });

    test('IMG-001 a short file is a typed error', () {
      expect(
        () => decodeTga(u8([...header(2, 100, 100, 24), 1, 2, 3])),
        throwsA(isA<CodecUnsupported>()),
      );
    });
  });

  group('IMG-001 PNM', () {
    test('IMG-001 P3 ASCII with comments', () {
      final f = decodePnm(
        u8('P3\n# a comment\n2 1\n255\n255 0 0  0 255 0\n'.codeUnits),
      );
      expect(px(f, 0), [255, 0, 0, 255]);
      expect(px(f, 1), [0, 255, 0, 255]);
    });

    test('IMG-001 P6 binary', () {
      final f = decodePnm(u8([...'P6 2 1 255\n'.codeUnits, 1, 2, 3, 4, 5, 6]));
      expect(px(f, 1), [4, 5, 6, 255]);
    });

    test('IMG-001 P5 16-bit grey scales to 8 bits', () {
      final f = decodePnm(
        u8([...'P5 2 1 65535\n'.codeUnits, ...u16be(0), ...u16be(65535)]),
      );
      expect(px(f, 0)[0], 0);
      expect(px(f, 1)[0], 255);
    });

    test('IMG-001 P1 and P4 bitmaps: 1 is black', () {
      final a = decodePnm(u8('P1\n3 1\n101\n'.codeUnits));
      expect([for (var i = 0; i < 3; i++) px(a, i)[0]], [0, 255, 0]);
      final b = decodePnm(u8([...'P4\n3 1\n'.codeUnits, 0xA0]));
      expect([for (var i = 0; i < 3; i++) px(b, i)[0]], [0, 255, 0]);
    });

    test('IMG-001 a bad header is a typed error', () {
      expect(
        () => decodePnm(u8('P9 1 1'.codeUnits)),
        throwsA(isA<CodecUnsupported>()),
      );
      expect(
        () => decodePnm(u8('P3\nx'.codeUnits)),
        throwsA(isA<CodecUnsupported>()),
      );
    });
  });

  group('IMG-001 PSD', () {
    List<int> psd(int w, int h, int channels, int mode, List<int> image) => [
      ...'8BPS'.codeUnits, ...u16be(1), 0, 0, 0, 0, 0, 0, //
      ...u16be(channels), ...u32be(h), ...u32be(w), ...u16be(8), ...u16be(mode),
      ...u32be(0), ...u32be(0), ...u32be(0), // colour data, resources, layers
      ...image,
    ];

    test('IMG-001 raw RGB composite', () {
      final f = decodePsd(
        u8(psd(2, 1, 3, 3, [...u16be(0), 255, 0, 0, 255, 0, 0])),
      );
      expect(px(f, 0), [255, 0, 0, 255]);
      expect(px(f, 1), [0, 255, 0, 255]);
    });

    test('IMG-001 RLE composite with alpha', () {
      // Three rows (R, G, A) of two bytes: literal runs of 2 → 3 bytes each.
      final f = decodePsd(
        u8(
          psd(2, 1, 4, 3, [
            ...u16be(1),
            ...u16be(3), ...u16be(3), ...u16be(3), ...u16be(2),
            1, 255, 0, //
            1, 0, 255,
            1, 0, 0,
            0xFF, 128, // run of 2 → alpha 128 128
          ]),
        ),
      );
      expect(px(f, 0), [255, 0, 0, 128]);
      expect(px(f, 1), [0, 255, 0, 128]);
    });

    test('IMG-001 grey and indexed', () {
      final g = decodePsd(u8(psd(2, 1, 1, 1, [...u16be(0), 10, 200])));
      expect(px(g, 1), [200, 200, 200, 255]);
      final palette = [
        ...List<int>.filled(256, 7), //
        ...List<int>.filled(256, 8),
        ...List<int>.filled(256, 9),
      ];
      final raw = psd(1, 1, 1, 2, [...u16be(0), 3]);
      // Insert the palette as colour-mode data.
      final withPalette = [
        ...raw.sublist(0, 26),
        ...u32be(768),
        ...palette,
        ...raw.sublist(30),
      ];
      expect(px(decodePsd(u8(withPalette)), 0), [7, 8, 9, 255]);
    });

    test('IMG-001 unsupported depth and garbage are typed errors', () {
      final b = psd(1, 1, 3, 3, [...u16be(0), 1, 2, 3]);
      b[22] = 0;
      b[23] = 32;
      expect(() => decodePsd(u8(b)), throwsA(isA<CodecUnsupported>()));
      expect(() => decodePsd(u8([0, 1, 2])), throwsA(isA<CodecUnsupported>()));
    });
  });

  group('IMG-001 DDS', () {
    List<int> dds(
      int w,
      int h, {
      required int flags,
      required String fourCC,
      required List<int> data,
      int bits = 0,
      List<int> masks = const [0, 0, 0, 0],
    }) {
      final head = Uint8List(128);
      final v = ByteData.sublistView(head)
        ..setUint32(0, 0x20534444, Endian.little)
        ..setUint32(4, 124, Endian.little)
        ..setUint32(12, h, Endian.little)
        ..setUint32(16, w, Endian.little)
        ..setUint32(76, 32, Endian.little)
        ..setUint32(80, flags, Endian.little)
        ..setUint32(88, bits, Endian.little)
        ..setUint32(92, masks[0], Endian.little)
        ..setUint32(96, masks[1], Endian.little)
        ..setUint32(100, masks[2], Endian.little)
        ..setUint32(104, masks[3], Endian.little);
      head.setRange(
        84,
        88,
        fourCC.codeUnits.isEmpty ? [0, 0, 0, 0] : fourCC.codeUnits,
      );
      expect(v.lengthInBytes, 128);
      return [...head, ...data];
    }

    test('IMG-001 DXT1 solid colour block', () {
      final f = decodeDds(
        u8(
          dds(
            4,
            4,
            flags: 4,
            fourCC: 'DXT1',
            data: [...u16le(0xF800), ...u16le(0x001F), 0, 0, 0, 0],
          ),
        ),
      );
      for (var i = 0; i < 16; i++) {
        expect(px(f, i), [255, 0, 0, 255]);
      }
    });

    test('IMG-001 DXT1 three-colour mode has transparent index 3', () {
      final f = decodeDds(
        u8(
          dds(
            4,
            4,
            flags: 4,
            fourCC: 'DXT1',
            data: [...u16le(0x001F), ...u16le(0xF800), 3, 0, 0, 0],
          ),
        ),
      );
      expect(px(f, 0)[3], 0);
      expect(px(f, 1), [0, 0, 255, 255]);
    });

    test('IMG-001 DXT5 alpha', () {
      final f = decodeDds(
        u8(
          dds(
            4,
            4,
            flags: 4,
            fourCC: 'DXT5',
            data: [
              255,
              0,
              0,
              0,
              0,
              0,
              0,
              0,
              ...u16le(0xF800),
              ...u16le(0xF800),
              0,
              0,
              0,
              0,
            ],
          ),
        ),
      );
      expect(px(f, 0), [255, 0, 0, 255]);
    });

    test('IMG-001 DXT3 explicit alpha', () {
      final f = decodeDds(
        u8(
          dds(
            4,
            4,
            flags: 4,
            fourCC: 'DXT3',
            data: [
              0xFF,
              0xFF,
              ...List.filled(6, 0xFF),
              ...u16le(0xF800),
              ...u16le(0xF800),
              0,
              0,
              0,
              0,
            ],
          ),
        ),
      );
      expect(px(f, 0)[3], 255);
    });

    test(
      'IMG-001 uncompressed BGRA with masks, and sizes not a multiple of 4',
      () {
        final f = decodeDds(
          u8(
            dds(
              1,
              1,
              flags: 0x41,
              fourCC: '',
              bits: 32,
              masks: [0xFF0000, 0xFF00, 0xFF, 0xFF000000],
              data: [30, 20, 10, 40],
            ),
          ),
        );
        expect(px(f, 0), [10, 20, 30, 40]);
        final g = decodeDds(
          u8(dds(5, 3, flags: 4, fourCC: 'DXT1', data: List.filled(4 * 8, 0))),
        );
        expect((g.width, g.height), (5, 3));
      },
    );

    test('IMG-001 DX10 headers and unknown formats are typed errors', () {
      expect(
        () => decodeDds(
          u8(dds(4, 4, flags: 4, fourCC: 'DX10', data: List.filled(64, 0))),
        ),
        throwsA(isA<CodecUnsupported>()),
      );
      expect(() => decodeDds(u8([1, 2, 3])), throwsA(isA<CodecUnsupported>()));
    });
  });

  test(
    'PRIV-005 random garbage never throws anything but CodecUnsupported',
    () {
      final rnd = Random(3);
      final decoders = <PixelFrame Function(Uint8List)>[
        decodeQoi,
        decodeTga,
        decodePnm,
        decodePsd,
        decodeDds,
      ];
      for (final d in decoders) {
        for (var i = 0; i < 200; i++) {
          final b = Uint8List.fromList(
            List.generate(rnd.nextInt(300) + 1, (_) => rnd.nextInt(256)),
          );
          // Give some a plausible magic so the parsers go deeper.
          if (i.isEven && b.length > 4) {
            b.setRange(
              0,
              4,
              d == decodeQoi
                  ? 'qoif'.codeUnits
                  : d == decodePsd
                  ? '8BPS'.codeUnits
                  : d == decodeDds
                  ? 'DDS '.codeUnits
                  : [0x50, 0x36, 0x0A, 0x31],
            );
          }
          try {
            d(b);
          } on CodecUnsupported {
            // expected
          }
        }
      }
    },
  );
}
