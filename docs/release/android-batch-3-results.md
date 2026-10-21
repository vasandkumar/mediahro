# Android device batch 3: results

Ran on the Samsung SM-M176B (Android 16) from main `311b583` on 2026-10-21, 22:10 to 22:52 IST. Store debug flavour, appId `com.mediahro.app`. Run list: 18 app integration test files and 10 engine example runs (28 runs). Logs are in `K:\Projects\batch3-logs\` (outside the repo; `plan.txt` is the run list, `driver.out` the summary). How the runner is set up: see "Batch runner notes" in `android-batch-1-checks.md`. The phone's keyguard returned during the last engine run (see AUD-043 below).

## Passed

| Test | Result | IDs / area |
|---|---|---|
| c4a_android_hdr_video_test | 2/2 | VID-031 `ready` retry (#83), HdrWindowMode (#85); the native view is still not wired into the player |
| c4a_android_purchases_test | 4/4 | SUP-002 Play Billing bindings (#74) |
| c4a_android_vault_test | 8/8 | IMG-011 native half (#88, #93): Keystore master key, tamper, wrong AAD, `FLAG_SECURE` |
| c4a_android_motion_test | 4/4 | MotionFacade (#98), IMG-001 |
| c4a_android_imaging_test | 10/10 | ImagingFacade (ADR-037), HDR ref count (#85) |
| c4a_android_storage_test | 14/14 | Motion Photo served in place through `MotionVideoProvider` (#109) |
| c3_edit_test | 3/3 | IMG-009; preview render at 1080 px is 158 ms against the 400 ms budget (was 655 ms); 12 MP edit and JPEG encode 3579 ms |
| c3_places_test | 2/2 | IMG-007 gazetteer and location chooser |
| c3_pano_test | 2/2 | IMG-001 360 viewer, real shader |
| c3_formats_test | 3/3 | IMG-001 SVG, clips, pages |
| engine_test ADR-032 | 5/5 | `decodeAudio` on Android 16 (SUB-050, SUB-052, MUS-010 engine halves) |
| engine_test AUD-046 | 3/3 | the audio tap analyses the playing audio, costs nothing unlistened, network sources |
| engine_test VID-041 | 3/3 | SBS/TAB 3D, anaglyph, 360 yaw and pitch (engine half) |
| engine_test "ADR-031 image" | 7/7 | PGS, VobSub, DVB bitmaps (SUB-051 engine half) |
| engine_test PRIV-007 | 2/2 | a sensitive source is never extracted, exported or captured; no converted subtitle copy on disk |
| engine_test VID-002 | 22/22 | includes `mkv_vvc.mkv`, `mp4_vvc.mp4` and `mov_hap.mov`; no VC-1 sample exists |
| engine_test VID-033 | 2/2 | Dolby Vision 8.1 `dv_p81.mp4` and `.mkv`; no 8.4 sample exists |
| engine_test VID-032 | 4/4 | HDR10+ `hdr10p.mp4` and `.mkv`, plus the two DV 8.1 files |
| engine_test AUD-001 | 24 pass, 1 skipped | APE and MPC decode; `midi_scale.mid` is skipped pending a synthesiser in mediahro-deps |

AUD-001 stays unticked: the MIDI decode case (`midi_scale.mid`) is the skipped one, and TAK and SACD ISO have no samples (STATUS section 3).

## Failed

| Test | Failure | Owner |
|---|---|---|
| c4a_android_tls_test | NET-017 mutual TLS "paired peers connect, unpaired ones are refused" hangs: `04:10 +5: ... did not complete [E]` after the 5 minute cap, then `tearDownAll` did not complete. The five NET-004 TLS facade tests pass (+5). | C4a |
| c4a_android_sftp_test | 1/7. Every connect fails with `PlatformException(NullPointerException ... Attempt to invoke interface method 'org.slf4j.Logger net.schmizz.sshj.common.LoggerFactory.getLogger(java.lang.Class)' on a null object reference` at `SSHClient.<init>(SSHClient.java:145)` from `SftpModule.connect (SftpModule.kt:66)`. A product bug: sshj has no slf4j binding on the phone. The test-server fix from #83 works (first test passes). | C4a |
| c4a_android_input_test | 3/4. SYS-008 audio description preference passes. SYS-009 "stick, trigger and hat events arrive with dead zone": `Null check operator used on a null value` at `c4a_android_input_test.dart:91:39` (the trigger axis reading is null). | C4a |
| c4a_android_enterprise_test | 4/5 plus a teardown hang. B2B-001 (3 tests) and B2B-002 kiosk supported and inactive pass. B2B-002 "start on boot works only in the enterprise build": `UnsupportedError: Starting after boot is only in the enterprise build` from `AndroidKiosk.setStartOnBoot (android_enterprise.dart:78)`, thrown after the test had completed; the store build is the one under test, so the test expectation or the guard is wrong. The file ran 473 s and was cut by the idle watchdog (`tearDownAll` did not complete). | C4a |
| c2_tag_edit_test | 0/1. MUS-003: `Expected: empty, Actual: WhereIterable<String>:[ '/data/user/0/com.mediahro.app/code_cache/c2te_mediaGYISQM/a.mp3', ... b.flac, c.ogg, d.opus, e.m4a, f.wma, g.wav, h.aiff, i.ape ]`. The leftover filter still matches the package path `com.mediahro.app` (and the test's own files under `code_cache`). Test bug. | C2 |
| c2_radio_scrobble_test | 1/2. MUS-009 passes (listens survive a restart and go out once the service is reachable). MUS-014 "a station streams over HTTP in live mode; skip keeps the station": `Expected: PlaybackStatus.paused, Actual: PlaybackStatus.playing` at `c2_radio_scrobble_test.dart:115` (pause on a live station keeps playing). | C2 |
| c3_compare_test | 0/4. Harness: `No KStringsScope found. The app installs one in MediahroApp; tests use package:mediahro_design/testing.dart.` while building `KCompareView`; the first test then finds 0 `RawImage` widgets. The test needs the strings scope wrapper. | C3 |
| c3_vault_test | 2/5. Product bug: `Unsupported operation: Cannot modify an unmodifiable list` (`_UnmodifiableUint8ArrayView.[]=`) at `OpenVault.close (vault_manager.dart:93)` and `VaultManager._changePin (vault_manager.dart:1105)`: the secret is wiped with `fillRange` on a view that cannot be written. Fails "two vaults, a PIN each", "Change PIN" and "locking releases the keystore handle and a tampered file fails". "nothing readable is on disk" and "reset deletes the Keystore key" pass. | C3 |
| engine_test AUD-043 | 6 pass, 1 fail, 8 not completed. "native DSD plays as DoP, bit-exact under volume and speed": `TimeoutException: waiting for DoP output path; last: PlaybackState(status: ended ...)`. The phone's keyguard returned mid-run (`keepalive.log` ends with `kg=1`), so the 8 later cases did not complete. Re-run on an unlocked phone before assigning. | B1 |

## Ticked in STATUS.md

AUD-046 (engine_test AUD-046 3/3 here, C2 side merged with unit and widget tests, no hand check listed), SUB-050 (engine_test ADR-032 5/5 here plus c1_video_player_test 33/33 in batch 2), VID-032 (engine_test VID-032 4/4 on HDR10+ in MP4 and MKV; the "no samples" blocker is resolved by #101).

## Not ticked, and why

- SUB-052, MUS-010: only the ADR-032 engine half has device evidence (5/5); the C1 auto-captions and C2 fingerprinting sides are not built yet.
- VID-002: the sample blocker is only partly resolved. VVC and HAP now decode; VC-1 still has no sample.
- VID-033: only profile 8.1 has a sample (2/2); 8.4 has none; "profile reported in the info panel" has no device check.
- VID-041: the engine half passes 3/3, but the row lists VID-040/041 among the hand checks and no UI check has run.
- AUD-001: TAK, SACD ISO and MIDI synthesis still have no samples.
- PRIV-007: the engine half passes 2/2; the vault video and music viewers (#104) are not merged.
- VID-031: the native HDR view tests pass 2/2, but the view is not wired into the player and the 8-bit texture blocker stands.
- B2B-001, B2B-002: B2B-002 start on boot fails and the file hangs; the managed values need the MDM test tenant.
- SYS-008, SYS-009: same file as the failing trigger axis test.
- SUP-002, IMG-007, IMG-009, IMG-011, IMG-001, IMG-008: hand checks outstanding or the matching test fails.
- NET-017, NET-004 SFTP, MUS-003, MUS-014, MUS-009 (same file as the MUS-014 failure): failing tests above.

## Hand checks still to do (batch 4)

1. MUS-013 cold car connect (#71): needs Android Auto DHU or a car.
2. VID-038 film-grain preset (#60) and the bundled shaders (#58): Picture, Shaders.
3. SUB-014 system captions (#46, #47) and SUB-030 editor (#42).
4. CORE-003, SYS-003, SYS-004 intents (#65: open-with, share targets, shortcuts). Nothing listens to `openRequests` yet; B3 wiring is needed first.
5. SUB-051 and SUB-053 native text services (#57): CLD3 and Bergamot builds are now in deps v2026.10.5-android.1, so drop the skips and try them.
6. VID-040 and VID-041 UI (#66; lutrgb, blend, v360 now pinned) and VID-037 crop (ADR-033).
7. IMG-007 (#73, #86, ADR-041): the Places tab and the location chooser; search a city or type coordinates.
8. IMG-008 compare (#76), including the un-reject fix (#84).
9. IMG-009 (#79): edit a photo on an SD-card or SAF folder with Replace original; check that share and batch strip PNG text and JPEG comments.
10. ImagingFacade (#72): wallpaper, print, HeifWriter EXIF, Ultra HDR keepHdr on a real gain-map JPEG.
11. SYS-009 with a real controller, once C1 uses the facade.
12. IMG-010 batch rename, convert and strip from the selection bar; IMG-015 share at 1280 px with strip (the receiver must see no GPS), wallpaper, print, copy; IMG-002 HDR photo (open an Ultra HDR photo, HDR button, pinch to zoom) (#81).
13. IMG-014 recently deleted bin (delete a photo, find it in Albums > Recently deleted, Undo, restore) and IMG-013 duplicate finder (Albums > Duplicates on a library with copies, delete the rest through the bin) (#84).
14. B2B-002 kiosk: enter kiosk and accept the pin prompt (the test does not run `enter()`); B2B-001 real restrictions need the MDM test tenant.
15. SUP-002 real payment: Play internal-testing track and the owner's Play Console products.
16. IMG-011 vault (#88, #93, #99): `requireBiometry: true` shows a fingerprint-only prompt (no PIN or pattern button), one prompt per open, Cancel gives `cancelled`; after enrolling a new fingerprint open gives `keyInvalidated`; the decoy PIN opens the decoy vault.
17. IMG-001 motion (#98): with the test app turn the phone right and yaw increases; tilt up and pitch increases; rotate to landscape and the aim stays on the camera axis (the sign for ROTATION_90/270 is unverified).
18. IMG-001 formats (#90, #91): open an SVG logo (zoom stays sharp, check its grid thumbnail); open a Motion Photo from the camera app and press play (the clip plays over the photo and ends by itself); an iPhone Live Photo pair copied to a folder; a multi-page TIFF shows Page n of m with working previous and next; a camera panorama opens full height and pans.
19. IMG-001 360 viewer (#96, #103): open a Photo Sphere or an equirectangular JPEG, press Look around in 360, drag, flick, pinch, check the buttons and TalkBack actions; with Remove animations on, a flick does not coast; turn the phone and the view follows (with Remove animations on, following starts off).
20. IMG-012 slideshow (#92), including reduced motion and the viewer Slideshow button; external display needs C4a's ADR-044 Android implementation.
21. AUD-043 real DAC (STATUS section 4 owner row).

All failures and hand checks are carried into batch 4 in STATUS.md section 1.
