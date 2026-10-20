// Pigeon messages for SecureStorageFacade and BiometricsFacade on Android
// (lane C4a, PRIV-006, PRIV-008, IMG-011, LIB-013, ADR-008).
//
//   dart run pigeon --input pigeons/android/security_api.dart   (from app/)
//
// Pigeon's schema is positional; named bool parameters do not map to Kotlin.
// ignore_for_file: avoid_positional_boolean_parameters

import 'package:pigeon/pigeon.dart';

@ConfigurePigeon(
  PigeonOptions(
    dartOut: 'lib/platform/android/gen/security_api.pigeon.dart',
    kotlinOut: 'android/app/src/main/kotlin/com/mediahro/mediahro/pigeon/SecurityApi.g.kt',
    kotlinOptions: KotlinOptions(
      // Shares FlutterError with StorageApi.g.kt.
      package: 'com.mediahro.mediahro.pigeon',
      includeErrorClass: false,
    ),
    dartPackageName: 'mediahro',
  ),
)
enum BiometricKindMsg { none, fingerprint, face, deviceCredential }

@HostApi()
abstract class SecureStorageHostApi {
  @async
  String? read(String key);

  @async
  void write(String key, String value);

  @async
  void delete(String key);

  @async
  Uint8List wrapKey(Uint8List key, bool requireBiometry);

  /// [reason] titles the system prompt when the wrapped key needs the user.
  @async
  Uint8List unwrapKey(Uint8List wrapped, String reason);
}

@HostApi()
abstract class BiometricsHostApi {
  BiometricKindMsg available();

  @async
  bool authenticate(String reason);
}
