import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mediahro/platform/android/android_security.dart';
import 'package:mediahro/platform/android/gen/security_api.pigeon.dart';
import 'package:mediahro/platform/security.dart';

/// The Dart half of lane C4a's secure storage and biometrics.
final class _FakeSecure extends SecureStorageHostApi {
  bool? lastRequire;
  String? lastReason;

  @override
  Future<Uint8List> wrapKey(Uint8List key, bool requireBiometry) async {
    lastRequire = requireBiometry;
    final mode = requireBiometry ? 1 : 0;
    return Uint8List.fromList([1, mode, ...key]);
  }

  @override
  Future<Uint8List> unwrapKey(Uint8List wrapped, String reason) async {
    lastReason = reason;
    return wrapped.sublist(2);
  }
}

final class _FakeBio extends BiometricsHostApi {
  @override
  Future<BiometricKindMsg> available() async => BiometricKindMsg.face;
}

void main() {
  test(
    'ADR-008 wrap and unwrap carry the user requirement and reason',
    () async {
      final api = _FakeSecure();
      final s = AndroidSecureStorage(api: api);
      final wrapped = await s.wrapKey([9, 8], requireBiometry: true);
      expect(api.lastRequire, isTrue);
      expect(await s.unwrapKey(wrapped, reason: 'Open the vault'), [9, 8]);
      expect(api.lastReason, 'Open the vault');
    },
  );

  test('PRIV-008 biometric kinds map one to one', () async {
    expect(
      await AndroidBiometrics(api: _FakeBio()).available(),
      BiometricKind.face,
    );
    expect(
      BiometricKindMsg.values.map((k) => k.name),
      BiometricKind.values.map((k) => k.name),
    );
  });
}
