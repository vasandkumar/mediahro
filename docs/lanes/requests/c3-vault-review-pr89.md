# PR #89 vault security re-review (Opus), orchestrator decisions, 2026-10-21

**Verdict: blocked; small Dart fixes needed.** All of #82's H1–H4 and M1/M4–M8 are fixed. Paths are under app/lib/features/photos/vault/.

## Fix before merge (C3)
- **N-H1. A PIN-B holder can brute-force PIN A.** Any successful unlock clears the miss counter (vault_manager.dart:323, 391), and the miss is recorded only after the KDF (330). Count the miss BEFORE deriving and resolve it after. Never clear on success; decay misses over time, with the same rule for both vaults. Guard against wall-clock changes if cheap.
- **N-H2. Change PIN isn't crash-safe.** rekey seals the index under the new token before _writeSalt (474-491; container 474-488), and _token is updated before _saveIndex succeeds. Write salt.next and index.mv.next, then rename both; at open, also try the .next pair. Restore _token on failure. Catch the errors in the screen (vault_screen.dart:407).
- **N-M1. One damaged container blocks both and leads to Reset** (308-321, 335-341). Treat a per-container keyLost or integrityFailure as "not this one". Report keyLost only when openMasterKey fails or every container fails that way. Close any container that already opened. Offer Reset only after repeated keyLost.
- **N-M2. A lock racing add, remove or rekey can seal an index under a zeroed token** (close 491-496). Check _closed before every mutation and save, snapshot the token, and serialise operations against close().
- **N-M3. Changing the PIN to the other vault's PIN orphans that vault** (vault_screen.dart:611-619, found ??= at 316). Test the new PIN against the other container through the same back-off accounting.
- **Old M2. Pop before dispose** (vault_screen.dart:191-199; LRU 84-86). popUntil first and dispose after the route completes. Hand widgets image.clone() so each owner disposes its own.
- **N-M4. Text.** The vault key is fingerprint-only (ADR-039 amendment 1). Remove "or screen lock" (photos_en.arb:849, 850, 915; photos-vault.md:6, 11). Remove "keys never leave the hardware" and "PIN turned into a key" until amendment 2 lands. Add the coercion warning that the fingerprint opens the vault it was enabled in. After Change PIN, re-read the global fingerprint state instead of setting it false (vault_screen.dart:409).

## Cheap, do in the same PR
- **L1.** Use PinPad for set-up and Change PIN, or fix the "no keyboard learns it" help text.
- **L2.** Clamp KDF rounds read from the salt file to [600k, 10M].
- **L3.** Before rollback, check whether the origin still exists (vault_mover.dart:186, 201-209).
- **L5.** AAD binding: purpose plus item id for .tm, container name for index.mv.
- **L6.** Delete .part on failure; best-effort directory fsync; Move-to-vault keeps the secure window and locks on background (vault_flows.dart:146-155).
- **L7.** The integration-test tearDown must not reset the app's global vault keys. Use a test-only namespace or alias prefix, or skip the reset when a real vault exists.

## Follow-up before IMG-011 is ticked (needs C4a, ADR-039 amendment 2)
- **N-H3. The PIN isn't key material.** The token is only AAD, so root or app-level Keystore access opens the real vault without PIN A. Amendment 2 adds an optional `secret` to `openMasterKey`. The native side derives the session wrapping key as HKDF-SHA256(master, secret, info "mediahro-vault-v1"), so each vault opens its own handle with its PIN token. C3 then opens one handle per container with that container's token and re-wraps on PIN change.

## Later
- **L4.** FTS5 secure-delete or optimize, wal_checkpoint(TRUNCATE), orphan place and person rows.
- **L8.** Earlier L4 (padding) and L7 (duplicates offer).
