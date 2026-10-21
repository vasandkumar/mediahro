import 'dart:typed_data';

import 'package:meta/meta.dart';

/// OS-backed crypto for the photo vault (IMG-011, ADR-039, ADR-008).
///
/// All AEAD work and all key handling happen natively, off the UI thread:
/// Android `javax.crypto` + Keystore (StrongBox where present), Apple
/// CryptoKit + Keychain / Secure Enclave, Windows CNG BCrypt + DPAPI-NG / TPM.
/// This keeps the export-compliance answer in docs/07 row 12 true (OS crypto
/// APIs only) and keeps the UI isolate free.
///
/// Dart owns the file *framing* only: it picks a nonce for each chunk and
/// builds the associated data (file id, chunk index, last-chunk flag and
/// lengths) so that truncation, reordering and cross-file splicing fail
/// authentication. The facade never invents nonces or framing.
///
/// The master key is never returned to Dart where the platform allows
/// non-exportable keys. Where it does not, it is wrapped by a non-exportable
/// key and zeroed after use. A [VaultKeyHandle] is an opaque reference that
/// must be released with [VaultCryptoFacade.close].
///
/// There is deliberately no pure-Dart fallback: the provider throws
/// `PlatformCapabilityUnavailable('vaultCrypto')` until a platform
/// implementation is registered, so the vault can never run on fake crypto.
abstract interface class VaultCryptoFacade {
  /// AES-256-GCM nonce length in bytes.
  static const int nonceLength = 12;

  /// AES-256-GCM tag length in bytes, appended to each sealed chunk.
  static const int tagLength = 16;

  /// Opens (creating on first use) the master key held by the OS keystore and
  /// returns an opaque handle. With [requireBiometry] the key needs a fresh
  /// biometric or device-credential authentication to use.
  ///
  /// With [secret] (a PIN-derived key, ADR-040) the handle's wrapping key is
  /// derived from the OS master key **and** the secret with HKDF-SHA-256
  /// (RFC 5869, no salt, info `mediahro-vault-v1`), so file keys wrapped under
  /// that handle cannot be opened without the same secret, nor by a handle
  /// opened with another secret or none (those fail with
  /// [VaultCryptoError.keyLost]). The native side zeroes its copy after use;
  /// the caller zeroes its own. Without a secret nothing changes. A [secret]
  /// must not be empty.
  ///
  /// Throws [VaultCryptoException] with [VaultCryptoError.cancelled],
  /// [VaultCryptoError.notEnrolled], [VaultCryptoError.keyInvalidated],
  /// [VaultCryptoError.keyLost], [VaultCryptoError.lockedOut],
  /// [VaultCryptoError.authFailed] or [VaultCryptoError.unavailable].
  Future<VaultKeyHandle> openMasterKey({
    required bool requireBiometry,
    Uint8List? secret,
  });

  /// Generates a fresh random 256-bit per-file data key and returns it wrapped
  /// under the master key behind [master]. The caller stores [WrappedKey.bytes]
  /// next to the file.
  Future<WrappedKey> newFileKey(VaultKeyHandle master);

  /// Re-attaches wrapped key bytes read from disk to the master key behind
  /// [master], so [seal] and [open] can use them. Fails with
  /// [VaultCryptoError.keyLost] or [VaultCryptoError.keyInvalidated] when the
  /// master key cannot unwrap it.
  Future<WrappedKey> adoptFileKey(VaultKeyHandle master, Uint8List wrapped);

  /// Encrypts [plaintext] with AES-256-GCM under [key]. [nonce] must be
  /// [nonceLength] bytes and never reused with the same key. [aad] is
  /// authenticated but not encrypted. Returns ciphertext followed by the
  /// [tagLength]-byte tag.
  Future<Uint8List> seal(
    WrappedKey key,
    Uint8List nonce,
    Uint8List aad,
    Uint8List plaintext,
  );

  /// Decrypts and authenticates [sealed] (ciphertext plus tag) produced by
  /// [seal] with the same [nonce] and [aad]. Throws [VaultCryptoException]
  /// with [VaultCryptoError.integrityFailure] when authentication fails.
  Future<Uint8List> open(
    WrappedKey key,
    Uint8List nonce,
    Uint8List aad,
    Uint8List sealed,
  );

  /// Deletes the vault's OS key and everything stored beside it, after the
  /// user explicitly confirmed. Wrapped file keys made under the old master
  /// key can never be opened again. Nothing re-creates a master key
  /// silently: after [VaultCryptoError.keyLost] or
  /// [VaultCryptoError.keyInvalidated] the UI must offer this reset
  /// (ADR-039 amendment 1). Open handles are closed.
  Future<void> reset();

  /// Releases [handle] and any native key material behind it. Safe to call
  /// more than once.
  Future<void> close(VaultKeyHandle handle);
}

/// Opaque reference to an open master key. Holds no key bytes.
@immutable
final class VaultKeyHandle {
  const VaultKeyHandle(this.id);

  /// Native-side identifier, meaningful only to the facade implementation.
  final int id;

  @override
  bool operator ==(Object other) => other is VaultKeyHandle && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'VaultKeyHandle($id)';
}

/// A per-file data key wrapped by the master key. [bytes] is safe to store on
/// disk (it is useless without the keystore key); [master] is the handle that
/// can unwrap it.
final class WrappedKey {
  const WrappedKey({required this.master, required this.bytes});

  final VaultKeyHandle master;
  final Uint8List bytes;
}

/// Why a vault crypto call failed. The UI maps each value to its own message
/// (docs/06 §8).
enum VaultCryptoError {
  /// The user dismissed the biometric or device-credential prompt.
  cancelled,

  /// No biometric or screen lock is enrolled, so a key that requires one
  /// cannot be used.
  notEnrolled,

  /// The OS invalidated the key (for example biometrics changed or the screen
  /// lock was removed). Existing wrapped keys can no longer be opened.
  keyInvalidated,

  /// The key is gone (app data restored on another device, keystore reset).
  keyLost,

  /// Too many failed attempts; the OS asks the user to wait or use the device
  /// credential.
  lockedOut,

  /// Authentication ran and was rejected.
  authFailed,

  /// No hardware-backed or OS crypto is available here, or a native call
  /// failed for another reason.
  unavailable,

  /// AEAD authentication failed: the data, nonce or associated data was
  /// altered or does not belong together.
  integrityFailure,
}

/// Thrown by [VaultCryptoFacade] implementations.
final class VaultCryptoException implements Exception {
  const VaultCryptoException(this.error, [this.message]);

  final VaultCryptoError error;

  /// Optional native detail for logs only; never shown to the user.
  final String? message;

  @override
  String toString() =>
      'VaultCryptoException(${error.name}'
      '${message == null ? '' : ': $message'})';
}
