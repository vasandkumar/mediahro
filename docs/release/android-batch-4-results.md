# Android device batch 4: results

Ran on the Samsung SM-M176B (Android 16) from main `7facf62` on 2026-10-22, 00:36 to 00:52 IST. Store debug flavour, appId `com.mediahro.app`. Run list: 8 app integration test files and 2 engine example runs (10 runs plus the install probe). Logs are in `K:\Projects\batch4-logs\` (outside the repo; `driver.sh` is the run list, `driver.out` the summary, `keepalive.log` the keyguard samples). The runner is set up as in "Batch runner notes" in `android-batch-1-checks.md`. The phone stayed unlocked; the keepalive saw the keyguard once (00:42:18) and woke the screen again.

This was an early run (owner present, phone unlocked): the only new feature on main was PRIV-007 vault video and music (#104), and the rest were the batch 3 re-runs. #108 (IMG-017), #106, #110, #111 and #112 were not merged at `7facf62`, so nothing from them ran.

## Passed

| Test | Result | IDs / area |
|---|---|---|
| c4a_android_tls_test | 6/6 | NET-004 TLS facades (5), NET-017 mutual TLS "paired peers connect, unpaired ones are refused"; no hang this time (72 s) |
| c4a_android_sftp_test | 7/7 | NET-004 SFTP facade (the sshj slf4j fix works on the phone) |
| c4a_android_enterprise_test | 5/5 | B2B-001 (3), B2B-002 kiosk supported/inactive and start on boot in the store build; no teardown hang |
| c3_compare_test | 4/4 | IMG-008, IMG-013, IMG-014 with the KStringsScope wrapper |
| c3_vault_test | 7/7 | IMG-011 (5: two vaults with a PIN each, Change PIN, nothing readable on disk, locking releases the handle, reset deletes the key) and PRIV-007 (2: video and song play from the vault and cannot be saved out; a detached fd is read in pieces on a worker isolate) |
| engine_test PRIV-007 | 2/2 | a sensitive source is never extracted, exported or captured; no converted subtitle copy on disk |

## Failed

| Test | Failure | Owner |
|---|---|---|
| c4a_android_input_test | 3/4. SYS-008 passes. SYS-009 "stick, trigger and hat events arrive with dead zone": the trigger axis now reads (the line-91 null is fixed), but `c4a_android_input_test.dart:98` fails with `Expected: empty  Actual: [Instance of 'GamepadAxisEvent', Instance of 'GamepadAxisEvent']`. After `seen.clear()`, sending the same X=1.0 again produced two events instead of none, so repeat suppression does not hold. | C4a |
| c2_tag_edit_test | 0/1. MUS-003, unchanged from batch 3: `Expected: empty  Actual: WhereIterable<String>:['/data/user/0/com.mediahro.app/code_cache/c2te_mediaZRVSZR/a.mp3', .../b.flac, .../c.ogg ...]`. The leftover filter still matches the package path `com.mediahro.app` and the test's own `code_cache` files. No C2 fix was merged for this. | C2 |
| c2_radio_scrobble_test | 1/2. MUS-009 passes. MUS-014 "a station streams over HTTP in live mode; skip keeps the station": `Expected: PlaybackStatus:<PlaybackStatus.paused>  Actual: PlaybackStatus:<PlaybackStatus.playing>` at `c2_radio_scrobble_test.dart:115` (pause on a live station keeps playing). Unchanged from batch 3; no C2 fix was merged. | C2 |
| engine_test AUD-043 | 8 pass, 7 fail (183 s, run to the end). Passing: DSD plays as PCM with the low-pass, DoP needs an exclusive output / a device listed as taking it / a 24-bit output / a named device, a DSD item is not joined gaplessly, and "on a phone the OS must grant the bit-perfect path (granted: false)". Failing: "native DSD plays as DoP, bit-exact under volume and speed" (`TimeoutException: waiting for DoP output path; last: PlaybackState(status: ended, position: 1.99 s, rate: 1.5 ...)`), "a DoP item is pinned to its device and falls back to null", "mpv losing the pinned device on its own leads to PCM", the three "DoP is re-checked while playing" cases, and "the OS moving the route off the DAC mid-DoP leads to PCM" (`TimeoutException: waiting for DoP opened and verified, paused; last: PlaybackState(status: paused, position: 0:00:00 ...)`). The keyguard blip (00:42:18) came after the first failure at 00:19, so it does not explain them. The phone has no DAC, so DoP never opens; the cases that need a DoP output belong on a device with one or need a phone-aware skip. | B1 |

## Ticked in STATUS.md

- **NET-004** (FTP/FTPS/SFTP): c4a_android_tls_test NET-004 5/5 and c4a_android_sftp_test 7/7 on the phone; FTP/FTPS/vsftpd covered by the network env in earlier merges; no hand check listed.
- **NET-017** (Mediahro-to-Mediahro): c4a_android_tls_test mutual TLS case passes (6/6); no hand check listed.

## Not ticked, and why

- IMG-008, IMG-013, IMG-014 (c3_compare_test 4/4): the hand checks stay (items 8 and 13 below).
- IMG-011 (c3_vault_test 7/7 and c4a_android_vault_test 8/8 in batch 3): the fingerprint-only prompt, key invalidation and decoy PIN hand checks are outstanding.
- PRIV-007: engine 2/2 and the vault test 2/2, but the hand check "vault video plays and stops when backgrounded" is outstanding.
- SYS-008, SYS-009: same file as the failing SYS-009 test; SYS-009 also needs a real controller.
- B2B-001, B2B-002: tests pass (5/5), but the kiosk `enter()` check and the MDM test tenant are hand checks.
- MUS-003, MUS-014, MUS-009 (same file as MUS-014), AUD-043: failing tests above.

## Hand checks still to do (batch 5)

The 21 from batch 3 (full text in `android-batch-3-results.md`) carry over unchanged, numbered the same way, plus one new check:

1. MUS-013 cold car connect (#71): needs Android Auto DHU or a car.
2. VID-038 film-grain preset (#60) and the bundled shaders (#58).
3. SUB-014 system captions (#46, #47) and SUB-030 editor (#42).
4. CORE-003, SYS-003, SYS-004 intents (#65): B3 wiring first.
5. SUB-051 and SUB-053 native text services (#57).
6. VID-040 and VID-041 UI (#66) and VID-037 crop (ADR-033).
7. IMG-007 Places tab and location chooser (#73, #86, ADR-041).
8. IMG-008 compare (#76), including the un-reject fix (#84).
9. IMG-009 (#79): Replace original on an SD-card or SAF folder; share and batch strip metadata.
10. ImagingFacade (#72): wallpaper, print, HeifWriter EXIF, Ultra HDR keepHdr.
11. SYS-009 with a real controller, once C1 uses the facade.
12. IMG-010, IMG-015, IMG-002 (#81).
13. IMG-014 recently deleted bin and IMG-013 duplicate finder (#84).
14. B2B-002 kiosk `enter()` and pin prompt; B2B-001 MDM tenant.
15. SUP-002 real payment on the Play internal-testing track.
16. IMG-011 vault (#88, #93, #99): fingerprint-only prompt, `cancelled`, `keyInvalidated`, decoy PIN.
17. IMG-001 motion (#98): yaw, pitch and landscape.
18. IMG-001 formats (#90, #91): SVG, Motion Photo, Live Photo, TIFF, panorama.
19. IMG-001 360 viewer (#96, #103).
20. IMG-012 slideshow (#92).
21. AUD-043 real DAC (STATUS section 4 owner row).
22. **New:** PRIV-007 (#104): a video and a song in the vault play, and stop when the app goes to the background or the screen turns off.

Failures and hand checks are carried into batch 5 in STATUS.md section 1.
