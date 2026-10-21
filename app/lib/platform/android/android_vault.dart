import 'package:flutter/services.dart';
import 'package:mediahro/platform/android/gen/vault_api.pigeon.dart';
import 'package:mediahro/platform/secure_window.dart';
import 'package:mediahro/platform/vault_crypto.dart';

/// [VaultCryptoFacade] on Android (IMG-011, ADR-039): AES-256-GCM through
/// `javax.crypto` off the main thread, the master key in the Android
/// Keystore (StrongBox where present). With biometry the master secret is
/// released only after one BiometricPrompt with a CryptoObject and is zeroed
/// on [close]. Failures arrive as a [VaultCryptoException] (`VaultModules`).
final class AndroidVaultCrypto implements VaultCryptoFacade {
  AndroidVaultCrypto({VaultCryptoHostApi? api})
    : _api = api ?? VaultCryptoHostApi();

  final VaultCryptoHostApi _api;

  @override
  Future<VaultKeyHandle> openMasterKey({
    required bool requireBiometry,
    Uint8List? secret,
  }) => _call(
    () async =>
        VaultKeyHandle(await _api.openMasterKey(requireBiometry, secret)),
  );

  @override
  Future<WrappedKey> newFileKey(VaultKeyHandle master) => _call(
    () async =>
        WrappedKey(master: master, bytes: await _api.newFileKey(master.id)),
  );

  @override
  Future<WrappedKey> adoptFileKey(VaultKeyHandle master, Uint8List wrapped) =>
      _call(() async {
        await _api.adoptFileKey(master.id, wrapped);
        return WrappedKey(master: master, bytes: wrapped);
      });

  @override
  Future<Uint8List> seal(
    WrappedKey key,
    Uint8List nonce,
    Uint8List aad,
    Uint8List plaintext,
  ) => _call(() => _api.seal(key.master.id, key.bytes, nonce, aad, plaintext));

  @override
  Future<Uint8List> open(
    WrappedKey key,
    Uint8List nonce,
    Uint8List aad,
    Uint8List sealed,
  ) => _call(() => _api.open(key.master.id, key.bytes, nonce, aad, sealed));

  @override
  Future<void> close(VaultKeyHandle handle) =>
      _call(() => _api.close(handle.id));

  @override
  Future<void> reset() => _call(_api.reset);
}

Future<T> _call<T>(Future<T> Function() op) async {
  try {
    return await op();
  } on PlatformException catch (e) {
    final error = VaultCryptoError.values.asNameMap()[e.code];
    throw VaultCryptoException(
      error ?? VaultCryptoError.unavailable,
      e.message,
    );
  }
}

/// [SecureWindowFacade] on Android (IMG-011, ADR-039): `FLAG_SECURE` on the
/// app window, remembered across activity re-creation, and the screen
/// recording state on Android 15+ (`SecureWindowModule.kt`).
final class AndroidSecureWindow implements SecureWindowFacade {
  AndroidSecureWindow({
    SecureWindowHostApi? api,
    Stream<bool> Function()? events,
  }) : _api = api ?? SecureWindowHostApi(),
       _events = events ?? captureStates;

  final SecureWindowHostApi _api;
  final Stream<bool> Function() _events;

  @override
  Future<void> setSecure({required bool secure}) => _api.setSecure(secure);

  @override
  Stream<bool> get captureActive => _events();
}
