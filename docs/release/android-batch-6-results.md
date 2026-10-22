# Android device batch 6: results

Ran on the Samsung SM-M176B (Android 16) on 2026-10-22, 04:37 to 13:11 IST, store debug flavour, appId `com.mediahro.app`. Main moved from `edcf8a1` (first pass, 04:37 to 05:15 IST) to `ff51e88` (resume and re-runs, 12:43 to 13:06 IST; presentation re-run at 13:10 IST). Plan: `docs/release/android-batch-6-plan.md`. Logs are in `K:\Projects\batch6-logs\` (outside the repo; `driver*.out` are the summaries, `<name>.log` one per file). Where a file ran more than once, the latest run is the one recorded. The QA lane ticked nothing; the orchestrator edited STATUS from this report.

This batch also carries the batch 5 items (SYS-009, MUS-003, MUS-014, AUD-043 re-runs) and the files for everything merged since batch 4 (#108, #110, #111, #112, #121, #126 and others).

## Passed

| Test | Result | IDs / area |
|---|---|---|
| c4a_android_intents_test | 4/4 | CORE-003, SYS-003, SYS-004 (adb VIEW and SEND checks not run, see below) |
| b2_library_sources_test | 11/11, no skips (ff51e88). First run on edcf8a1: 9 pass, 2 self-skipped (trash restore, parental PIN) | LIB-001, LIB-002, LIB-005, LIB-007, LIB-013, FILE-001, FILE-002, FILE-006, CORE-014 |
| c4a_android_storage_test | 14/14 | LIB-002, FILE-002, SYS-007 |
| c4a_android_display_test | 6/6 | VID-067, VID-070 |
| c1_video_player_test | 33/33 | VID-060..070, SUB-012..016 UI, VID-037 and VID-038 UI |
| engine `SUB-01[0-6]` | 25/25 | SUB-010..016 |
| c4a_android_caption_style_test | 2/2 | SUB-014 |
| c4a_android_media_test | 8 pass, 1 skip (the notification prompt skips itself, benign) | AUD-045, AUD-044, SYS-001, SYS-002, SYS-006 |
| engine `AUD-04[45]` | 3/3 (ff51e88; the first attempt did not run, `flutter.bat` treats the regex alternation bar as a pipe) | AUD-045, AUD-044 engine side |
| c3_photos_test | 5/5 | IMG-001, IMG-003, IMG-004 |
| c3_formats_test | 3/3 | IMG-001 SVG, clips, pages |
| c3_pano_test | 2/2 | IMG-001 360 viewer |
| c4a_android_motion_test | 4/4 | IMG-001 motion |
| c4a_android_imaging_test | 10/10 | IMG-001, IMG-002, IMG-015 |
| c3_compare_test | 4/4 | IMG-008, IMG-013, IMG-014 |
| c4a_android_input_test | 4/4 | SYS-008, SYS-009 (batch 4 failure fixed) |
| c4a_android_security_test | 6/6 | PRIV-006 |
| b3_foundations_test | 9/9 on ff51e88 (first run on edcf8a1: 8 pass; CORE-001 last-mode restore failed, route `/video` not `/photos`) | CORE-001 restore, CORE-002, CORE-006, CORE-007, CORE-008, CORE-009, CORE-015 |
| app_smoke_test | 3/3 | regression |
| c4a_android_back_test | 1/1 | CORE-001 back behaviour |
| c4a_mode_switch_test | 1/1, debug build with `MEDIAHRO_ENFORCE_BUDGET`: p95 71.1 ms, p50 55.1 ms, n=20; first visits 490, 191 and 85 ms | CORE-001 speed |
| c2_tag_edit_test | 1/1 (batch 4 failure fixed) | MUS-003 |
| c2_radio_scrobble_test | 2/2 (batch 4 failure fixed) | MUS-014, MUS-009 |
| c2_books_test | 1/1 | POD-001 |
| c2_playlists_car_test | 2/2 | MUS-008, MUS-013 car tree |
| c4a_android_car_alarm_test | 4/4 | MUS-011, MUS-013 |
| c3_places_test | 2/2 | IMG-007 |
| c3_edit_test | 3/3 | IMG-009 |
| c4a_android_presentation_test | 4/4 on ff51e88 re-run. First run on edcf8a1: 2 pass, 1 fail ("display never showed the expected colour; last pixel (250,250,250)"), then 2 tests did not complete; the phone dropped off adb right after | IMG-012, CAST-004 |
| c3_remote_sources_test | 5/5 | IMG-016 |
| c4a_android_network_test | 6/6 | NET-005, NET-019 (NET-007 is removed, ADR-048) |
| c4a_android_purchases_test | 4/4 | SUP-002 Play Billing bindings |
| b2_native_libraries_test | 6/6, no skips on ff51e88 (edcf8a1: 1 pass, 5 skips because the archive, ebur128, chromaprint, smb2 and nfs libraries were missing) | FILE-004 library, LIB-014 libraries, NET-001 and NET-002 libraries, subtitle charset |
| c4a_android_background_test | 6/6 on ff51e88 (edcf8a1: 5 pass; the schedule-constraints test saw RUNNING, not ENQUEUED) | ADR-049 / POD-002 capability |
| c4a_android_text_test | 2/2 | SUB-040 |
| c2_podcasts_test | 1/1 | POD-002 |
| c3_vault_test | 7/7 | IMG-011, PRIV-007 |
| c4a_android_vault_test | 8/8 | IMG-011 native half |
| c4a_android_enterprise_test | 5/5 | B2B-001, B2B-002 |
| c4a_android_tls_test | 6/6 | NET-004, NET-017 |
| c4a_android_sftp_test | 7/7 | NET-004 SFTP |
| c4a_android_hdr_video_test | 2/2 | VID-031 regression |
| c4a_android_home_widgets_test | 3/3 | MUS-012 |
| b2_library_perf_test | 2/2 | LIB-003, LIB-005 |
| engine `ADR-031` | 12/12 | SUB-030, SUB-051, SUB-053, PRIV-007 engine side |
| engine `VID-037`, `VID-040`, `VID-041` | 1/1, 1/1, 3/3 | crop, colour management, 3D and 360 engine half |
| engine `PRIV-007` | 2/2 | PRIV-007 |

## Failed (open)

| Test | Failure | Owner |
|---|---|---|
| c3_archives_test | 1/3. "a CBZ opens in reading order through libarchive" (test line 114) and "an archive that arrives as a detached fd is read" (line 163) both throw `ArchiveBookException(ArchiveProblem.unreadable)` from `ArchiveBook.open` (`archive_book.dart:80`) via `FfiArchiveBooks.open` (`archive_book.dart:193`). "a file that is not an archive is refused" passes. libarchive itself works on the phone (b2_native_libraries_test FILE-004 passes), so the fault is in the book opener, not the library. IMG-017 stays unticked. | C4a (fix in progress) |
| engine AUD-043 | 14 pass, 1 fail. The 7 DoP cases that failed in batch 4 now pass (#119). The failing case is "on a phone the OS must grant the bit-perfect path (granted: true) [simulated OS answer, no DAC]": it fails in teardown with `FileSystemException: An async operation is currently pending, path = .../mediahro_corpus/dsd64.dsf` in `LocalVirtualFile.close` (`mp4_gapless.dart:275`) from `MpvEngine.dispose` (`mpv_engine.dart:1985`). A close races a pending read on dispose. AUD-043 stays unticked (the real-DAC hand check H64 is also open). | C4a (fix in progress) |

## Not run or not proven

- **adb checks X1 to X10 (Open with, Share, shortcuts, refused schemes, cold start #133): not run.** The installed debug APK, launched on its own (`am start`, with and without a VIEW intent), stays on the Flutter splash: the Dart VM service listens, no Dart output, CPU about 15 %, for more than 75 s. Debug builds only start under the test tooling. These checks need a profile or release APK (`flutter build apk --profile --flavor store`). A profile APK build is in progress; the checks move to batch 7. Until then CORE-003, SYS-003 and SYS-004 have no evidence beyond c4a_android_intents_test 4/4, and the #129 and #133 cold-start check has none.
- **Hand checks (owner), section 3 of the plan:** H1 to H15 Essential, H20 to H45 Good to have, H50 to H64 Advanced. H31, H44, H45, H61, H62 and H64 need hardware or accounts the owner may not have yet (Android Auto DHU, Play internal track, foldable or tablet, gamepad, MDM tenant, USB DAC).
- Skipped by design: SUP-002 real payment, SYS-011 foldable, B2B MDM tenant, AUD-043 real DAC.

## Ticked in STATUS.md (Android cell, 11)

Rule (same as batch 4): a feature is ticked when passing device tests prove its Android acceptance criteria and the plan lists no owner hand check for it.

| ID | Evidence |
|---|---|
| LIB-001 | b2_library_sources_test 11/11 |
| LIB-002 | b2_library_sources_test 11/11, c4a_android_storage_test 14/14 |
| LIB-007 | b2_library_sources_test 11/11 |
| FILE-001 | b2_library_sources_test 11/11 |
| FILE-002 | b2_library_sources_test 11/11, c4a_android_storage_test 14/14 |
| SUB-010 | engine `SUB-01[0-6]` 25/25, c1_video_player_test 33/33 |
| AUD-045 | c4a_android_media_test (focus, ducking, regain, headphone unplug), engine `AUD-04[45]` 3/3 |
| PRIV-006 | c4a_android_security_test 6/6 |
| CORE-001 | c4a_mode_switch_test 1/1 (p95 71.1 ms against the 100 ms budget, in a debug build, so a profile build has headroom), b3_foundations_test 9/9 (last-mode restore), c4a_android_back_test 1/1 |
| MUS-003 | c2_tag_edit_test 1/1 |
| MUS-014 | c2_radio_scrobble_test 2/2 |

## Not ticked, and why

Device tests pass, owner hand check pending (kept ☐ with a note in STATUS):

- Essential: CORE-003 (H14, X1 to X3), VID-067 (H2), VID-068 (H3), VID-070 (H4), SUB-012 and SUB-013 (H5), SUB-014 (H6), IMG-001 (H7), IMG-014 (H8), IMG-015 (H9), SYS-008 (H10), PRIV-004 (H12), PRIV-005 (H13, X7).
- Good to have: CORE-014 (H42), FILE-006 (H25), VID-037 (H26), VID-066 (H27), VID-069 (H28), SUB-011 (H29), SUB-015 (H30), MUS-013 (H31), POD-001 (H32), IMG-007 (H33), IMG-009 (H34), IMG-010 (H35), IMG-012 (H36), IMG-013 (H37), NET-005 (H39), SYS-003 and SYS-004 (H43, X4 to X6), SUP-002 (H44).
- Advanced: LIB-013 (H50), VID-038 (H52), VID-041 (H53), SUB-016 and SUB-030 (H54), SUB-051 and SUB-053 (H55), IMG-002 (H56), IMG-008 (H57), IMG-011 and PRIV-007 (H58), NET-019 (H60), SYS-009 (H61), B2B-001 and B2B-002 (H62), MUS-009 (H63).

Held for another reason:

- IMG-017: failing test (c3_archives_test 1/3). AUD-043: failing teardown case and the real-DAC hand check (H64).
- AUD-044: the device tests only cover the output list and honest bit-perfect reporting; AVRCP metadata, absolute volume, codec display and the A/V offset over Bluetooth need Bluetooth hardware.
- LIB-014: only the loudness and chromaprint libraries ran on the phone; the finder UI has no device test.
- IMG-016: c3_remote_sources_test 5/5, but the Immich, Nextcloud / ownCloud and PhotoPrism sources wait on C4d.
- VID-071, CAST-004: c4a_android_display_test covers the bindings and c4a_android_presentation_test covers image frames on an external display; full-screen video with on-device controls and HDR passthrough on the external display has no device test.
- FILE-004: the libarchive library works on the phone; the browse and play UI has no device test.
- NET-007: removed from 1.0 (ADR-048); never ticked.
- POD-002: only the background capability ran (6/6); feeds are not merged.
- CORE-013, LIB-004: no device test; hand checks H15 and H1.

## Hand checks still to do (batch 7)

The owner's list is H1 to H15, H20 to H45 and H50 to H64 in `android-batch-6-plan.md` section 3, unchanged.

## Batch 7

Re-run: `c3_archives_test` (IMG-017, after C4a's fix) and engine `AUD-043` (after C4a's fix). New: the adb checks X1 to X10 on a profile APK. Hand checks as above.

## Process notes

- The phone dropped off wireless adb once (05:14, right after the first presentation run) and the keyguard returned at 05:32, which held the batch for about 7 hours. Both times the driver stopped on the condition.
- A broad `taskkill`/Stop-Process at 05:15 matched any `flutter_tools` process and may have killed a C2 test run (reported to the orchestrator).
- Lock `/data/local/tmp/mediahro-lock` removed at 13:11; keepalive stopped; the QA lane's Gradle and Kotlin daemons stopped by PID. Worktree `K:\Projects\mh-batch6` (main ff51e88) kept in case a profile build is wanted.
