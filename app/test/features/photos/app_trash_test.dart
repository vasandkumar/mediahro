import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mediahro/core/db/library_database.dart';
import 'package:mediahro/features/photos/timeline/timeline_model.dart';
import 'package:mediahro/features/photos/trash/app_trash.dart';

import '../../core/seed.dart';
import 'disk_support.dart';
import 'photos_harness.dart';

void main() {
  late Directory dir;
  late LibraryDatabase db;
  late Seed seed;
  late DiskIo io;
  late AppTrash trash;
  var now = DateTime(2026, 10, 21, 12);

  setUp(() {
    dir = Directory.systemTemp.createTempSync('mediahro-trash');
    db = LibraryDatabase.memory();
    seed = Seed(db);
    io = DiskIo();
    now = DateTime(2026, 10, 21, 12);
    trash = AppTrash(
      directory: Directory('${dir.path}/bin'),
      files: DiskFiles(dir, io),
      io: io,
      db: db,
      capBytes: 1000,
      clock: () => now,
    );
  });

  tearDown(() async {
    await db.close();
    dir.deleteSync(recursive: true);
  });

  Future<PhotoEntry> photo(String rel, {int size = 100}) async {
    final id = await seed.item(rel, kind: ItemKind.image);
    File('${dir.path}/$rel')
      ..createSync(recursive: true)
      ..writeAsBytesSync(
        Uint8List.fromList(List.generate(size, (i) => i % 251)),
      );
    final base = fakeEntries(days: 1, perDay: 1, firstId: id).single;
    return PhotoEntry(
      id: id,
      sourceId: 1,
      relPath: rel,
      name: rel.split('/').last,
      ext: rel.split('.').last,
      isVideo: false,
      size: size,
      mtime: base.mtime,
      date: base.date,
    );
  }

  Future<bool> missing(int id) async => (await (db.select(
    db.items,
  )..where((i) => i.id.equals(id))).getSingle()).missing;

  test(
    'IMG-014 a deleted photo waits in the bin and leaves its folder',
    () async {
      final p = await photo('trip/a.jpg');
      final out = await trash.moveToTrash([p]);
      expect(out.moved, hasLength(1));
      expect(File('${dir.path}/trip/a.jpg').existsSync(), isFalse);
      final listed = await trash.list();
      expect(listed.single.name, 'a.jpg');
      expect(trash.fileOf(listed.single).lengthSync(), 100);
      expect(await missing(p.id), isTrue);
    },
  );

  test('IMG-014 the bin lists the newest first', () async {
    final a = await photo('a.jpg');
    await trash.moveToTrash([a]);
    now = now.add(const Duration(minutes: 5));
    final b = await photo('b.jpg');
    await trash.moveToTrash([b]);
    expect((await trash.list()).map((t) => t.name), ['b.jpg', 'a.jpg']);
  });

  test('IMG-014 restoring puts the file back and the photo returns', () async {
    final p = await photo('trip/a.jpg');
    final bytes = File('${dir.path}/trip/a.jpg').readAsBytesSync();
    final moved = (await trash.moveToTrash([p])).moved;
    expect(await trash.restore(moved), 1);
    expect(File('${dir.path}/trip/a.jpg').readAsBytesSync(), bytes);
    expect(await trash.list(), isEmpty);
    expect(await missing(p.id), isFalse);
  });

  test('IMG-014 a name that is taken again gets a new one', () async {
    final p = await photo('a.jpg');
    final moved = (await trash.moveToTrash([p])).moved;
    File('${dir.path}/a.jpg').writeAsStringSync('another photo');
    expect(await trash.restore(moved), 1);
    expect(File('${dir.path}/a.jpg').readAsStringSync(), 'another photo');
    expect(File('${dir.path}/a_restored.jpg').existsSync(), isTrue);
    expect(await missing(p.id), isTrue, reason: 'it is another file now');
  });

  test('IMG-014 a photo whose original cannot be removed stays put', () async {
    final p = await photo('a.jpg');
    io.failDelete = true;
    final out = await trash.moveToTrash([p]);
    expect(out.failed, ['a.jpg']);
    expect(File('${dir.path}/a.jpg').existsSync(), isTrue);
    expect(await trash.list(), isEmpty);
    final binFiles = Directory('${dir.path}/bin')
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.bin'));
    expect(binFiles, isEmpty);
    expect(await missing(p.id), isFalse);
  });

  test('IMG-014 a file too big for the bin is handed back', () async {
    final big = await photo('big.jpg', size: 800);
    final small = await photo('small.jpg', size: 50);
    final out = await trash.moveToTrash([big, small]);
    expect(out.tooBig.map((p) => p.name), ['big.jpg']);
    expect(out.moved.map((t) => t.name), ['small.jpg']);
    expect(File('${dir.path}/big.jpg').existsSync(), isTrue);
  });

  test('IMG-014 what is older than 30 days is removed', () async {
    final a = await photo('a.jpg');
    await trash.moveToTrash([a]);
    now = now.add(const Duration(days: 29));
    final b = await photo('b.jpg');
    await trash.moveToTrash([b]);
    expect(await trash.list(), hasLength(2));
    now = now.add(const Duration(days: 2));
    expect(await trash.purge(), 1);
    expect((await trash.list()).map((t) => t.name), ['b.jpg']);
  });

  test('IMG-014 when the bin is over its size the oldest go first', () async {
    for (var i = 0; i < 4; i++) {
      final p = await photo('p$i.jpg', size: 300);
      await trash.moveToTrash([p]);
      now = now.add(const Duration(minutes: 1));
    }
    final left = await trash.list();
    expect(left.fold<int>(0, (a, t) => a + t.size), lessThanOrEqualTo(1000));
    expect(left.map((t) => t.name), ['p3.jpg', 'p2.jpg', 'p1.jpg']);
  });

  test('IMG-014 deleting for good removes the file', () async {
    final a = await photo('a.jpg');
    final moved = (await trash.moveToTrash([a])).moved;
    final f = trash.fileOf(moved.single);
    await trash.deleteForever(moved);
    expect(f.existsSync(), isFalse);
    expect(await trash.list(), isEmpty);
  });

  test('IMG-014 emptying clears everything', () async {
    await trash.moveToTrash([await photo('a.jpg'), await photo('b.jpg')]);
    await trash.empty();
    expect(await trash.list(), isEmpty);
  });

  test('IMG-014 an entry whose file is gone is not listed', () async {
    final a = await photo('a.jpg');
    final moved = (await trash.moveToTrash([a])).moved;
    trash.fileOf(moved.single).deleteSync();
    expect(await trash.list(), isEmpty);
  });

  test('IMG-014 a damaged index means an empty bin, not a crash', () async {
    File('${dir.path}/bin/index.json')
      ..createSync(recursive: true)
      ..writeAsStringSync('{ not json');
    expect(await trash.list(), isEmpty);
    File('${dir.path}/bin/index.json').writeAsStringSync(jsonEncode({'a': 1}));
    expect(await trash.list(), isEmpty);
  });

  test('IMG-014 several photos move together', () async {
    final out = await trash.moveToTrash([
      await photo('a.jpg'),
      await photo('b.jpg'),
      await photo('c.jpg'),
    ]);
    expect(out.moved, hasLength(3));
    expect(await trash.list(), hasLength(3));
  });
}
