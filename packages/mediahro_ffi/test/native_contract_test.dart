// FFI contract tests (docs/11 §1): run wherever the native library can be
// loaded (desktop runners with mediahro-deps archives, the Linux network
// job), skipped elsewhere with the reason.
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:mediahro_ffi/mediahro_ffi.dart';
import 'package:test/test.dart';

String? _skip(NativeLibrary lib) => NativeLibraries.isAvailable(lib)
    ? null
    : 'blocked: STATUS §3 — mediahro-deps lib${lib.baseName} for this '
          'platform (B4)';

/// Minimal ZIP writer (stored entries) for archive tests.
Uint8List zipStored(Map<String, List<int>> files) {
  final out = BytesBuilder();
  final central = BytesBuilder();
  var count = 0;
  int crc32(List<int> d) {
    var c = 0xFFFFFFFF;
    for (final b in d) {
      c ^= b;
      for (var k = 0; k < 8; k++) {
        c = (c & 1) != 0 ? (c >>> 1) ^ 0xEDB88320 : c >>> 1;
      }
    }
    return c ^ 0xFFFFFFFF;
  }

  void u16(BytesBuilder b, int v) => b.add([v & 0xff, (v >> 8) & 0xff]);
  void u32(BytesBuilder b, int v) =>
      b.add([v & 0xff, (v >> 8) & 0xff, (v >> 16) & 0xff, (v >> 24) & 0xff]);
  files.forEach((name, data) {
    final n = utf8.encode(name);
    final crc = crc32(data);
    final offset = out.length;
    u32(out, 0x04034b50);
    u16(out, 20);
    u16(out, 0x0800); // UTF-8 names
    u16(out, 0);
    u16(out, 0);
    u16(out, 0x5821);
    u32(out, crc);
    u32(out, data.length);
    u32(out, data.length);
    u16(out, n.length);
    u16(out, 0);
    out
      ..add(n)
      ..add(data);
    u32(central, 0x02014b50);
    u16(central, 20);
    u16(central, 20);
    u16(central, 0x0800);
    u16(central, 0);
    u16(central, 0);
    u16(central, 0x5821);
    u32(central, crc);
    u32(central, data.length);
    u32(central, data.length);
    u16(central, n.length);
    u16(central, 0);
    u16(central, 0);
    u16(central, 0);
    u16(central, 0);
    u32(central, 0);
    u32(central, offset);
    central.add(n);
    count++;
  });
  final cdOffset = out.length;
  final cd = central.takeBytes();
  out.add(cd);
  u32(out, 0x06054b50);
  u16(out, 0);
  u16(out, 0);
  u16(out, count);
  u16(out, count);
  u32(out, cd.length);
  u32(out, cdOffset);
  u16(out, 0);
  return out.takeBytes();
}

