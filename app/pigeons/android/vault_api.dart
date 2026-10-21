// Pigeon messages for VaultCryptoFacade and SecureWindowFacade on Android
// (lane C4a, IMG-011, ADR-039).
//
//   dart run pigeon --input pigeons/android/vault_api.dart   (from app/)
//
// Pigeon's schema is positional; named bool parameters do not map to Kotlin.
// ignore_for_file: avoid_positional_boolean_parameters

import 'package:pigeon/pigeon.dart';

@ConfigurePigeon(
  PigeonOptions(
    dartOut: 'lib/platform/android/gen/vault_api.pigeon.dart',
    kotlinOut: 'android/app/src/main/kotlin/com/mediahro/mediahro/pigeon/VaultApi.g.kt',
    kotlinOptions: KotlinOptions(
      // Shares FlutterError and the event-channel classes of StorageApi.g.kt.
      package: 'com.mediahro.mediahro.pigeon',
      includeErrorClass: false,
    ),
    dartPackageName: 'mediahro',
  ),
)
/// Failures are `PlatformException`s whose code is a `VaultCryptoError` name:
/// cancelled, notEnrolled, keyInvalidated, keyLost, lockedOut, authFailed,
/// unavailable, integrityFailure.
@HostApi()
abstract class VaultCryptoHostApi {
  /// Opens (creating on first use) the master key; returns a handle id.
  @async
  int openMasterKey(bool requireBiometry);

  /// A fresh per-file key, wrapped under the master key.
  @async
  Uint8List newFileKey(int handle);

  /// Checks that the master key can unwrap [wrapped] and caches the key.
  @async
  void adoptFileKey(int handle, Uint8List wrapped);

  /// AES-256-GCM: ciphertext followed by the 16-byte tag.
  @async
  Uint8List seal(
    int handle,
    Uint8List wrapped,
    Uint8List nonce,
    Uint8List aad,
    Uint8List plaintext,
  );

  @async
  Uint8List open(
    int handle,
    Uint8List wrapped,
    Uint8List nonce,
    Uint8List aad,
    Uint8List sealed,
  );

  @async
  void close(int handle);
}

@HostApi()
abstract class SecureWindowHostApi {
  /// FLAG_SECURE on the app's windows, kept across activity re-creation.
  void setSecure(bool secure);
}

@EventChannelApi(
  kotlinOptions: KotlinEventChannelOptions(includeSharedClasses: false),
)
abstract class SecureWindowEventsApi {
  /// Screen recording of the app's windows started or stopped (Android 15+).
  bool captureStates();
}
