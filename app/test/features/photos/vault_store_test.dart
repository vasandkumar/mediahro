import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mediahro/core/db/library_database.dart';
import 'package:mediahro/features/photos/timeline/timeline_model.dart';
import 'package:mediahro/features/photos/vault/vault_crypto.dart';
import 'package:mediahro/features/photos/vault/vault_keys.dart';
import 'package:mediahro/features/photos/vault/vault_mover.dart';
import 'package:mediahro/features/photos/vault/vault_store.dart';
import 'package:mediahro/images/pipeline/image_worker.dart';
import 'package:mediahro/images/pipeline/mediahro_image_pipeline.dart';
import 'package:mediahro/images/pipeline/thumbnail_cache.dart';
import 'package:mediahro/images/pipeline/worker_pool.dart';
import 'package:mediahro/platform/security.dart';

import '../../core/seed.dart';
import '../../images/pipeline_fakes.dart';
import 'disk_support.dart';
import 'photos_harness.dart';

Uint8List bytesOf(int n, [int seed = 1]) =>
    Uint8List.fromList(List.generate(n, (i) => (i * 31 + seed) & 0xFF));

/// "Hardware" wrapping by a fixed pad: only this fake can unwrap.
final class FakeSecure implements SecureStorageFacade {
  bool failUnwrap = false;
  bool lastRequiredBiometry = false;

  @override
  Future<List<int>> wrapKey(
    List<int> key, {
    required bool requireBiometry,
  }) async {
    lastRequiredBiometry = requireBiometry;
    return [0xAB, ...key.map((b) => b ^ 0x5A)];
  }

  @override
  Future<List<int>> unwrapKey(
    List<int> wrapped, {
    required String reason,
  }) async {
    if (failUnwrap) throw StateError('cancelled');
    return [for (final b in wrapped.skip(1)) b ^ 0x5A];
  }

  @override
  Future<String?> read(String key) async => null;

  @override
  Future<void> write(String key, String value) async {}

  @override
  Future<void> delete(String key) async {}
}

final class FakeBiometrics implements BiometricsFacade {
  FakeBiometrics([this.kind = BiometricKind.fingerprint]);

  BiometricKind kind;

  @override
  Future<BiometricKind> available() async => kind;

  @override
  Future<bool> authenticate({required String reason}) async => true;
}

