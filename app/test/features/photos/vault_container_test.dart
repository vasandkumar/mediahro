import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mediahro/features/photos/vault/vault_container.dart';
import 'package:mediahro/features/photos/vault/vault_framing.dart';
import 'package:mediahro/platform/vault_crypto.dart';

import 'fake_vault_crypto.dart';

Uint8List bytesOf(int n, [int seed = 1]) =>
    Uint8List.fromList(List.generate(n, (i) => (i * 31 + seed) & 0xFF));

void main() {
  late Directory dir;
  late FakeVaultCrypto crypto;
  late VaultKeyHandle master;
  late Uint8List token;

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('mediahro-vault-container');
    crypto = FakeVaultCrypto();
    master = await crypto.openMasterKey(requireBiometry: false);
    token = bytesOf(32, 9);
  });

  tearDown(() {
    try {
      dir.deleteSync(recursive: true);
    } on FileSystemException {
      // Best effort on Windows.
    }
  });

  Future<VaultContainer> make() => VaultContainer.create(
    directory: Directory('${dir.path}/c'),
    crypto: crypto,
    master: master,
    token: token,
  );

  Future<VaultContainer> reopen([Uint8List? t]) => VaultContainer.open(
    directory: Directory('${dir.path}/c'),
    crypto: crypto,
    master: master,
    token: t ?? token,
  );

  Future<VaultItem> put(
    VaultContainer c,
    String name,
    Uint8List data, {
    DateTime? now,
  }) => c.add(
    name: name,
    kind: 'image',
    content: Stream.value(data),
    size: data.length,
    now: now,
  );

  test(
    'IMG-011 items survive closing and opening with the same token',
    () async {
      final c = await make();
      final a = await put(c, 'beach.jpg', bytesOf(1000));
      await put(c, 'cat.png', bytesOf(300000, 3), now: DateTime(2026, 1, 2));
      c.close();
      final again = await reopen();
      expect(again.list().map((i) => i.name).toSet(), {'beach.jpg', 'cat.png'});
      expect(await again.readAll(a.id), bytesOf(1000));
    },
  );

  test(
    'IMG-011 a wrong token opens nothing, as if the index were damaged',
    () async {
      (await make()).close();
      await expectLater(reopen(bytesOf(32)), throwsA(isA<VaultCorrupt>()));
    },
  );

  test(
    'IMG-011 nothing readable is written outside the encrypted files',
    () async {
      final c = await make();
      final secret = bytesOf(5000, 4);
      final item = await put(c, 'private holiday.jpg', secret);
      await c.putThumbnail(item.id, bytesOf(500, 6));
      final files = dir.listSync(recursive: true).whereType<File>().toList();
      expect(
        files.map((f) => f.path.split(Platform.pathSeparator).last).toSet(),
        {'index.mv', '${item.id}.mv', '${item.id}.tm', '.nomedia'},
      );
      for (final f in files) {
        final text = latin1.decode(f.readAsBytesSync());
        expect(text, isNot(contains('private')));
        expect(text, isNot(contains('holiday')));
        expect(text, isNot(contains(latin1.decode(secret.sublist(100, 140)))));
      }
    },
  );

  test('IMG-011 a failed encryption leaves no file and no item', () async {
    final c = await make();
    crypto.failChunks = VaultCryptoError.unavailable;
    await expectLater(
      put(c, 'a.jpg', bytesOf(100)),
      throwsA(isA<VaultCryptoException>()),
    );
    crypto.failChunks = null;
    expect(c.list(), isEmpty);
    final names = dir
        .listSync(recursive: true)
        .whereType<File>()
        .map((f) => f.path.split(Platform.pathSeparator).last);
    expect(names, isNot(anyElement(endsWith('.part'))));
    expect(names.where((n) => n != 'index.mv' && n != '.nomedia'), isEmpty);
  });

  test('IMG-011 an item is read back before it is listed', () async {
    final c = await make();
    crypto.openCalls = 0;
    await put(c, 'a.jpg', bytesOf(600000));
    // First and last chunk of a three-chunk file.
    expect(crypto.openCalls, greaterThanOrEqualTo(2));
  });

  test('IMG-011 items are opened as files for the image pipeline', () async {
    final c = await make();
    final item = await put(c, 'a.jpg', bytesOf(300000, 2));
    final f = await c.openFile(item.id);
    expect(f.uri.scheme, 'vault');
    expect(await f.length(), 300000);
    expect(
      await f.read(262140, 10),
      bytesOf(300000, 2).sublist(262140, 262150),
    );
    await f.close();
  });

  test('IMG-011 two readers of one file do not trip over each other', () async {
    final c = await make();
    final data = bytesOf(800000, 8);
    final item = await put(c, 'a.jpg', data);
    final a = await c.openFile(item.id);
    final b = await c.openFile(item.id);
    final reads = await Future.wait([
      a.read(10, 100),
      b.read(700000, 1000),
      a.read(300000, 5000),
      b.read(0, 50),
    ]);
    expect(reads[0], data.sublist(10, 110));
    expect(reads[1], data.sublist(700000, 701000));
    expect(reads[2], data.sublist(300000, 305000));
    expect(reads[3], data.sublist(0, 50));
    await a.close();
    await b.close();
  });

  test('IMG-011 pictures are stored sealed and need the token', () async {
    final c = await make();
    final item = await put(c, 'a.jpg', bytesOf(100));
    expect(await c.thumbnail(item.id), isNull);
    await c.putThumbnail(item.id, bytesOf(777, 5));
    expect(await c.thumbnail(item.id), bytesOf(777, 5));
    c.close();
    final other = await VaultContainer.open(
      directory: Directory('${dir.path}/c'),
      crypto: crypto,
      master: master,
      token: token,
    );
    expect(await other.thumbnail(item.id), bytesOf(777, 5));
  });

  test(
    'IMG-011 removing an item deletes its files and stays removed',
    () async {
      final c = await make();
      final a = await put(c, 'a.jpg', bytesOf(100));
      final b = await put(c, 'b.jpg', bytesOf(100, 2));
      await c.putThumbnail(a.id, bytesOf(10));
      await c.remove(a.id);
      expect(File('${dir.path}/c/${a.id}.mv').existsSync(), isFalse);
      expect(File('${dir.path}/c/${a.id}.tm').existsSync(), isFalse);
      c.close();
      expect((await reopen()).list().map((i) => i.id), [b.id]);
    },
  );

  test('IMG-011 what the library knew rides along in the index', () async {
    final c = await make();
    final item = await c.add(
      name: 'a.jpg',
      kind: 'image',
      content: Stream.value(bytesOf(10)),
      size: 10,
      tags: ['trip', 'family'],
      halfStars: 8,
      favourite: true,
      label: 'red',
    );
    c.close();
    final back = (await reopen()).byId(item.id)!;
    expect(back.tags, ['trip', 'family']);
    expect(back.halfStars, 8);
    expect(back.favourite, isTrue);
    expect(back.label, 'red');
  });

  test(
    'IMG-011 a new token re-seals the index and pictures, old one stops',
    () async {
      final c = await make();
      final item = await put(c, 'a.jpg', bytesOf(100));
      await c.putThumbnail(item.id, bytesOf(50, 2));
      final newToken = bytesOf(32, 77);
      await c.rekey(newToken);
      c.close();
      await expectLater(reopen(), throwsA(isA<VaultCorrupt>()));
      final again = await reopen(newToken);
      expect(again.list().single.name, 'a.jpg');
      expect(await again.thumbnail(item.id), bytesOf(50, 2));
      expect(await again.readAll(item.id), bytesOf(100));
    },
  );

  test('IMG-011 a locked vault lists nothing and gives nothing back', () async {
    final c = await make();
    final item = await put(c, 'a.jpg', bytesOf(100));
    c.close();
    expect(c.isClosed, isTrue);
    expect(c.list, throwsA(isA<VaultLocked>()));
    expect(c.tokenCopy, throwsA(isA<VaultLocked>()));
    await expectLater(c.readAll(item.id), throwsA(isA<VaultLocked>()));
  });

  test('IMG-011 a token the caller keeps is not the one inside', () async {
    final mine = bytesOf(32, 9);
    final c = await VaultContainer.create(
      directory: Directory('${dir.path}/c'),
      crypto: crypto,
      master: master,
      token: mine,
    );
    c.close();
    // Zeroing the container's copy leaves the caller's alone.
    expect(mine, bytesOf(32, 9));
  });
}
