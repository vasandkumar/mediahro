/// OS secure storage (PRIV-006): Keychain (I M), Keystore / StrongBox (A),
/// DPAPI / Credential Locker (W). Secrets never reach plain files or the
/// index database; the index stores only the key name.
abstract interface class SecureStorageFacade {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);

  /// Wraps a vault master key with the hardware-backed key (ADR-008).
  Future<List<int>> wrapKey(List<int> key, {required bool requireBiometry});
  Future<List<int>> unwrapKey(List<int> wrapped, {required String reason});
}

/// Biometric / device-credential gate for the vault, app lock and parental
/// PIN (IMG-011, PRIV-008, LIB-013).
abstract interface class BiometricsFacade {
  Future<BiometricKind> available();
  Future<bool> authenticate({required String reason});
}

enum BiometricKind { none, fingerprint, face, deviceCredential }
