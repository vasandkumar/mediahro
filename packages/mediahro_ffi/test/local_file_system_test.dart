import 'dart:io';
import 'dart:typed_data';

import 'package:mediahro_ffi/mediahro_ffi.dart';
import 'package:test/test.dart';

void main() {
  late Directory tmp;
  const fs = LocalFileSystem();

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('mediahro_vfs_');
    await File('${tmp.path}${Platform.pathSeparator}a.bin')
        .writeAsBytes(List<int>.generate(4096, (i) => i % 256));
    await Directory('${tmp.path}${Platform.pathSeparator}sub').create();
  });

  tearDown(() => tmp.delete(recursive: true));

  test(
    'VirtualFile reads arbitrary ranges (seekable source contract, docs/05 §9)',
    () async {
      final f = await fs.open(
        File('${tmp.path}${Platform.pathSeparator}a.bin').uri,
      );
      expect(f.isSeekable, isTrue);
      expect(await f.length(), 4096);
      expect(
        await f.read(1000, 4),
        Uint8List.fromList([1000 % 256, 1001 % 256, 1002 % 256, 1003 % 256]),
      );
      expect(
        await f.read(4094, 10),
        hasLength(2),
        reason: 'short read only at EOF',
      );
      await f.close();
      expect(() => f.read(0, 1), throwsA(isA<VirtualFileException>()));
    },
  );

  test('concurrent reads are serialised and correct', () async {
    final f = await fs.open(
      File('${tmp.path}${Platform.pathSeparator}a.bin').uri,
    );
    final results = await Future.wait([
      for (var i = 0; i < 16; i++) f.read(i * 256, 1),
    ]);
    expect([for (final r in results) r.single], everyElement(0));
    await f.close();
  });

  test('list and stat report directories and sizes', () async {
    final entries = await fs.list(tmp.uri).toList();
    entries.sort((a, b) => a.name.compareTo(b.name));
    expect(entries.map((e) => e.name), ['a.bin', 'sub']);
    expect(entries.first.size, 4096);
    expect(entries.last.isDirectory, isTrue);
  });

  test('missing file maps to notFound', () async {
    final uri = File('${tmp.path}${Platform.pathSeparator}nope').uri;
    await expectLater(
      fs.open(uri),
      throwsA(
        isA<VirtualFileException>().having(
          (e) => e.error,
          'error',
          VirtualFileError.notFound,
        ),
      ),
    );
    await expectLater(fs.stat(uri), throwsA(isA<VirtualFileException>()));
  });
}
