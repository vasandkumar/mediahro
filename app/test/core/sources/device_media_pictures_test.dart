import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mediahro/core/db/library_database.dart';
import 'package:mediahro/core/files/media_store_file_system.dart';
import 'package:mediahro/core/scanner/scan_service.dart';
import 'package:mediahro/core/sources/source_access.dart';
import 'package:mediahro/core/sources/source_builders.dart';
import 'package:mediahro/core/sources/source_repository.dart';
import 'package:mediahro/platform/platform_facades.dart';

import '../files/storage_fakes.dart';

/// Records which permissions were asked for.
final class _Asking extends FakeSafStorage {
  _Asking(super.dir, super.io);

  final state = <PickKind, MediaPermission>{};
  final asked = <PickKind>[];

  @override
  Future<MediaPermission> mediaPermission(PickKind kind) async =>
      state[kind] ?? MediaPermission.denied;

  @override
  Future<MediaPermission> requestMediaPermission(PickKind kind) async {
    asked.add(kind);
    return state[kind] = MediaPermission.granted;
  }
}

/// IMG-001 / IMG-014 (owner hand check): the Photos screen showed none of
/// the device's screenshots. The "Device media" source listed the MediaStore's
/// video and audio only, and never asked to see pictures.
void main() {
  late Directory dir;
  late FakeFdIo io;
  late LibraryDatabase db;

  MediaStoreEntry entry(
    String folder,
    String name,
    PickKind kind,
    int id,
  ) => MediaStoreEntry(
    uri: Uri.parse(
      'content://media/external/${kind == PickKind.image ? 'images' : 'video'}/media/$id',
    ),
    relativePath: folder,
    name: name,
    size: 12,
    modified: DateTime.utc(2026),
    kind: kind,
  );

  setUp(() {
    dir = Directory.systemTemp.createTempSync('device_pics');
    io = FakeFdIo();
    db = LibraryDatabase.memory();
    for (final f in [
      'DCIM/Screenshots/Screenshot_1.png',
      'Pictures/Screenshots/Screenshot_2.jpg',
      'DCIM/Camera/IMG_1.jpg',
      'Movies/Film.mkv',
    ]) {
      File('${dir.path}/$f')
        ..createSync(recursive: true)
        ..writeAsBytesSync(List.filled(12, 1));
    }
  });
  tearDown(() async {
    await db.close();
    for (final f in io.open.values) {
      f.closeSync();
    }
    dir.deleteSync(recursive: true);
  });

  void fill(FakeSafStorage s) => s.media.addAll([
    entry('DCIM/Screenshots/', 'Screenshot_1.png', PickKind.image, 1),
    entry('Pictures/Screenshots/', 'Screenshot_2.jpg', PickKind.image, 2),
    entry('DCIM/Camera/', 'IMG_1.jpg', PickKind.image, 3),
    entry('Movies/', 'Film.mkv', PickKind.video, 4),
  ]);

  test('IMG-001 the device media tree lists the screenshot folders', () async {
    final storage = FakeSafStorage(dir, io);
    fill(storage);
    final fs = MediaStoreFileSystem(storage, io: io);

    final root = await fs.list(MediaStoreFileSystem.root).toList();
    expect(root.map((e) => e.name).toSet(), {'DCIM', 'Pictures', 'Movies'});
    final dcim = await fs
        .list(MediaStoreFileSystem.root.resolve('DCIM/'))
        .toList();
    expect(dcim.map((e) => e.name).toSet(), {'Screenshots', 'Camera'});
    final shots = await fs
        .list(MediaStoreFileSystem.root.resolve('DCIM/Screenshots/'))
        .toList();
    expect(shots.single.name, 'Screenshot_1.png');
    final more = await fs
        .list(MediaStoreFileSystem.root.resolve('Pictures/Screenshots/'))
        .toList();
    expect(more.single.name, 'Screenshot_2.jpg');
  });

  test('IMG-001 a scan of the device media indexes the pictures', () async {
    final storage = FakeSafStorage(dir, io);
    fill(storage);
    await db
        .into(db.sources)
        .insert(
          SourcesCompanion.insert(
            kind: SourceKind.local,
            name: 'Device media',
            rootUri: MediaStoreFileSystem.root.toString(),
            addedAt: DateTime.utc(2026),
          ),
        );
    final resolver = DefaultSourceResolver(
      builders: defaultFileSystemBuilders(storage: storage, fdIo: io),
      storage: storage,
    );

    final out = await ScanService(db: db, resolver: resolver).scan(1);

    expect(out.state, ScanJobState.done, reason: '${out.error}');
    final items = await db.select(db.items).get();
    expect(
      items.where((i) => i.kind == ItemKind.image).map((i) => i.relPath),
      unorderedEquals([
        'DCIM/Screenshots/Screenshot_1.png',
        'Pictures/Screenshots/Screenshot_2.jpg',
        'DCIM/Camera/IMG_1.jpg',
      ]),
    );
    expect(items.where((i) => i.kind == ItemKind.video), hasLength(1));
  });

  test('IMG-001 adding the device media asks to see pictures too', () async {
    final storage = _Asking(dir, io);
    final repo = SourceRepository(
      db: db,
      resolver: DefaultSourceResolver(
        builders: defaultFileSystemBuilders(storage: storage, fdIo: io),
        storage: storage,
      ),
      storage: storage,
    );

    final id = await repo.addDeviceMedia('Device media');

    expect(id, isNotNull);
    expect(
      storage.asked,
      containsAll([PickKind.video, PickKind.audio, PickKind.image]),
    );
  });

  test('IMG-001 refused on every kind adds no source', () async {
    final storage = _Refusing(dir, io);
    final repo = SourceRepository(
      db: db,
      resolver: DefaultSourceResolver(
        builders: defaultFileSystemBuilders(storage: storage, fdIo: io),
        storage: storage,
      ),
      storage: storage,
    );

    expect(await repo.addDeviceMedia('Device media'), isNull);
  });
}

final class _Refusing extends FakeSafStorage {
  _Refusing(super.dir, super.io);

  @override
  Future<MediaPermission> mediaPermission(PickKind kind) async =>
      MediaPermission.denied;

  @override
  Future<MediaPermission> requestMediaPermission(PickKind kind) async =>
      MediaPermission.denied;
}
