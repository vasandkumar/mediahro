import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mediahro_engine/src/mpv/dsd_dop.dart';
import 'package:mediahro_ffi/mediahro_ffi.dart';

final class _Mem implements VirtualFile {
  _Mem(this.bytes);

  final Uint8List bytes;
  @override
  Uri get uri => Uri.parse('mem:/x');
  @override
  bool get isSeekable => true;
  @override
  Future<int?> length() async => bytes.length;
  @override
  Future<Uint8List> read(int offset, int length) async {
    if (offset >= bytes.length) return Uint8List(0);
    return Uint8List.sublistView(
      bytes,
      offset,
      (offset + length).clamp(0, bytes.length),
    );
  }

  @override
  Future<void> close() async {}
}

List<int> _le(int v, int n) => [
  for (var i = 0; i < n; i++) (v >> (8 * i)) & 255,
];
List<int> _be(int v, int n) => [
  for (var i = n - 1; i >= 0; i--) (v >> (8 * i)) & 255,
];

int _rev(int b) {
  var r = 0;
  for (var i = 0; i < 8; i++) {
    if (b & (1 << i) != 0) r |= 1 << (7 - i);
  }
  return r;
}

// Per channel DSD bytes in time order, most significant bit first.
List<Uint8List> _signal(int channels, int bytes) => [
  for (var c = 0; c < channels; c++)
    Uint8List.fromList([
      for (var i = 0; i < bytes; i++) (i * 37 + c * 101 + 7) & 255,
    ]),
];

Uint8List _dsf(
  List<Uint8List> signal, {
  int rate = 2822400,
  int block = 8,
  int bits = 1,
  int formatId = 0,
}) {
  final channels = signal.length;
  final n = signal.first.length;
  final blocks = (n + block - 1) ~/ block;
  final data = <int>[];
  for (var b = 0; b < blocks; b++) {
    for (var c = 0; c < channels; c++) {
      for (var i = 0; i < block; i++) {
        final k = b * block + i;
        // DSF keeps the oldest sample in the least significant bit.
        data.add(k < n ? _rev(signal[c][k]) : 0);
      }
    }
  }
  return Uint8List.fromList([
    ...ascii.encode('DSD '),
    ..._le(28, 8),
    ..._le(0, 8),
    ..._le(0, 8),
    ...ascii.encode('fmt '),
    ..._le(52, 8),
    ..._le(1, 4),
    ..._le(formatId, 4),
    ..._le(2, 4),
    ..._le(channels, 4),
    ..._le(rate, 4),
    ..._le(bits, 4),
    ..._le(n * 8, 8),
    ..._le(block, 4),
    ..._le(0, 4),
    ...ascii.encode('data'),
    ..._le(12 + data.length, 8),
    ...data,
  ]);
}

Uint8List _dff(
  List<Uint8List> signal, {
  int rate = 2822400,
  String compression = 'DSD ',
}) {
  final channels = signal.length;
  final n = signal.first.length;
  final prop = [
    ...ascii.encode('SND '),
    ...ascii.encode('FS  '),
    ..._be(4, 8),
    ..._be(rate, 4),
    ...ascii.encode('CHNL'),
    ..._be(2 + 4 * channels, 8),
    ..._be(channels, 2),
    for (var c = 0; c < channels; c++)
      ...ascii.encode(c == 0 ? 'SLFT' : 'SRGT'),
    ...ascii.encode('CMPR'),
    ..._be(4 + 1 + 14, 8),
    ...ascii.encode(compression),
    14,
    ...ascii.encode('not compressed'),
    0,
  ];
  final sound = [
    for (var i = 0; i < n; i++)
      for (var c = 0; c < channels; c++) signal[c][i],
  ];
  final body = [
    ...ascii.encode('DSD '),
    ...ascii.encode('FVER'),
    ..._be(4, 8),
    ..._be(0x01050000, 4),
    ...ascii.encode('PROP'),
    ..._be(prop.length, 8),
    ...prop,
    ...ascii.encode('DSD '),
    ..._be(sound.length, 8),
    ...sound,
  ];
  return Uint8List.fromList([
    ...ascii.encode('FRM8'),
    ..._be(body.length, 8),
    ...body,
  ]);
}

