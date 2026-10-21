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
Uint8List zipStored(
  Map<String, List<int>> files, {
  Map<String, int> unixModes = const {},
  Map<String, int> declared = const {},
}) {
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
    u32(out, declared[name] ?? data.length);
    u16(out, n.length);
    u16(out, 0);
    out
      ..add(n)
      ..add(data);
    u32(central, 0x02014b50);
    // Made by Unix when a file mode is given (links need it).
    u16(central, unixModes.containsKey(name) ? (3 << 8) | 20 : 20);
    u16(central, 20);
    u16(central, 0x0800);
    u16(central, 0);
    u16(central, 0);
    u16(central, 0x5821);
    u32(central, crc);
    u32(central, data.length);
    u32(central, declared[name] ?? data.length);
    u16(central, n.length);
    u16(central, 0);
    u16(central, 0);
    u16(central, 0);
    u16(central, 0);
    u32(central, (unixModes[name] ?? 0) << 16);
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

  test('PRIV-005 absolute entry names are ignored, not made relative', () {
    expect(normaliseEntryPath('/etc/passwd'), isNull);
    expect(normaliseEntryPath(r'\windows\system32\x.dll'), isNull);
    expect(normaliseEntryPath(r'C:\Users\me\x.png'), isNull);
    expect(normaliseEntryPath('c:/x.png'), isNull);
    expect(normaliseEntryPath('~/.ssh/id_rsa'), isNull);
    // Only a name that starts that way: a colon deeper in is just a name.
    expect(normaliseEntryPath('a/c:/x.png'), 'a/c:/x.png');
    expect(normaliseEntryPath('page.png'), 'page.png');
  });

  group('PRIV-005 zip-bomb limits', () {
    const limits = ArchiveLimits();

    test('an archive within its limits is accepted', () {
      expect(archiveBombReason(50 << 20, 40 << 20, limits), isNull);
      // Small files may compress very well: below the floor it is not a bomb.
      expect(archiveBombReason(200 << 20, 1 << 10, limits), isNull);
      expect(archiveBombReason(1 << 30, null, limits), isNull);
    });

    test('too much in total is refused, whatever the ratio', () {
      expect(archiveBombReason((64 << 30) + 1, 1 << 40, limits), isNotNull);
      expect(archiveBombReason(64 << 30, 1 << 40, limits), isNull);
    });

    test('a huge ratio above the floor is refused', () {
      // 1 GiB out of 100 KiB is 10 000 times.
      expect(archiveBombReason(1 << 30, 100 << 10, limits), isNotNull);
      // Just inside the ratio.
      expect(archiveBombReason(1000 << 20, 1 << 20, limits), isNull);
      expect(archiveBombReason((1000 << 20) + 1, 1 << 20, limits), isNotNull);
    });

    test('the limits can be tightened', () {
      const tight = ArchiveLimits(
        maxTotalBytes: 1 << 20,
        maxRatio: 10,
        ratioFloorBytes: 1 << 10,
      );
      expect(archiveBombReason((1 << 20) + 1, null, tight), isNotNull);
      expect(archiveBombReason(10 << 10, 1 << 10, tight), isNull);
      expect(archiveBombReason((10 << 10) + 1, 1 << 10, tight), isNotNull);
    });
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

    test(
      'PRIV-005 a crafted ZIP: links, escapes, absolute names, depth and sizes',
      () {
        final deep = List.filled(80, 'd').join('/');
        final zip = zipStored(
          {
            'ok/page1.jpg': [1, 2, 3],
            '../x': [9],
            '/abs.jpg': [9],
            'link.jpg': utf8.encode('/etc/passwd'),
            '$deep/too-deep.jpg': [9],
          },
          unixModes: {'link.jpg': 0xA1FF, 'ok/page1.jpg': 0x81A4},
        );
        final f = File('${tmp.path}/crafted.zip')..writeAsBytesSync(zip);
        final fs = ArchiveSyncFileSystem(LocalArchiveSource(f.path));
        // Only the one honest page: no escape, no absolute name, no symlink, no
        // entry past the depth limit.
        expect(fs.entryCount, 1);
        expect(fs.list('').map((e) => e.name), ['ok']);
        fs.dispose();
      },
      skip: _skip(NativeLibrary.archive),
    );

    test(
      'PRIV-005 an entry that declares far more than the limit is refused',
      () {
        final zip = zipStored(
          {
            'big.bin': [1, 2, 3],
          },
          declared: {'big.bin': 3 << 30},
        );
        final f = File('${tmp.path}/bomb.zip')..writeAsBytesSync(zip);
        expect(
          () => ArchiveSyncFileSystem(
            LocalArchiveSource(f.path),
            limits: const ArchiveLimits(maxTotalBytes: 1 << 30),
          ),
          throwsA(
            isA<VirtualFileException>().having(
              (e) => e.error,
              'error',
              VirtualFileError.unsupported,
            ),
          ),
        );
      },
      skip: _skip(NativeLibrary.archive),
    );

    test('PRIV-005 a ratio far above the limit is refused', () {
      final zip = zipStored(
        {
          'a.bin': [1, 2, 3],
        },
        declared: {'a.bin': 400 << 20},
      );
      final f = File('${tmp.path}/ratio.zip')..writeAsBytesSync(zip);
      expect(
        () => ArchiveSyncFileSystem(LocalArchiveSource(f.path)),
        throwsA(isA<VirtualFileException>()),
      );
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
