import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mediahro_ffi/mediahro_ffi.dart';

/// Lane B2's native libraries on real devices: each test loads the
/// mediahro-deps build of the library bundled in the app and calls it.
/// A library the build does not contain yet (deps.lock pins no archive for
/// that platform) is skipped with the reason, never faked.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  bool missing(NativeLibrary lib) {
    if (NativeLibraries.isAvailable(lib)) return false;
    markTestSkipped('${lib.baseName} is not in this build (deps.lock)');
    return true;
  }

  late Directory tmp;
  setUp(() async => tmp = await Directory.systemTemp.createTemp('b2_native'));
  tearDown(() => tmp.delete(recursive: true));

  testWidgets('FILE-004 libarchive lists and reads a CBZ on the device', (
    tester,
  ) async {
    if (missing(NativeLibrary.archive)) return;
    final f = File('${tmp.path}/comic.cbz')
      ..writeAsBytesSync(
        _zipStored({
          'Chapter 1/001.jpg': List.generate(5000, (i) => i % 256),
          'info.txt': utf8.encode('hello'),
          '../evil.txt': [1],
        }),
      );
    final fs = ArchiveSyncFileSystem(LocalArchiveSource(f.path));
    expect(fs.entryCount, 2, reason: 'the escaping entry is dropped');
    final h = fs.open('Chapter 1/001.jpg');
    expect(fs.length(h), 5000);
    expect(fs.read(h, 4998, 10), [4998 % 256, 4999 % 256]);
    fs
      ..close(h)
      ..dispose();
  });

  testWidgets('SUB charset: uchardet tells UTF-8 from legacy text', (
    tester,
  ) async {
    if (missing(NativeLibrary.uchardet)) return;
    expect(
      detectCharset(
        Uint8List.fromList(utf8.encode('héllo wörld ünïcode ' * 20)),
      ),
      'UTF-8',
    );
  });

  testWidgets('LIB-014/NET loudness: ebur128 measures a −20 dBFS sine', (
    tester,
  ) async {
    if (missing(NativeLibrary.ebur128)) return;
    final m = LoudnessMeter(2, 48000);
    final amp = math.pow(10, -20 / 20).toDouble();
    const frames = 48000 * 3;
    final pcm = Float32List(frames * 2);
    for (var i = 0; i < frames; i++) {
      final v = amp * math.sin(2 * math.pi * 1000 * i / 48000);
      pcm[2 * i] = v;
      pcm[2 * i + 1] = v;
    }
    m.addFrames(pcm);
    expect(m.integrated, closeTo(-23, 0.5));
    m.dispose();
  });

  testWidgets('LIB-014 chromaprint fingerprints are stable per audio', (
    tester,
  ) async {
    if (missing(NativeLibrary.chromaprint)) return;
    Int16List tone(double f) => Int16List.fromList([
      for (var i = 0; i < 11025 * 15; i++)
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
      c.dispose();
      return raw;
    }

    final a = fp(tone(440));
    expect(fp(tone(440)), a);
    expect(fp(tone(1200)), isNot(a));
  });

  // The protocol clients run on their own isolate; a refused connection
  // proves the library loaded there and its connect path ran.
  for (final (id, lib, fs)
      in <(String, NativeLibrary, VirtualFileSystem Function())>[
        (
          'NET-001 libsmb2',
          NativeLibrary.smb2,
          () => smbFileSystem(
            Uri.parse('smb://127.0.0.1:1/share/'),
            const SmbOptions(
              server: '127.0.0.1',
              share: 'share',
              port: 1,
              guest: true,
              timeout: Duration(seconds: 5),
            ),
          ),
        ),
        (
          'NET-002 libnfs',
          NativeLibrary.nfs,
          () => nfsFileSystem(
            Uri.parse('nfs://127.0.0.1/export/'),
            const NfsOptions(server: '127.0.0.1', export: '/export'),
          ),
        ),
        (
          'NET-004 libcurl',
          NativeLibrary.curl,
          () => curlFileSystem(
            Uri.parse('ftp://127.0.0.1:1/'),
            const CurlOptions(
              protocol: CurlProtocol.ftp,
              host: '127.0.0.1',
              port: 1,
            ),
          ),
        ),
      ]) {
    testWidgets('$id loads on the device and reports a refused connection', (
      tester,
    ) async {
      if (missing(lib)) return;
      final f = fs();
      await expectLater(
        f
            .list(
              f.schemes.contains('smb')
                  ? Uri.parse('smb://127.0.0.1:1/share/')
                  : f.schemes.contains('nfs')
                  ? Uri.parse('nfs://127.0.0.1/export/')
                  : Uri.parse('ftp://127.0.0.1:1/'),
            )
            .toList()
            .timeout(const Duration(seconds: 60)),
        throwsA(isA<VirtualFileException>()),
      );
      if (f case final IsolateFileSystem i) await i.close();
    });
  }
}

/// Minimal ZIP writer (stored entries).
Uint8List _zipStored(Map<String, List<int>> files) {
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
    for (final b in [out, central]) {
      u32(b, b == out ? 0x04034b50 : 0x02014b50);
      if (b == central) u16(b, 20);
      u16(b, 20);
      u16(b, 0x0800);
      u16(b, 0);
      u16(b, 0);
      u16(b, 0x5821);
      u32(b, crc);
      u32(b, data.length);
      u32(b, data.length);
      u16(b, n.length);
      u16(b, 0);
    }
    out
      ..add(n)
      ..add(data);
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
