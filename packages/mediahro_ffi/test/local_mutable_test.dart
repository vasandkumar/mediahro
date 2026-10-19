import 'dart:io';

import 'package:mediahro_ffi/mediahro_ffi.dart';
import 'package:test/test.dart';

void main() {
  late Directory tmp;
  const fs = LocalFileSystem();
  final sep = Platform.pathSeparator;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('mediahro_mut_');
    File('${tmp.path}${sep}a.mkv').writeAsStringSync('film');
    File('${tmp.path}${sep}b.mkv').writeAsStringSync('other');
  });
  tearDown(() => tmp.delete(recursive: true));

  Matcher error(VirtualFileError e) =>
      throwsA(isA<VirtualFileException>().having((x) => x.error, 'error', e));

  test('FILE-002 new folder, rename, move and delete', () async {
    final dir = await fs.createDirectory(tmp.uri, 'Films');
    expect(Directory.fromUri(dir).existsSync(), isTrue);
    await expectLater(
      fs.createDirectory(tmp.uri, 'Films'),
      error(VirtualFileError.alreadyExists),
    );
    final a = File('${tmp.path}${sep}a.mkv').uri;
    final renamed = await fs.rename(a, 'Alpha.mkv');
    expect(File.fromUri(renamed).readAsStringSync(), 'film');
    await expectLater(
      fs.rename(renamed, 'b.mkv'),
      error(VirtualFileError.alreadyExists),
    );
    final moved = await fs.move(renamed, dir);
    expect(moved.path, endsWith('/Films/Alpha.mkv'));
    await fs.delete(dir, recursive: true);
    expect(Directory.fromUri(dir).existsSync(), isFalse);
    await expectLater(fs.delete(dir), error(VirtualFileError.notFound));
    expect(() => fs.rename(moved, '../x'), throwsArgumentError);
  });

  test('FILE-005 writers commit atomically and abort cleanly', () async {
    final target = File('${tmp.path}${sep}up.bin').uri;
    final w = await fs.create(target);
    await w.write([1, 2]);
    await w.write([3]);
    expect(
      File.fromUri(target).existsSync(),
      isFalse,
      reason: 'no partial file',
    );
    await w.close();
    expect(File.fromUri(target).readAsBytesSync(), [1, 2, 3]);

    final w2 = await fs.create(File('${tmp.path}${sep}gone.bin').uri);
    await w2.write([9]);
    await w2.abort();
    expect(tmp.listSync().map((e) => e.path.split(sep).last).toSet(), {
      'a.mkv',
      'b.mkv',
      'up.bin',
    });
  });
}
