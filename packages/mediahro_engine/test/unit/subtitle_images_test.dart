import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mediahro_engine/mediahro_engine.dart';
import 'package:mediahro_engine/src/mpv/subtitle_image/matroska.dart';
import 'package:mediahro_engine/src/mpv/subtitle_image/subtitle_images.dart';
import 'package:mediahro_engine/testing.dart';

// A Matroska writer for the pieces mpv's dump-cache emits.
List<int> _idBytes(int id) => [
  for (var s = 24; s >= 0; s -= 8)
    if (id >> s != 0) (id >> s) & 0xFF,
];

List<int> _el(int id, List<int> body) => [
  ..._idBytes(id),
  0x01,
  for (var s = 48; s >= 0; s -= 8) (body.length >> s) & 0xFF,
  ...body,
];

List<int> _uint(int id, int v) =>
    _el(id, [for (var s = 24; s >= 0; s -= 8) (v >> s) & 0xFF]);

List<int> _mkv({
  required String codecId,
  required List<(int pts, List<int> data)> packets,
  List<int> codecPrivate = const [],
  int scale = 1000000,
  bool group = false,
  int clusterAt = 0,
}) => [
  ..._el(0x1A45DFA3, const []),
  ..._el(0x18538067, [
    ..._el(0x1549A966, _uint(0x2AD7B1, scale)),
    ..._el(0x1654AE6B, [
      ..._el(0xAE, [
        ..._uint(0xD7, 3),
        ..._el(0x86, codecId.codeUnits),
        if (codecPrivate.isNotEmpty) ..._el(0x63A2, codecPrivate),
      ]),
    ]),
    ..._el(0x1F43B675, [
      ..._uint(0xE7, clusterAt),
      for (final (pts, data) in packets) ...[
        if (group)
          ..._el(0xA0, [
            ..._el(0xA1, [
              0x83,
              (pts - clusterAt) >> 8,
              (pts - clusterAt) & 0xFF,
              0,
              ...data,
            ]),
            ..._uint(0x9B, 1500),
          ])
        else
          ..._el(0xA3, [
            0x83,
            (pts - clusterAt) >> 8,
            (pts - clusterAt) & 0xFF,
            0x80,
            ...data,
          ]),
      ],
    ]),
  ]),
];

List<int> _u16(int v) => [(v >> 8) & 0xFF, v & 0xFF];

// PGS segments of one display set.
List<int> _seg(int type, List<int> payload) => [
  type,
  ..._u16(payload.length),
  ...payload,
];

// Colour 1 white, colour 2 black at the given alpha, 0 transparent.
List<int> _pgsPalette(int alpha) => _seg(0x14, [
  0, 0, 1, 235, 128, 128, 255, 2, 16, 128, 128, alpha, //
]);

// 4×2: [1 1 2 0] / [0 2 2 1], rows coded with single pixels and a run.
final _pgsRle = [
  1, 1, 2, 0x00, 0x01, 0x00, 0x00, //
  0x00, 0x01, 0x00, 0x82, 2, 1, 0x00, 0x00,
];

List<int> _pgsShow({
  required int x,
  required int y,
  int number = 0,
  int alpha = 255,
}) => [
  ..._seg(0x16, [
    ..._u16(640), ..._u16(360), 0x10, ..._u16(number), 0x80, 0, 0, 1, //
    ..._u16(0), 0, 0x00, ..._u16(x), ..._u16(y),
  ]),
  ..._seg(0x17, [1, 0, ..._u16(x), ..._u16(y), ..._u16(4), ..._u16(2)]),
  ..._pgsPalette(alpha),
  ..._seg(0x15, [
    ..._u16(0),
    0,
    0xC0,
    0,
    ..._u16(_pgsRle.length + 4),
    ..._u16(4),
    ..._u16(2),
    ..._pgsRle,
  ]),
  ..._seg(0x80, const []),
];

List<int> _pgsClear({int number = 1}) => [
  ..._seg(0x16, [
    ..._u16(640),
    ..._u16(360),
    0x10,
    ..._u16(number),
    0,
    0,
    0,
    0,
  ]),
  ..._seg(0x80, const []),
];

Uint8List _bytes(List<int> v) => Uint8List.fromList(v);

