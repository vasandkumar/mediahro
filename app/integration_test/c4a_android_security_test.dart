import 'dart:io';
import 'dart:math';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mediahro/platform/android/android_security.dart';
import 'package:mediahro/platform/platform_bindings.dart';
import 'package:mediahro/platform/platform_facades.dart';

/// Lane C4a: SecureStorageFacade and BiometricsFacade on an Android device.
/// The Keystore paths that need no user run here; prompts that need a
/// finger or the PIN (user-bound unwrap, authenticate) are manual checks.
/// A debug-only hook (`mediahro.test/secure`) reads the raw stored entry.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final android = Platform.isAndroid;

  const hook = BasicMessageChannel<Object?>(
    'mediahro.test/secure',
    StandardMessageCodec(),
  );
  Future<Map<Object?, Object?>> raw(String key) async =>
      (await hook.send(key))! as Map<Object?, Object?>;

  final run = DateTime.now().microsecondsSinceEpoch;
  late AndroidSecureStorage secure;
  late AndroidBiometrics biometrics;
  setUp(() {
    if (!android) return;
    secure = AndroidSecureStorage();
    biometrics = AndroidBiometrics();
  });

  testWidgets(
    'PRIV-006 Android bindings provide SecureStorage and Biometrics',
    (tester) async {
      final c = ProviderContainer(overrides: platformOverrides());
      addTearDown(c.dispose);
      expect(c.read(secureStorageProvider), isA<AndroidSecureStorage>());
      expect(c.read(biometricsProvider), isA<AndroidBiometrics>());
    },
    skip: !android,
  );

  testWidgets(
    'PRIV-006 secrets round-trip through the Keystore and never sit in plain text',
    (tester) async {
      final key = 'c4a.test.$run';
      final value = 'smb-password-$run-ünï';
      addTearDown(() => secure.delete(key));
      expect(await secure.read(key), isNull);
      await secure.write(key, value);
      expect(await secure.read(key), value);
      final stored = await raw(key);
      expect(stored['stored'], isNotNull);
      expect(stored['stored'], isNot(contains('smb-password')));
      expect(stored['file'], isNot(contains('smb-password')));
      await secure.write(key, '$value-2');
      expect(await secure.read(key), '$value-2');
      await secure.delete(key);
      expect(await secure.read(key), isNull);
      expect((await raw(key))['stored'], isNull);
    },
    skip: !android,
  );

  testWidgets('PRIV-006 secrets are bound to their key names', (tester) async {
    final a = 'c4a.a.$run';
    final b = 'c4a.b.$run';
    addTearDown(() async {
      await secure.delete(a);
      await secure.delete(b);
    });
    await secure.write(a, 'alpha');
    await secure.write(b, 'beta');
    expect(await secure.read(a), 'alpha');
    expect(await secure.read(b), 'beta');
  }, skip: !android);

  testWidgets('ADR-008 vault key wraps and unwraps with the device key', (
    tester,
  ) async {
    final rng = Random.secure();
    final key = List<int>.generate(32, (_) => rng.nextInt(256));
    final wrapped = await secure.wrapKey(key, requireBiometry: false);
    expect(wrapped.sublist(0, 2), [1, 0], reason: 'format v1, no user');
    expect(wrapped.length, greaterThan(key.length));
    expect(await secure.unwrapKey(wrapped, reason: 'test'), key);
    // Tampering is detected (AES-GCM tag).
    final bad = [...wrapped]..[wrapped.length - 1] ^= 1;
    await expectLater(
      secure.unwrapKey(bad, reason: 'test'),
      throwsA(isA<PlatformException>()),
    );
  }, skip: !android);

  testWidgets(
    'ADR-008 user-bound wrap needs a screen lock and no prompt to wrap',
    (tester) async {
      final key = List<int>.filled(32, 7);
      final kind = await biometrics.available();
      if (kind == BiometricKind.none) {
        await expectLater(
          secure.wrapKey(key, requireBiometry: true),
          throwsA(
            isA<PlatformException>().having(
              (e) => e.code,
              'code',
              'notEnrolled',
            ),
          ),
        );
        return;
      }
      final wrapped = await secure.wrapKey(key, requireBiometry: true);
      expect(wrapped.sublist(0, 2), [1, 1], reason: 'format v1, user-bound');
      expect(wrapped.length, 2 + 256, reason: 'RSA-2048 OAEP');
    },
    skip: !android,
  );

  testWidgets('PRIV-008 biometrics report what the device offers', (
    tester,
  ) async {
    final kind = await biometrics.available();
    expect(BiometricKind.values, contains(kind));
    if (kind == BiometricKind.none) {
      expect(await biometrics.authenticate(reason: 'test'), isFalse);
    }
  }, skip: !android);
}
