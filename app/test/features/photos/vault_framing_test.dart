import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mediahro/features/photos/vault/vault_framing.dart';
import 'package:mediahro/platform/vault_crypto.dart';

import 'fake_vault_crypto.dart';

Uint8List bytesOf(int n, [int seed = 1]) =>
    Uint8List.fromList(List.generate(n, (i) => (i * 31 + seed) & 0xFF));

const int chunk = VaultFormat.chunkSize;

void main() {
  late FakeVaultCrypto crypto;
  late VaultKeyHandle master;
  late VaultSealer sealer;

  setUp(() async {
    crypto = FakeVaultCrypto();
    master = await crypto.openMasterKey(requireBiometry: false);
    sealer = VaultSealer(crypto);
  });

  Future<(Uint8List, WrappedKey)> sealed(
    Uint8List plain, {
    Stream<List<int>>? as,
    bool embed = false,
    Uint8List? context,
    Uint8List? secret,
    WrappedKey? key,
  }) async {
    final k = key ?? await crypto.newFileKey(master);
    final out = BytesBuilder();
    await sealer.seal(
      key: k,
      plain: as ?? Stream.value(plain),
      plainLength: plain.length,
      out: (b) async => out.add(b),
      embedKey: embed,
      secret: secret,
      context: context,
    );
    return (out.takeBytes(), k);
  }

  Future<VaultReader> reader(
    Uint8List file,
    WrappedKey key, {
    Uint8List? secret,
    Uint8List? context,
  }) => VaultReader.open(
    crypto: crypto,
    source: MemoryVaultSource(file),
    key: key,
    secret: secret,
    context: context,
  );

  group('IMG-011 sealed file layout', () {
    test('IMG-011 sizes of every shape of file add up exactly', () async {
      for (final n in [
        0,
        1,
        100,
        chunk - 1,
        chunk,
        chunk + 1,
        2 * chunk,
        2 * chunk + 7,
      ]) {
        final (file, _) = await sealed(bytesOf(n));
        expect(file.length, VaultFormat.sealedLength(n), reason: '$n bytes');
      }
    });

    test('IMG-011 round trip across chunk boundaries', () async {
      for (final n in [0, 1, chunk - 1, chunk, chunk + 1, 2 * chunk + 5]) {
        final plain = bytesOf(n, n);
        final (file, key) = await sealed(plain);
        final r = await reader(file, key);
        expect(r.plainLength, n);
        expect(await r.readAll(), plain, reason: '$n bytes');
      }
    });

    test(
      'IMG-011 any chunking of the input gives the same file content',
      () async {
        final plain = bytesOf(chunk * 2 + 1234);
        Stream<List<int>> pieces(int size) async* {
          for (var i = 0; i < plain.length; i += size) {
            yield plain.sublist(i, (i + size).clamp(0, plain.length));
          }
        }

        for (final size in [1000, chunk - 1, chunk + 17, plain.length]) {
          final (file, key) = await sealed(plain, as: pieces(size));
          expect(
            await (await reader(file, key)).readAll(),
            plain,
            reason: '$size',
          );
        }
      },
    );

    test('IMG-011 ranges are read from the chunks that hold them', () async {
      final plain = bytesOf(chunk * 3 + 99, 5);
      final (file, key) = await sealed(plain);
      final r = await reader(file, key);
      crypto.openCalls = 0;
      expect(await r.read(10, 20), plain.sublist(10, 30));
      expect(crypto.openCalls, 1);
      expect(await r.read(chunk - 5, 10), plain.sublist(chunk - 5, chunk + 5));
      expect(await r.read(chunk * 3 + 90, 100), plain.sublist(chunk * 3 + 90));
      expect(await r.read(plain.length, 5), isEmpty);
      expect(await r.read(0, 0), isEmpty);
    });

    test('IMG-011 two files of the same bytes look nothing alike', () async {
      final plain = bytesOf(5000);
      final (a, _) = await sealed(plain);
      final (b, _) = await sealed(plain);
      expect(a, isNot(b));
      // The plaintext appears nowhere in the file.
      final text = String.fromCharCodes(a);
      expect(
        text,
        isNot(contains(String.fromCharCodes(plain.sublist(100, 140)))),
      );
    });

    test('IMG-011 a stream of the wrong length is refused', () async {
      final k = await crypto.newFileKey(master);
      await expectLater(
        sealer.seal(
          key: k,
          plain: Stream.value(bytesOf(10)),
          plainLength: 20,
          out: (_) async {},
        ),
        throwsA(isA<VaultCorrupt>()),
      );
      await expectLater(
        sealer.seal(
          key: k,
          plain: Stream.value(bytesOf(30)),
          plainLength: 20,
          out: (_) async {},
        ),
        throwsA(isA<VaultCorrupt>()),
      );
    });
  });

  group('IMG-011 tampering is noticed', () {
    late Uint8List plain;
    late Uint8List file;
    late WrappedKey key;
    const stride = chunk + VaultFormat.nonceLength + VaultFormat.tagLength;

    setUp(() async {
      plain = bytesOf(chunk * 3, 2);
      (file, key) = await sealed(plain);
    });

    Future<void> expectBad(Uint8List f) async {
      Object? error;
      try {
        final r = await reader(f, key);
        await r.readAll();
      } on Object catch (e) {
        error = e;
      }
      expect(error, isA<VaultCorrupt>());
    }

    test('IMG-011 a changed byte in any chunk', () async {
      for (final at in [
        VaultFormat.fixedHeader + 20,
        VaultFormat.fixedHeader + stride + 50,
        file.length - 20,
      ]) {
        await expectBad(Uint8List.fromList(file)..[at] ^= 1);
      }
    });

    test('IMG-011 a changed nonce', () async {
      await expectBad(Uint8List.fromList(file)..[VaultFormat.fixedHeader] ^= 1);
    });

    test('IMG-011 a cut file', () async {
      await expectBad(Uint8List.sublistView(file, 0, file.length - 100));
      await expectBad(
        Uint8List.sublistView(file, 0, VaultFormat.fixedHeader + 5),
      );
    });

    test('IMG-011 a whole chunk removed from the end', () async {
      final cut = Uint8List.sublistView(file, 0, file.length - stride);
      // The header still says three chunks.
      await expectBad(cut);
    });

    test('IMG-011 two chunks swapped', () async {
      final f = Uint8List.fromList(file);
      const a = VaultFormat.fixedHeader;
      const b = a + stride;
      final first = f.sublist(a, b);
      f
        ..setRange(a, b, f.sublist(b, b + stride))
        ..setRange(b, b + stride, first);
      await expectBad(f);
    });

    test('IMG-011 a chunk from another file with the same key', () async {
      final (other, _) = await sealed(bytesOf(chunk * 3, 9), key: key);
      final f = Uint8List.fromList(file);
      const a = VaultFormat.fixedHeader + stride;
      f.setRange(a, a + stride, other.sublist(a, a + stride));
      await expectBad(f);
    });

    test('IMG-011 a changed length in the header', () async {
      final f = Uint8List.fromList(file);
      ByteData.sublistView(f).setUint64(25, chunk * 3 - 1);
      await expectBad(f);
    });

    test('IMG-011 a different key opens nothing', () async {
      final other = await crypto.newFileKey(master);
      final r = await reader(file, other);
      await expectLater(r.readAll(), throwsA(isA<Object>()));
    });

    test('IMG-011 not a vault file', () async {
      await expectBad(bytesOf(500));
      await expectBad(Uint8List(0));
    });
  });

  group('IMG-011 files bound to the PIN token', () {
    test('IMG-011 the wrong token fails and the right one reads', () async {
      final token = bytesOf(32, 3);
      final (file, key) = await sealed(bytesOf(2000), secret: token);
      final good = await reader(file, key, secret: token);
      expect(await good.readAll(), bytesOf(2000));
      for (final bad in [bytesOf(32, 4), null]) {
        final r = await reader(file, key, secret: bad);
        await expectLater(r.readAll(), throwsA(isA<VaultCorrupt>()));
      }
    });

    test(
      'IMG-011 a file opens only for the purpose and item it was sealed for',
      () async {
        final token = bytesOf(32, 3);
        final ctx = Uint8List.fromList(utf8.encode('thumb:a'));
        final (file, key) = await sealed(
          bytesOf(500),
          secret: token,
          context: ctx,
        );
        final good = await reader(file, key, secret: token, context: ctx);
        expect(await good.readAll(), bytesOf(500));
        for (final bad in [
          Uint8List.fromList(utf8.encode('thumb:b')),
          Uint8List.fromList(utf8.encode('index:a')),
          null,
        ]) {
          final r = await reader(file, key, secret: token, context: bad);
          await expectLater(r.readAll(), throwsA(isA<VaultCorrupt>()));
        }
      },
    );

    test(
      'IMG-011 a file that carries its key opens with the master only',
      () async {
        final token = bytesOf(32, 8);
        final (file, _) = await sealed(
          bytesOf(300),
          embed: true,
          secret: token,
        );
        final r = await VaultReader.open(
          crypto: crypto,
          source: MemoryVaultSource(file),
          master: master,
          secret: token,
        );
        expect(await r.readAll(), bytesOf(300));
        await expectLater(
          VaultReader.open(
            crypto: crypto,
            source: MemoryVaultSource(file),
            secret: token,
          ),
          throwsA(isA<VaultCorrupt>()),
        );
      },
    );

    test(
      'IMG-011 a lost keystore key reaches the caller as the OS error',
      () async {
        final (file, _) = await sealed(bytesOf(300), embed: true);
        final fresh = await crypto.openMasterKey(requireBiometry: false);
        crypto.loseKeys();
        await expectLater(
          VaultReader.open(
            crypto: crypto,
            source: MemoryVaultSource(file),
            master: fresh,
          ),
          throwsA(
            isA<VaultCryptoException>().having(
              (e) => e.error,
              'error',
              VaultCryptoError.keyInvalidated,
            ),
          ),
        );
      },
    );
  });
}
