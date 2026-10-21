# PR #88 security review (Opus, orchestrator decisions), 2026-10-21

**Verdict: fix, then merge.** The design is sound: the master secret never reaches Dart and is never stored in plaintext; AES-GCM is used correctly; there are no new dependencies or exports.

## Must fix (blocks merge)
- **H1. close() races seal/open/newFileKey.** It can encrypt with an all-zero key, wrap under a zero master, or re-cache keys after lock (VaultCryptoModule.kt 120-156, 175-192; VaultCipher.kt:33).
  - Keep one state object per handle (master, cache, closed flag, ReentrantReadWriteLock or Mutex).
  - Operations take the read lock, check !closed, copy the key, and zero the copy in finally.
  - close takes the write lock, sets closed, then zeroes.
  - dataKey checks the handle.
  - VaultCipher.requireShape rejects an all-zero key.
  - Add a JVM test with concurrent seals plus close.

## Fix in the same pass (orchestrator decisions)
- **M1 (decided): use a fingerprint-only key for the vault** (AUTH_BIOMETRIC_STRONG only, setInvalidatedByBiometricEnrollment(true)). The PIN path is ADR-040's PIN-derived key wrapped by a device key. The reason: with device credential also allowed, API 30+ ignores biometric-enrolment invalidation. Use a separate vault RSA alias; don't change BiometricAuth's existing key. Check on the Samsung via the device test.
- **M2.** Guard first-time master creation with a Mutex and re-check the stored secret inside it.
- **M3.** Never silently create a new master or RSA alias:
  - If the blob exists but the alias is missing, throw keyLost.
  - After keyInvalidated, don't auto-delete and recreate on the next open.
  - Add an explicit `Future<void> reset()` to VaultCryptoFacade (ADR-039 amendment 1, authorised below). It deletes the vault alias and blob after the UI's explicit confirmation.
  - C3 stores a wrapped canary key at set-up.
- **M4.** Cache one SecretKeySpec per open key. Zeroing is best effort and recorded in the ADR-039 amendment.
- **L1.** Catch IllegalArgumentException → keyLost. Map only AEADBadTagException → integrityFailure; other GeneralSecurityException → unavailable.
- **L2.** Add an LRU limit of 64 to the key cache, zeroing evicted keys (after H1).
- **L3.** Native dispose on engine teardown (onEngineWillDestroy) from VaultModules.
- **L4.** Check KeyInfo.isInsideSecureHardware and report it. Use setUnlockedDeviceRequired(true) on the vault alias. Use a SHA-256-only digest for the new vault RSA key (StrongBox).
- **L5.** Include the wrapped-key header (version, mode) in the wrap AAD.
- **L6.** keystore.delete goes off the main thread.
- **Tests:** H1 concurrency, M2 create race, a strict error code on a closed handle, and an AES-GCM known-answer vector.
