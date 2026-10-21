import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' show Variable;
import 'package:flutter_test/flutter_test.dart';
import 'package:mediahro/core/db/library_database.dart';
import 'package:mediahro/features/photos/organise/photo_organiser.dart';
import 'package:mediahro/features/photos/timeline/timeline_model.dart';
import 'package:mediahro/features/photos/vault/vault_container.dart';
import 'package:mediahro/features/photos/vault/vault_mover.dart';
import 'package:mediahro/images/metadata/metadata_codec.dart';
import 'package:mediahro/images/pipeline/image_worker.dart';
import 'package:mediahro/images/pipeline/mediahro_image_pipeline.dart';
import 'package:mediahro/images/pipeline/thumbnail_cache.dart';
import 'package:mediahro/images/pipeline/worker_pool.dart';
import 'package:mediahro/platform/vault_crypto.dart';

import '../../core/seed.dart';
import '../../images/fixtures.dart';
import '../../images/pipeline_fakes.dart';
import 'disk_support.dart';
import 'fake_vault_crypto.dart';
import 'photos_harness.dart';

Uint8List bytesOf(int n, [int seed = 1]) =>
    Uint8List.fromList(List.generate(n, (i) => (i * 31 + seed) & 0xFF));

void main() {
  late Directory dir;
  late LibraryDatabase db;
  late DiskIo io;
  late FakeVaultCrypto crypto;
  late VaultContainer vault;
  late MediahroImagePipeline pipeline;
  late ThumbnailCache cache;
  late VaultMover mover;
  late Seed seed;
  late PhotoOrganiser org;

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('mediahro-vault-mover');
    db = LibraryDatabase.memory();
    seed = Seed(db);
    org = PhotoOrganiser(db: db);
    io = DiskIo();
    crypto = FakeVaultCrypto();
    final master = await crypto.openMasterKey(requireBiometry: false);
    vault = await VaultContainer.create(
      directory: Directory('${dir.path}/v'),
      crypto: crypto,
      master: master,
      token: bytesOf(32, 5),
    );
    cache = ThumbnailCache(db: db, directory: Directory('${dir.path}/thumbs'));
    pipeline = MediahroImagePipeline(
      worker: ImageWorkerClient(
        IsolateWorkerPool(size: 1, factory: fakeWorker),
      ),
      cache: cache,
      io: io,
      fallback: FakeUiFallback(),
    );
    mover = VaultMover(
      files: DiskFiles(Directory('${dir.path}/lib'), io),
      io: io,
      db: db,
      pipeline: pipeline,
    );
  });

  tearDown(() async {
    await pipeline.dispose();
    await db.close();
    try {
      dir.deleteSync(recursive: true);
    } on FileSystemException {
      // Best effort on Windows.
    }
  });

  Future<PhotoEntry> photo(
    String rel, {
    Uint8List? data,
    bool video = false,
  }) async {
    final bytes = data ?? bytesOf(4000, rel.length);
    File('${dir.path}/lib/$rel')
      ..createSync(recursive: true)
      ..writeAsBytesSync(bytes);
    final id = await seed.item(
      rel,
      kind: video ? ItemKind.video : ItemKind.image,
      size: bytes.length,
    );
    final base = fakeEntries(days: 1, perDay: 1, firstId: id).single;
    return PhotoEntry(
      id: id,
      sourceId: 1,
      relPath: rel,
      name: rel.split('/').last,
      ext: rel.split('.').last,
      isVideo: video,
      size: bytes.length,
      mtime: base.mtime,
      date: base.date,
      width: 40,
      height: 30,
    );
  }

  Future<int> itemRows() async => (await db.select(db.items).get()).length;

  group('IMG-011 moving photos in', () {
    test('IMG-011 a moved photo is encrypted in, read back and gone from its folder', () async {
      final data = bytesOf(5000, 3);
      final p = await photo('trip/a.jpg', data: data);
      final r = await mover.moveIn(vault, [p]);
      expect(r.moved, 1);
      expect(File('${dir.path}/lib/trip/a.jpg').existsSync(), isFalse);
      final item = vault.list().single;
      expect(
        (item.name, item.kind, item.size, item.width),
        ('a.jpg', 'image', 5000, 40),
      );
      expect(await vault.readAll(item.id), data);
    });

    test('IMG-011 videos are kept as videos', () async {
      final v = await photo('c.mp4', video: true);
      await mover.moveIn(vault, [v]);
      expect(vault.list().single.kind, 'video');
    });

    test('IMG-011 progress is reported and a move can be stopped', () async {
      final ps = [
        await photo('a.jpg'),
        await photo('b.jpg'),
        await photo('c.jpg'),
      ];
      final seen = <int>[];
      final r = await mover.moveIn(
        vault,
        ps,
        onProgress: seen.add,
        cancelled: () => seen.length >= 2,
      );
      expect(seen, [1, 2]);
      expect(r.stopped, isTrue);
      expect(r.moved, 2);
      expect(File('${dir.path}/lib/c.jpg').existsSync(), isTrue);
    });

    test('IMG-011 a missing file is reported and the rest are moved', () async {
      final a = await photo('a.jpg');
      final b = await photo('b.jpg');
      File('${dir.path}/lib/a.jpg').deleteSync();
      final r = await mover.moveIn(vault, [a, b]);
      expect(r.moved, 1);
      expect(r.failed, ['a.jpg']);
      expect(vault.list().single.name, 'b.jpg');
    });
  });

  group('IMG-011 a failure never costs the photo', () {
    test(
      'IMG-011 an original that cannot be removed stays out of the vault',
      () async {
        final p = await photo('a.jpg');
        io.failDelete = true;
        final r = await mover.moveIn(vault, [p]);
        expect(r.moved, 0);
        expect(r.failed, ['a.jpg']);
        expect(vault.list(), isEmpty);
        expect(File('${dir.path}/lib/a.jpg').existsSync(), isTrue);
        final files = Directory('${dir.path}/v')
            .listSync()
            .whereType<File>()
            .map((f) => f.path.split(Platform.pathSeparator).last)
            .where((n) => n.endsWith('.mv') && n != 'index.mv');
        expect(files, isEmpty);
        // Still in the library, untouched.
        expect(await itemRows(), 1);
      },
    );

    test(
      'IMG-011 if the library clean-up fails the vault copy stays',
      () async {
        final p = await photo('a.jpg');
        // Take the table away so the clean-up cannot run.
        await db.customStatement('DROP TABLE playlist_item');
        final r = await mover.moveIn(vault, [p]);
        expect(r.moved, 1);
        expect(r.leftInLibrary, ['a.jpg']);
        expect(r.failed, isEmpty);
        expect(File('${dir.path}/lib/a.jpg').existsSync(), isFalse);
        // The only copy is in the vault and reads.
        expect(vault.list().single.name, 'a.jpg');
        expect(
          await vault.readAll(vault.list().single.id),
          bytesOf(4000, 'a.jpg'.length),
        );
      },
    );

    test(
      'IMG-011 if clearing cached pictures fails the vault copy stays',
      () async {
        final p = await photo('a.jpg');
        await db.customStatement('DROP TABLE thumb_cache');
        final r = await mover.moveIn(vault, [p]);
        expect(r.moved, 1);
        expect(vault.list(), hasLength(1));
        expect(File('${dir.path}/lib/a.jpg').existsSync(), isFalse);
      },
    );

    test(
      'IMG-011 a failed encryption leaves the original and the library alone',
      () async {
        final p = await photo('a.jpg');
        crypto.failChunks = VaultCryptoError.unavailable;
        final r = await mover.moveIn(vault, [p]);
        expect(r.failed, ['a.jpg']);
        expect(File('${dir.path}/lib/a.jpg').existsSync(), isTrue);
        expect(await itemRows(), 1);
        expect(vault.list(), isEmpty);
      },
    );
  });

  group('IMG-011 nothing about the photo stays in the library', () {
    test(
      'IMG-011 the entry and everything hanging on it go in one step',
      () async {
        final p = await photo('trip/a.jpg');
        final keep = await photo('b.jpg');
        await org.addTag([p.id], 'holiday');
        await org.setRating([p.id], 4);
        await org.setFavourite([p.id], value: true);
        await org.setLabel([p.id], LabelColor.red);
        await org.createAlbum('Trip', items: [p.id, keep.id]);
        await mover.moveIn(vault, [p]);
        expect((await db.select(db.items).get()).map((i) => i.id), [keep.id]);
        expect(await db.select(db.ratings).get(), isEmpty);
        expect(await db.select(db.labels).get(), isEmpty);
        expect(await db.select(db.itemTags).get(), isEmpty);
        expect(
          (await db.select(db.imageMeta).get()).where((m) => m.itemId == p.id),
          isEmpty,
        );
        final fts = await db
            .customSelect(
              'SELECT rowid FROM item_fts WHERE rowid = ?',
              variables: [Variable.withInt(p.id)],
            )
            .get();
        expect(fts, isEmpty);
        // The album keeps the photo that stayed, with no trace of the other.
        final rows = await db.select(db.playlistItems).get();
        expect(rows.map((r) => r.itemId), [keep.id]);
      },
    );

    test('IMG-011 the vault keeps what the library knew', () async {
      final p = await photo('a.jpg');
      await org.addTag([p.id], 'holiday');
      await org.addTag([p.id], 'family');
      await org.setRating([p.id], 3);
      await org.setFavourite([p.id], value: true);
      await org.setLabel([p.id], LabelColor.blue);
      await mover.moveIn(vault, [p]);
      final item = vault.list().single;
      expect(item.tags.toSet(), {'holiday', 'family'});
      expect(item.halfStars, 6);
      expect(item.favourite, isTrue);
      expect(item.label, 'blue');
    });

    test('IMG-011 its cached thumbnails go too', () async {
      final p = await photo('a.jpg');
      final uri = File('${dir.path}/lib/a.jpg').uri;
      final key = ThumbnailCache.keyFor(
        uri: uri,
        edge: 256,
        mtime: p.mtime,
        size: p.size,
      );
      final thumb = await cache.store(key, bytesOf(100));
      expect(thumb.existsSync(), isTrue);
      await mover.moveIn(vault, [p]);
      expect(thumb.existsSync(), isFalse);
      expect(await cache.lookup(key), isNull);
    });

    test(
      'IMG-011 the picture of an item is made without touching the cache',
      () async {
        final p = await photo('a.jpg');
        await mover.moveIn(vault, [p]);
        expect(
          Directory('${dir.path}/thumbs').existsSync()
              ? Directory('${dir.path}/thumbs').listSync()
              : <FileSystemEntity>[],
          isEmpty,
        );
        expect(await db.select(db.thumbCache).get(), isEmpty);
      },
    );
  });

  group('IMG-011 taking items out', () {
    test('IMG-011 an item streams back in pieces', () async {
      final data = bytesOf(2500000, 8);
      final item = await vault.add(
        name: 'big.jpg',
        kind: 'image',
        content: Stream.value(data),
        size: data.length,
      );
      final out = BytesBuilder(copy: false);
      await vaultContent(vault, item).forEach(out.add);
      expect(out.takeBytes(), data);
    });

    test('IMG-011 the rating, label and tags are written into the file that comes out', () async {
      final jpeg = sampleJpeg(exif: sampleExif());
      final item = await vault.add(
        name: 'a.jpg',
        kind: 'image',
        content: Stream.value(jpeg),
        size: jpeg.length,
        tags: ['holiday', 'family'],
        halfStars: 7,
        label: 'red',
      );
      final out = BytesBuilder(copy: false);
      await restoredContent(vault, item).forEach(out.add);
      final m = parseMetadata(out.takeBytes(), extension: 'jpg').metadata;
      expect(m.rating, 4);
      expect(m.keywords, containsAll(['holiday', 'family']));
    });

    test(
      'IMG-011 an item with nothing to restore comes out byte for byte',
      () async {
        final jpeg = sampleJpeg(exif: sampleExif());
        final item = await vault.add(
          name: 'a.jpg',
          kind: 'image',
          content: Stream.value(jpeg),
          size: jpeg.length,
        );
        final out = BytesBuilder(copy: false);
        await restoredContent(vault, item).forEach(out.add);
        expect(out.takeBytes(), jpeg);
      },
    );

    test(
      'IMG-011 a format that cannot hold the metadata comes out unchanged',
      () async {
        final data = bytesOf(3000, 4);
        final item = await vault.add(
          name: 'a.bin',
          kind: 'image',
          content: Stream.value(data),
          size: data.length,
          tags: ['x'],
        );
        final out = BytesBuilder(copy: false);
        await restoredContent(vault, item).forEach(out.add);
        expect(out.takeBytes(), data);
      },
    );
  });
}
