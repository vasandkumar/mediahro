# Android device batch 6: plan (Essential first)

Date: 2026-10-22. Owner priority: Essential, then Good to have, then Advanced (`feature-tiers-android.md`). This batch proves every feature whose Android status is **Built** in that file, plus the batch-5 items. Main is `edcf8a1` or later (includes #132 About screen and CORE-001 probe, #133 debug job receiver).

Rules for this run (orchestrator, 2026-10-22): the QA lane ticks nothing. It reports pass/fail per feature with the test name, and the orchestrator edits STATUS. POD-002 feeds and POD-003 are out (not merged). Samsung SM-M176B (Android 16), store debug flavour, appId `com.mediahro.app`, activity `com.mediahro.app/com.mediahro.mediahro.MainActivity` (the Kotlin namespace is `com.mediahro.mediahro`; use the appId for `adb`, `pm`, `appops` and `jobscheduler`).

## 1. How the run works

1. Orchestrator grants the heavy slot; the owner unlocks the phone and leaves it awake.
2. Fresh worktree of origin/main under `K:\Projects\mh-batch6`, logs in `K:\Projects\batch6-logs\`. Bootstrap: `tools/bootstrap` (FVM Flutter 3.47.7 first on PATH), `dart run tools/corpus/generate.dart`, `python packages/mediahro_engine/tool/stage_corpus.py`, `git lfs pull`.
3. Gate: free RAM at least 4 GB and no `flutter_tester` running (`gate.sh`).
4. Take the device lock: `adb -s $S shell "echo qa-batch6 $(date +%s) > /data/local/tmp/mediahro-lock"`; release it on exit (trap), even on failure.
5. Install probe (`c4a_android_power_status_test`), then grant `READ_MEDIA_VIDEO`, `READ_MEDIA_AUDIO`, `READ_MEDIA_IMAGES`, `POST_NOTIFICATIONS`, and `appops set com.mediahro.app SCHEDULE_EXACT_ALARM allow`.
6. Run every file below separately with `--no-uninstall` (never `--no-dds`), 5-minute cap on `c4a_android_tls_test`, 10-minute cap on `c4a_android_enterprise_test`, 25 minutes on others, 7-minute silence watchdog. Keyguard keepalive every 20 s (wake only; never a PIN). If the keyguard blocks a run, stop and ask the orchestrator to ask the owner to unlock.
7. After the files, the adb-driven checks in section 4 (they need the app installed and `Download/MediahroTest` staged).
8. Report. Release the lock, `gradlew --stop`, remove the worktree.

Shell setup used by every command (Git Bash):

```bash
export MSYS_NO_PATHCONV=1 PATH=~/fvm/versions/3.47.7/bin:$PATH GRADLE_OPTS=-Dorg.gradle.project.kotlin.incremental=false
ADB="$LOCALAPPDATA/Android/Sdk/platform-tools/adb.exe"
S=adb-RZGL225BN7H-KoTKDF._adb-tls-connect._tcp
A="-d $S --no-uninstall --flavor store --dart-define=MEDIAHRO_FLAVOR=store"
APP=/k/Projects/mh-batch6/app
E=/k/Projects/mh-batch6/packages/mediahro_engine/example
# app file:    (cd $APP && flutter test integration_test/<file>.dart $A)
# engine run:  (cd $E && flutter test integration_test/engine_test.dart -d $S --no-uninstall --name "<regex>")
```

Driver and helper scripts: copy `K:\Projects\batch4-logs\{driver,run_one,gate,keepalive}.sh`, change the log directory to `batch6-logs` and the run list to section 2.

## 2. Automated device runs, in order

"Covers" lists the Built features whose device evidence the file gives. A feature with a hand check in section 3 also needs that check before the orchestrator ticks it; the file result only covers the automated part.

### 2.1 Essential (run first)

| # | Command target | Covers (Essential unless marked) | Notes |
|---|---|---|---|
| E1 | app `c4a_android_intents_test` | CORE-003; SYS-003, SYS-004 (G) | plus the adb checks in section 4 |
| E2 | app `b2_library_sources_test` | LIB-001, LIB-002, LIB-007, FILE-001, FILE-002; LIB-013 (A); CORE-014 (G) | never run on a device before |
| E3 | app `c4a_android_storage_test` | LIB-002, FILE-002; IMG-016 Motion Photo (G) | 14 tests, passed in batch 3 |
| E4 | app `c4a_android_display_test` | VID-067, VID-070; SYS-011 layout part (G); VID-071 (A) | batch 1: 6/6 |
| E5 | app `c1_video_player_test` | VID-066, VID-067, VID-068, VID-069, VID-070; SUB-012, SUB-013, SUB-014 (UI); SUB-015 (G); SUB-016, SUB-030, SUB-053 (A); VID-037, VID-038 (UI) | 33 tests; the UI half of the hand checks |
| E6 | engine `--name "SUB-01[0-6]"` | SUB-010, SUB-011, SUB-012, SUB-013, SUB-014, SUB-015, SUB-016 engine side | corpus staged |
| E7 | app `c4a_android_caption_style_test` | SUB-014 system caption style | 2 tests |
| E8 | app `c4a_android_media_test` | AUD-045; AUD-044 (G); SYS-001, SYS-002, SYS-006 (regression) | |
| E9 | engine `--name "AUD-045\|AUD-044"` | AUD-045 audio focus, AUD-044 Bluetooth | engine side |
| E10 | app `c3_photos_test` | IMG-001 (JPEG/HEIC/RAW decode), IMG-003, IMG-004 (regression) | batch 2: 5/5 |
| E11 | app `c3_formats_test` | IMG-001 SVG, clips, pages; IMG-010 (G) | |
| E12 | app `c3_pano_test` | IMG-001 360 viewer | |
| E13 | app `c4a_android_motion_test` | IMG-001 MotionFacade | |
| E14 | app `c4a_android_imaging_test` | IMG-001, IMG-015 share, wallpaper, print, copy; IMG-002 (A); IMG-010 (G) | 10 tests |
| E15 | app `c3_compare_test` | IMG-014 recently deleted bin; IMG-013 (G); IMG-008 (A) | batch 4: 4/4 |
| E16 | app `c4a_android_input_test` | SYS-008; SYS-009 (A, the #116 fix) | |
| E17 | app `c4a_android_security_test` | PRIV-006 keystore; PRIV-008 helper | never run on a device before |
| E18 | app `b3_foundations_test` | PRIV-004 allow-list, CORE-008 (G), CORE-015 (regression) | |
| E19 | app `app_smoke_test` | regression | |
| E20 | app `c4a_android_back_test` | CORE-001 back behaviour (regression) | |
| E21 | app `c4a_mode_switch_test` (new in #132) | CORE-001: 20 warm tab switches, p95 at most 100 ms | add `--dart-define=MEDIAHRO_ENFORCE_BUDGET=true` to the usual flags; the `perf: mode-switch <ms>` lines are in the log. If the debug build misses 100 ms only because it is a debug build, try once with `--profile` and report both. A line `perf: mode-switch invalid` or "only 0 of 20 switches were timed" means the clocks do not match (report as a probe bug for C4a) |

LIB-004, PRIV-001, PRIV-005 have no device test (hand checks H1, H11, H13). CORE-013 About is a short hand check (H15); the screen has Dart widget tests only.

### 2.2 Good to have

| # | Command target | Covers | Notes |
|---|---|---|---|
| G1 | app `c2_tag_edit_test` | MUS-003 | #117 fix |
| G2 | app `c2_radio_scrobble_test` | MUS-014; MUS-009 (A) | #117 fix |
| G3 | app `c2_books_test` | POD-001 | new in #121 |
| G4 | app `c2_playlists_car_test` | MUS-013 car tree (engine part) | |
| G5 | app `c4a_android_car_alarm_test` | MUS-013 car, MUS-011 alarm | #8893306 fixed a timing wait |
| G6 | app `c3_places_test` | IMG-007 | |
| G7 | app `c3_edit_test` | IMG-009 | |
| G8 | app `c4a_android_presentation_test` | IMG-012, CAST-004 (A) | new in #110, 4 tests |
| G9 | app `c3_remote_sources_test` | IMG-016 | new in #111 |
| G10 | app `c4a_android_network_test` | NET-005, NET-007; NET-019 (A) | never run on a device before |
| G11 | app `c4a_android_purchases_test` | SUP-002 Play Billing bindings | |
| G12 | app `b2_native_libraries_test` | LIB-014 duplicates (loudness, chromaprint); FILE-004 (A, libarchive CBZ); SUB charset | never run on a device before |
| G13 | app `c4a_android_background_test` | ADR-049 background work (POD-002 capability only) | new in #126, 6 tests; cold-start check X9 in section 4 |
| G14 | app `c4a_android_text_test` | SUB-040 (regression) | |

### 2.3 Advanced

| # | Command target | Covers | Notes |
|---|---|---|---|
| A1 | app `c3_vault_test` | IMG-011, PRIV-007 | 7 tests |
| A2 | app `c4a_android_vault_test` | IMG-011 native half | |
| A3 | app `c3_archives_test` | IMG-017 comics, PRIV-005 (zip-bomb limits) | new in #108, 3 tests |
| A4 | app `c4a_android_enterprise_test` | B2B-001, B2B-002 | 10-minute cap |
| A5 | app `c4a_android_power_status_test` | VID-038 thermal gating (regression); install probe | |
| A6 | engine `--name "ADR-031"` | SUB-030 conversion, SUB-051 PGS/VobSub bitmaps, SUB-053, PRIV-007 | engine side |
| A7 | engine `--name "VID-037\|VID-040\|VID-041"` | crop, colour management, 3D and 360 (engine half) | |
| A8 | engine `--name "PRIV-007"` | PRIV-007 | |
| A9 | engine `--name "AUD-043"` | AUD-043 DoP cases (#119: no DAC needed) | 15 cases; real-DAC hand check stays |
| A10 | app `c4a_android_tls_test`, `c4a_android_sftp_test` | NET-017, NET-004 (regression) | tls on a 5-minute cap |
| A11 | app `c4a_android_hdr_video_test` | VID-031 (blocked, regression) | |
| A12 | app `c4a_android_home_widgets_test` | MUS-012 (regression) | |
| A13 | app `b2_library_perf_test` | LIB-003, LIB-005 (regression); library perf budget | |

Not run (not Built or blocked): VID-002, VID-003, AUD-001, VID-004, VID-030, VID-031, VID-033..035, AUD-040, NET-001, NET-002, FILE-004 UI, POD-002 feeds, POD-003, SUB-052, IMG-005 face grouping, and everything marked Not built.

## 3. Hand checks for the owner

Each is at most three steps. Test files: `Download/MediahroTest` on the phone holds `sample.mp4` with `sample.en.srt`, `cyrillic.mp4` with `cyrillic.srt` (Windows-1251), `styled.mp4` with `styled.ass`, `dual.mkv` (English and French). The QA lane adds `truncated.mp4`, `random.mp4`, a CBZ/CBR and photo files before the run (section 4). Add the folder as a source once: Sources › Add folder.

### 3.1 Essential

- **H1 LIB-004 Folder and library views.** 1. Open Video. 2. Tap the view toggle. 3. Expected: the list switches between folders and the flat library, and the choice stays after you leave and return.
- **H2 VID-067 Picture-in-picture.** 1. Play `sample.mp4`, then More › Picture-in-picture. 2. Expected: a small window keeps playing. 3. Play again and press Home: it enters PiP by itself.
- **H3 VID-068 Background and sound only.** 1. Play `sample.mp4`, turn on More › Sound only, switch the screen off. 2. Expected: sound continues and the lock screen shows controls. 3. Play a song, then a video: the lock-screen buttons control only what is playing.
- **H4 VID-070 Rotation, notch, keep-awake.** 1. Play a video and lock rotation to landscape. 2. Leave the player. 3. Expected: the app returns to portrait; the screen stays on while the video plays.
- **H5 SUB-012 and SUB-013 Subtitle files and character sets.** 1. Open `sample.mp4`: English subtitles appear by themselves. 2. Subtitles › Add a subtitle file › `cyrillic.srt`, choose the Cyrillic encoding. 3. Expected: the Russian text reads correctly.
- **H6 SUB-014 Subtitle styling.** 1. Settings › Subtitles: Size Huge, Background Solid box. 2. Play a video with subtitles. 3. Expected: the subtitles change at once; with Android's own caption style changed (Settings › Accessibility › Caption), Mediahro follows it when "Use system style" is on.
- **H7 IMG-001 Photo formats.** 1. Open an SVG logo (zoom stays sharp), a multi-page TIFF (Page n of m with working Previous/Next), a camera panorama (opens full height, pans). 2. Open a Motion Photo from the camera and press play: the clip plays and ends by itself. 3. Open an iPhone Live Photo pair copied to a folder: it shows as one item.
- **H8 IMG-014 Recently deleted.** 1. Delete a photo. 2. Albums › Recently deleted: it is there; tap Undo or Restore. 3. Expected: the photo returns to its place.
- **H9 IMG-015 Share, wallpaper, print, copy.** 1. Open a photo with GPS, Share it at 1280 px with metadata stripped; check in the receiving app that it shows no location. 2. Set as wallpaper. 3. Print shows the system print preview; Copy puts the photo on the clipboard (paste in a messaging app).
- **H10 SYS-008 TalkBack and large text.** 1. Settings › Accessibility › Font size: largest. Open Video and Settings. 2. Turn on TalkBack; swipe through the player controls. 3. Expected: nothing is cut off, every control is read aloud with a name.
- **H11 PRIV-001 No telemetry by default.** 1. First-run (or Settings › Privacy) explainer. 2. Expected: it says nothing is sent, and the privacy dashboard shows no endpoints in use on a fresh install. 3. Fresh install check: no network prompt appears.
- **H12 PRIV-004 Network allow-list.** 1. Settings › Privacy dashboard. 2. Turn a per-feature network toggle on, then off. 3. Expected: the list of allowed endpoints changes accordingly and nothing else appears.
- **H13 PRIV-005 Broken files.** 1. Open `truncated.mp4` and `random.mp4` (staged by the QA lane) from the folder. 2. Expected for each: an error message in plain words; the app does not crash. 3. Open the library: it still lists the other files.
- **H15 CORE-013 About and licences (#132).** 1. Settings › About: it shows the name, version, build and flavour. 2. Open-source licences: look for ffmpeg, mpv and dav1d in the list. 3. Source code and build details: the FFmpeg configure line must not contain `--enable-gpl`. (The screen makes no network connection; the domain and repo address are placeholders.)
- **H14 CORE-003 Open with from Files.** 1. In the Files app tap `sample.mp4`, choose Mediahro. 2. Repeat with a song and a photo. 3. Expected: it opens in the right screen; going back leaves the app or returns to the library (no crash).

### 3.2 Good to have

- **H20 CORE-005 Open a link.** 1. Video › Open link, paste a public HLS or MP4 URL you trust. 2. Expected: it plays. 3. Open the link box again: the link is in the last 50.
- **H21 LIB-006 Continue watching.** 1. Watch part of a video, leave. 2. Open Video home. 3. Expected: a Continue watching row shows it with progress; Recently added shows new files.
- **H22 LIB-011 Info and posters.** 1. Put a poster image (`poster.jpg`) beside a video. 2. Rescan. 3. Expected: the poster shows as the cover; no online lookup is made.
- **H23 LIB-012 Grouping.** 1. Music › Albums and Artists. 2. Video: files named `Show S01E01..` group as a series. 3. Expected: groups open to their items.
- **H24 FILE-003 Batch tools.** 1. Select several files, open the bar menu. 2. Rename with a token, then Tag edit. 3. Expected: names/tags change on all and Undo works.
- **H25 FILE-006 Subtitles follow their video.** 1. Move `sample.mp4` to another folder with Mediahro. 2. Expected: `sample.en.srt` moves with it and the subtitle still shows.
- **H26 VID-037 Picture controls.** 1. More › Picture: rotate, mirror, aspect, crop. 2. Expected: the picture changes at once. 3. Reset restores it.
- **H27 VID-066 Audio delay and boost.** 1. Audio sheet: volume 250 %. 2. Expected: louder, no crackling. 3. Headphones in: the level you last set for headphones returns.
- **H28 VID-069 Video sleep timer.** 1. More › Sleep timer › End of this video. 2. Seek to 10 s before the end. 3. Expected: it fades out and pauses.
- **H29 SUB-011 Image subtitles.** 1. Open a video with PGS or DVD subtitles (the corpus has them). 2. Pick the image track in Subtitles. 3. Expected: the images appear and the timing is right.
- **H30 SUB-015 Subtitle delay and speed.** 1. Subtitles › Delay: +2 s. 2. Speed: 23.976 → 25. 3. Expected: the lines move as set.
- **H31 MUS-013 Android Auto.** Needs the Android Auto test app (DHU) or a car. 1. Connect. 2. Open Mediahro on the car screen. 3. Expected: browse, play, and a cold connect starts the app.
- **H32 POD-001 Audiobooks.** 1. Put an M4B with chapters in a folder. 2. Audiobooks tab: open it; check chapters, speed 1.5×, skip silence audible, bookmark. 3. Shake the phone while the sleep timer runs: it extends; walking does not.
- **H33 IMG-007 Places.** 1. Photos › Places. 2. Search a city, or enter coordinates, on a photo without GPS. 3. Expected: the location is saved and the photo appears under Places.
- **H34 IMG-009 Photo editor.** 1. Edit a photo: crop, adjust, save. 2. On an SD card or SAF folder choose Replace original. 3. Expected: it replaces; Share and batch strip metadata.
- **H35 IMG-010 Batch photo tools.** 1. Select photos. 2. Rename, Convert, Strip metadata from the bar. 3. Expected: results as chosen.
- **H36 IMG-012 Slideshow.** 1. Open a photo, Slideshow. 2. With Remove animations on, the transition is a cut. 3. Press the viewer's Slideshow button again to stop.
- **H37 IMG-013 Duplicates.** 1. Albums › Duplicates in a library with copies. 2. Delete the extras. 3. Expected: they go to Recently deleted.
- **H38 NET-003 WebDAV.** 1. Sources › Add › WebDAV with your server. 2. Browse and play a file. 3. Expected: it plays; the password is not shown again.
- **H39 NET-005 DLNA.** 1. Sources › Network devices. 2. Browse a DLNA server on your Wi-Fi. 3. Expected: it lists and plays.
- **H40 NET-006 Streams.** 1. Open a link for HLS, DASH, RTSP in turn. 2. Expected: each plays or says why not.
- **H41 NET-018 Offline downloads.** 1. Choose Download on a network video. 2. Turn on airplane mode. 3. Expected: it still plays from the phone.
- **H42 CORE-014 Backup and restore.** 1. Settings › Backup: make a backup with a passphrase. 2. Clear data, restore. 3. Expected: playlists and settings return.
- **H43 SYS-003 and SYS-004** are covered by the adb checks (section 4); the owner confirms only: long-press the app icon, the Resume shortcut works.
- **H44 SUP-002 Real payment.** Needs the Play internal-test track and Play Console products: skip until the first upload.
- **H45 SYS-011 Foldable/tablet layout.** Needs a foldable or tablet: not on this phone.

### 3.3 Advanced

- **H50 LIB-013 Parental PIN.** 1. Settings › Parental PIN: set one. 2. Hide an item. 3. Expected: it disappears from lists and the PIN is asked to see it.
- **H51 FILE-005 Wi-Fi transfer.** 1. Start Wi-Fi transfer; scan the QR code with another device. 2. Upload a file from that device. 3. Expected: the file appears in the library.
- **H52 VID-038 Shaders.** 1. More › Picture › Shaders: pick Anime4K, then film grain. 2. Expected: the picture changes; the hot-device warning pauses them.
- **H53 VID-041 3D and 360.** 1. Open a side-by-side clip; More › 3D. 2. Open a 360 clip: drag to look around. 3. Expected: both show correctly.
- **H54 SUB-016 and SUB-030.** 1. `dual.mkv`: turn on a second subtitle track; it shows at the top. 2. Subtitles › Edit: change a line, save. 3. Expected: the change shows in the video.
- **H55 SUB-051 and SUB-053.** 1. Open a PGS video; Subtitles › Convert to text (OCR). 2. Subtitles › Translate to another language (consent to the download). 3. Expected: a new text track appears.
- **H56 IMG-002 HDR photos.** 1. Open an Ultra HDR photo. 2. Press the HDR button and pinch to zoom. 3. Expected: highlights brighten with HDR on.
- **H57 IMG-008 Compare.** 1. Select two photos, Compare. 2. Slide the divider, reject one, un-reject. 3. Expected: both views stay in sync.
- **H58 IMG-011 and PRIV-007 Vault.** 1. Create a vault with fingerprint. The prompt is fingerprint only. 2. Add a video and a song; play them; send the app to the background. 3. Expected: playback stops; Cancel on the prompt leaves it locked; after enrolling a new fingerprint the vault says the key changed; the decoy PIN opens the decoy vault.
- **H59 IMG-017 Comics.** 1. Open a CBZ and a CBR; page through. 2. Right-to-left on; open a password-protected archive and enter a wrong password, then the right one. 3. Expected: spreads, RTL order and a clear wrong-password message.
- **H60 NET-019 Connection health.** 1. Sources › a server › Test connection. 2. Expected: shows reachable, speed and the reason when it fails.
- **H61 SYS-009 Controllers.** Needs a Bluetooth gamepad. 1. Pair it. 2. Move around the library and play/pause with the buttons. 3. Expected: D-pad focus and the dead zone work.
- **H62 B2B-001 and B2B-002.** Need an MDM test tenant and a kiosk setup: skip until the owner has them.
- **H63 MUS-009 ListenBrainz.** 1. Settings › Scrobbling: paste your ListenBrainz token. 2. Play a song for over half its length. 3. Expected: the listen appears on listenbrainz.org.
- **H64 AUD-043 real DAC** (STATUS section 4 owner row): needs a USB DAC; skip until the owner has one.

## 4. adb-driven checks (the QA lane runs these, with expected results)

Run after the files, under the same lock. Files staged to `Download/MediahroTest` first: `truncated.mp4` (`head -c 100000 sample.mp4`), `random.mp4` (`head -c 5000 /dev/urandom`), a 24 MP JPEG, a short WAV, a CBZ.

Find a content URI: `adb -s $S shell content query --uri content://media/external/video/media --projection _id:_display_name --where "_display_name='sample.mp4'"`, then use `content://media/external/video/media/<id>`.

| # | Feature | Command | Expected |
|---|---|---|---|
| X1 | CORE-003 Open with, app closed | `am force-stop com.mediahro.app; am start -a android.intent.action.VIEW -d <video uri> -t video/mp4 -n com.mediahro.app/com.mediahro.mediahro.MainActivity` | the player opens and plays (UI dump shows the player; `dumpsys media_session` has an active Mediahro session) |
| X2 | CORE-003, app running | same, with the app in the foreground | the new file replaces the old one |
| X3 | CORE-003 audio and picture | the same with an audio URI (`-t audio/wav`) and a picture URI (`-t image/jpeg`) | audio plays; the external viewer shows the picture |
| X4 | SYS-004 text | `am start -a android.intent.action.SEND -t text/plain --es android.intent.extra.TEXT "cats" -n <component>` | Search opens with "cats", no fetch |
| X5 | SYS-004 link | `am start -a android.intent.action.SEND -t text/plain --es android.intent.extra.TEXT "https://example.com/video.mp4" -n <component>` | the stream is offered/opened; the link is in recent links |
| X6 | SYS-003 shortcut | `cmd shortcut` is not scriptable on Android 16; the owner long-presses the icon (H43) | the Resume shortcut works |
| X7 | PRIV-005 | open `truncated.mp4` and `random.mp4` through VIEW | an error message, no crash (no `FATAL EXCEPTION` in `logcat -b crash`) |
| X8 | refused schemes | `am start -a VIEW -d "javascript:alert(1)"`, `-d "smb://x/y"`, `-d "intent:#Intent;end"` | refused with the plain message, no crash |
| X9 | ADR-049 cold start (#129, #133; debug build) | `adb shell am broadcast -n com.mediahro.app/com.mediahro.mediahro.testing.DebugJobReceiver --es op schedule`; press Home (`input keyevent KEYCODE_HOME`), then `adb shell am kill com.mediahro.app` to end the process the way the OS does when it frees memory (do not use `am force-stop`: it cancels the scheduled job; if the process does not die, ask the owner to swipe the app away from recents); `adb shell dumpsys jobscheduler com.mediahro.app` to find the job id; `adb shell cmd jobscheduler run -f com.mediahro.app <job id>`; `adb logcat -d -s flutter MediahroBackground`; then `... --es op cancel` | `bg: schedule debug.leave` after the first command, and `bg: ran debug.leave` after the run (`app: no view in this engine` may also appear and is fine); cancel always run at the end |
| X10 | Cold-start with a view | `am force-stop com.mediahro.app; am start -n <component>`, then `logcat -d | grep "app: no view"` | no such line when a view exists |

## 5. What the report contains

For each file in section 2: pass/total or the failure with a 2-3 line excerpt. For each feature in the tier tables: which files covered it and whether each passed, so the orchestrator can tick or hold. Hand checks (section 3) are listed as "owner" with the numbered list the owner receives. The orchestrator edits STATUS.

## 6. Estimates

About 60 app/engine runs at roughly one minute each plus the c1 player file (several minutes) and the 10-minute enterprise cap: under 90 minutes if nothing hangs. Disk: the worktree and builds need about 6 GB on K: (delete the worktree afterwards).
