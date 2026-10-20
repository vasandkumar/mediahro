import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:mediahro/features/photos/vault/vault_crypto.dart';
import 'package:mediahro/features/photos/vault/vault_store.dart';
import 'package:mediahro/platform/security.dart';

/// What came of an attempt to open the vault.
enum VaultUnlock {
  opened,

  /// The user backed out of the biometric / screen-lock prompt.
  cancelled,

  /// No vault yet.
  needsSetup,

  /// The device has no screen lock or biometrics to protect it with.
  unavailable,

  /// The key could not be unwrapped (the lock method changed, the key store
  /// was reset): the vault cannot be opened.
  failed,

  wrongPin,
}

/// The vault's keys (IMG-011, ADR-008): a random master key wrapped by the
/// hardware-backed key and opened with the device's biometric / screen lock,
/// kept in a folder the OS never backs up. An optional decoy vault, off
/// until the user creates it, opens with a PIN instead and holds other
/// things.
final class VaultKeys {
  VaultKeys({
    required this.root,
    required this.secure,
    required this.biometrics,
    this.pinIterations = 120000,
  });

  /// The no-backup folder; the real vault is `real/`, the decoy `decoy/`.
  final Directory root;
  final SecureStorageFacade secure;
  final BiometricsFacade biometrics;
  final int pinIterations;

  Directory get realDirectory =>
      Directory('${root.path}${Platform.pathSeparator}real');

  Directory get decoyDirectory =>
      Directory('${root.path}${Platform.pathSeparator}decoy');

  File get _wrapped =>
      File('${realDirectory.path}${Platform.pathSeparator}master.key');

  File get _salt =>
      File('${decoyDirectory.path}${Platform.pathSeparator}pin.salt');

  /// Whether the device can protect a vault at all.
  Future<bool> available() async =>
      await biometrics.available() != BiometricKind.none;

  bool get exists => _wrapped.existsSync();

  bool get decoyExists => _salt.existsSync();

  /// Makes the vault: a new master key, wrapped, and an empty index.
  Future<VaultStore> create() async {
    final key = VaultCrypto.randomBytes(32);
    final wrapped = await secure.wrapKey(key, requireBiometry: true);
    await realDirectory.create(recursive: true);
    await _wrapped.writeAsBytes(wrapped, flush: true);
    final store = VaultStore(
      directory: realDirectory,
      crypto: VaultCrypto(key),
    );
    await store.open();
    return store;
  }

  /// Opens the vault after the device asks the user to prove who they are.
  Future<({VaultUnlock result, VaultStore? store})> unlock({
    required String reason,
  }) async {
    if (!exists) return (result: VaultUnlock.needsSetup, store: null);
    final Uint8List key;
    try {
      key = Uint8List.fromList(
        await secure.unwrapKey(await _wrapped.readAsBytes(), reason: reason),
      );
    } on Object {
      // A cancelled prompt and a lost key both end here; the screen tells
      // them apart by asking again.
      return (result: VaultUnlock.cancelled, store: null);
    }
    try {
      final store = VaultStore(
        directory: realDirectory,
        crypto: VaultCrypto(key),
      );
      await store.open();
      return (result: VaultUnlock.opened, store: store);
    } on VaultCorrupt {
      return (result: VaultUnlock.failed, store: null);
    }
  }

  Future<Uint8List> _pinKey(String pin, List<int> salt) async {
    final key = await Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: pinIterations,
      bits: 256,
    ).deriveKeyFromPassword(password: pin, nonce: salt);
    return Uint8List.fromList(await key.extractBytes());
  }

  /// Creates the decoy vault behind [pin].
  Future<VaultStore> createDecoy(String pin) async {
    final salt = VaultCrypto.randomBytes(16);
    await decoyDirectory.create(recursive: true);
    await _salt.writeAsBytes(salt, flush: true);
    final store = VaultStore(
      directory: decoyDirectory,
      crypto: VaultCrypto(await _pinKey(pin, salt)),
    );
    await store.open();
    return store;
  }

  /// Opens the decoy vault; [VaultUnlock.wrongPin] when [pin] is not its PIN.
  Future<({VaultUnlock result, VaultStore? store})> unlockDecoy(
    String pin,
  ) async {
    if (!decoyExists) return (result: VaultUnlock.needsSetup, store: null);
    final store = VaultStore(
      directory: decoyDirectory,
      crypto: VaultCrypto(await _pinKey(pin, await _salt.readAsBytes())),
    );
    try {
      await store.open();
      return (result: VaultUnlock.opened, store: store);
    } on VaultCorrupt {
      return (result: VaultUnlock.wrongPin, store: null);
    }
  }

  /// Removes the decoy vault and everything in it.
  Future<void> removeDecoy() async {
    if (decoyDirectory.existsSync()) decoyDirectory.deleteSync(recursive: true);
  }
}
