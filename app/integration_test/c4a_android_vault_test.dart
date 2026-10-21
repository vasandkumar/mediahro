import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mediahro/platform/android/android_vault.dart';
import 'package:mediahro/platform/platform_bindings.dart';
import 'package:mediahro/platform/platform_facades.dart';

/// Lane C4a: the vault's OS crypto and the secure window on an Android device
/// (IMG-011, ADR-039). The Keystore path runs for real; the biometric path
/// needs a person at the prompt, so it is a hand check.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final android = Platform.isAndroid;

  const window = BasicMessageChannel<Object?>(
    'mediahro.test/window',
    StandardMessageCodec(),
  );
  Future<bool> secureFlag() async =>
      ((await window.send(null))! as Map<Object?, Object?>)['secure']! as bool;

  Uint8List bytes(int n, [int seed = 1]) =>
      Uint8List.fromList(List.generate(n, (i) => (i * 7 + seed) & 0xff));

  testWidgets('IMG-011 Android bindings provide vault crypto and window', (
    tester,
  ) async {
    final c = ProviderContainer(overrides: platformOverrides());
    addTearDown(c.dispose);
    expect(c.read(vaultCryptoProvider), isA<AndroidVaultCrypto>());
    expect(c.read(secureWindowProvider), isA<AndroidSecureWindow>());
  }, skip: !android);

  testWidgets('IMG-011 Keystore master key: seal, open, tamper, wrong AAD', (
    tester,
  ) async {
    final crypto = AndroidVaultCrypto();
    final master = await crypto.openMasterKey(requireBiometry: false);
    addTearDown(() => crypto.close(master));
    final key = await crypto.newFileKey(master);
    final nonce = bytes(VaultCryptoFacade.nonceLength);
    final aad = bytes(24, 3);
    final plain = bytes(100000, 9);

    final sealed = await crypto.seal(key, nonce, aad, plain);
    expect(sealed.length, plain.length + VaultCryptoFacade.tagLength);
    expect(sealed.sublist(0, 16), isNot(plain.sublist(0, 16)));
    expect(await crypto.open(key, nonce, aad, sealed), plain);

    // The wrapped key reopens through adopt, as after an app restart.
    final adopted = await crypto.adoptFileKey(master, key.bytes);
    expect(await crypto.open(adopted, nonce, aad, sealed), plain);

    Future<void> expectIntegrityFailure(Future<Object?> f) => expectLater(
      f,
      throwsA(
        isA<VaultCryptoException>().having(
          (e) => e.error,
          'error',
          VaultCryptoError.integrityFailure,
        ),
      ),
    );
    final flipped = Uint8List.fromList(sealed)..[10] ^= 1;
    await expectIntegrityFailure(crypto.open(key, nonce, aad, flipped));
    await expectIntegrityFailure(crypto.open(key, nonce, bytes(24, 4), sealed));
    await expectIntegrityFailure(
      crypto.open(key, bytes(VaultCryptoFacade.nonceLength, 2), aad, sealed),
    );
    await expectIntegrityFailure(
      crypto.open(key, nonce, aad, sealed.sublist(0, sealed.length - 1)),
    );
  }, skip: !android);

  testWidgets('IMG-011 another file key and damaged wrapped keys are refused', (
    tester,
  ) async {
    final crypto = AndroidVaultCrypto();
    final master = await crypto.openMasterKey(requireBiometry: false);
    addTearDown(() => crypto.close(master));
    final a = await crypto.newFileKey(master);
    final b = await crypto.newFileKey(master);
    expect(a.bytes, isNot(b.bytes));
    final nonce = bytes(VaultCryptoFacade.nonceLength);
    final sealed = await crypto.seal(a, nonce, Uint8List(0), bytes(64));
    await expectLater(
      crypto.open(b, nonce, Uint8List(0), sealed),
      throwsA(isA<VaultCryptoException>()),
    );
    final damaged = Uint8List.fromList(a.bytes)..[a.bytes.length - 1] ^= 1;
    await expectLater(
      crypto.adoptFileKey(master, damaged),
      throwsA(
        isA<VaultCryptoException>().having(
          (e) => e.error,
          'error',
          VaultCryptoError.keyLost,
        ),
      ),
    );
  }, skip: !android);

  testWidgets('IMG-011 a closed handle can no longer seal', (tester) async {
    final crypto = AndroidVaultCrypto();
    final master = await crypto.openMasterKey(requireBiometry: false);
    final key = await crypto.newFileKey(master);
    await crypto.close(master);
    await crypto.close(master); // safe to repeat
    await expectLater(
      crypto.seal(
        key,
        bytes(VaultCryptoFacade.nonceLength),
        Uint8List(0),
        bytes(8),
      ),
      throwsA(isA<VaultCryptoException>()),
    );
  }, skip: !android);

  testWidgets('IMG-011 opening the master key twice at once gives one key', (
    tester,
  ) async {
    final crypto = AndroidVaultCrypto();
    final handles = await Future.wait([
      crypto.openMasterKey(requireBiometry: false),
      crypto.openMasterKey(requireBiometry: false),
      crypto.openMasterKey(requireBiometry: false),
    ]);
    addTearDown(() => Future.wait(handles.map(crypto.close)));
    expect(handles.toSet(), hasLength(3));
    final key = await crypto.newFileKey(handles[0]);
    final nonce = bytes(VaultCryptoFacade.nonceLength);
    final sealed = await crypto.seal(key, nonce, Uint8List(0), bytes(32));
    // A file key made under one handle opens under another: the same master key.
    final other = await crypto.adoptFileKey(handles[2], key.bytes);
    expect(await crypto.open(other, nonce, Uint8List(0), sealed), bytes(32));
  }, skip: !android);

  testWidgets('IMG-011 a secret binds the file keys of a handle to it', (
    tester,
  ) async {
    final crypto = AndroidVaultCrypto();
    final a1 = await crypto.openMasterKey(
      requireBiometry: false,
      secret: bytes(32, 11),
    );
    final b = await crypto.openMasterKey(
      requireBiometry: false,
      secret: bytes(32, 12),
    );
    final none = await crypto.openMasterKey(requireBiometry: false);
    addTearDown(() => Future.wait([a1, b, none].map(crypto.close)));
    final key = await crypto.newFileKey(a1);
    final nonce = bytes(VaultCryptoFacade.nonceLength);
    final sealed = await crypto.seal(key, nonce, Uint8List(0), bytes(48));

    Matcher keyLost() => throwsA(
      isA<VaultCryptoException>().having(
        (e) => e.error,
        'error',
        VaultCryptoError.keyLost,
      ),
    );
    await expectLater(crypto.adoptFileKey(b, key.bytes), keyLost());
    await expectLater(crypto.adoptFileKey(none, key.bytes), keyLost());

    // The same secret on a new handle (after a restart) opens it.
    final a2 = await crypto.openMasterKey(
      requireBiometry: false,
      secret: bytes(32, 11),
    );
    addTearDown(() => crypto.close(a2));
    final again = await crypto.adoptFileKey(a2, key.bytes);
    expect(await crypto.open(again, nonce, Uint8List(0), sealed), bytes(48));

    // A file key made without a secret does not open under one.
    final plain = await crypto.newFileKey(none);
    await expectLater(crypto.adoptFileKey(a1, plain.bytes), keyLost());
    // A secret that is not exactly 32 bytes is refused, never treated as none.
    for (final n in [0, 1, 31, 33]) {
      await expectLater(
        crypto.openMasterKey(requireBiometry: false, secret: bytes(n, 5)),
        throwsA(
          isA<VaultCryptoException>().having(
            (e) => e.error,
            'error',
            VaultCryptoError.unavailable,
          ),
        ),
      );
    }
  }, skip: !android);

  testWidgets('IMG-011 reset deletes the master key; nothing re-creates it', (
    tester,
  ) async {
    // Touches only the vault's own keys; run before the vault holds real data.
    final crypto = AndroidVaultCrypto();
    final master = await crypto.openMasterKey(requireBiometry: false);
    final old = await crypto.newFileKey(master);
    await crypto.reset();
    // The open handle was closed by the reset.
    await expectLater(
      crypto.newFileKey(master),
      throwsA(isA<VaultCryptoException>()),
    );
    final fresh = await crypto.openMasterKey(requireBiometry: false);
    addTearDown(() => crypto.close(fresh));
    await expectLater(
      crypto.adoptFileKey(fresh, old.bytes),
      throwsA(
        isA<VaultCryptoException>().having(
          (e) => e.error,
          'error',
          VaultCryptoError.keyLost,
        ),
      ),
    );
    // And a strict error code on a handle that was never open.
    await expectLater(
      crypto.newFileKey(const VaultKeyHandle(987654)),
      throwsA(
        isA<VaultCryptoException>().having(
          (e) => e.error,
          'error',
          VaultCryptoError.unavailable,
        ),
      ),
    );
  }, skip: !android);

  testWidgets('IMG-011 the secure window sets and clears FLAG_SECURE', (
    tester,
  ) async {
    final secure = AndroidSecureWindow();
    addTearDown(() => secure.setSecure(secure: false));
    await secure.setSecure(secure: true);
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(await secureFlag(), isTrue);
    await secure.setSecure(secure: false);
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(await secureFlag(), isFalse);
    final sub = secure.captureActive.listen((_) {});
    await sub.cancel();
  }, skip: !android);
}
