import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediahro/features/photos/vault/vault_container.dart';
import 'package:mediahro/features/photos/vault/vault_kdf.dart';
import 'package:mediahro/features/photos/vault/vault_manager.dart';
import 'package:mediahro/features/photos/vault/vault_providers.dart';
import 'package:mediahro/platform/platform_facades.dart';

import 'fake_vault_crypto.dart';

Uint8List bytesOf(int n, [int seed = 1]) =>
    Uint8List.fromList(List.generate(n, (i) => (i * 31 + seed) & 0xFF));

void main() {
  late Directory root;
  late FakeVaultCrypto crypto;
  late MemorySecureStorage secure;
  late DateTime now;
  late VaultManager manager;

  VaultManager make() => VaultManager(
    root: root,
    crypto: crypto,
    secure: secure,
    iterations: 4,
    minRounds: 1,
    kdf: inlinePinToken,
    clock: () => now,
  );

  setUp(() {
    root = Directory.systemTemp.createTempSync('mediahro-vault-manager');
    crypto = FakeVaultCrypto();
    secure = MemorySecureStorage();
    now = DateTime(2026, 10, 21, 12);
    manager = make();
  });

  tearDown(() {
    try {
      root.deleteSync(recursive: true);
    } on FileSystemException {
      // Best effort on Windows.
    }
  });

  Future<void> addTo(OpenVault v, String name) => v.container
      .add(
        name: name,
        kind: 'image',
        content: Stream.value(bytesOf(50)),
        size: 50,
      )
      .then((_) {});

  Set<String> baseNames(Directory d) => d
      .listSync(recursive: true)
      .whereType<File>()
      .map((f) => f.path.split(Platform.pathSeparator).last)
      .toSet();

  group('PRIV-007 set-up', () {
    test(
      'PRIV-007 both vaults exist from the start, named at random',
      () async {
        final r = await manager.setUp(pin: '246810', decoyPin: '135790');
        expect(r.isOpen, isTrue);
        final dirs = root.listSync().whereType<Directory>().toList();
        expect(dirs, hasLength(2));
        for (final d in dirs) {
          expect(
            d.path.split(Platform.pathSeparator).last,
            matches(r'^[0-9a-f]{16}$'),
          );
        }
        expect(manager.exists, isTrue);
        await r.vault!.close();
      },
    );

    test(
      'PRIV-007 without a decoy PIN the second vault is still there',
      () async {
        final r = await manager.setUp(pin: '246810');
        expect(root.listSync().whereType<Directory>(), hasLength(2));
        await r.vault!.close();
        // No PIN a person could type opens it.
        expect(
          (await manager.openWithPin('000000')).outcome,
          VaultOutcome.wrongPin,
        );
      },
    );

    test('PRIV-007 the two vaults hold the same set of files', () async {
      final r = await manager.setUp(pin: '246810', decoyPin: '135790');
      await r.vault!.close();
      final dirs = root.listSync().whereType<Directory>().toList();
      expect(baseNames(dirs[0]), baseNames(dirs[1]));
      expect(baseNames(dirs[0]), {'index.mv', 'salt', 'secret.mv', '.nomedia'});
    });

    test('PRIV-007 set-up twice is refused', () async {
      await (await manager.setUp(pin: '246810')).vault!.close();
      expect((await manager.setUp(pin: '111111')).isOpen, isFalse);
    });

    test('PRIV-007 a keystore failure leaves nothing behind', () async {
      crypto.failPlainOpen = VaultCryptoError.notEnrolled;
      final r = await manager.setUp(pin: '246810');
      expect(r.outcome, VaultOutcome.notEnrolled);
      expect(manager.exists, isFalse);
      crypto
        ..failPlainOpen = null
        ..failChunks = VaultCryptoError.unavailable;
      final r2 = await manager.setUp(pin: '246810');
      expect(r2.outcome, VaultOutcome.unavailable);
      expect(manager.exists, isFalse);
      expect(crypto.openHandles, 0);
    });
  });

  group('PRIV-007 PIN', () {
    late String realDir;

    setUp(() async {
      final r = await manager.setUp(pin: '246810', decoyPin: '135790');
      await addTo(r.vault!, 'real.jpg');
      realDir = r.vault!.container.directory.path;
      await r.vault!.close();
    });

    test('PRIV-007 each PIN opens its own vault', () async {
      final a = await manager.openWithPin('246810');
      expect(a.isOpen, isTrue);
      expect(a.vault!.container.directory.path, realDir);
      expect(a.vault!.container.list().single.name, 'real.jpg');
      await a.vault!.close();
      final b = await manager.openWithPin('135790');
      expect(b.isOpen, isTrue);
      expect(b.vault!.container.directory.path, isNot(realDir));
      expect(b.vault!.container.list(), isEmpty);
      await b.vault!.close();
    });

    test('PRIV-007 a wrong PIN says only that', () async {
      final r = await manager.openWithPin('246811');
      expect(r.outcome, VaultOutcome.wrongPin);
      expect(r.vault, isNull);
      expect(crypto.openHandles, 0);
    });

    test('PRIV-007 a wrong PIN does the PIN work of a right one, plus one check of the keys', () async {
      crypto.calls.clear();
      await (await manager.openWithPin('246810')).vault!.close();
      final right = crypto.calls
          .where((c) => c.startsWith('openMaster'))
          .length;
      crypto.calls.clear();
      await manager.openWithPin('999999');
      final wrong = crypto.calls
          .where((c) => c.startsWith('openMaster'))
          .length;
      // A right PIN opens the container handle; a wrong one opens the two probe
      // handles instead: one more.
      expect(wrong, right + 1);
    });

    test('PRIV-007 closing a vault releases the key handle', () async {
      final r = await manager.openWithPin('246810');
      expect(crypto.openHandles, 1);
      await r.vault!.close();
      expect(crypto.openHandles, 0);
      expect(r.vault!.container.isClosed, isTrue);
    });

    test('PRIV-007 three misses are free, then the wait doubles', () async {
      for (var i = 0; i < 3; i++) {
        expect(
          (await manager.openWithPin('000001')).outcome,
          VaultOutcome.wrongPin,
        );
      }
      final fourth = await manager.openWithPin('000001');
      expect(fourth.outcome, VaultOutcome.waitToRetry);
      expect(fourth.wait, const Duration(seconds: 30));
      // Even the right PIN waits.
      final right = await manager.openWithPin('246810');
      expect(right.outcome, VaultOutcome.waitToRetry);
      now = now.add(const Duration(seconds: 31));
      expect(
        (await manager.openWithPin('000001')).outcome,
        VaultOutcome.waitToRetry,
      );
      now = now.add(const Duration(seconds: 61));
      final ok = await manager.openWithPin('246810');
      expect(ok.isOpen, isTrue);
      await ok.vault!.close();
    });

    test('PRIV-007 the wait survives restarting the app', () async {
      for (var i = 0; i < 4; i++) {
        await manager.openWithPin('000001');
      }
      final restarted = make();
      final r = await restarted.openWithPin('246810');
      expect(r.outcome, VaultOutcome.waitToRetry);
      expect(r.wait, isNotNull);
    });

    test('PRIV-007 a right PIN does not clear the misses before it', () async {
      await manager.openWithPin('000001');
      await manager.openWithPin('000001');
      await (await manager.openWithPin('246810')).vault!.close();
      // Two misses are still on record: one more is free, the next waits.
      expect(
        (await manager.openWithPin('000001')).outcome,
        VaultOutcome.wrongPin,
      );
      expect(
        (await manager.openWithPin('000001')).outcome,
        VaultOutcome.waitToRetry,
      );
    });

    test(
      'PRIV-007 the holder of one PIN cannot reset the count for the other',
      () async {
        // Guesses at the first vault, each followed by a good entry of the second.
        for (var i = 0; i < 3; i++) {
          expect(
            (await manager.openWithPin('00000$i')).outcome,
            VaultOutcome.wrongPin,
          );
          final ok = await manager.openWithPin('135790');
          expect(ok.isOpen, isTrue, reason: 'round $i');
          await ok.vault!.close();
        }
        final next = await manager.openWithPin('000009');
        expect(next.outcome, VaultOutcome.waitToRetry);
      },
    );

    test(
      'PRIV-007 an attempt is counted even if the app stops in the middle',
      () async {
        // The keystore fails before the PIN is checked, as a killed app would.
        crypto.failPlainOpen = VaultCryptoError.unavailable;
        for (var i = 0; i < 4; i++) {
          await manager.openWithPin('000001');
        }
        crypto.failPlainOpen = null;
        final r = await manager.openWithPin('246810');
        expect(r.outcome, VaultOutcome.waitToRetry);
      },
    );

    test('PRIV-007 misses fade, one every four hours', () async {
      for (var i = 0; i < 3; i++) {
        await manager.openWithPin('000001');
      }
      now = now.add(const Duration(hours: 9));
      // Two forgiven: only one miss left on record.
      for (var i = 0; i < 2; i++) {
        expect(
          (await manager.openWithPin('000001')).outcome,
          VaultOutcome.wrongPin,
          reason: 'try $i',
        );
      }
      expect(
        (await manager.openWithPin('000001')).outcome,
        VaultOutcome.waitToRetry,
      );
    });

    test('PRIV-007 a clock set back earns no forgiveness', () async {
      for (var i = 0; i < 4; i++) {
        await manager.openWithPin('000001');
      }
      now = now.subtract(const Duration(days: 30));
      final r = await manager.openWithPin('246810');
      expect(r.outcome, VaultOutcome.waitToRetry);
      expect(r.wait! <= const Duration(days: 1), isTrue);
    });

    test(
      'PRIV-007 a clock set back and then forward again forgives nothing',
      () async {
        final start = now;
        for (var i = 0; i < 4; i++) {
          await manager.openWithPin('000001');
        }
        now = start.subtract(const Duration(days: 10));
        expect(
          (await manager.openWithPin('000001')).outcome,
          VaultOutcome.waitToRetry,
        );
        now = start.add(const Duration(hours: 1));
        // About four misses are still on record: the next wrong try waits.
        expect(
          (await manager.openWithPin('000001')).outcome,
          VaultOutcome.waitToRetry,
        );
      },
    );

    test('PRIV-007 tries made at the same moment are all counted', () async {
      await Future.wait([
        for (var i = 0; i < 5; i++) manager.openWithPin('000001'),
      ]);
      expect(
        (await manager.openWithPin('000001')).outcome,
        VaultOutcome.waitToRetry,
      );
    });

    test('PRIV-007 the wait never exceeds a day', () async {
      for (var i = 0; i < 40; i++) {
        await manager.openWithPin('000001');
        now = now.add(const Duration(days: 1, minutes: 1));
      }
      for (var i = 0; i < 12; i++) {
        await manager.openWithPin('000001');
      }
      final r = await manager.openWithPin('000001');
      expect(r.outcome, VaultOutcome.waitToRetry);
      expect(r.wait! <= const Duration(days: 1), isTrue);
    });

    test('PRIV-007 a keystore error comes back as its own answer', () async {
      crypto.failPlainOpen = VaultCryptoError.keyLost;
      expect(
        (await manager.openWithPin('246810')).outcome,
        VaultOutcome.keyLost,
      );
      crypto.failPlainOpen = VaultCryptoError.unavailable;
      expect(
        (await manager.openWithPin('246810')).outcome,
        VaultOutcome.unavailable,
      );
      crypto
        ..failPlainOpen = null
        ..loseKeys();
      final r = await manager.openWithPin('246810');
      expect(r.outcome, VaultOutcome.keyLost);
      expect(crypto.openHandles, 0);
    });

    test('PRIV-007 no vault yet asks for set-up', () async {
      final empty = VaultManager(
        root: Directory('${root.path}/none'),
        crypto: crypto,
        secure: secure,
        iterations: 4,
        minRounds: 1,
        kdf: inlinePinToken,
      );
      expect(
        (await empty.openWithPin('123456')).outcome,
        VaultOutcome.needsSetup,
      );
      expect(
        (await empty.openWithFingerprint()).outcome,
        VaultOutcome.noFingerprint,
      );
    });
  });

  group('PRIV-007 fingerprint', () {
    setUp(() async {
      final r = await manager.setUp(pin: '246810', decoyPin: '135790');
      await addTo(r.vault!, 'real.jpg');
      await r.vault!.close();
    });

    test('PRIV-007 off until it is turned on', () async {
      expect(await manager.fingerprintOn, isFalse);
      expect(
        (await manager.openWithFingerprint()).outcome,
        VaultOutcome.noFingerprint,
      );
    });

    test('PRIV-007 turned on in a vault, it opens that vault', () async {
      final v = (await manager.openWithPin('246810')).vault!;
      expect(
        await manager.setFingerprint(v, enabled: true),
        VaultOutcome.opened,
      );
      await v.close();
      expect(await manager.fingerprintOn, isTrue);
      expect(crypto.calls, contains('openMaster:true'));
      final r = await manager.openWithFingerprint();
      expect(r.isOpen, isTrue);
      expect(r.vault!.container.list().single.name, 'real.jpg');
      await r.vault!.close();
      expect(crypto.openHandles, 0);
    });

    test('PRIV-007 turned on in the other vault, it opens that one', () async {
      final v = (await manager.openWithPin('135790')).vault!;
      await manager.setFingerprint(v, enabled: true);
      await v.close();
      final r = await manager.openWithFingerprint();
      expect(r.vault!.container.list(), isEmpty);
      await r.vault!.close();
    });

    test(
      'PRIV-007 the fingerprint never holds the PIN token on disk',
      () async {
        final v = (await manager.openWithPin('246810')).vault!;
        await manager.setFingerprint(v, enabled: true);
        await v.close();
        final entry = secure.values.values.join();
        final token = pbkdf2Sha256(
          '246810'.codeUnits,
          await _saltOf(root, 0),
          4,
        );
        expect(entry.contains(String.fromCharCodes(token)), isFalse);
      },
    );

    test('PRIV-007 backing out of the prompt keeps it locked', () async {
      final v = (await manager.openWithPin('246810')).vault!;
      await manager.setFingerprint(v, enabled: true);
      await v.close();
      crypto.failBiometricOpen = VaultCryptoError.cancelled;
      final r = await manager.openWithFingerprint();
      expect(r.outcome, VaultOutcome.cancelled);
      expect(await manager.fingerprintOn, isTrue);
      expect(crypto.openHandles, 0);
    });

    test('PRIV-007 a new fingerprint on the phone ends fingerprint unlock, not the PIN', () async {
      final v = (await manager.openWithPin('246810')).vault!;
      await manager.setFingerprint(v, enabled: true);
      await v.close();
      crypto.invalidateBiometricKey();
      final r = await manager.openWithFingerprint();
      expect(r.outcome, VaultOutcome.fingerprintInvalidated);
      expect(await manager.fingerprintOn, isFalse);
      final pin = await manager.openWithPin('246810');
      expect(pin.isOpen, isTrue);
      await pin.vault!.close();
    });

    test('PRIV-007 no screen lock is reported when turning it on', () async {
      final v = (await manager.openWithPin('246810')).vault!;
      crypto.failBiometricOpen = VaultCryptoError.notEnrolled;
      expect(
        await manager.setFingerprint(v, enabled: true),
        VaultOutcome.notEnrolled,
      );
      expect(await manager.fingerprintOn, isFalse);
      await v.close();
    });

    test('PRIV-007 turning it off removes it', () async {
      final v = (await manager.openWithPin('246810')).vault!;
      await manager.setFingerprint(v, enabled: true);
      await manager.setFingerprint(v, enabled: false);
      await v.close();
      expect(await manager.fingerprintOn, isFalse);
    });

    test('PRIV-007 set-up can turn it on at once', () async {
      final fresh = Directory('${root.path}/fresh');
      final m = VaultManager(
        root: fresh,
        crypto: crypto,
        secure: MemorySecureStorage(),
        iterations: 4,
        minRounds: 1,
        kdf: inlinePinToken,
      );
      final r = await m.setUp(pin: '112233', fingerprint: true);
      await r.vault!.close();
      expect(await m.fingerprintOn, isTrue);
    });
  });

  group('PRIV-007 changing and ending', () {
    test(
      'PRIV-007 a new PIN opens, the old one does not, items stay',
      () async {
        final r = await manager.setUp(pin: '246810', decoyPin: '135790');
        await addTo(r.vault!, 'real.jpg');
        expect(
          await manager.changePin(r.vault!, '555555'),
          VaultOutcome.opened,
        );
        await r.vault!.close();
        expect((await manager.openWithPin('246810')).isOpen, isFalse);
        final ok = await manager.openWithPin('555555');
        expect(ok.vault!.container.list().single.name, 'real.jpg');
        await ok.vault!.close();
        // The other vault is untouched.
        final other = await manager.openWithPin('135790');
        expect(other.isOpen, isTrue);
        await other.vault!.close();
      },
    );

    test(
      'PRIV-007 the fingerprint keeps working when the PIN is changed',
      () async {
        final r = await manager.setUp(pin: '246810', decoyPin: '135790');
        await addTo(r.vault!, 'real.jpg');
        await manager.setFingerprint(r.vault!, enabled: true);
        expect(
          await manager.changePin(r.vault!, '555555'),
          VaultOutcome.opened,
        );
        await r.vault!.close();
        expect(await manager.fingerprintOn, isTrue);
        final f = await manager.openWithFingerprint();
        expect(f.isOpen, isTrue, reason: '${f.outcome}');
        expect(f.vault!.container.list().single.name, 'real.jpg');
        await f.vault!.close();
      },
    );

    test(
      'PRIV-007 a PIN under six digits is refused, at set-up and on change',
      () async {
        expect(
          (await manager.setUp(pin: '12345', decoyPin: '135790')).outcome,
          VaultOutcome.pinTooShort,
        );
        expect(
          (await manager.setUp(pin: '246810', decoyPin: '1357')).outcome,
          VaultOutcome.pinTooShort,
        );
        expect(manager.exists, isFalse);
        final r = await manager.setUp(pin: '246810', decoyPin: '135790');
        expect(
          await manager.changePin(r.vault!, '12345'),
          VaultOutcome.pinTooShort,
        );
        await r.vault!.close();
        expect((await manager.openWithPin('246810')).isOpen, isTrue);
      },
    );

    test('PRIV-007 the same PIN for both vaults is refused', () async {
      expect(
        (await manager.setUp(pin: '246810', decoyPin: '246810')).outcome,
        VaultOutcome.pinNotAllowed,
      );
    });

    test('PRIV-007 the other vault PIN is refused as a new PIN', () async {
      final r = await manager.setUp(pin: '246810', decoyPin: '135790');
      await addTo(r.vault!, 'real.jpg');
      expect(
        await manager.changePin(r.vault!, '135790'),
        VaultOutcome.pinNotAllowed,
      );
      await r.vault!.close();
      // Nothing changed: both PINs still open their own vaults.
      final a = await manager.openWithPin('246810');
      expect(a.vault!.container.list().single.name, 'real.jpg');
      await a.vault!.close();
      final b = await manager.openWithPin('135790');
      expect(b.isOpen, isTrue);
      await b.vault!.close();
    });

    test('PRIV-007 trying a new PIN counts like any attempt', () async {
      final r = await manager.setUp(pin: '246810', decoyPin: '135790');
      for (var i = 0; i < 4; i++) {
        expect(
          await manager.changePin(r.vault!, '55555$i'),
          VaultOutcome.opened,
        );
      }
      // The fourth set a wait, as a fourth wrong PIN does.
      expect(
        await manager.changePin(r.vault!, '444444'),
        VaultOutcome.waitToRetry,
      );
      await r.vault!.close();
    });

    test('PRIV-007 reset also deletes the OS key, first', () async {
      final r = await manager.setUp(pin: '246810', decoyPin: '135790');
      await r.vault!.close();
      crypto.calls.clear();
      await manager.reset();
      expect(crypto.resets, 1);
      expect(crypto.calls.first, 'reset');
      expect(manager.exists, isFalse);
      // A new vault can be made afterwards, with a new key.
      final again = await manager.setUp(pin: '111111');
      expect(again.isOpen, isTrue);
      await again.vault!.close();
    });

    test('PRIV-007 if the OS key cannot be deleted nothing else is', () async {
      final r = await manager.setUp(pin: '246810', decoyPin: '135790');
      await r.vault!.close();
      crypto.failReset = VaultCryptoError.unavailable;
      await expectLater(manager.reset(), throwsA(isA<VaultCryptoException>()));
      expect(manager.exists, isTrue);
      crypto.failReset = null;
      final ok = await manager.openWithPin('246810');
      expect(ok.isOpen, isTrue);
      await ok.vault!.close();
    });

    test('PRIV-007 reset deletes both vaults and the fingerprint', () async {
      final r = await manager.setUp(
        pin: '246810',
        decoyPin: '135790',
        fingerprint: true,
      );
      await r.vault!.close();
      await manager.openWithPin('000001');
      await manager.reset();
      expect(manager.exists, isFalse);
      expect(root.listSync().whereType<Directory>(), isEmpty);
      expect(secure.values, isEmpty);
      expect(
        (await manager.openWithPin('246810')).outcome,
        VaultOutcome.needsSetup,
      );
    });
  });

  group('PRIV-007 a Change PIN that is cut short', () {
    late Directory dir;
    late Uint8List oldSalt;
    late Uint8List oldSecret;
    late Uint8List newSalt;
    late Uint8List newSecret;
    late Uint8List indexBefore;

    setUp(() async {
      final r = await manager.setUp(pin: '246810', decoyPin: '135790');
      await addTo(r.vault!, 'real.jpg');
      await manager.setFingerprint(r.vault!, enabled: true);
      dir = r.vault!.container.directory;
      oldSalt = File('${dir.path}/salt').readAsBytesSync();
      oldSecret = File('${dir.path}/secret.mv').readAsBytesSync();
      indexBefore = File('${dir.path}/index.mv').readAsBytesSync();
      expect(await manager.changePin(r.vault!, '555555'), VaultOutcome.opened);
      newSalt = File('${dir.path}/salt').readAsBytesSync();
      newSecret = File('${dir.path}/secret.mv').readAsBytesSync();
      await r.vault!.close();
    });

    void put(String name, Uint8List bytes) =>
        File('${dir.path}/$name').writeAsBytesSync(bytes);

    /// The folder as it was before the change plus the files a cut-off left.
    void state({
      required bool secretNext,
      required bool saltNext,
      bool swapped = false,
    }) {
      put('salt', oldSalt);
      put('secret.mv', swapped ? newSecret : oldSecret);
      for (final f in ['salt.next', 'secret.mv.next']) {
        if (File('${dir.path}/$f').existsSync()) {
          File('${dir.path}/$f').deleteSync();
        }
      }
      if (secretNext) put('secret.mv.next', newSecret);
      if (saltNext) put('salt.next', newSalt);
    }

    test('PRIV-007 a finished change opens with the new PIN only', () async {
      expect((await manager.openWithPin('246810')).isOpen, isFalse);
      final r = await manager.openWithPin('555555');
      expect(r.isOpen, isTrue);
      expect(r.vault!.container.list().single.name, 'real.jpg');
      await r.vault!.close();
    });

    test('PRIV-007 changing the PIN does not touch the index or the files', () {
      expect(File('${dir.path}/index.mv').readAsBytesSync(), indexBefore);
    });

    test(
      'PRIV-007 after only the new secret file is written the old PIN opens',
      () async {
        state(secretNext: true, saltNext: false);
        final r = await manager.openWithPin('246810');
        expect(r.isOpen, isTrue);
        expect(r.vault!.container.list().single.name, 'real.jpg');
        await r.vault!.close();
        // The leftover is cleaned and the new PIN does not open.
        expect(File('${dir.path}/secret.mv.next').existsSync(), isFalse);
        expect((await manager.openWithPin('555555')).isOpen, isFalse);
      },
    );

    test('PRIV-007 with both new files written the new PIN opens', () async {
      state(secretNext: true, saltNext: true);
      final fresh = make();
      final r = await fresh.openWithPin('555555');
      expect(r.isOpen, isTrue, reason: '${r.outcome}');
      expect(r.vault!.container.list().single.name, 'real.jpg');
      await r.vault!.close();
      // The new pair is now the folder's own; the old PIN is gone.
      expect(File('${dir.path}/salt.next').existsSync(), isFalse);
      expect(File('${dir.path}/secret.mv.next').existsSync(), isFalse);
      expect((await manager.openWithPin('246810')).isOpen, isFalse);
      final again = await manager.openWithPin('555555');
      expect(again.isOpen, isTrue);
      await again.vault!.close();
    });

    test(
      'PRIV-007 with both new files written the old PIN still opens too',
      () async {
        state(secretNext: true, saltNext: true);
        final r = await manager.openWithPin('246810');
        expect(r.isOpen, isTrue);
        await r.vault!.close();
        expect((await manager.openWithPin('555555')).isOpen, isFalse);
      },
    );

    test('PRIV-007 after the secret file is swapped but not the salt the new PIN opens', () async {
      state(secretNext: false, saltNext: true, swapped: true);
      final r = await manager.openWithPin('555555');
      expect(r.isOpen, isTrue, reason: '${r.outcome}');
      expect(r.vault!.container.list().single.name, 'real.jpg');
      await r.vault!.close();
      expect(File('${dir.path}/salt.next').existsSync(), isFalse);
      expect(File('${dir.path}/salt').readAsBytesSync(), newSalt);
    });

    test('PRIV-007 the fingerprint opens a half-made change and drops the new secret file', () async {
      state(secretNext: true, saltNext: false);
      final r = await manager.openWithFingerprint();
      expect(r.isOpen, isTrue, reason: '${r.outcome}');
      await r.vault!.close();
      expect(File('${dir.path}/secret.mv.next').existsSync(), isFalse);
      expect((await manager.openWithPin('246810')).isOpen, isTrue);
    });

    test('PRIV-007 the fingerprint finishes a change whose secret file was swapped', () async {
      state(secretNext: false, saltNext: true, swapped: true);
      final r = await manager.openWithFingerprint();
      expect(r.isOpen, isTrue, reason: '${r.outcome}');
      await r.vault!.close();
      // Not left half done: the new PIN opens, the old does not.
      expect(File('${dir.path}/salt.next').existsSync(), isFalse);
      expect((await manager.openWithPin('555555')).isOpen, isTrue);
      expect((await manager.openWithPin('246810')).isOpen, isFalse);
    });

    test('PRIV-007 the fingerprint opens when both new files were written and drops the change', () async {
      state(secretNext: true, saltNext: true);
      final r = await manager.openWithFingerprint();
      expect(r.isOpen, isTrue, reason: '${r.outcome}');
      await r.vault!.close();
      expect(File('${dir.path}/salt.next').existsSync(), isFalse);
      expect(File('${dir.path}/secret.mv.next').existsSync(), isFalse);
      // Dropped, not finished: the old PIN is the one that opens.
      expect((await manager.openWithPin('246810')).isOpen, isTrue);
    });

    test('PRIV-007 half-written files are swept at the next open', () async {
      File('${dir.path}/abc.tm.part').writeAsBytesSync([1, 2, 3]);
      File('${dir.path}/salt.part').writeAsBytesSync([1, 2, 3]);
      final r = await manager.openWithPin('555555');
      await r.vault!.close();
      expect(File('${dir.path}/abc.tm.part').existsSync(), isFalse);
    });
  });

  group('PRIV-007 locking while the vault is being changed', () {
    test(
      'PRIV-007 a lock during Change PIN does not seal a zero secret',
      () async {
        final r = await manager.setUp(pin: '246810', decoyPin: '135790');
        await addTo(r.vault!, 'real.jpg');
        final change = manager.changePin(r.vault!, '555555');
        // The vault locks while the new PIN is still being worked out.
        await r.vault!.close();
        expect(await change, VaultOutcome.opened);
        final again = await manager.openWithPin('555555');
        expect(again.isOpen, isTrue, reason: '${again.outcome}');
        expect(again.vault!.container.list().single.name, 'real.jpg');
        await again.vault!.close();
      },
    );

    test(
      'PRIV-007 a lock during the fingerprint prompt seals the real secret',
      () async {
        final r = await manager.setUp(pin: '246810', decoyPin: '135790');
        await addTo(r.vault!, 'real.jpg');
        final on = manager.setFingerprint(r.vault!, enabled: true);
        await r.vault!.close();
        expect(await on, VaultOutcome.opened);
        final f = await manager.openWithFingerprint();
        expect(f.isOpen, isTrue, reason: '${f.outcome}');
        expect(f.vault!.container.list().single.name, 'real.jpg');
        await f.vault!.close();
      },
    );

    test('PRIV-007 a locked vault cannot turn the fingerprint on', () async {
      final r = await manager.setUp(pin: '246810', decoyPin: '135790');
      await r.vault!.close();
      expect(
        await manager.setFingerprint(r.vault!, enabled: true),
        VaultOutcome.unavailable,
      );
      expect(await manager.fingerprintOn, isFalse);
    });
  });

  group('PRIV-007 the fingerprint key and the phone keys', () {
    test(
      'PRIV-007 a lost fingerprint key only turns the fingerprint off',
      () async {
        final r = await manager.setUp(
          pin: '246810',
          decoyPin: '135790',
          fingerprint: true,
        );
        await r.vault!.close();
        crypto.invalidateBiometricKey();
        final f = await manager.openWithFingerprint();
        expect(f.outcome, VaultOutcome.fingerprintInvalidated);
        expect(await manager.fingerprintOn, isFalse);
        expect((await manager.openWithPin('246810')).isOpen, isTrue);
      },
    );

    test(
      'PRIV-007 a keystore that lost every key is a fingerprint problem first',
      () async {
        final r = await manager.setUp(
          pin: '246810',
          decoyPin: '135790',
          fingerprint: true,
        );
        await r.vault!.close();
        crypto.loseKeys();
        // Not "the vault is lost": that is what the PIN says, after asking the
        // keystore.
        expect(
          (await manager.openWithFingerprint()).outcome,
          VaultOutcome.fingerprintInvalidated,
        );
        expect(
          (await manager.openWithPin('246810')).outcome,
          VaultOutcome.keyLost,
        );
      },
    );
  });

  group('PRIV-007 set-up, Change PIN and reset that fail half way', () {
    List<Directory> vaultDirs() =>
        root.listSync().whereType<Directory>().where((d) {
          final n = d.path.split(Platform.pathSeparator).last;
          return RegExp(r'^[0-9a-f]{16}$').hasMatch(n);
        }).toList();

    test('PRIV-007 a stop before any folder was made is no vault', () async {
      // The marker alone, as after a stop right after it was written.
      root.createSync(recursive: true);
      File('${root.path}/.setup').writeAsBytesSync(const []);
      expect(manager.exists, isFalse);
      final r = await manager.setUp(pin: '246810', decoyPin: '135790');
      expect(r.isOpen, isTrue, reason: '${r.outcome}');
      await r.vault!.close();
      expect(File('${root.path}/.setup').existsSync(), isFalse);
      expect(vaultDirs(), hasLength(2));
    });

    test(
      'PRIV-007 a stop with an empty folder is no vault and is swept',
      () async {
        root.createSync(recursive: true);
        File('${root.path}/.setup').writeAsBytesSync(const []);
        Directory('${root.path}/0123456789abcdef').createSync();
        expect(manager.exists, isFalse);
        expect(
          (await manager.openWithPin('246810')).outcome,
          VaultOutcome.needsSetup,
        );
        final r = await manager.setUp(pin: '246810', decoyPin: '135790');
        expect(r.isOpen, isTrue);
        await r.vault!.close();
        expect(
          Directory('${root.path}/0123456789abcdef').existsSync(),
          isFalse,
        );
        expect(vaultDirs(), hasLength(2));
      },
    );

    test('PRIV-007 a stop with only one finished folder never leaves a lone vault', () async {
      final r = await manager.setUp(pin: '246810', decoyPin: '135790');
      await r.vault!.close();
      final dirs = vaultDirs();
      // Back to the moment before the commit, with the second folder not made.
      File('${root.path}/.setup').writeAsBytesSync(const []);
      dirs.last.deleteSync(recursive: true);
      expect(manager.exists, isFalse);
      final again = await manager.setUp(pin: '246810', decoyPin: '135790');
      expect(again.isOpen, isTrue, reason: '${again.outcome}');
      await again.vault!.close();
      expect(vaultDirs(), hasLength(2));
      // And both PINs open their own vault.
      expect((await manager.openWithPin('135790')).isOpen, isTrue);
    });

    test(
      'PRIV-007 deleting the marker is the commit: both folders are the vault',
      () async {
        final r = await manager.setUp(pin: '246810', decoyPin: '135790');
        await r.vault!.close();
        expect(File('${root.path}/.setup').existsSync(), isFalse);
        expect(manager.exists, isTrue);
        expect((await manager.openWithPin('246810')).isOpen, isTrue);
      },
    );

    String last(FileSystemEntity e) =>
        e.path.split(Platform.pathSeparator).last;

    test('PRIV-007 a reset stopped after the folders were moved is finished at the next start', () async {
      final r = await manager.setUp(
        pin: '246810',
        decoyPin: '135790',
        fingerprint: true,
      );
      await r.vault!.close();
      await manager.openWithPin('000001');
      File('${root.path}/.reset').writeAsBytesSync(const []);
      for (final d in vaultDirs()) {
        d.renameSync('${root.path}/.trash-${last(d)}');
      }
      final before = crypto.resets;
      expect(manager.exists, isFalse);
      expect(
        (await manager.openWithPin('246810')).outcome,
        VaultOutcome.needsSetup,
      );
      final s = await manager.setUp(pin: '111111', decoyPin: '222222');
      expect(s.isOpen, isTrue, reason: '${s.outcome}');
      await s.vault!.close();
      expect(crypto.resets, before + 1);
      expect(File('${root.path}/.reset').existsSync(), isFalse);
      expect(
        root.listSync().where((e) => last(e).startsWith('.trash-')),
        isEmpty,
      );
      expect(await manager.fingerprintOn, isFalse);
      expect(vaultDirs(), hasLength(2));
    });

    test(
      'PRIV-007 a reset stopped right after its journal is finished too',
      () async {
        final r = await manager.setUp(pin: '246810', decoyPin: '135790');
        await r.vault!.close();
        File('${root.path}/.reset').writeAsBytesSync(const []);
        expect(manager.exists, isFalse);
        final s = await manager.setUp(pin: '111111', decoyPin: '222222');
        expect(s.isOpen, isTrue, reason: '${s.outcome}');
        await s.vault!.close();
        expect(vaultDirs(), hasLength(2));
        expect((await manager.openWithPin('246810')).isOpen, isFalse);
      },
    );

    test('PRIV-007 if the key cannot be deleted while finishing, the journal stays', () async {
      final r = await manager.setUp(pin: '246810', decoyPin: '135790');
      await r.vault!.close();
      File('${root.path}/.reset').writeAsBytesSync(const []);
      crypto.failReset = VaultCryptoError.unavailable;
      expect(
        (await manager.setUp(pin: '111111', decoyPin: '222222')).outcome,
        VaultOutcome.unavailable,
      );
      expect(File('${root.path}/.reset').existsSync(), isTrue);
      crypto.failReset = null;
      final s = await manager.setUp(pin: '111111', decoyPin: '222222');
      expect(s.isOpen, isTrue, reason: '${s.outcome}');
      await s.vault!.close();
    });

    test('PRIV-007 a reset whose undo finds a folder gone says it will finish later', () async {
      final r = await manager.setUp(pin: '246810', decoyPin: '135790');
      await r.vault!.close();
      // At the moment the key is to go, one moved folder disappears.
      crypto
        ..failReset = VaultCryptoError.unavailable
        ..beforeReset = () {
          root
              .listSync()
              .whereType<Directory>()
              .firstWhere(
                (d) => d.path
                    .split(Platform.pathSeparator)
                    .last
                    .startsWith('.trash-'),
              )
              .deleteSync(recursive: true);
        };
      await expectLater(manager.reset(), throwsA(isA<VaultResetPending>()));
      crypto
        ..failReset = null
        ..beforeReset = null;
      // The journal stays, so the next start finishes the reset.
      expect(File('${root.path}/.reset').existsSync(), isTrue);
      expect(manager.exists, isFalse);
      await manager.recoverPending();
      expect(File('${root.path}/.reset').existsSync(), isFalse);
      expect(root.listSync().whereType<Directory>(), isEmpty);
    });

    test('PRIV-007 the real provider finishes a stopped reset as the manager starts', () async {
      final r = await manager.setUp(pin: '246810', decoyPin: '135790');
      await r.vault!.close();
      File('${root.path}/.reset').writeAsBytesSync(const []);
      final before = crypto.resets;
      final container = ProviderContainer(
        overrides: [
          vaultRootProvider.overrideWith((ref) async => root),
          vaultCryptoProvider.overrideWithValue(crypto),
          secureStorageProvider.overrideWithValue(secure),
        ],
      );
      addTearDown(container.dispose);
      final made = await container.read(vaultManagerProvider.future);
      expect(crypto.resets, before + 1);
      expect(File('${root.path}/.reset').existsSync(), isFalse);
      expect(made.exists, isFalse);
    });

    test('PRIV-007 a reset that works leaves no journal', () async {
      final r = await manager.setUp(pin: '246810', decoyPin: '135790');
      await r.vault!.close();
      await manager.reset();
      expect(File('${root.path}/.reset').existsSync(), isFalse);
    });

    test(
      'PRIV-007 the rounds of new PINs are kept within the allowed range',
      () {
        final low = VaultManager(
          root: root,
          crypto: crypto,
          secure: secure,
          iterations: 1,
          minRounds: 4,
          kdf: inlinePinToken,
        );
        expect(low.iterations, 4);
        final high = VaultManager(
          root: root,
          crypto: crypto,
          secure: secure,
          iterations: 999999999,
          minRounds: 4,
          kdf: inlinePinToken,
        );
        expect(high.iterations, VaultManager.maxRounds);
      },
    );

    test('PRIV-007 a storage error turning the fingerprint on at set-up costs nothing else', () async {
      secure.failWrites = StateError('storage');
      final r = await manager.setUp(
        pin: '246810',
        decoyPin: '135790',
        fingerprint: true,
      );
      secure.failWrites = null;
      expect(r.isOpen, isTrue, reason: '${r.outcome}');
      await addTo(r.vault!, 'real.jpg');
      await r.vault!.close();
      expect(vaultDirs(), hasLength(2));
      expect(await manager.fingerprintOn, isFalse);
      final again = await manager.openWithPin('246810');
      expect(again.vault!.container.list().single.name, 'real.jpg');
      await again.vault!.close();
      expect((await manager.openWithPin('135790')).isOpen, isTrue);
    });

    test(
      'PRIV-007 a stopped reset is finished as the app starts, without set-up',
      () async {
        final r = await manager.setUp(pin: '246810', decoyPin: '135790');
        await r.vault!.close();
        File('${root.path}/.reset').writeAsBytesSync(const []);
        File('${root.path}/.reset.part').writeAsBytesSync(const []);
        expect(manager.exists, isFalse);
        final before = crypto.resets;
        await manager.recoverPending();
        expect(crypto.resets, before + 1);
        expect(File('${root.path}/.reset').existsSync(), isFalse);
        expect(File('${root.path}/.reset.part').existsSync(), isFalse);
        expect(vaultDirs(), isEmpty);
        // A keystore failure there is not thrown: the journal waits.
        File('${root.path}/.reset').writeAsBytesSync(const []);
        crypto.failReset = VaultCryptoError.unavailable;
        await manager.recoverPending();
        expect(File('${root.path}/.reset').existsSync(), isTrue);
        crypto.failReset = null;
      },
    );

    test(
      'PRIV-007 a storage error while finishing a reset is reported by set-up',
      () async {
        File('${root.path}/.reset').createSync(recursive: true);
        // A platform error, not the keystore's own kind.
        crypto.failResetWith = StateError('platform');
        expect(
          (await manager.setUp(pin: '246810', decoyPin: '135790')).outcome,
          VaultOutcome.unavailable,
        );
        crypto.failResetWith = null;
      },
    );
    test(
      'PRIV-007 a set-up that fails leaves no folder and no marker',
      () async {
        crypto.failChunks = VaultCryptoError.unavailable;
        await manager.setUp(pin: '246810', decoyPin: '135790');
        crypto.failChunks = null;
        expect(
          root.existsSync() ? root.listSync() : const <FileSystemEntity>[],
          isEmpty,
        );
      },
    );

    test(
      'PRIV-007 a failing set-up leaves no folder behind, marked or not',
      () async {
        crypto.failChunks = VaultCryptoError.unavailable;
        expect(
          (await manager.setUp(pin: '246810', decoyPin: '135790')).isOpen,
          isFalse,
        );
        expect(
          root.existsSync() ? root.listSync() : const <FileSystemEntity>[],
          isEmpty,
        );
      },
    );

    test(
      'PRIV-007 a Change PIN whose last rename fails still succeeds',
      () async {
        final r = await manager.setUp(pin: '246810', decoyPin: '135790');
        await addTo(r.vault!, 'real.jpg');
        final dir = r.vault!.container.directory;
        final oldSalt = File('${dir.path}/salt').readAsBytesSync();
        File('${dir.path}/salt').deleteSync();
        Directory('${dir.path}/salt').createSync();
        expect(
          await manager.changePin(r.vault!, '555555'),
          VaultOutcome.opened,
        );
        expect(File('${dir.path}/salt.next').existsSync(), isTrue);
        await r.vault!.close();
        Directory('${dir.path}/salt').deleteSync();
        File('${dir.path}/salt').writeAsBytesSync(oldSalt);
        final again = await manager.openWithPin('555555');
        expect(again.isOpen, isTrue, reason: '${again.outcome}');
        await again.vault!.close();
      },
    );

    test(
      'PRIV-007 a keystore failure while checking the other vault is reported',
      () async {
        final r = await manager.setUp(pin: '246810', decoyPin: '135790');
        crypto.failPlainOpen = VaultCryptoError.unavailable;
        expect(
          await manager.changePin(r.vault!, '555555'),
          VaultOutcome.unavailable,
        );
        crypto.failPlainOpen = null;
        await r.vault!.close();
        expect((await manager.openWithPin('246810')).isOpen, isTrue);
      },
    );

    test('PRIV-007 a reset that fails puts the folders back', () async {
      final r = await manager.setUp(pin: '246810', decoyPin: '135790');
      await addTo(r.vault!, 'real.jpg');
      await r.vault!.close();
      crypto.failReset = VaultCryptoError.unavailable;
      await expectLater(manager.reset(), throwsA(isA<VaultCryptoException>()));
      crypto.failReset = null;
      expect(root.listSync().whereType<Directory>(), hasLength(2));
      for (final d in root.listSync().whereType<Directory>()) {
        expect(
          d.path.split(Platform.pathSeparator).last,
          matches(r'^[0-9a-f]{16}$'),
        );
      }
      final ok = await manager.openWithPin('246810');
      expect(ok.vault!.container.list().single.name, 'real.jpg');
      await ok.vault!.close();
    });

    test(
      'PRIV-007 a reset that worked leaves nothing, trash included',
      () async {
        final r = await manager.setUp(pin: '246810', decoyPin: '135790');
        await r.vault!.close();
        await manager.reset();
        expect(root.listSync(), isEmpty);
      },
    );
  });

  group('PRIV-007 Change PIN with a damaged or closed vault', () {
    test('PRIV-007 a damaged other vault does not block Change PIN', () async {
      final r = await manager.setUp(pin: '246810', decoyPin: '135790');
      final other = root.listSync().whereType<Directory>().firstWhere(
        (d) => d.path != r.vault!.container.directory.path,
      );
      File('${other.path}/secret.mv').writeAsBytesSync(bytesOf(100));
      expect(await manager.changePin(r.vault!, '555555'), VaultOutcome.opened);
      await r.vault!.close();
    });

    test(
      'PRIV-007 a closed vault refuses Change PIN and counts no try',
      () async {
        final r = await manager.setUp(pin: '246810', decoyPin: '135790');
        await r.vault!.close();
        for (var i = 0; i < 6; i++) {
          await expectLater(
            manager.changePin(r.vault!, '555555'),
            throwsA(isA<VaultLocked>()),
          );
        }
        expect((await manager.openWithPin('246810')).isOpen, isTrue);
      },
    );
  });

  group('PRIV-007 one damaged vault does not shut out the other', () {
    test(
      'PRIV-007 a damaged index in one folder leaves the other PIN working',
      () async {
        final r = await manager.setUp(pin: '246810', decoyPin: '135790');
        final real = r.vault!.container.directory;
        await r.vault!.close();
        File('${real.path}/index.mv').writeAsBytesSync(bytesOf(300));
        final other = await manager.openWithPin('135790');
        expect(other.isOpen, isTrue, reason: '${other.outcome}');
        await other.vault!.close();
        // The damaged one is just a PIN that opens nothing.
        expect(
          (await manager.openWithPin('246810')).outcome,
          VaultOutcome.wrongPin,
        );
      },
    );

    test(
      'PRIV-007 a lost key is reported only when every vault is lost',
      () async {
        final r = await manager.setUp(pin: '246810', decoyPin: '135790');
        await r.vault!.close();
        crypto.loseKeys();
        expect(
          (await manager.openWithPin('246810')).outcome,
          VaultOutcome.keyLost,
        );
        expect(crypto.openHandles, 0);
      },
    );
  });

  group('PRIV-007 hardening', () {
    test(
      'PRIV-007 a salt file cannot be edited to make the PIN cheap to guess',
      () async {
        final strict = VaultManager(
          root: root,
          crypto: crypto,
          secure: secure,
          iterations: 4,
          minRounds: 4,
          kdf: inlinePinToken,
          clock: () => now,
        );
        final r = await strict.setUp(pin: '246810', decoyPin: '135790');
        final dir = r.vault!.container.directory;
        await r.vault!.close();
        final f = File('${dir.path}/salt');
        final b = f.readAsBytesSync();
        ByteData.sublistView(b).setUint32(16, 1);
        f.writeAsBytesSync(b);
        // Read as 4 rounds, as made: the PIN still opens (with one round the
        // token would differ and nothing would).
        final ok = await strict.openWithPin('246810');
        expect(ok.isOpen, isTrue);
        await ok.vault!.close();
      },
    );
  });

  group('PRIV-007 PIN work', () {
    test('PRIV-007 PBKDF2 matches the published test vector', () {
      // RFC 7914 §11: PBKDF2-HMAC-SHA-256("passwd", "salt", 1, 32) starts
      // 55 ac 04 6e 56 e3 08 9f ec 16 91 c2 25 44 b6 05.
      final out = pbkdf2Sha256('passwd'.codeUnits, 'salt'.codeUnits, 1);
      expect(out.sublist(0, 16), [
        0x55,
        0xac,
        0x04,
        0x6e,
        0x56,
        0xe3,
        0x08,
        0x9f,
        0xec,
        0x16,
        0x91,
        0xc2,
        0x25,
        0x44,
        0xb6,
        0x05,
      ]);
    });

    test('PRIV-007 new vaults use at least 600,000 rounds', () {
      expect(vaultKdfIterations, greaterThanOrEqualTo(600000));
      expect(
        VaultManager(root: root, crypto: crypto, secure: secure).iterations,
        vaultKdfIterations,
      );
    });

    test('PRIV-007 a made-up PIN is 16 digits', () {
      final p = VaultManager.randomPin();
      expect(p, matches(r'^\d{16}$'));
      expect(VaultManager.randomPin(), isNot(p));
    });
  });
}

/// The salt of the first vault folder, for checking nothing keeps the token.
Future<Uint8List> _saltOf(Directory root, int i) async {
  final dirs = root.listSync().whereType<Directory>().toList()
    ..sort((a, b) => a.path.compareTo(b.path));
  return Uint8List.sublistView(
    File('${dirs[i].path}/salt').readAsBytesSync(),
    0,
    16,
  );
}