void main() {
  late Directory dir;
  late VaultStore store;
  late Uint8List key;

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('mediahro-vault');
    key = VaultCrypto.randomBytes(32);
    store = VaultStore(
      directory: Directory('${dir.path}/v'),
      crypto: VaultCrypto(key),
    );
    await store.open();
  });

  tearDown(() => dir.deleteSync(recursive: true));

  Future<VaultItem> put(
    String name,
    Uint8List data, {
    DateTime? taken,
    String kind = 'image',
  }) => store.add(
    name: name,
    kind: kind,
    content: Stream.value(data),
    size: data.length,
    takenAt: taken,
  );

  group('IMG-011 vault store', () {
    test('IMG-011 a new vault is an empty folder nobody lists', () {
      expect(store.list(), isEmpty);
      expect(File('${dir.path}/v/.nomedia').existsSync(), isTrue);
      expect(File('${dir.path}/v/index.mv').existsSync(), isTrue);
    });

    test('IMG-011 an added file reads back, in whole and in ranges', () async {
      final data = bytesOf(200000);
      final item = await put('holiday.jpg', data);
      final f = await store.openFile(item.id);
      expect(await f.length(), data.length);
      expect(f.isSeekable, isTrue);
      expect(await f.read(0, 100), data.sublist(0, 100));
      expect(await f.read(70000, 70000), data.sublist(70000, 140000));
      await f.close();
      expect(await store.readAll(item.id), data);
    });

    test(
      'IMG-011 no name and no picture byte is on disk in the clear',
      () async {
        final data = Uint8List.fromList(
          utf8.encode('SECRET-PICTURE-BYTES-' * 200),
        );
        await put('my-secret-name.jpg', data);
        for (final f in Directory(
          '${dir.path}/v',
        ).listSync().whereType<File>()) {
          if (f.path.endsWith('.nomedia')) continue;
          final raw = f.readAsBytesSync();
          final text = latin1.decode(raw);
          expect(text.contains('my-secret-name'), isFalse, reason: f.path);
          expect(text.contains('SECRET-PICTURE'), isFalse, reason: f.path);
        }
        expect(
          Directory('${dir.path}/v')
              .listSync()
              .whereType<File>()
              .where((f) => f.path.endsWith('.mv')),
          hasLength(2),
        );
      },
    );

    test(
      'IMG-011 files are called by a random id, not by their name',
      () async {
        final item = await put('a.jpg', bytesOf(10));
        expect(item.id, matches(RegExp(r'^[0-9a-f]{32}$')));
        expect(File('${dir.path}/v/${item.id}.mv').existsSync(), isTrue);
      },
    );

    test('IMG-011 a reopened vault lists the same items', () async {
      await put('b.jpg', bytesOf(10), taken: DateTime(2026, 2));
      await put('a.jpg', bytesOf(10), taken: DateTime(2026, 5));
      final again = VaultStore(
        directory: Directory('${dir.path}/v'),
        crypto: VaultCrypto(key),
      );
      await again.open();
      expect(again.list().map((i) => i.name), [
        'a.jpg',
        'b.jpg',
      ], reason: 'newest first');
      expect(again.byId(again.list().first.id)?.name, 'a.jpg');
      expect(again.byId('nope'), isNull);
    });

    test('IMG-011 another key cannot open the vault', () async {
      await put('a.jpg', bytesOf(10));
      final wrong = VaultStore(
        directory: Directory('${dir.path}/v'),
        crypto: VaultCrypto(VaultCrypto.randomBytes(32)),
      );
      await expectLater(wrong.open(), throwsA(isA<VaultCorrupt>()));
    });

    test('IMG-011 removing an item removes its file', () async {
      final item = await put('a.jpg', bytesOf(10));
      await store.remove(item.id);
      expect(store.list(), isEmpty);
      expect(File('${dir.path}/v/${item.id}.mv').existsSync(), isFalse);
    });

    test('IMG-011 a failed add leaves nothing behind', () async {
      final before = Directory('${dir.path}/v').listSync().length;
      await expectLater(
        store.add(
          name: 'x.jpg',
          kind: 'image',
          content: Stream<List<int>>.error(StateError('read failed')),
          size: 100,
        ),
        throwsStateError,
      );
      expect(Directory('${dir.path}/v').listSync().length, before);
      expect(store.list(), isEmpty);
    });

    test('IMG-011 facts about an item are kept', () async {
      final item = await store.add(
        name: 'p.jpg',
        kind: 'image',
        content: Stream.value(bytesOf(5)),
        size: 5,
        takenAt: DateTime(2026, 3, 4),
        width: 4000,
        height: 3000,
      );
      final again = VaultStore(
        directory: Directory('${dir.path}/v'),
        crypto: VaultCrypto(key),
      );
      await again.open();
      final back = again.byId(item.id)!;
      expect(
        (back.width, back.height, back.kind, back.size),
        (4000, 3000, 'image', 5),
      );
      expect(back.takenAt, DateTime(2026, 3, 4));
      expect(back.ext, 'jpg');
    });

    test('IMG-011 a damaged file is reported when it is opened', () async {
      final item = await put('a.jpg', bytesOf(100000));
      final f = File('${dir.path}/v/${item.id}.mv');
      final raw = f.readAsBytesSync();
      raw[200] ^= 1;
      f.writeAsBytesSync(raw);
      final vf = await store.openFile(item.id);
      await expectLater(vf.read(0, 1000), throwsA(isA<VaultCorrupt>()));
      await vf.close();
    });

    test('IMG-011 a bigger file streams in through several pieces', () async {
      final data = bytesOf(300000, 9);
      final item = await store.add(
        name: 'big.jpg',
        kind: 'image',
        content: Stream.fromIterable([
          for (var i = 0; i < data.length; i += 50000)
            data.sublist(i, i + 50000),
        ]),
        size: data.length,
      );
      expect(await store.readAll(item.id), data);
    });
  });

  group('IMG-011 keys', () {
    late FakeSecure secure;
    late FakeBiometrics bio;
    late VaultKeys keys;

    setUp(() {
      secure = FakeSecure();
      bio = FakeBiometrics();
      keys = VaultKeys(
        root: Directory('${dir.path}/root'),
        secure: secure,
        biometrics: bio,
        pinIterations: 100,
      );
    });

    test('IMG-011 the device needs a screen lock or biometrics', () async {
      expect(await keys.available(), isTrue);
      bio.kind = BiometricKind.none;
      expect(await keys.available(), isFalse);
    });

    test(
      'IMG-011 creating the vault wraps its key with the hardware',
      () async {
        expect(keys.exists, isFalse);
        final s = await keys.create();
        expect(keys.exists, isTrue);
        expect(secure.lastRequiredBiometry, isTrue);
        final wrapped = File('${dir.path}/root/real/master.key')
            .readAsBytesSync();
        expect(wrapped.length, 33);
        await s.add(
          name: 'a.jpg',
          kind: 'image',
          content: Stream.value(bytesOf(10)),
          size: 10,
        );
      },
    );

    test('IMG-011 unlocking brings back the same vault', () async {
      final s = await keys.create();
      await s.add(
        name: 'a.jpg',
        kind: 'image',
        content: Stream.value(bytesOf(10)),
        size: 10,
      );
      final r = await keys.unlock(reason: 'Open the vault');
      expect(r.result, VaultUnlock.opened);
      expect(r.store!.list().single.name, 'a.jpg');
    });

    test('IMG-011 no vault yet means set it up', () async {
      final r = await keys.unlock(reason: 'x');
      expect(r.result, VaultUnlock.needsSetup);
      expect(r.store, isNull);
    });

    test('IMG-011 backing out of the prompt opens nothing', () async {
      await keys.create();
      secure.failUnwrap = true;
      final r = await keys.unlock(reason: 'x');
      expect(r.result, VaultUnlock.cancelled);
      expect(r.store, isNull);
    });

    test('IMG-011 a master key that does not fit is a failure', () async {
      await keys.create();
      final bad = VaultKeys(
        root: Directory('${dir.path}/root'),
        secure: _OtherKey(),
        biometrics: bio,
      );
      final r = await bad.unlock(reason: 'x');
      expect(r.result, VaultUnlock.failed);
    });

    test(
      'IMG-011 the decoy opens with its PIN and holds other things',
      () async {
        final real = await keys.create();
        await real.add(
          name: 'real.jpg',
          kind: 'image',
          content: Stream.value(bytesOf(10)),
          size: 10,
        );
        expect(keys.decoyExists, isFalse);
        final decoy = await keys.createDecoy('2468');
        await decoy.add(
          name: 'cat.jpg',
          kind: 'image',
          content: Stream.value(bytesOf(10, 4)),
          size: 10,
        );
        expect(keys.decoyExists, isTrue);
        final d = await keys.unlockDecoy('2468');
        expect(d.result, VaultUnlock.opened);
        expect(d.store!.list().single.name, 'cat.jpg');
        final r = await keys.unlock(reason: 'x');
        expect(r.store!.list().single.name, 'real.jpg');
      },
    );

    test('IMG-011 a wrong PIN opens nothing', () async {
      await keys.createDecoy('2468');
      final d = await keys.unlockDecoy('1111');
      expect(d.result, VaultUnlock.wrongPin);
      expect(d.store, isNull);
    });

    test('IMG-011 no decoy unless one was made', () async {
      final d = await keys.unlockDecoy('2468');
      expect(d.result, VaultUnlock.needsSetup);
    });

    test('IMG-011 removing the decoy removes its files', () async {
      await keys.createDecoy('2468');
      await keys.removeDecoy();
      expect(keys.decoyExists, isFalse);
      expect(keys.decoyDirectory.existsSync(), isFalse);
    });
  });

  group('IMG-011 moving photos in', () {
    late LibraryDatabase db;
    late DiskIo io;
    late MediahroImagePipeline pipeline;
    late ThumbnailCache cache;
    late VaultMover mover;
    late Seed seed;

    setUp(() {
      db = LibraryDatabase.memory();
      seed = Seed(db);
      io = DiskIo();
      cache = ThumbnailCache(
        db: db,
        directory: Directory('${dir.path}/thumbs'),
      );
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

    test(
      'IMG-011 a moved photo is encrypted in, and gone from its folder',
      () async {
        final data = bytesOf(5000, 3);
        final p = await photo('trip/a.jpg', data: data);
        final r = await mover.moveIn(store, [p]);
        expect(r.moved, 1);
        expect(File('${dir.path}/lib/trip/a.jpg').existsSync(), isFalse);
        final item = store.list().single;
        expect(
          (item.name, item.kind, item.size, item.width),
          ('a.jpg', 'image', 5000, 40),
        );
        expect(await store.readAll(item.id), data);
        final row = await (db.select(
          db.items,
        )..where((i) => i.id.equals(p.id))).getSingle();
        expect(row.missing, isTrue);
      },
    );

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
      await mover.moveIn(store, [p]);
      expect(thumb.existsSync(), isFalse);
      expect(await cache.lookup(key), isNull);
    });

    test('IMG-011 a photo that cannot be removed from its source stays out of the vault', () async {
      final p = await photo('a.jpg');
      io.failDelete = true;
      final r = await mover.moveIn(store, [p]);
      expect(r.moved, 0);
      expect(r.failed, ['a.jpg']);
      expect(store.list(), isEmpty);
      expect(File('${dir.path}/lib/a.jpg').existsSync(), isTrue);
      expect(
        Directory('${dir.path}/v').listSync().whereType<File>().where(
          (f) => f.path.endsWith('.mv') && !f.path.endsWith('index.mv'),
        ),
        isEmpty,
      );
    });

    test('IMG-011 a missing file is reported and the rest are moved', () async {
      final a = await photo('a.jpg');
      final b = await photo('b.jpg');
      File('${dir.path}/lib/a.jpg').deleteSync();
      final r = await mover.moveIn(store, [a, b]);
      expect(r.moved, 1);
      expect(r.failed, ['a.jpg']);
      expect(store.list().single.name, 'b.jpg');
    });

    test('IMG-011 videos are kept as videos', () async {
      final v = await photo('c.mp4', video: true);
      await mover.moveIn(store, [v]);
      expect(store.list().single.kind, 'video');
    });

    test('IMG-011 progress is reported and a move can be stopped', () async {
      final ps = [
        await photo('a.jpg'),
        await photo('b.jpg'),
        await photo('c.jpg'),
      ];
      final seen = <int>[];
      final r = await mover.moveIn(
        store,
        ps,
        onProgress: seen.add,
        cancelled: () => seen.length >= 2,
      );
      expect(seen, [1, 2]);
      expect(r.stopped, isTrue);
      expect(r.moved, 2);
      expect(File('${dir.path}/lib/c.jpg').existsSync(), isTrue);
    });

    test('IMG-011 a saved-out item streams back in pieces', () async {
      final data = bytesOf(2500000, 8);
      final item = await put('big.jpg', data);
      final out = BytesBuilder(copy: false);
      await vaultContent(store, item).forEach(out.add);
      expect(out.takeBytes(), data);
    });
  });
}

final class _OtherKey extends FakeSecure {
  @override
  Future<List<int>> unwrapKey(
    List<int> wrapped, {
    required String reason,
  }) async => VaultCrypto.randomBytes(32);
}