void main() {
  group('SUB-051 Matroska packets', () {
    test('SUB-051 reads tracks, cluster times and simple blocks', () {
      final f = MatroskaFile.parse(
        _bytes(
          _mkv(
            codecId: 'S_HDMV/PGS',
            packets: [
              (1500, [1, 2, 3]),
              (2500, [4]),
            ],
            clusterAt: 1000,
          ),
        ),
      );
      expect(f.tracks.single.codecId, 'S_HDMV/PGS');
      expect(f.tracks.single.number, 3);
      expect([for (final b in f.blocks) b.pts.inMilliseconds], [1500, 2500]);
      expect(f.blocks.first.data, [1, 2, 3]);
    });

    test('SUB-051 block groups keep their duration; unlaced only', () {
      final f = MatroskaFile.parse(
        _bytes(
          _mkv(
            codecId: 'S_VOBSUB',
            packets: [
              (10, [7, 7]),
            ],
            group: true,
            codecPrivate: 'palette: 000000'.codeUnits,
          ),
        ),
      );
      expect(f.blocks.single.duration, const Duration(milliseconds: 1500));
      expect(
        String.fromCharCodes(f.tracks.single.codecPrivate!),
        contains('palette'),
      );
    });

    test('SUB-051 truncated or hostile data parses to what is there', () {
      final whole = _mkv(
        codecId: 'S_HDMV/PGS',
        packets: [
          (0, [1, 2, 3]),
        ],
      );
      for (final cut in [3, 20, whole.length - 3]) {
        expect(
          () => MatroskaFile.parse(_bytes(whole.sublist(0, cut))),
          returnsNormally,
        );
      }
      expect(
        () => MatroskaFile.parse(_bytes(List.filled(64, 0xFF))),
        returnsNormally,
      );
      expect(MatroskaFile.parse(Uint8List(0)).blocks, isEmpty);
    });
  });

  group('SUB-051 PGS', () {
    List<SubtitleImage> decode(List<(int, List<int>)> packets) =>
        decodeSubtitleImages(
          _bytes(_mkv(codecId: 'S_HDMV/PGS', packets: packets)),
          'S_HDMV/PGS',
        ).toList();

    test('SUB-051 a display set becomes a bitmap until the next clears', () {
      final images = decode([
        (1000, _pgsShow(x: 10, y: 20)),
        (3000, _pgsClear()),
      ]);
      expect(images, hasLength(1));
      final i = images.single;
      expect(
        (i.start, i.end),
        (const Duration(seconds: 1), const Duration(seconds: 3)),
      );
      expect((i.x, i.y, i.width, i.height), (10, 20, 4, 2));
      expect((i.frameWidth, i.frameHeight), (640, 360));
      Matcher px(int r, int g, int b, int a) => equals([r, g, b, a]);
      List<int> at(int x, int y) =>
          i.rgba.sublist((y * 4 + x) * 4, (y * 4 + x) * 4 + 4);
      expect(at(0, 0), px(255, 255, 255, 255));
      expect(at(2, 0), px(0, 0, 0, 255));
      expect(at(3, 0)[3], 0, reason: 'colour 0 is transparent');
      expect(at(0, 1)[3], 0);
      expect(at(1, 1), px(0, 0, 0, 255));
      expect(at(3, 1), px(255, 255, 255, 255));
    });

    test('SUB-051 palette alpha is kept, and the next set ends the last', () {
      final images = decode([
        (1000, _pgsShow(x: 0, y: 0, alpha: 128)),
        (2000, _pgsShow(x: 5, y: 6, number: 1)),
      ]);
      expect(images, hasLength(2));
      expect(images.first.end, const Duration(seconds: 2));
      expect(images.first.rgba[2 * 4 + 3], 128);
      // No clear: the last one shows for its block's duration or a default.
      expect(images.last.end, greaterThan(images.last.start));
      expect((images.last.x, images.last.y), (5, 6));
    });

    test('SUB-051 first-packet time is placed on the media timeline', () {
      final images = decodeSubtitleImages(
        _bytes(
          _mkv(
            codecId: 'S_HDMV/PGS',
            packets: [(0, _pgsShow(x: 1, y: 1)), (900, _pgsClear())],
          ),
        ),
        'S_HDMV/PGS',
        firstAt: const Duration(seconds: 61),
      ).toList();
      expect(images.single.start, const Duration(seconds: 61));
      expect(images.single.end, const Duration(milliseconds: 61900));
    });

    test('SUB-051 an object split over segments and garbage are survived', () {
      final data = [
        ..._u16(0),
        0,
        0x80,
        0,
        ..._u16(_pgsRle.length + 4),
        ..._u16(4),
        ..._u16(2),
        ..._pgsRle.sublist(0, 5),
      ];
      final more = [..._u16(0), 0, 0x40, ..._pgsRle.sublist(5)];
      final set = [
        ..._seg(0x16, [
          ..._u16(640),
          ..._u16(360),
          0x10,
          ..._u16(0),
          0x80,
          0,
          0,
          1,
          ..._u16(0),
          0,
          0x00,
          ..._u16(2),
          ..._u16(3),
        ]),
        ..._pgsPalette(255),
        ..._seg(0x15, data),
        ..._seg(0x15, more),
        ..._seg(0x80, const []),
      ];
      final images = decode([(0, set), (500, _pgsClear())]);
      expect(images.single.width, 4);
      expect(images.single.rgba[3], 255);
      // Random bytes never throw.
      final junk = [for (var i = 0; i < 400; i++) (i * 37 + 11) & 0xFF];
      expect(
        () => decode([(0, junk), (5, junk.reversed.toList())]),
        returnsNormally,
      );
    });
  });

  group('SUB-051 VobSub', () {
    // A 4×2 subpicture: top row [1 1 2 0], bottom row [0 3 3 1]. Nibble
    // codes are (run << 2 | colour), padded to bytes per line.
    List<int> spu({int stopDate = 88}) {
      final top = [0x96, 0x40];
      final bottom = [0x4B, 0x50];
      const ctrl = 8;
      final first = <int>[
        0x03, 0x32, 0x10, // pixel v shows palette[v]
        0x04, 0xFF, 0xF0, // pixel 0 transparent
        0x05, 0x06, 0x40, 0x67, 0x0C, 0x80, 0xC9, // x 100-103, y 200-201
        0x06, ..._u16(4), ..._u16(6),
        0x01, 0xFF,
      ];
      final second = ctrl + 4 + first.length;
      final body = [
        ...top,
        ...bottom,
        ..._u16(0),
        ..._u16(second),
        ...first,
        ..._u16(stopDate),
        ..._u16(second),
        0x02,
        0xFF,
      ];
      final total = 4 + body.length;
      return [..._u16(total), ..._u16(ctrl), ...body];
    }

    final idx = [
      'size: 720x480',
      'palette: 000000, ff0000, 00ff00, 0000ff, ffffff, 808080, 111111, 222222, 333333, 444444, 555555, 666666, 777777, 888888, 999999, aaaaaa',
    ].join('\n').codeUnits;

    test('SUB-051 control sequences give the area, colours and times', () {
      final images = decodeSubtitleImages(
        _bytes(
          _mkv(
            codecId: 'S_VOBSUB',
            packets: [(5000, spu())],
            codecPrivate: idx,
          ),
        ),
        'S_VOBSUB',
      ).toList();
      final i = images.single;
      expect((i.x, i.y, i.width, i.height), (100, 200, 4, 2));
      expect((i.frameWidth, i.frameHeight), (720, 480));
      expect(i.start, const Duration(seconds: 5));
      expect(i.end, const Duration(seconds: 5, microseconds: 1001244));
      List<int> at(int x, int y) =>
          i.rgba.sublist((y * 4 + x) * 4, (y * 4 + x) * 4 + 4);
      expect(at(0, 0), [255, 0, 0, 255]);
      expect(at(2, 0), [0, 255, 0, 255]);
      expect(at(3, 0)[3], 0);
      expect(at(1, 1), [0, 0, 255, 255]);
      expect(at(3, 1), [255, 0, 0, 255]);
    });

    test('SUB-051 a damaged packet gives nothing, never an error', () {
      final good = spu();
      for (final cut in [0, 3, 9, 20, good.length - 2]) {
        expect(
          () => decodeSubtitleImages(
            _bytes(
              _mkv(
                codecId: 'S_VOBSUB',
                packets: [(0, good.sublist(0, cut))],
                codecPrivate: idx,
              ),
            ),
            'S_VOBSUB',
          ).toList(),
          returnsNormally,
        );
      }
    });
  });

  group('SUB-051 DVB', () {
    final bits = <int>[];
    void put(int value, int n) {
      for (var i = n - 1; i >= 0; i--) {
        bits.add((value >> i) & 1);
      }
    }

    List<int> flush() {
      while (bits.length % 8 != 0) {
        bits.add(0);
      }
      final out = [
        for (var i = 0; i < bits.length; i += 8)
          bits.sublist(i, i + 8).fold<int>(0, (a, b) => (a << 1) | b),
      ];
      bits.clear();
      return out;
    }

    List<int> seg(int type, List<int> payload) => [
      0x0F, type, ..._u16(1), ..._u16(payload.length), ...payload, //
    ];

    // Region of 8×4 at depth [depth] (1: 2-bit, 2: 4-bit, 3: 8-bit) with
    // one object at (1, 1); [top] and [bottom] are its pixel-data blocks.
    List<int> displaySet({
      required int depth,
      required List<int> top,
      required List<int> bottom,
      int timeout = 3,
      bool clear = false,
    }) => [
      ...seg(0x10, [
        timeout,
        0x08,
        if (!clear) ...[1, 0, ..._u16(10), ..._u16(20)],
      ]),
      if (!clear) ...[
        ...seg(0x11, [
          1,
          0,
          ..._u16(8),
          ..._u16(4),
          depth << 2,
          1,
          0,
          0,
          ..._u16(5),
          0x00,
          0x01,
          0x00,
          0x01,
        ]),
        ...seg(0x12, [
          1,
          0,
          1,
          0xE1,
          235,
          128,
          128,
          0,
          2,
          0xE1,
          16,
          128,
          128,
          0,
        ]),
        ...seg(0x13, [
          ..._u16(5),
          0,
          ..._u16(top.length),
          ..._u16(bottom.length),
          ...top,
          ...bottom,
        ]),
      ],
      ...seg(0x80, const []),
    ];

    List<int> block(int type, void Function() fill) {
      fill();
      return [type, ...flush(), 0xF0];
    }

    void expectLetters(SubtitleImage i) {
      expect((i.x, i.y, i.width, i.height), (10, 20, 8, 4));
      List<int> at(int x, int y) =>
          i.rgba.sublist((y * 8 + x) * 4, (y * 8 + x) * 4 + 4);
      // Row 1 of the region: [1 1 2], row 2: [2 1 1 1 1 1].
      expect(at(1, 1), [255, 255, 255, 255]);
      expect(at(3, 1), [0, 0, 0, 255]);
      expect(at(4, 1)[3], 0, reason: 'nothing drawn there');
      expect(at(1, 2), [0, 0, 0, 255]);
      expect(at(6, 2), [255, 255, 255, 255]);
      expect(at(0, 0)[3], 0);
    }

    Iterable<SubtitleImage> run(List<int> set, [List<int>? clear]) =>
        decodeSubtitleImages(
          _bytes(
            _mkv(
              codecId: 'S_DVBSUB',
              packets: [(2000, set), if (clear != null) (3000, clear)],
            ),
          ),
          'S_DVBSUB',
        );

    test('SUB-051 4-bit pixel data, with the timeout as the end', () {
      final top = block(0x11, () {
        put(1, 4);
        put(1, 4);
        put(2, 4);
        put(0, 8); // end of string
      });
      final bottom = block(0x11, () {
        put(2, 4);
        // Run of 5 pixels of colour 1: 0000 1 0 01 0001.
        put(0, 4);
        put(1, 1);
        put(0, 1);
        put(1, 2);
        put(1, 4);
        put(0, 8);
      });
      final images = run(displaySet(depth: 2, top: top, bottom: bottom))
          .toList();
      expect(images, hasLength(1));
      expectLetters(images.single);
      expect(images.single.start, const Duration(seconds: 2));
      expect(images.single.end, const Duration(seconds: 5));
    });

    test('SUB-051 2-bit and 8-bit data, and a clear that ends it early', () {
      final top2 = block(0x10, () {
        put(1, 2);
        put(1, 2);
        put(2, 2);
        put(0, 6); // end of string
      });
      final bottom2 = block(0x10, () {
        put(2, 2);
        // Run of 5 of colour 1: 00 1 010 01.
        put(0, 2);
        put(1, 1);
        put(2, 3);
        put(1, 2);
        put(0, 6);
      });
      expectLetters(
        run(displaySet(depth: 1, top: top2, bottom: bottom2)).single,
      );
      final top8 = [0x12, 1, 1, 2, 0, 0, 0xF0];
      final bottom8 = [0x12, 2, 0x00, 0x85, 1, 0, 0, 0xF0];
      final images = run(
        displaySet(depth: 3, top: top8, bottom: bottom8),
        displaySet(depth: 3, top: const [], bottom: const [], clear: true),
      ).toList();
      expect(images, hasLength(1));
      expectLetters(images.single);
      expect(images.single.end, const Duration(seconds: 3));
    });

    test('SUB-051 truncated or random segments never throw', () {
      final set = displaySet(
        depth: 2,
        top: block(0x11, () {
          put(1, 4);
          put(0, 8);
        }),
        bottom: const [],
      );
      for (var cut = 0; cut < set.length; cut += 5) {
        expect(() => run(set.sublist(0, cut)).toList(), returnsNormally);
      }
      final junk = [0x0F, for (var i = 0; i < 300; i++) (i * 91 + 5) & 0xFF];
      expect(() => run(junk).toList(), returnsNormally);
    });
  });

  group('SUB-051 streaming', () {
    test('SUB-051 the isolate streams bitmaps in order and ends', () async {
      final dir = Directory.systemTemp.createTempSync('mh-subimg');
      addTearDown(() => dir.deleteSync(recursive: true));
      final file = File('${dir.path}${Platform.pathSeparator}t.mkv')
        ..writeAsBytesSync(
          _mkv(
            codecId: 'S_HDMV/PGS',
            packets: [
              for (var n = 0; n < 40; n++) ...[
                (n * 1000, _pgsShow(x: n, y: 0, number: n * 2)),
                (n * 1000 + 600, _pgsClear(number: n * 2 + 1)),
              ],
            ],
          ),
        );
      final images = await streamSubtitleImages(
        file,
        'hdmv_pgs_subtitle',
      ).toList();
      expect(images, hasLength(40));
      expect([for (final i in images) i.x], [for (var n = 0; n < 40; n++) n]);
      expect(images[7].start, const Duration(seconds: 7));
      expect(images[7].end, const Duration(milliseconds: 7600));
    });

    test(
      'SUB-051 a text codec or a broken dump is an EngineException',
      () async {
        final dir = Directory.systemTemp.createTempSync('mh-subimg');
        addTearDown(() => dir.deleteSync(recursive: true));
        final bad = File('${dir.path}${Platform.pathSeparator}bad.mkv')
          ..writeAsBytesSync(List.filled(30, 7));
        await expectLater(
          streamSubtitleImages(bad, 'subrip').toList(),
          throwsA(
            isA<EngineException>().having(
              (e) => e.error.code,
              'code',
              EngineErrorCode.notSupported,
            ),
          ),
        );
        // Garbage yields no bitmaps (nothing to decode), not a crash.
        expect(
          await streamSubtitleImages(bad, 'hdmv_pgs_subtitle').toList(),
          isEmpty,
        );
      },
    );

    test('SUB-051 cancelling the listener stops the isolate', () async {
      final dir = Directory.systemTemp.createTempSync('mh-subimg');
      addTearDown(() => dir.deleteSync(recursive: true));
      final file = File('${dir.path}${Platform.pathSeparator}t.mkv')
        ..writeAsBytesSync(
          _mkv(
            codecId: 'S_HDMV/PGS',
            packets: [
              for (var n = 0; n < 200; n++)
                (n * 100, _pgsShow(x: n, y: 0, number: n)),
            ],
          ),
        );
      final first = await streamSubtitleImages(file, 'hdmv_pgs_subtitle').first;
      expect(first.x, 0);
    });
  });

  group('SUB-051 engine API', () {
    test(
      'SUB-051 the fake engine streams bitmaps of image tracks only',
      () async {
        final e = FakePlaybackEngine(
          mediaTracks: const [
            Track(id: 1, type: TrackType.subtitle, codec: 'subrip'),
            Track(id: 2, type: TrackType.subtitle, codec: 'hdmv_pgs_subtitle'),
          ],
        );
        addTearDown(e.dispose);
        final image = SubtitleImage(
          start: Duration.zero,
          end: const Duration(seconds: 1),
          x: 0,
          y: 0,
          width: 1,
          height: 1,
          frameWidth: 10,
          frameHeight: 10,
          rgba: Uint8List(4),
        );
        e.extractedSubtitleImages = [image];
        await e.open(UriSource(Uri.parse('https://example.test/film.mkv')));
        expect(await e.extractSubtitleImages(2).toList(), [image]);
        for (final (id, code) in [
          (1, EngineErrorCode.notSupported),
          (9, EngineErrorCode.invalidArgument),
        ]) {
          await expectLater(
            e.extractSubtitleImages(id).toList(),
            throwsA(
              isA<EngineException>().having((x) => x.error.code, 'code', code),
            ),
          );
        }
      },
    );
  });
}
