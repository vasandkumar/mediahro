# Android device batch 2: results

Ran on the Samsung SM-M176B (Android 16) from main `bd9dc8a` on 2026-10-21, 03:40 to 04:57 IST. Store debug flavour, appId `com.mediahro.app`. Run list: 18 app integration test files and 5 engine example runs. Logs are in `K:\Projects\batch2-logs\` (outside the repo). How the runner is set up: see "Batch runner notes" in `android-batch-1-checks.md`.

## Passed

| Test | Result | IDs / area |
|---|---|---|
| c1_video_player_test | 33/33 | VID-037, VID-038, VID-039, SUB-030, SUB-040, SUB-050 (UI), SUB-053 (UI) and the batch 1 video player set |
| c2_music_test | 4/4 | MUS-001, MUS-002, MUS-004, MUS-006, MUS-007 |
| c2_playlists_car_test | 2/2 | MUS-008, MUS-013 (warm car tree) |
| c4a_android_caption_style_test | 2/2 | SUB-014 system caption style |
| c4a_android_car_alarm_test | 4/4 | MUS-011 alarms, MUS-013 warm car browse |
| c4a_android_power_status_test | 2/2 | thermal level and battery saver (VID-038 guard) |
| c4a_android_home_widgets_test | 3/3 | MUS-012 |
| c4a_android_intents_test | 4/4 | CORE-003, SYS-003, SYS-004 platform side |
| c4a_android_text_test | 2/2 | SUB-040 speech synthesis facade |
| c3_photos_test | 5/5 | IMG-001, IMG-003, IMG-004, IMG-006 |
| c3_map_test | 2/2 | IMG-007 gazetteer, map tiles, pan and zoom |
| c4a_android_imaging_test | 10/10 | ImagingFacade (ADR-037), IMG-002, IMG-011, IMG-015 pieces |
| engine_test ADR-031 | 5/5 | subtitle text and extraction |
| engine_test MUS-014 | 1/1 | live titles |
| engine_test "VID-002 decoder stalls" | 2/2 | Exynos stall fallback |

## Failed

| Test | Failure | Owner |
|---|---|---|
| c4a_android_tls_test | NET-017: an unpaired peer is not refused. The file can hang after a failure; run it with a timeout. | C4a |
| c4a_android_sftp_test | 0/7: the in-app sshd test server needs `PathUtils.setUserHomeFolderResolver` (test-infra bug, not a product failure) | C4a |
| c4a_android_hdr_video_test | VID-031: `MissingPluginException` on channel `mediahro/hdr_video/4242` method `ready` | C4a |
| c2_tag_edit_test | MUS-003: a leftover filter matches the package path `com.mediahro.app` (test bug) | C2 |
| c2_radio_scrobble_test | MUS-014: pause on a live station, the station keeps playing | C2 |
| c3_edit_test | IMG-009: preview render 655 ms against the 400 ms budget | C3 |
| engine_test ADR-032 | 0/5: `PathAccessException` opening `/proc/self/fd/N` on Android 16 (`audio_decoder.dart:174`). Blocks SUB-050 | B1 |
| engine_test AUD-046 | 0/3: the audio tap delivers 0 frames | B1 |

## Ticked in STATUS.md

IMG-003, IMG-004, IMG-006 (c3_photos_test), MUS-008 (c2_playlists_car_test), MUS-011 (c4a_android_car_alarm_test plus the batch 1 sleep timer test), MUS-012 (c4a_android_home_widgets_test), SUB-040 (c4a_android_text_test, c1_video_player_test, engine_test ADR-031), VID-039 (c1_video_player_test).

## Hand checks not run

- MUS-013 cold car connect (#71): needs Android Auto DHU or a car.
- Film-grain preset (#60) and bundled shaders (#58): Picture, Shaders.
- SUB-014 and SUB-030 manual checks (#46, #47, #42).
- Intents manual checks (#65: open-with, share targets, shortcuts); nothing listens to `openRequests` yet.
- Wallpaper and print (ImagingFacade, #72); HeifWriter EXIF and Ultra HDR keepHdr on a real gain-map JPEG.
- IMG-007, IMG-008, IMG-009 by hand (#73, #76, #79).
- VID-031 real HDR: needs C1 to wire the view into the player.
- SUB-051 and SUB-053 native text services: wait on B4a's CLD3 and Bergamot builds.
- VID-040 and VID-041: wait on B4a's lutrgb, blend and v360 filters; crop waits on ADR-033 work.

All failures and hand checks are carried into batch 3 in STATUS.md section 1.