void main() {
  test('FILE-004 entry names are normalised and never escape the archive', () {
    expect(normaliseEntryPath('./a//b/c.jpg'), 'a/b/c.jpg');
    expect(normaliseEntryPath(r'win\style\p.png'), 'win/style/p.png');
    expect(normaliseEntryPath('../../etc/passwd'), isNull);
    expect(normaliseEntryPath('a/../../x'), isNull);
    expect(normaliseEntryPath('/'), isNull);
  });

  group('FILE-004 libarchive', () {
    late Directory tmp;
    setUp(
      () async => tmp = await Directory.systemTemp.createTemp('mediahro_zip'),
    );
    tearDown(() => tmp.delete(recursive: true));

    test('lists a CBZ, reads entries and refuses writes', () {
      final pages = {
        'Chapter 1/001.jpg': List.generate(5000, (i) => i % 256),
        'Chapter 1/002.jpg': List.filled(100, 7),
        'info.txt': utf8.encode('hello'),
        '../evil.txt': [1],
      };
      final f = File('${tmp.path}/comic.cbz')
        ..writeAsBytesSync(zipStored(pages));
      final fs = ArchiveSyncFileSystem(LocalArchiveSource(f.path));
      expect(fs.entryCount, 3, reason: 'the escaping entry is dropped');
      final root = fs.list('');
      expect(root.map((e) => (e.name, e.isDirectory)).toSet(), {
        ('Chapter 1', true),
        ('info.txt', false),
      });
      final ch = fs.list('Chapter 1');
      expect(ch.map((e) => e.name).toList()..sort(), ['001.jpg', '002.jpg']);
      final h = fs.open('Chapter 1/001.jpg');
      expect(fs.length(h), 5000);
      expect(fs.read(h, 4998, 10), [4998 % 256, 4999 % 256]);
      fs.close(h);
      expect(() => fs.mkdir('x'), throwsA(isA<VirtualFileException>()));
      fs.dispose();
    }, skip: _skip(NativeLibrary.archive));

    test('reads an archive from a blocking source without copying it', () {
      final bytes = zipStored({'a/b.txt': utf8.encode('inside')});
      final fs = ArchiveSyncFileSystem(
        SyncArchiveSource(() => _BytesSync(bytes), 'x.zip'),
      );
      final h = fs.open('a/b.txt');
      expect(utf8.decode(fs.read(h, 0, 100)), 'inside');
      fs.dispose();
    }, skip: _skip(NativeLibrary.archive));

    test('not an archive maps to unsupported', () {
      final f = File('${tmp.path}/x.zip')..writeAsStringSync('nope');
      expect(
        () => ArchiveSyncFileSystem(LocalArchiveSource(f.path)),
        throwsA(
          isA<VirtualFileException>().having(
            (e) => e.error,
            'error',
            VirtualFileError.unsupported,
          ),
        ),
      );
    }, skip: _skip(NativeLibrary.archive));
  });

  test('uchardet detects legacy Cyrillic', () {
    // "Привет мир, это тест кодировки" in Windows-1251, repeated.
    final cp1251 = <int>[
      0xCF,
      0xF0,
      0xE8,
      0xE2,
      0xE5,
      0xF2,
      0x20,
      0xEC,
      0xE8,
      0xF0,
      0x2C,
      0x20,
      0xFD,
      0xF2,
      0xEE,
      0x20,
      0xF2,
      0xE5,
      0xF1,
      0xF2,
      0x20,
      0xEA,
      0xEE,
      0xE4,
      0xE8,
      0xF0,
      0xEE,
      0xE2,
      0xEA,
      0xE8,
      0x2E,
      0x20,
    ];
    final text = Uint8List.fromList([for (var i = 0; i < 20; i++) ...cp1251]);
    expect(
      detectCharset(text),
      anyOf('WINDOWS-1251', 'MAC-CYRILLIC', 'KOI8-R', 'ISO-8859-5', 'IBM866'),
    );
    expect(
      detectCharset(
        Uint8List.fromList(utf8.encode('héllo wörld ünïcode ' * 20)),
      ),
      'UTF-8',
    );
  }, skip: _skip(NativeLibrary.uchardet));

  // EBU Tech 3341 / ITU-R BS.1770: a 1 kHz sine of peak amplitude A has a
  // mean square of A²/2 per channel and K-weighting adds ≈ +0.69 dB at 1 kHz,
  // cancelling the −0.691 offset. So a −20 dBFS sine reads −20 LUFS on two
  // channels (their energies add) and ≈ −23 LUFS on one.
  Float32List sine(int channels, double dbfs, int frames) {
    final amp = math.pow(10, dbfs / 20).toDouble();
    final pcm = Float32List(frames * channels);
    for (var i = 0; i < frames; i++) {
      final v = amp * math.sin(2 * math.pi * 1000 * i / 48000);
      for (var c = 0; c < channels; c++) {
        pcm[channels * i + c] = v;
      }
    }
    return pcm;
  }

  test('LIB-014/AUD ebur128: a stereo −20 dBFS 1 kHz sine reads −20 LUFS', () {
    final m = LoudnessMeter(2, 48000)..addFrames(sine(2, -20, 48000 * 5));
    expect(m.integrated, closeTo(-20, 0.1));
    expect(m.truePeak(0), closeTo(math.pow(10, -20 / 20), 0.02));
    m.dispose();
  }, skip: _skip(NativeLibrary.ebur128));

  test('LIB-014/AUD ebur128: a mono −20 dBFS 1 kHz sine reads −23 LUFS', () {
    final m = LoudnessMeter(1, 48000)..addFrames(sine(1, -20, 48000 * 5));
    expect(m.integrated, closeTo(-23, 0.1));
    m.dispose();
  }, skip: _skip(NativeLibrary.ebur128));

  test(
    'chromaprint: same audio, same fingerprint; different audio differs',
    () {
      Int16List tone(double f) => Int16List.fromList([
        for (var i = 0; i < 11025 * 20; i++)
          (8000 *
                  math.sin(2 * math.pi * f * i / 11025) *
                  (1 + 0.5 * math.sin(i / 3000)))
              .round(),
      ]);
      Uint32List fp(Int16List pcm) {
        final c = Fingerprinter()
          ..start(11025, 1)
          ..feed(pcm)
          ..finish();
        final raw = c.raw();
        expect(c.encoded(), isNotEmpty);
        c.dispose();
        return raw;
      }

      final a = fp(tone(440));
      expect(fp(tone(440)), a);
      expect(fp(tone(1200)), isNot(a));
    },
    skip: _skip(NativeLibrary.chromaprint),
  );
}

final class _BytesSync implements SyncFileSystem {
  _BytesSync(this.bytes);

  final Uint8List bytes;

  @override
  int open(String path, {bool write = false, bool create = false}) => 1;
  @override
  int? length(int handle) => bytes.length;
  @override
  Uint8List read(int handle, int offset, int length) => offset >= bytes.length
      ? Uint8List(0)
      : Uint8List.sublistView(
          bytes,
          offset,
          math.min(bytes.length, offset + length),
        );
  @override
  void close(int handle) {}
  @override
  void dispose() {}
  @override
  List<VirtualEntry> list(String path) => const [];
  @override
  VirtualEntry stat(String path) => throw UnimplementedError();
  @override
  void write(int handle, int offset, List<int> bytes) {}
  @override
  void mkdir(String path) {}
  @override
  void rename(String from, String to) {}
  @override
  void unlink(String path) {}
  @override
  void rmdir(String path) {}
}
