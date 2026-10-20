# PR #82 vault security review (orchestrator, 2026-10-21)

**Verdict: blocked.** Split the bin (IMG-014), the duplicates (IMG-013) and the IMG-008 un-reject fix into their own PR: they have no blocking findings and can merge now. The vault stays in #82 until the items below are fixed. ADR-039 (VaultCryptoFacade + SecureWindowFacade) and ADR-040 (decoy design) are being added to docs/05 §12. Build the vault against them.

## Must fix before merge
- **H1. Moving a photo in can destroy it.** vault_mover.dart:80-110: if forgetThumbnails or the DB update throws after io.delete(origin), the catch block calls store.remove, and both copies are gone. Set an originalDeleted flag after the delete and roll back only while it is false. Post-delete cleanup goes in its own try, which must never remove the vault copy. Add a test with a failing pipeline or DB fake.
- **H2. Vaulted photos' details stay readable in the library database.** vault_mover only sets missing=true, so the item row (name, relPath, size, mtime), image_meta (GPS, camera, phash), tags, ratings, people, albums and the item_fts entry all survive. The library DB is in Auto Backup. In one transaction, delete the item and every dependent row including FTS, or set vault=1 and blank the identifying columns. Copy tags and rating into the encrypted VaultItem so Take out can restore them. Use PRAGMA secure_delete=ON as a best effort. Add a test.
- **H3. The decoy can be detected.** Implement ADR-040:
  - one PIN pad for both vaults, with fingerprint as an option the user can turn off;
  - PIN A opens the real vault, PIN B the decoy;
  - an identical UI and menu in both, and moving items never prompts for the other vault;
  - random folder names, with both containers created at set-up;
  - honest help and ARB text (photosVaultDecoyBody, docs/help/photos-vault.md).
- **H4. The crypto library.** docs/07 row 12 requires OS crypto APIs. Move AES-GCM and key wrapping onto the VaultCryptoFacade from ADR-039 (C4a builds Android). Remove package:cryptography from the vault code.

## Before IMG-011 is ticked
- **M1.** Call SecureWindowFacade.setSecure(true) while the vault is open (ADR-039).
- **M2.** Lock must popUntil the vault route before disposing images; the viewer must not survive a lock.
- **M3.** The PIN-derived key also gets wrapped by a non-exportable keystore key. Use Argon2id (or PBKDF2 ≥ 600k) in an isolate, with exponential back-off persisted in secure storage.
- **M4.** Map the unwrap errors (keyInvalidated, keyLost, lockedOut and so on). Offer "Reset vault" with explicit confirmation, and don't auto-create the auth key on unwrap. The help must say that adding a fingerprint invalidates the vault key.
- **M5.** Catch notEnrolled and the other set-up errors in _unlock and moveToVaultFlow, and show actionable copy.
- **M6.** No crypto on the UI isolate. Use the facade, and store an encrypted thumbnail per item.
- **M7.** fsync encrypted files, then verify by decrypting the last chunk, before deleting the original. Fix the same issue in AppTrash._copyIn.
- **M8.** Exclude photo-trash/ from Auto Backup and device transfer, or move it under noBackupFilesDir. vaultRootProvider must fail closed instead of falling back to a backed-up folder.

## Low
- **L1.** Deletion wording: deletion is best effort on flash, and copies in cloud backups or other apps are not affected.
- **L2.** Picker adds: tell the user that originals stay in place, and that files over 64 MiB are skipped. Guard _add/_takeOut against a lock that happens mid-operation.
- **L3.** Zero or destroy key bytes on lock.
- **L4.** Size-bucket padding is optional.
- **L5.** Serialise _FileSource.read.
- **L6.** Take out is not an export; it's recorded in ADR-039/040 context.
- **L7.** Offer to remove exact duplicates on move-in.
- **L9.** Bin purge leaves missing=true rows; use the H2 remedy.
- PRIV-007 (video/audio) stays open.