void main() {
  group('AUD-043 DoP packing', () {
    test('AUD-043 two DSD bytes go under an alternating marker', () {
      final out = dopPack(
        [
          Uint8List.fromList([0xAA, 0x55, 0x12, 0x34]),
        ],
        firstFrame: 0,
        lsbFirst: false,
      );
      // 24-bit little-endian: newer byte, older byte, marker.
      expect(out, [0x55, 0xAA, 0x05, 0x34, 0x12, 0xFA]);
      // The marker follows the frame's absolute parity.
      final odd = dopPack(
        [
          Uint8List.fromList([0xAA, 0x55]),
        ],
        firstFrame: 7,
        lsbFirst: false,
      );
      expect(odd, [0x55, 0xAA, 0xFA]);
    });

    test('AUD-043 DSF bytes are bit-reversed to oldest-first', () {
      final out = dopPack(
        [
          Uint8List.fromList([0x01, 0x80]),
        ],
        firstFrame: 0,
        lsbFirst: true,
      );
      expect(out, [0x01, 0x80, 0x05]);
    });

    test('AUD-043 channels interleave frame by frame', () {
      final out = dopPack(
        [
          Uint8List.fromList([1, 2]),
          Uint8List.fromList([3, 4]),
        ],
        firstFrame: 0,
        lsbFirst: false,
      );
      expect(out, [2, 1, 0x05, 4, 3, 0x05]);
    });
  });

  group('AUD-043 DSF and DFF as DoP streams', () {
    final signal = _signal(2, 1000);

    Future<Uint8List> whole(VirtualFile f) async {
      final n = (await f.length())!;
      final bytes = await f.read(0, n);
      return bytes;
    }

    test(
      'AUD-043 a DSF file becomes a 24-bit WAV at a sixteenth of the rate',
      () async {
        final info = (await inspectDsd(_Mem(_dsf(signal))))!;
        expect(
          (info.isDsf, info.channels, info.dsdRate, info.dopRate, info.frames),
          (true, 2, 2822400, 176400, 500),
        );
        final dop = DopVirtualFile(_Mem(_dsf(signal)), info);
        expect(await dop.length(), 44 + 500 * 2 * 3);
        final wav = await whole(dop);
        final h = ByteData.sublistView(wav);
        expect(String.fromCharCodes(wav.sublist(0, 4)), 'RIFF');
        expect(String.fromCharCodes(wav.sublist(8, 12)), 'WAVE');
        expect(h.getUint16(20, Endian.little), 1, reason: 'PCM');
        expect(h.getUint16(22, Endian.little), 2, reason: 'channels');
        expect(h.getUint32(24, Endian.little), 176400, reason: 'rate');
        expect(h.getUint16(34, Endian.little), 24, reason: 'bits');
        expect(
          h.getUint32(40, Endian.little),
          500 * 2 * 3,
          reason: 'data size',
        );
        // Every DSD bit comes out in order under 0x05 / 0xFA.
        for (var f = 0; f < 500; f++) {
          for (var c = 0; c < 2; c++) {
            final at = 44 + (f * 2 + c) * 3;
            expect(wav[at + 2], f.isEven ? 0x05 : 0xFA, reason: 'marker $f');
            expect(wav[at + 1], signal[c][2 * f], reason: 'older $f/$c');
            expect(wav[at], signal[c][2 * f + 1], reason: 'newer $f/$c');
          }
        }
      },
    );

    test('AUD-043 any read is the same bytes as the whole stream', () async {
      final dop = DopVirtualFile(
        _Mem(_dsf(signal)),
        (await inspectDsd(_Mem(_dsf(signal))))!,
      );
      final all = await whole(dop);
      for (final (offset, length) in [
        (0, 10),
        (43, 5),
        (44, 3),
        (45, 7),
        (47, 1),
        (100, 333),
        (3000 - 7, 100),
        (all.length - 2, 50),
        (7, 4096),
      ]) {
        final got = await dop.read(offset, length);
        final end = (offset + length).clamp(0, all.length);
        expect(got, all.sublist(offset, end), reason: '$offset+$length');
      }
      expect(await dop.read(all.length, 10), isEmpty);
    });

    test('AUD-043 DFF carries the same signal as DSF, byte for byte', () async {
      final dsf = DopVirtualFile(
        _Mem(_dsf(signal)),
        (await inspectDsd(_Mem(_dsf(signal))))!,
      );
      final dffBytes = _dff(signal);
      final info = (await inspectDsd(_Mem(dffBytes)))!;
      expect((info.isDsf, info.channels, info.dopRate), (false, 2, 176400));
      final dff = DopVirtualFile(_Mem(dffBytes), info);
      expect(await whole(dff), await whole(dsf));
      expect(await dff.read(1001, 777), await dsf.read(1001, 777));
    });

    test('AUD-043 mono works, DSD256 is the ceiling', () async {
      final mono = _signal(1, 64);
      final info = (await inspectDsd(_Mem(_dsf(mono))))!;
      expect((info.channels, info.frames), (1, 32));
      expect(
        (await inspectDsd(_Mem(_dsf(_signal(2, 64), rate: 2822400 * 4))))
            ?.dopRate,
        705600,
      );
      expect(
        await inspectDsd(_Mem(_dsf(_signal(2, 64), rate: 2822400 * 8))),
        isNull,
        reason: 'DSD512 is converted to PCM',
      );
    });

    test(
      'AUD-043 what DoP cannot carry is left to the PCM conversion',
      () async {
        expect(
          await inspectDsd(_Mem(_dff(signal, compression: 'DST '))),
          isNull,
        );
        expect(await inspectDsd(_Mem(_dsf(_signal(3, 64)))), isNull);
        expect(await inspectDsd(_Mem(_dsf(signal, bits: 8))), isNull);
        expect(await inspectDsd(_Mem(_dsf(signal, formatId: 1))), isNull);
        expect(
          await inspectDsd(_Mem(Uint8List.fromList(List.filled(200, 7)))),
          isNull,
        );
        expect(await inspectDsd(_Mem(Uint8List(0))), isNull);
        final good = _dsf(signal);
        for (final cut in [4, 20, 60, 79, 90]) {
          expect(
            await inspectDsd(_Mem(good.sublist(0, cut))),
            isNull,
            reason: '$cut',
          );
        }
        final dff = _dff(signal);
        for (final cut in [5, 20, 40, 100]) {
          expect(
            await inspectDsd(_Mem(dff.sublist(0, cut))),
            isNull,
            reason: '$cut',
          );
        }
      },
    );
  });
}
