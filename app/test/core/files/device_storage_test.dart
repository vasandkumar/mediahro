import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:mediahro/core/db/library_database.dart';
import 'package:mediahro/core/files/file_operations.dart';
import 'package:mediahro/core/files/file_systems.dart';
import 'package:mediahro/core/files/media_store_file_system.dart';
import 'package:mediahro/core/files/picked_files.dart';
import 'package:mediahro/core/files/saf_file_system.dart';
import 'package:mediahro/core/providers.dart' show withMulticast;
import 'package:mediahro/core/scanner/scan_service.dart';
import 'package:mediahro/core/sources/source_access.dart';
import 'package:mediahro/core/sources/source_builders.dart';
import 'package:mediahro/platform/platform_facades.dart';
import 'package:mediahro_ffi/mediahro_ffi.dart';

import 'storage_fakes.dart';

void main() {
  late Directory dir;
  late FakeFdIo io;
  late FakeSafStorage storage;
  late LibraryDatabase db;
  final root = SafFileSystem.rootFor('g1');
  Uri at(String rel) => root.replace(
    pathSegments: [
      ...root.pathSegments.where((s) => s.isNotEmpty),
      ...rel.split('/'),
    ],
  );

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('mediahro_saf');
    io = FakeFdIo();
    storage = FakeSafStorage(dir, io);
    db = LibraryDatabase.memory();
    File('${dir.path}/Films/Movie.mkv')
      ..createSync(recursive: true)
      ..writeAsBytesSync(List.generate(5000, (i) => i % 251));
    File('${dir.path}/Films/Movie.en.srt').writeAsStringSync('subs');
    File('${dir.path}/readme.txt').writeAsStringSync('hi');
  });
  tearDown(() async {
    await db.close();
    for (final f in io.open.values) {
      f.closeSync();
    }
    await dir.delete(recursive: true);
  });

  SafFileSystem saf() =>
      SafFileSystem(storage, tree: FakeSafStorage.tree, root: root, io: io);

  test('LIB-002/FILE-001 SAF trees as paths: list, stat, ranged reads through a detached fd', () async {
    final fs = saf();
    final top = await fs.list(root).toList();
    expect(
      {for (final e in top) e.name: e.isDirectory},
      {'Films': true, 'readme.txt': false},
    );
    final films = top.firstWhere((e) => e.name == 'Films');
    expect(films.uri, at('Films'));
    final movie = (await fs.list(films.uri).toList()).firstWhere(
      (e) => e.name == 'Movie.mkv',
    );
    expect(movie.uri, at('Films/Movie.mkv'));
    expect((await fs.stat(at('Films/Movie.mkv'))).size, 5000);
    final f = await fs.open(movie.uri);
    expect(await f.read(4998, 10), [4998 % 251, 4999 % 251]);
    expect(await f.read(100, 3), [100 % 251, 101 % 251, 102 % 251]);
    expect(await f.read(5000, 1), isEmpty);
    await f.close();
    expect(io.open, isEmpty, reason: 'the fd is closed');
    // A cold file system finds deep paths by walking the tree.
    expect((await saf().stat(at('Films/Movie.en.srt'))).size, 4);
    await expectLater(
      saf().stat(at('Films/missing.mkv')),
      throwsA(isA<VirtualFileException>()),
    );
    expect(
      await fs.documentUri(at('Films/Movie.mkv')),
      isNot(at('Films/Movie.mkv')),
    );
  });

  test('FILE-002 SAF: create, write, rename, move and delete; name clashes are refused, not renamed', () async {
    final fs = saf();
    final up = await fs.createDirectory(root, 'Up');
    expect(Directory('${dir.path}/Up').existsSync(), isTrue);
    await expectLater(
      fs.createDirectory(root, 'Up'),
      throwsA(
        isA<VirtualFileException>().having(
          (e) => e.error,
          'error',
          VirtualFileError.alreadyExists,
        ),
      ),
    );
    expect(Directory('${dir.path}/Up (1)').existsSync(), isFalse);
    final w = await fs.create(at('Up/note.txt'));
    await w.write(utf8.encode('saf '));
    await w.write(utf8.encode('write'));
    await w.close();
    expect(File('${dir.path}/Up/note.txt').readAsStringSync(), 'saf write');
    final renamed = await fs.rename(at('Up/note.txt'), 'n2.txt');
    expect(renamed, at('Up/n2.txt'));
    await expectLater(
      fs.rename(at('readme.txt'), 'Films'),
      throwsA(isA<VirtualFileException>()),
    );
    final moved = await fs.move(renamed, at('Films'));
    expect(moved, at('Films/n2.txt'));
    expect(File('${dir.path}/Films/n2.txt').existsSync(), isTrue);
    await expectLater(
      fs.delete(at('Films')),
      throwsA(isA<VirtualFileException>()),
      reason: 'not empty',
    );
    await fs.delete(up.replace(path: up.path), recursive: true);
    expect(Directory('${dir.path}/Up').existsSync(), isFalse);
    final partial = await fs.create(at('partial.bin'));
    await partial.write([1, 2]);
    await partial.abort();
    expect(File('${dir.path}/partial.bin').existsSync(), isFalse);
    expect(io.open, isEmpty);
  });

  test('FILE-006 renames on SAF keep sidecars together (path-based file operations)', () async {
    final fs = saf();
    final mounts = MountedFileSystems()..mount(root, fs);
    final ops = FileOperations(fileSystems: mounts, db: db);
    final r = await ops.rename(at('Films/Movie.mkv'), 'Holiday.mkv');
    expect(r, at('Films/Holiday.mkv'));
    expect(File('${dir.path}/Films/Holiday.en.srt').existsSync(), isTrue);
    expect(File('${dir.path}/Films/Movie.en.srt').existsSync(), isFalse);
  });

  test('LIB-002/LIB-003 a granted SAF tree scans on the main isolate and releases scoped access', () async {
    final sid = await db
        .into(db.sources)
        .insert(
          SourcesCompanion.insert(
            kind: SourceKind.local,
            name: 'Phone',
            rootUri: FakeSafStorage.tree.toString(),
            grantId: const Value('g1'),
            addedAt: DateTime.utc(2026),
          ),
        );
    final resolver = DefaultSourceResolver(
      builders: defaultFileSystemBuilders(storage: storage, fdIo: io),
      storage: storage,
    );
    final access = await resolver.resolve(
      await (db.select(db.sources)..where((s) => s.id.equals(sid))).getSingle(),
    );
    expect(access.root, root);
    expect(access.mainIsolate, isTrue);
    expect(access.spec.options['safTree'], FakeSafStorage.tree.toString());
    await access.close();
    final out = await ScanService(db: db, resolver: resolver).scan(sid);
    expect(out.state, ScanJobState.done, reason: '${out.error}');
    final items = await db.select(db.items).get();
    expect(
      items.map((i) => i.relPath),
      containsAll(['Films/Movie.mkv', 'Films/Movie.en.srt']),
    );
    expect(storage.started, 2);
    expect(storage.stopped, 2, reason: 'access ends with each scan');
  });

  test('LIB-002 device media: a MediaStore tree, reads by fd, deletes through the MediaStore trash with undo', () async {
    storage.media.addAll([
      MediaStoreEntry(
        uri: Uri.parse('content://media/external/video/media/7'),
        relativePath: 'Films/',
        name: 'Movie.mkv',
        size: 5000,
        modified: DateTime.utc(2026),
        kind: PickKind.video,
      ),
      MediaStoreEntry(
        uri: Uri.parse('content://media/external/audio/media/9'),
        relativePath: 'Music/Artist/',
        name: 'readme.txt',
        size: 2,
        modified: DateTime.utc(2026),
        kind: PickKind.audio,
      ),
    ]);
    File('${dir.path}/Music/Artist/readme.txt')
      ..createSync(recursive: true)
      ..writeAsStringSync('hi');
    final fs = MediaStoreFileSystem(storage, io: io);
    final r = MediaStoreFileSystem.root;
    expect(
      (await fs.list(r).toList()).map((e) => (e.name, e.isDirectory)).toSet(),
      {('Films', true), ('Music', true)},
    );
    final artist = await fs.list(r.resolve('Music/Artist/')).toList();
    expect(artist.single.name, 'readme.txt');
    final movie = r.resolve('Films/Movie.mkv');
    expect((await fs.stat(movie)).size, 5000);
    final f = await fs.open(movie);
    expect(await f.read(10, 2), [10, 11]);
    await f.close();
    expect(
      await fs.contentUri(movie),
      Uri.parse('content://media/external/video/media/7'),
    );

    final sid = await db
        .into(db.sources)
        .insert(
          SourcesCompanion.insert(
            kind: SourceKind.local,
            name: 'Device media',
            rootUri: r.toString(),
            addedAt: DateTime.utc(2026),
          ),
        );
    final resolver = DefaultSourceResolver(
      builders: defaultFileSystemBuilders(storage: storage, fdIo: io),
      storage: storage,
    );
    expect(
      (await resolver.resolve(
        await (db.select(
          db.sources,
        )..where((s) => s.id.equals(sid))).getSingle(),
      )).mainIsolate,
      isTrue,
    );
    expect(
      (await ScanService(db: db, resolver: resolver).scan(sid)).state,
      ScanJobState.done,
    );

    final mounts = MountedFileSystems()..mount(r, fs);
    final ops = FileOperations(fileSystems: mounts, db: db, storage: storage);
    final del = await ops.delete([movie]);
    expect(storage.trashed.single, [
      Uri.parse('content://media/external/video/media/7'),
    ]);
    expect(del.trashed, [movie]);
    expect(del.canUndo, isTrue);
    final item = (await db.select(db.items).get()).firstWhere(
      (i) => i.name == 'Movie.mkv',
    );
    expect(
      (await (db.select(
        db.items,
      )..where((i) => i.id.equals(item.id))).getSingle()).missing,
      isTrue,
    );
    await ops.undoDelete(del);
    expect(storage.restored, hasLength(1));
    expect(
      (await (db.select(
        db.items,
      )..where((i) => i.id.equals(item.id))).getSingle()).missing,
      isFalse,
    );
  });

  test('CORE-014/LIB-007 picked files: content URIs read through an fd, file URIs with dart:io; size limit', () async {
    final content = await storage.createDocument(
      FakeSafStorage.tree,
      'backup.bin',
    );
    File('${dir.path}/backup.bin').writeAsBytesSync([1, 2, 3]);
    expect(await readPickedFile(storage, content, io: io), [1, 2, 3]);
    expect(io.open, isEmpty);
    expect(
      await readPickedFile(storage, File('${dir.path}/readme.txt').uri),
      utf8.encode('hi'),
    );
    await expectLater(
      readPickedFile(storage, File('${dir.path}/readme.txt').uri, maxBytes: 1),
      throwsA(isA<VirtualFileException>()),
    );
  });

  test('FILE-002 share/open-in hand over URIs other apps can read; network files have none', () async {
    final fs = saf();
    final doc = await shareableUri(fs, at('Films/Movie.mkv'));
    expect(doc?.scheme, 'content');
    expect(
      await shareableUri(
        const LocalFileSystem(),
        File('${dir.path}/readme.txt').uri,
      ),
      isNotNull,
    );
    expect(
      await shareableUri(const LocalFileSystem(), Uri.parse('smb://nas/x.mkv')),
      isNull,
    );
  });

  test(
    'NET-001/NET-005 discovery holds the multicast lease while it runs',
    () async {
      final mc = _FakeMulticast();
      final out = await withMulticast(
        mc,
        'mediahro-ssdp',
        () => Stream.fromIterable([1, 2]),
      ).toList();
      expect(out, [1, 2]);
      expect(mc.acquired, ['mediahro-ssdp']);
      expect(mc.released, 1);
      // Cancelling early releases too.
      final sub = withMulticast(
        mc,
        't',
        () => Stream<int>.periodic(const Duration(milliseconds: 5), (i) => i),
      ).listen((_) {});
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await sub.cancel();
      expect(mc.released, 2);
    },
  );
}

final class _FakeMulticast implements MulticastFacade {
  final List<String> acquired = [];
  int released = 0;

  @override
  Future<MulticastLease> acquire(String tag) async {
    acquired.add(tag);
    return _Lease(this);
  }
}

final class _Lease implements MulticastLease {
  _Lease(this.m);

  final _FakeMulticast m;

  @override
  Future<void> release() async => m.released++;
}
