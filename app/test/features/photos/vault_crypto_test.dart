import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mediahro/features/photos/vault/vault_crypto.dart';

Uint8List noise(int n, [int seed = 1]) {
  final r = Random(seed);
  return Uint8List.fromList(List.generate(n, (_) => r.nextInt(256)));
}

void main() {
  late VaultCrypto crypto;

  setUp(() => crypto = VaultCrypto(VaultCrypto.randomBytes(32)));

  group('IMG-011 vault file format', () {
    for (final n in [
      0,
      1,
      100,
      VaultCrypto.chunkSize - 1,
      VaultCrypto.chunkSize,
      VaultCrypto.chunkSize + 1,
      3 * VaultCrypto.chunkSize,
      200000,
    ]) {
      test('IMG-011 $n bytes survive a round trip', () async {
        final plain = noise(n);
        final sealed = await crypto.sealBytes(plain);
        expect(sealed.length, VaultCrypto.sealedLength(n));
        expect(await crypto.unsealBytes(sealed), plain);
      });
    }

    test('IMG-011 the same bytes never encrypt the same way twice', () async {
      final plain = noise(5000);
      final a = await crypto.sealBytes(plain);
      final b = await crypto.sealBytes(plain);
      expect(a, isNot(b));
      // Nothing of the plaintext shows in the file.
      expect(
        a.length > 200 && _contains(a, Uint8List.sublistView(plain, 100, 140)),
        isFalse,
      );
    });

    test(
      'IMG-011 any chunking of the source gives the same file content',
      () async {
        final plain = noise(150000, 7);
        for (final piece in [1, 999, 65536, 65537, 150000]) {
          final out = BytesBuilder(copy: false);
          await crypto.seal(
            Stream.fromIterable([
              for (var i = 0; i < plain.length; i += piece)
                Uint8List.sublistView(plain, i, min(plain.length, i + piece)),
            ]),
            plain.length,
            out.add,
          );
          expect(
            await crypto.unsealBytes(out.takeBytes()),
            plain,
            reason: '$piece',
          );
        }
      },
    );

    test('IMG-011 a source of the wrong length is refused', () async {
      await expectLater(
        crypto.seal(Stream.value(noise(10)), 20, BytesBuilder().add),
        throwsA(isA<VaultCorrupt>()),
      );
      await expectLater(
        crypto.seal(Stream.value(noise(30)), 20, BytesBuilder().add),
        throwsA(isA<VaultCorrupt>()),
      );
    });
  });

  group('IMG-011 reading ranges', () {
    late Uint8List plain;
    late VaultReader reader;

    setUp(() async {
      plain = noise(3 * VaultCrypto.chunkSize + 1234, 3);
      reader = await crypto.open(
        MemoryVaultSource(await crypto.sealBytes(plain)),
      );
    });

    test(
      'IMG-011 ranges inside, across and at the end match the original',
      () async {
        for (final (o, l) in [
          (0, 10),
          (65530, 20),
          (65536, 65536),
          (60000, 140000),
          (plain.length - 5, 100),
          (plain.length - 1, 1),
          (0, plain.length),
        ]) {
          final end = min(plain.length, o + l);
          expect(
            await reader.read(o, l),
            plain.sublist(o, end),
            reason: '$o+$l',
          );
        }
      },
    );

    test('IMG-011 reading past the end or nothing gives nothing', () async {
      expect(await reader.read(plain.length, 10), isEmpty);
      expect(await reader.read(plain.length + 100, 10), isEmpty);
      expect(await reader.read(5, 0), isEmpty);
      expect(await reader.read(5, -3), isEmpty);
    });

    test('IMG-011 the length is the plain length', () {
      expect(reader.plainLength, plain.length);
    });
  });

  group('IMG-011 tampering', () {
    late Uint8List plain;
    late Uint8List sealed;

    setUp(() async {
      plain = noise(3 * VaultCrypto.chunkSize, 5);
      sealed = await crypto.sealBytes(plain);
    });

    Future<void> expectCorrupt(Uint8List bad, {bool onOpen = false}) async {
      if (onOpen) {
        await expectLater(
          crypto.open(MemoryVaultSource(bad)),
          throwsA(isA<VaultCorrupt>()),
        );
        return;
      }
      await expectLater(
        () async =>
            await (await crypto.open(MemoryVaultSource(bad)))
                .read(0, bad.length),
        throwsA(isA<VaultCorrupt>()),
      );
    }

    test('IMG-011 another key cannot open the file', () async {
      final other = VaultCrypto(VaultCrypto.randomBytes(32));
      await expectLater(
        other.open(MemoryVaultSource(sealed)),
        throwsA(isA<VaultCorrupt>()),
      );
    });

    test('IMG-011 a changed byte in a chunk is noticed', () async {
      final bad = Uint8List.fromList(sealed);
      bad[VaultCrypto.headerSize + 70000] ^= 1;
      await expectCorrupt(bad);
    });

    test('IMG-011 a changed tag is noticed', () async {
      final bad = Uint8List.fromList(sealed);
      bad[bad.length - 1] ^= 0x80;
      await expectCorrupt(bad);
    });

    test('IMG-011 a changed header is noticed on opening', () async {
      for (final at in [10, 25, 30, 40, 60, 90]) {
        final bad = Uint8List.fromList(sealed);
        bad[at] ^= 1;
        await expectCorrupt(bad, onOpen: true);
      }
    });

    test('IMG-011 a file cut short or extended is refused', () async {
      await expectCorrupt(
        Uint8List.sublistView(sealed, 0, sealed.length - 1),
        onOpen: true,
      );
      await expectCorrupt(
        Uint8List.sublistView(sealed, 0, VaultCrypto.headerSize + 100),
        onOpen: true,
      );
      await expectCorrupt(Uint8List.fromList([...sealed, 0]), onOpen: true);
    });

    test('IMG-011 chunks swapped with each other are noticed', () async {
      const step = VaultCrypto.chunkSize + VaultCrypto.tagSize;
      final bad = Uint8List.fromList(sealed);
      const a = VaultCrypto.headerSize;
      const b = VaultCrypto.headerSize + step;
      for (var i = 0; i < step; i++) {
        final t = bad[a + i];
        bad[a + i] = bad[b + i];
        bad[b + i] = t;
      }
      await expectCorrupt(bad);
    });

    test('IMG-011 a chunk from another file does not fit', () async {
      final other = await crypto.sealBytes(
        noise(3 * VaultCrypto.chunkSize, 99),
      );
      const step = VaultCrypto.chunkSize + VaultCrypto.tagSize;
      final bad = Uint8List.fromList(sealed)
        ..setRange(
          VaultCrypto.headerSize,
          VaultCrypto.headerSize + step,
          other,
          VaultCrypto.headerSize,
        );
      await expectCorrupt(bad);
    });

    test(
      'IMG-011 the end of the file cannot be passed off as a middle chunk',
      () async {
        // A file whose last chunk is dropped and the rest relabelled stays refused:
        // the header length no longer matches.
        const step = VaultCrypto.chunkSize + VaultCrypto.tagSize;
        await expectCorrupt(
          Uint8List.sublistView(sealed, 0, sealed.length - step),
          onOpen: true,
        );
      },
    );

    test('IMG-011 something that is not a vault file is refused', () async {
      await expectLater(
        crypto.open(MemoryVaultSource(noise(500))),
        throwsA(isA<VaultCorrupt>()),
      );
      await expectLater(
        crypto.open(MemoryVaultSource(Uint8List(10))),
        throwsA(isA<VaultCorrupt>()),
      );
    });
  });

  test(
    'IMG-011 two megabytes are sealed and opened in a few seconds',
    () async {
      final plain = noise(2 << 20, 11);
      final sw = Stopwatch()..start();
      final back = await crypto.unsealBytes(await crypto.sealBytes(plain));
      sw.stop();
      expect(back, plain);
      expect(sw.elapsedMilliseconds, lessThan(20000));
    },
  );
}

bool _contains(Uint8List hay, Uint8List needle) {
  outer:
  for (var i = 0; i + needle.length <= hay.length; i++) {
    for (var j = 0; j < needle.length; j++) {
      if (hay[i + j] != needle[j]) continue outer;
    }
    return true;
  }
  return false;
}
