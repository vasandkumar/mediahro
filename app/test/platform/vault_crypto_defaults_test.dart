import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediahro/platform/platform_facades.dart';

void main() {
  test('IMG-011 vault crypto has no fake default and throws', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    expect(
      () => c.read(vaultCryptoProvider),
      // Riverpod may wrap the error; the capability name must survive.
      throwsA(
        predicate<Object>(
          (e) => '$e'.contains('PlatformCapabilityUnavailable(vaultCrypto)'),
        ),
      ),
    );
  });

  test('IMG-011 secure window defaults to a no-op', () async {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final w = c.read(secureWindowProvider);
    expect(w, isA<UnsupportedSecureWindow>());
    await w.setSecure(secure: true);
    await w.setSecure(secure: false);
    expect(await w.captureActive.isEmpty, isTrue);
  });

  test('IMG-011 vault key value types and error mapping', () {
    expect(const VaultKeyHandle(3), const VaultKeyHandle(3));
    expect(const VaultKeyHandle(3), isNot(const VaultKeyHandle(4)));
    final k = WrappedKey(
      master: const VaultKeyHandle(1),
      bytes: Uint8List.fromList([1, 2, 3]),
    );
    expect(k.bytes, hasLength(3));
    const e = VaultCryptoException(VaultCryptoError.keyInvalidated, 'x');
    expect(e.error, VaultCryptoError.keyInvalidated);
    expect(
      VaultCryptoError.values.map((v) => v.name),
      containsAll(<String>[
        'cancelled',
        'notEnrolled',
        'keyInvalidated',
        'keyLost',
        'lockedOut',
        'authFailed',
        'unavailable',
        'integrityFailure',
      ]),
    );
    expect(VaultCryptoFacade.nonceLength, 12);
    expect(VaultCryptoFacade.tagLength, 16);
  });
}
