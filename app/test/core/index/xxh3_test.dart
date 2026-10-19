import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mediahro/core/index/content_hash.dart';
import 'package:mediahro/core/index/xxh3.dart';
import 'package:mediahro_ffi/mediahro_ffi.dart';

// Reference values from xxHash 0.8 (python-xxhash 4.0.2, xxh3_64) over the
// pattern byte[i] = (i * 31 + 7) & 0xff; covers every length branch.
const _vectors = <(int, String)>[
  (0, '2d06800538d394c2'),
  (1, '4c5cca45d0f4811f'),
  (2, 'a7e250c97710ff27'),
  (3, '15f7093b173d005c'),
  (4, 'dca012f95811b6b9'),
  (5, 'b290cafc7b254345'),
  (7, '7561869c23da3c1b'),
  (8, 'dec6a9a43575982e'),
  (9, 'cbe393399f17ffbd'),
  (15, '545e19990471dc37'),
  (16, '7e484c18d74895d0'),
  (17, '208bde5ee2bed407'),
  (31, 'a937652b0119ca11'),
  (32, '03df0ac5255d1446'),
  (33, '199a362122d71f46'),
  (63, '76d4eec1f092847f'),
  (64, 'dd30702ab46b3745'),
  (65, 'fab36b851b94ce20'),
  (96, 'd245cd2541582982'),
  (97, '60e3e1d0d43785b3'),
  (127, 'a915ed6396db8cc0'),
  (128, 'f92b70eaa21a6288'),
  (129, 'f8f76713f2bb60fa'),
  (200, '12fdb864685f344d'),
  (239, 'caa9b7a588464745'),
  (240, 'ccc7375172c41f03'),
  (241, '0b3b630948ce4a00'),
  (255, '89932170686cdd9a'),
  (256, 'ec85b75bafe6ca74'),
  (500, 'e1e3ce93f69c5043'),
  (1023, 'f0d330ce2b3300fb'),
  (1024, '23bc880ebf0d29c6'),
  (1025, 'c09fdfbc398c7d82'),
  (1087, '3ab6ed4b5be06fcc'),
  (1088, 'a16bad67843c5a45'),
  (2048, '19f6f9c987331373'),
  (4096, 'a3c19f8174cde0bb'),
  (10000, '441f01d9711bebed'),
  (100003, 'e0950e66cf107fe8'),
];

Uint8List _pattern(int n) =>
    Uint8List.fromList([for (var i = 0; i < n; i++) (i * 31 + 7) & 0xff]);

final class _MemFile implements VirtualFile {
  _MemFile(this.bytes);

  final Uint8List bytes;
  final reads = <(int, int)>[];

  @override
  Uri get uri => Uri.parse('mem:/f');

  @override
  bool get isSeekable => true;

  @override
  Future<int?> length() async => bytes.length;

  @override
  Future<Uint8List> read(int offset, int length) async {
    reads.add((offset, length));
    final end = offset + length > bytes.length ? bytes.length : offset + length;
    return Uint8List.sublistView(bytes, offset, end);
  }

  @override
  Future<void> close() async {}
}

void main() {
  test(
    'LIB-001 xxh3-64 matches the xxHash reference for every length class',
    () {
      for (final (n, expected) in _vectors) {
        expect(xxh3Hex(_pattern(n)), expected, reason: 'length $n');
      }
    },
  );

  test('LIB-001 content hash reads only the first and last MiB', () async {
    final big = _MemFile(_pattern(5 * contentHashWindow + 17));
    final h = await contentHash(big);
    expect(h, hasLength(16));
    expect(big.reads, [
      (0, contentHashWindow),
      (4 * contentHashWindow + 17, contentHashWindow),
    ]);
  });

  test(
    'LIB-001 content hash changes with size and is stable across reads',
    () async {
      final a = await contentHash(_MemFile(_pattern(3000)));
      final b = await contentHash(_MemFile(_pattern(3000)));
      final c = await contentHash(_MemFile(_pattern(3001)));
      expect(a, b);
      expect(a, isNot(c));
      // Files between 1 and 2 MiB hash the tail without overlapping the head.
      final mid = _MemFile(_pattern(contentHashWindow + 10));
      await contentHash(mid);
      expect(mid.reads.last, (contentHashWindow, 10));
    },
  );
}
