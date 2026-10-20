import 'dart:typed_data';

import 'package:mediahro/platform/android/gen/security_api.pigeon.dart';
import 'package:mediahro/platform/security.dart';

/// [SecureStorageFacade] on Android (PRIV-006, ADR-008): values sealed with
/// a Keystore AES-256-GCM key (StrongBox where present); vault keys wrapped
/// with it, or with a Keystore RSA key that needs the user for every unwrap
/// (`SecureStorageModule.kt`).
///
/// Errors arrive as `PlatformException` codes: `notEnrolled` (no screen
/// lock for a user-bound key), `cancelled`, `lockedOut`, `authFailed`,
/// `keyInvalidated` (biometrics changed; use the recovery key), `keyLost`.
final class AndroidSecureStorage implements SecureStorageFacade {
  AndroidSecureStorage({SecureStorageHostApi? api})
    : _api = api ?? SecureStorageHostApi();

  final SecureStorageHostApi _api;

  @override
  Future<String?> read(String key) => _api.read(key);

  @override
  Future<void> write(String key, String value) => _api.write(key, value);

  @override
  Future<void> delete(String key) => _api.delete(key);

  @override
  Future<List<int>> wrapKey(List<int> key, {required bool requireBiometry}) =>
      _api.wrapKey(Uint8List.fromList(key), requireBiometry);

  @override
  Future<List<int>> unwrapKey(List<int> wrapped, {required String reason}) =>
      _api.unwrapKey(Uint8List.fromList(wrapped), reason);
}

/// [BiometricsFacade] on Android (PRIV-008, IMG-011, LIB-013):
/// BiometricPrompt with the device credential as fallback
/// (`BiometricsModule.kt`). A cancel is `false`; lockout and missing
/// enrolment throw `PlatformException`.
final class AndroidBiometrics implements BiometricsFacade {
  AndroidBiometrics({BiometricsHostApi? api})
    : _api = api ?? BiometricsHostApi();

  final BiometricsHostApi _api;

  @override
  Future<BiometricKind> available() async =>
      BiometricKind.values[(await _api.available()).index];

  @override
  Future<bool> authenticate({required String reason}) =>
      _api.authenticate(reason);
}
