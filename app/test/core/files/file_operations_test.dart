import 'dart:io';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:mediahro/core/db/library_database.dart';
import 'package:mediahro/core/files/batch.dart';
import 'package:mediahro/core/files/file_operations.dart';
import 'package:mediahro/core/files/file_systems.dart';
import 'package:mediahro/core/scanner/scan_service.dart';
import 'package:mediahro/images/image_pipeline.dart';
import 'package:mediahro/platform/storage.dart';
import 'package:mediahro_ffi/mediahro_ffi.dart';

import '../scanner/scanner_test.dart' show addSource, localResolver, touch;

/// Moves files into a hidden folder and back (stands in for the OS trash).
final class _FakeTrash implements StorageFacade {
  _FakeTrash(this.bin);

  final Directory bin;
  final moved = <String, String>{};

  @override
  Future<TrashResult> moveToTrash(List<Uri> uris) async {
    final out = <Uri>[];
    for (final u in uris) {
      final f = File.fromUri(u);
      final dest =
          '${bin.path}${Platform.pathSeparator}${moved.length}-${f.uri.pathSegments.last}';
      f.renameSync(dest);
      moved[dest] = f.path;
      out.add(u);
    }
    return TrashResult(trashed: out, undoToken: 'token');
  }

  @override
  Future<void> restoreFromTrash(TrashResult result) async {
    moved.forEach((from, to) => File(from).renameSync(to));
    moved.clear();
  }

  @override
  Object? noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late LibraryDatabase db;
  late Directory dir;
  late Directory bin;
  late FileOperations ops;
  late int sid;

  setUp(() async {
    db = LibraryDatabase.memory();
    dir = await Directory.systemTemp.createTemp('mediahro_ops');
    bin = await Directory.systemTemp.createTemp('mediahro_bin');
    await touch(dir, 'Films/Old Name.mkv', 'film');
    await touch(dir, 'Films/Old Name.en.srt', 'subs');
    await touch(dir, 'Films/Other.mkv', 'other');
    sid = await addSource(db, dir.uri);
    await ScanService(
      db: db,
      resolver: localResolver(),
      useIsolates: false,
    ).scan(sid);
    ops = FileOperations(
      fileSystems: MountedFileSystems(),
      db: db,
      storage: _FakeTrash(bin),
    );
  });
  tearDown(() async {
    await db.close();
    await dir.delete(recursive: true);
    await bin.delete(recursive: true);
  });

  Uri u(String rel) => File('${dir.path}/$rel').uri;

  Future<ItemRow> item(String rel) =>
      (db.select(db.items)..where((i) => i.relPath.equals(rel))).getSingle();

  test(
    'FILE-002/FILE-006 rename carries sidecars and keeps the index row',
    () async {
      final before = await item('Films/Old Name.mkv');
      await db
          .into(db.progress)
          .insert(
            ProgressCompanion.insert(
              itemId: Value(before.id),
              positionMs: 9000,
              updatedAt: DateTime.utc(2026),
            ),
          );
      await ops.rename(u('Films/Old Name.mkv'), 'New Name.mkv');
      expect(File('${dir.path}/Films/New Name.mkv').existsSync(), isTrue);
      expect(
        File('${dir.path}/Films/New Name.en.srt').existsSync(),
        isTrue,
        reason: 'sidecar follows',
      );
      final after = await item('Films/New Name.mkv');
      expect(after.id, before.id);
      expect(after.title, 'New Name');
      expect((await db.select(db.progress).getSingle()).itemId, before.id);
    },
  );

  test('FILE-002 new folder, move, copy; delete to trash with undo', () async {
    final archive = await ops.newFolder(dir.uri, 'Archive');
    await ops.copy([u('Films/Other.mkv')], archive).drain<void>();
    expect(File('${dir.path}/Archive/Other.mkv').readAsStringSync(), 'other');
    final progress = await ops.move([u('Films/Other.mkv')], dir.uri).toList();
    expect(progress.last.done, 1);
    expect(File('${dir.path}/Other.mkv').existsSync(), isTrue);
    expect((await item('Other.mkv')).name, 'Other.mkv');

    final del = await ops.delete([u('Other.mkv')]);
    expect(del.canUndo, isTrue);
    expect(File('${dir.path}/Other.mkv').existsSync(), isFalse);
    expect((await item('Other.mkv')).missing, isTrue);
    await ops.undoDelete(del);
    expect(File('${dir.path}/Other.mkv').existsSync(), isTrue);
    expect((await item('Other.mkv')).missing, isFalse);
  });

  test(
    'FILE-002 sources without a trash need explicit permanent delete',
    () async {
      final noTrash = FileOperations(fileSystems: MountedFileSystems(), db: db);
      await expectLater(
        noTrash.delete([u('Films/Other.mkv')]),
        throwsA(isA<VirtualFileException>()),
      );
      final r = await noTrash.delete([
        u('Films/Other.mkv'),
      ], allowPermanent: true);
      expect(r.canUndo, isFalse);
      expect(File('${dir.path}/Films/Other.mkv').existsSync(), isFalse);
    },
  );

  test(
    'FILE-003 batch rename with patterns and metadata tokens; conflicts block',
    () async {
      final facts = [
        RenameFacts(
          name: 'IMG_0001.JPG',
          modified: DateTime.utc(2026, 7, 4, 9, 30),
        ),
        RenameFacts(
          name: 'IMG_0002.JPG',
          modified: DateTime.utc(2026, 7, 4, 9, 31),
        ),
      ];
      final plan = planRename(facts, '{date:yyyy-MM-dd} Holiday {n:3}');
      expect(plan.map((p) => p.to), [
        '2026-07-04 Holiday 001.JPG',
        '2026-07-04 Holiday 002.JPG',
      ]);
      expect(plan.any((p) => p.conflict), isFalse);
      expect(planRename(facts, 'same').every((p) => p.conflict), isTrue);
      const ep = RenameFacts(
        name: 'x.mkv',
        title: 'Pilot',
        season: 1,
        episode: 2,
        year: 2008,
      );
      expect(
        expandPattern(
          'S{season:2}E{episode:2} - {title} ({year}).{ext}',
          ep,
          0,
        ),
        'S01E02 - Pilot (2008).mkv',
      );
      expect(
        expandPattern('a/b:c', ep, 0),
        'a_b_c.mkv',
        reason: 'unsafe characters replaced',
      );
      expect(
        () => expandPattern('{bogus}', ep, 0),
        throwsA(isA<PatternError>()),
      );

      final films = [u('Films/Old Name.mkv'), u('Films/Other.mkv')];
      final rows = [
        await item('Films/Old Name.mkv'),
        await item('Films/Other.mkv'),
      ];
      final p = planRename([
        for (final r in rows) await factsFor(db, r),
      ], 'Film {n}');
      await applyRename(ops, films, p);
      expect(File('${dir.path}/Films/Film 1.mkv').existsSync(), isTrue);
      expect(File('${dir.path}/Films/Film 1.en.srt').existsSync(), isTrue);
      expect(File('${dir.path}/Films/Film 2.mkv').existsSync(), isTrue);
    },
  );

  test(
    'FILE-003 batch image conversion goes through the image pipeline',
    () async {
      await touch(dir, 'Photos/a.png', 'png');
      final pipeline = _FakePipeline();
      final out = await convertImages(
        pipeline,
        MountedFileSystems(),
        [u('Photos/a.png')],
        const EncodeOptions(
          format: EncodeFormat.webp,
          quality: 80,
          maxEdge: 2048,
        ),
      );
      expect(out.single.path, endsWith('/Photos/a.webp'));
      expect(pipeline.exports.single.$2.format, EncodeFormat.webp);
    },
  );
}

final class _FakePipeline implements ImagePipeline {
  final exports = <(Uri, EncodeOptions)>[];

  @override
  Future<void> export(
    ImageSource src,
    List<EditOp> ops,
    Uri destination,
    EncodeOptions options,
  ) async {
    exports.add((destination, options));
    File.fromUri(destination).writeAsBytesSync(Uint8List(1));
  }

  @override
  Object? noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
