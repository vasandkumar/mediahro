# Mediahro — STATUS

The single progress view for the owner. Every PR updates the rows it touches. Generated once from `docs/04` by `tools/status/gen_status.py`; CI (`tools/status/check_status.py`) fails if a doc 04 ID is missing or a 1.0 platform cell is narrowed.

**Legend:** ☐ to do · ☑ done (AC verified on that platform through the CI matrix) · ⛔ blocked (see Blockers) · — not applicable on that platform (doc 04) · 1.1/1.2 later release per doc 04 · Platforms: A Android · I iOS/iPadOS · M macOS · W Windows.

_Last updated: 2026-10-19 by the orchestrator._

## 1. Phase and milestone gates

| Phase / milestone | Lanes | State | Exit criteria (docs/10 §3, §8) |
|---|---|---|---|
| **A — Skeleton (M0)** | orchestrator | ☑ done 2026-10-19 (deps archives → B4 per Phase B exit) | Shell builds on all platforms; stubs compile; CI green; deps archives published with SHA-256; licence scan passes |
| **B — Foundations (M1, M2)** | B1 Engine · B2 Library & sources · B3 Design system & shell · B4 Native deps (Android / Apple / Windows) | **interface freeze 2026-10-20 at a138542 (ADR-025)**; all six lanes merged; open items: combined deps release v2026.10.4 + deps.lock pin (B4a), network-env green (B2) | M1 + M2 exit criteria; B3 goldens green; deps archives published and pinned; **interface freeze** |
| **C — Experiences (M3–M7)** | C1 Video & subtitles · C2 Music & podcasts · C3 Photos · C4a Android · C4b Apple · C4c Windows · C4d Servers & casting · C5 Supporter, privacy, B2B, store metadata | started 2026-10-20, then **paused by the owner's rule: at most 3 lane sessions run at once.** The slots go first to the Phase B finishers (B1 pin switch-over, B2 network-env, B4a deps pin). After that the lanes rotate in this order: C4a Android → C4c Windows → C4b Apple → B4b/B4c (Tesseract + deps cache, v2026.10.5) → C1 → C3 → C2 → C5 → C4d. Briefs are in docs/lanes. | Each lane's IDs ☑ on every platform; integration branch builds daily |
| **D — Hardening (M8)** | D1 Android · D2 iOS/iPadOS · D3 macOS · D4 Windows · D5 Localisation · D6 Store submission packs | not started | All doc 11 §7 release gates pass; 1.0 tagged |

### Android device batch (owner, 2026-10-20: test 25 features at a time on the Samsung)

| Batch | Features waiting for the device run | State |
|---|---|---|
| 1 | Ran on the Samsung at main 475f3df: all 14 functional test files pass (100+ tests); library perf passes; shell perf harness can't reach the VM service over wireless adb (CORE-001 stays ⛔). Ticked: VID-036, VID-060…065, VID-072, MUS-001, MUS-002, MUS-005, MUS-006, LIB-003, LIB-005. **Waiting for the owner's manual checks** (docs/release/android-batch-1-checks.md): VID-066, VID-067, VID-068, VID-069, VID-070, SUB-012…016. Not ticked: MUS-011 (Android AlarmFacade missing), SYS-011 (needs a foldable or tablet), VID-074 (only the session part is done). | automated done; manual checks pending |
| 2 | Ran on the Samsung SM-M176B (Android 16) at main bd9dc8a, 2026-10-21 03:40-04:57 IST, 23 test runs. **Passed:** c1_video_player_test 33/33; c2_music_test 4/4; c2_playlists_car_test 2/2; c4a_android_caption_style_test 2/2; c4a_android_car_alarm_test 4/4; c4a_android_power_status_test 2/2; c4a_android_home_widgets_test 3/3; c4a_android_intents_test 4/4; c4a_android_text_test 2/2; c3_photos_test 5/5; c3_map_test 2/2; c4a_android_imaging_test 10/10; engine_test ADR-031 5/5, MUS-014 1/1, VID-002 decoder stalls 2/2. **Failed:** c4a_android_tls_test (NET-017 unpaired peer not refused); c4a_android_sftp_test 0/7 (test-infra: in-app sshd needs PathUtils.setUserHomeFolderResolver); c2_tag_edit_test (MUS-003 leftover filter matches the package path com.mediahro.app; test bug); c2_radio_scrobble_test (MUS-014 pause on a live station still plays); c4a_android_hdr_video_test (VID-031 MissingPluginException on mediahro/hdr_video/4242 `ready`); c3_edit_test (IMG-009 preview 655 ms vs 400 ms budget); engine_test ADR-032 0/5 (PathAccessException opening /proc/self/fd/N on Android 16, audio_decoder.dart:174); engine_test AUD-046 0/3 (audio tap delivers 0 frames). **Ticked (8):** IMG-003, IMG-004, IMG-006, MUS-008, MUS-011, MUS-012, SUB-040, VID-039. **Not ticked:** MUS-003, MUS-009, MUS-014, AUD-046, SUB-050, VID-031, IMG-009, NET-017 (failing tests); MUS-013, SUB-014, SUB-030, SUB-051, SUB-053, VID-038, VID-040, VID-041, IMG-007, IMG-008, CORE-003, SYS-003, SYS-004 (hand checks not run); VID-037 (crop waits on ADR-033). Details, owners and the hand-check list: docs/release/android-batch-2-results.md. | done 2026-10-21; failures routed to lanes |
| 3 | Carried over from batch 2. **Failed, fix and re-run:** NET-017 TLS client/mTLS server (#41, C4a: unpaired peer not refused; run with a timeout) · SFTP facade (#45, C4a: test server needs PathUtils.setUserHomeFolderResolver) · MUS-003 (#44, C2: test filter matches com.mediahro.app) · MUS-014 pause on a live station and MUS-009 (#52, C2; same c2_radio_scrobble_test file) · AUD-046 visualiser (#55, B1: audio tap delivers 0 frames; engine_test --name AUD-046) · SUB-050 auto-sync (#49 + #61, B1: ADR-032 decodeAudio fails opening /proc/self/fd/N on Android 16; engine_test --name ADR-032) · VID-031 Android native HDR view (#77, C4a: `ready` MissingPluginException on mediahro/hdr_video/4242; real HDR also needs C1 wiring) · IMG-009 photo editing (#79, C3: preview 655 ms vs 400 ms budget). **Hand checks still to do:** MUS-013 cold car connect (#71, DHU or car) · VID-038 film-grain preset (#60) and bundled shaders (#58) · SUB-014 system captions (#46/#47) and SUB-030 editor (#42) manual checks · CORE-003, SYS-003, SYS-004 manual checks (#65; nothing listens to openRequests/intents yet, B3 wiring needed) · SUB-051/053 native text services (#57; wait on B4a CLD3/Bergamot builds) · VID-040/041 (#66; wait on B4a lutrgb/blend/v360) and VID-037 crop (ADR-033) · IMG-007 by hand (#73), IMG-008 compare (#76), IMG-009 by hand (#79) · ImagingFacade by hand: wallpaper, print, HeifWriter EXIF and Ultra HDR keepHdr (#72). New work for the batch (2026-10-21): **SYS-008** audio-description preference and **SYS-009** gamepad axes, Android halves (#80, C4a; `integration_test/c4a_android_input_test.dart`, 4 tests, with a debug-only joystick MotionEvent hook; real controller by hand once C1 uses the facade) · **IMG-010** batch tools, **IMG-015** share/wallpaper/print/copy and **IMG-002** HDR photo view (#81, C3; no integration test, by hand on the Samsung: batch rename/convert/strip from the selection bar; share at 1280 px with strip and check the receiver has no GPS; wallpaper, print, copy; open an Ultra HDR photo, HDR button, pinch to zoom). #78 (C4a, SYS-011 manifest guard) is a unit test only, so SYS-011 is not counted: the tabletop layout waits on the UI lanes. | collecting (5 new features: SYS-008, SYS-009, IMG-010, IMG-015, IMG-002; plus carry-overs)

### Phase A (M0) deliverables

| Deliverable | State | Evidence |
|---|---|---|
| Repo layout per docs/05 §3 (`app/`, `packages/mediahro_{design,engine,ffi,servers,subtitles}`, `tools/`, `test-media/`, `fastlane/`, `.github/workflows/`, licence/policy files) | ☑ | Dart pub workspace (`pubspec.yaml`) |
| Toolchain pins (`.fvmrc` Flutter 3.47.7, NDK r28c, API 36/min 29) | ☑ | `TOOLCHAIN.md` |
| Flavours `store/direct/foss/enterprise` + `Capabilities` service | ☑ Android Gradle + dart-define; Apple Xcode configurations → C4 (ADR-015) | `app/lib/app/capabilities.dart`, tests |
| Design tokens + theme builders per platform family | ☑ | `packages/mediahro_design`, 23 tests |
| l10n pipeline (ARB fragments → merge → gen-l10n; 12 launch locales + ar/he) | ☑ | `tools/l10n/merge_arb.dart`, ADR-013 |
| Interface stubs: `PlaybackEngine`, `ImagePipeline`, `ServerLibrary`, `VirtualFile`, 14 platform facades, `NetworkGateway` | ☑ | `packages/mediahro_engine/lib/src/api`, `app/lib/images`, `packages/mediahro_servers`, `packages/mediahro_ffi/lib/src/vfs`, `app/lib/platform`, `app/lib/core/net` |
| Custom lint rules, licence scan + SBOM, manifest guard, status guard, size budget | ☑ | `tools/lints`, `tools/licence_scan`, `tools/compliance`, `tools/status`, `tools/perf` |
| CI matrix (analyze, unit/widget, licence-sbom, build A/I/M/W per flavour, integration A/I/M/W, nightly fuzz/corpus, release) | ☑ written | `.github/workflows/` |
| `mediahro-deps` skeleton (versions, exact flags, verify, package, CI) | ☑ | `../mediahro-deps` |
| Shell builds locally: Windows | ☑ debug build + integration tests pass | local |
| Shell builds locally: Android | ☑ `foss` debug APK builds (API 36, NDK r28c) | local |
| Shell builds: iOS, macOS | ☑ CI: iOS device + simulator builds, macOS store/direct builds, integration tests on iOS simulator and macOS | `ci` run 39260124066 |
| CI green on GitHub (16 jobs: analyze, unit, licence/SBOM, 4 Android flavours, iOS, 2 macOS, 2 Windows, integration A/I/M/W) | ☑ | [run 39260124066](https://github.com/vasandkumar/mediahro/actions/runs/39260124066) |
| Size budgets at M0 | ☑ Android 19.7 MB/ABI, macOS 43.6 MB universal, Windows 28.2 MB; 16 KB alignment verified | CI logs |

### Lane ownership (folders; lanes never edit each other's folders)

| Lane | Folders owned |
|---|---|
| B1 Engine | `app/lib/engine`, `packages/mediahro_engine` (whole package except `sdk/` and `capi/`, incl. bundling the `mediahro-deps` libraries into the plugin's Gradle/podspec/CMake builds; stays the engine lane through Phase C, ADR-025), `packages/mediahro_ffi` (mpv part: `lib/src/mpv/`, `ffigen/mpv.yaml`), `tools/corpus`, `test-media` |
| B2 Library & sources | `app/lib/core`, `app/lib/features/sources`, `app/lib/features/library`, `packages/mediahro_ffi` (smb2/nfs/curl/archive/ebur128/chromaprint/uchardet parts, `lib/src/vfs/`) |
| B3 Design system & shell | `packages/mediahro_design`, `app/lib/app`, `app/lib/ui`, `app/lib/features/settings`, `app/lib/features/onboarding`, `tools/l10n` |
| B4 Native deps | `../mediahro-deps` (sub-lanes `android/`, `apple/`, `windows/`), `deps.lock`, `tools/deps`, `tools/licence_scan` |
| C1 Video & subtitles | `app/lib/features/video`, `packages/mediahro_subtitles`, `packages/mediahro_ffi` (tesseract part) |
| C2 Music & podcasts | `app/lib/features/music` |
| C3 Photos | `app/lib/features/photos`, `app/lib/images`, `packages/mediahro_ffi` (vips/jxl/avif/raw parts) |
| C4a Android | `app/android`, `app/pigeons/android`, `app/lib/platform/android` |
| C4b Apple | `app/ios`, `app/macos`, `app/pigeons/apple`, `app/lib/platform/apple` |
| C4c Windows | `app/windows`, `app/pigeons/windows`, `app/lib/platform/windows` |
| C4d Servers & casting | `packages/mediahro_servers`, `app/lib/features/servers`, `app/lib/features/cast` |
| Orchestrator | facade interfaces `app/lib/platform/*.dart`, `app/lib/platform/platform_bindings.dart`, `app/lib/main.dart`, `app/pubspec.yaml`, `.github/workflows`, `STATUS.md`, `CHANGELOG.md`, `tools/perf/baseline.json` |
| C5 Supporter, privacy, B2B, store | `app/lib/features/supporter`, `app/lib/features/b2b`, `app/lib/features/privacy` (telemetry opt-in, app lock; the dashboard screen CORE-015 is B3's), `packages/mediahro_engine/sdk/` and `capi/` (Phase C: SDK packaging, C/Kotlin/Swift APIs, samples), `fastlane/` |

Shared files (`STATUS.md` own rows only, `CHANGELOG.md` own entries, `docs/05 §12` via ADR PRs, `app/pubspec.yaml`, `app/lib/main.dart` via the orchestrator) are merged by the orchestrator. Each lane keeps its UI strings in its own ARB fragment `<owned folder>/l10n/<module>_<locale>.arb`; `tools/l10n/merge_arb.dart` merges fragments before `gen-l10n`.

## 2. Feature checklist (every doc 04 ID)

### 1. CORE — App shell, settings, onboarding

| ID | Feature | Lane | A | I | M | W | Notes |
|---|---|---|:-:|:-:|:-:|:-:|---|
| CORE-001 | Three-mode shell (Video, Music, Photos) with a shared Sources and Settings area | B3 | ⛔ | ⛔ | ☐ | ☑ | W ☑ perf-windows run 39355442122: profile median 18.2 ms, max 19.6 ms (budget 100 ms). M: perf-macos on main. A I ⛔ profile mode needs a physical device (device lab, §4). |
| CORE-002 | First-run without walls | B3 | ☑ | ☑ | ☑ | ☑ | B3 PR #2: one screen, three actions via FirstRunActions facade, privacy line + PRIV-001 note; no platform calls on launch (tested) Proven by CI on PR #2: integration_test/b3_foundations_test.dart on A/I/M/W plus widget, golden and a11y suites. |
| CORE-003 | Open-with / default handler | C4 | ☐ | ☐ | ☐ | ☐ |  |
| CORE-004 | Drag-and-drop | C4 | — | ☐ | ☐ | ☐ |  |
| CORE-005 | URL/stream open | B2 | ☐ | ☐ | ☐ | ☐ | B2: URL validation, headers/UA, history of 50, Open URL dialog. Playback hand-off is the `openUrlActionProvider` seam (C1 wires it). |
| CORE-006 | Settings model | B3 | ☑ | ☑ | ☑ | ☑ | B3 PR #2: typed SettingKey/SettingsStore (JSON in app support dir, atomic, debounced), registry for other lanes, search, descriptions, Advanced collapsed, reset per section, import/export, managed overlay hook Proven by CI on PR #2: integration_test/b3_foundations_test.dart on A/I/M/W plus widget, golden and a11y suites. |
| CORE-007 | Themes | B3 | ☑ | ☑ | ☑ | ⛔ | B3 PR #2: light/dark/system, AMOLED, per-mode + custom accents (contrast-safe), high contrast, Material You (A), glass bars (Apple), Mica-ready shell. W: Mica needs the runner, owned by C4 (see §3) Proven by CI on PR #2: integration_test/b3_foundations_test.dart on A/I/M/W plus widget, golden and a11y suites. |
| CORE-008 | Localisation | B3 | ☐ | ☐ | ☐ | ☐ | B3 PR #2: pipeline (fragments, ICU checks, placeholder checks), pseudo-locales en-XA/ar-XB in tests, missing-string report in CI summary, Weblate components, locale formatting helpers. The 12 translations themselves come from Weblate (D5) |
| CORE-009 | Keyboard shortcuts | B3 | ☑ | ☑ | ☑ | ☑ | B3 PR #2: action catalogue (docs/06 §6.2) with platform defaults, remapping UI, conflict detection, cheat sheet on ? with copyable text; ShortcutScopeWidget for lanes Proven by CI on PR #2: integration_test/b3_foundations_test.dart on A/I/M/W plus widget, golden and a11y suites. |
| CORE-010 | Window management | C4 | — | ☐ | ☐ | ☐ |  |
| CORE-011 | Crash resilience | B1 | ☑ | ☑ | ☑ | ☑ | AIMW ☑ engine run 39355966616 (7bc4f9b, merge head).  |
| CORE-012 | Updates | C5 | ☐ | ☐ | ☐ | ☐ |  |
| CORE-013 | About and licences | C5 | ☐ | ☐ | ☐ | ☐ |  |
| CORE-014 | Backup/restore | B2 | ☐ | ☐ | ☐ | ☐ | B2: MHROBK1 file (PBKDF2-SHA256 + AES-256-GCM), cross-device restore by hash→path→name+size; backup screen. Saving/picking the file on A/I needs C4 StorageFacade. |
| CORE-015 | Privacy dashboard | B3 | ☑ | ☑ | ☑ | ☑ | A I M W ☑ ci run 39355442122 (PR #10, c747a1e): "CORE-015 dashboard reads the live network policy", "CORE-015 privacy dashboard lists every endpoint" on integration-android/-apple (iOS+macOS)/-windows. |

### 2. LIB — Library, indexing, search

| ID | Feature | Lane | A | I | M | W | Notes |
|---|---|---|:-:|:-:|:-:|:-:|---|
| LIB-001 | Unified index | B2 | ☐ | ☐ | ☐ | ☐ | B2: drift index (docs/05 §6 tables, FTS5), scanner isolate pool, viewport probe queue. Codec/duration fields fill from B1 through the `MediaProber` seam. |
| LIB-002 | Local sources | B2 | ☐ | ☐ | ☐ | ☐ | B2: local sources via StorageFacade grants (fakes in tests); Win32 fast path. ⛔ C4 StorageFacade (SAF/MediaStore, bookmarks, pickers). |
| LIB-003 | Scan performance | B2 | ☑ | ☐ | ☐ | ☐ | B2: 10 k files 1.0–2.5 s initial / 0.2–0.55 s incremental (desktop); pause/resume/cancel; manual/on-open/watch. Phone budget: device lab. A ☑ device batch 1 (Samsung SM-M176B, main 475f3df): b2_library_perf_test: initial 1951 ms, incremental 969 ms; c4a storage changes(). |
| LIB-004 | Folder mode and library mode | B2 | ☐ | ☐ | ☐ | ☐ | B2: folder browser + `ViewModeToggle` persisted per mode; C1–C3 place them in each mode. |
| LIB-005 | Search | B2 | ☑ | ☑ | ☑ | ☑ | B2: FTS5 prefix search, bm25, all doc 04 filters; 50 k items median 9.5 ms (desktop CI). Proven by CI run 39334797330 (9971a48): integration-android/-ios/-macos/-windows + test-unit; b2_library_sources_test.dart. |
| LIB-006 | Continue watching / recently added / recently played | B2 | ☐ | ☐ | ☐ | ☐ | B2: `HomeRow` continue/recently added/played/unwatched queries + widgets; C1–C3 place them; resume thumbnails from B1/C3. |
| LIB-007 | Playlists | B2 | ☐ | ☐ | ☐ | ☐ | B2: manual + smart playlists (rule builder, AND/OR, limit, sort), M3U/M3U8/PLS/XSPF/CUE parse (isolate, limits) and export. File import/export pickers → C4. |
| LIB-008 | Multiple queues | B2 | ☑ | ☑ | ☑ | ☑ | B2: named audio queues + one video queue, persisted, repeat/shuffle; queues screen. Proven by CI run 39334797330 (9971a48): integration-android/-ios/-macos/-windows + test-unit; b2_library_sources_test.dart. |
| LIB-009 | Tags and labels | B2 | ☑ | ☑ | ☑ | ☑ | B2: tags, colour labels, bulk apply; tag editor sheet. Proven by CI run 39334797330 (9971a48): integration-android/-ios/-macos/-windows + test-unit; b2_library_sources_test.dart. |
| LIB-010 | Watched/unwatched state and progress sync | B2 | ☐ | ☐ | ☐ | ☐ | B2: per-item progress/watched; `ProgressSyncTarget` seam for Jellyfin/Emby/Plex (C4 servers) and Trakt (needs owner client ID). |
| LIB-011 | Metadata scraping (video) | B2 | ☐ | ☐ | ☐ | ☐ | B2: filename parser, TMDB/TVDB clients through NetworkGateway, NFO, artwork cache, manual match. Live tests need owner API keys (§4). |
| LIB-012 | Collections | B2 | ☐ | ☐ | ☐ | ☐ | B2: series/season, albums/artists/genres/years/composers, TMDB collections; photo people/places come from C3. |
| LIB-013 | Parental PIN and hidden items | B2 | ☐ | ☐ | ☐ | ☐ | B2: PBKDF2 PIN (isolate), lockout, biometrics, locked sources/folders, hidden items excluded. Needs C4 SecureStorage/Biometrics facades on device. |
| LIB-014 | Duplicate finder | B2 | ☐ | ☐ | ☐ | ☐ | B2: exact hash, pHash (images), duration+size (video), chromaprint (audio) review UI; never deletes. ⛔ chromaprint native lib (B4). |
| LIB-015 | Statistics | B2 | ☑ | ☑ | ☑ | ☑ | B2: play counts, time played, top items, storage by type/source; statistics screen. Proven by CI run 39334797330 (9971a48): integration-android/-ios/-macos/-windows + test-unit; b2_library_sources_test.dart. |

### 3. FILE — File browser and management

| ID | Feature | Lane | A | I | M | W | Notes |
|---|---|---|:-:|:-:|:-:|:-:|---|
| FILE-001 | Browser | B2 | ☐ | ☐ | ☐ | ☐ | B2: browser with breadcrumbs, list, sort (name/date/size/type), selection. Grid thumbnails/resume bar use C1/C3 thumbnails. |
| FILE-002 | Operations | B2 | ☐ | ☐ | ☐ | ☐ | B2: rename/move/copy/new folder, delete to trash with undo, permanent delete only on request. OS trash/share/"open in" via C4 StorageFacade. |
| FILE-003 | Batch operations | B2 | ☐ | ☐ | ☐ | ☐ | B2: multi-select, batch rename with tokens, batch tag edit, batch image convert through ImagePipeline (C3). |
| FILE-004 | Archives | B2 | ⛔ | ⛔ | ⛔ | ⛔ | B2: libarchive VFS (ZIP/CBZ/RAR/7z/CBR) via ffigen. ⛔ libarchive archives from B4. |
| FILE-005 | Transfer | B2 | ☐ | ☐ | ☐ | ☐ | B2: Wi-Fi transfer page (shelf, 128-bit path token, QR). iOS Files integration and USB-C drives → C4. |
| FILE-006 | Subtitle/audio sidecars | B2 | ☐ | ☐ | ☐ | ☐ | B2: sidecar detection by name + language suffix; rename/move keeps them together. |

### 4.1 Formats and decoding

| ID | Feature | Lane | A | I | M | W | Notes |
|---|---|---|:-:|:-:|:-:|:-:|---|
| VID-001 | Containers | B1 | ☑ | ☑ | ☑ | ☑ | AIMW ☑ engine run 39355966616 |
| VID-002 | Video codecs | B1 | ⛔ | ⛔ | ⛔ | ⛔ | ⛔ no VC-1/VVC samples (LGPL FFmpeg has no encoders) (§3) |
| VID-003 | Audio codecs in video | B1 | ⛔ | ⛔ | ⛔ | ⛔ | ⛔ DTS-HD MA/HRA/DTS:X samples (§3) |
| VID-004 | Audio passthrough | B1 | ⛔ | — | ⛔ | ⛔ | ⛔ needs HDMI/SPDIF device lab (§3) |
| VID-005 | Playback edge cases | B1 | ☑ | ☑ | ☑ | ☑ | AIMW ☑ engine run 39355966616 (7bc4f9b, merge head).  |
| VID-006 | Network playback | B1 | ☑ | ☑ | ☑ | ☑ | AIMW ☑ engine run 39355966616 (7bc4f9b, merge head).  |
| VID-007 | DVD/Blu-ray folder playback | B1 | ☑ | ☑ | ☑ | ☑ | AIMW ☑ engine run 39355966616 (7bc4f9b, merge head).  |

### 4.2 Rendering, HDR, quality

| ID | Feature | Lane | A | I | M | W | Notes |
|---|---|---|:-:|:-:|:-:|:-:|---|
| VID-030 | GPU renderer | B1 | ⛔ | ⛔ | ⛔ | ⛔ | ⛔ device lab: zero-copy hwdec and the 4K60 budget (§3). CI proves frames reach the texture through the bridge on A I M W, and the backend reaches VideoStats.renderBackend |
| VID-031 | HDR10 / HLG | B1 | ⛔ | ⛔ | ⛔ | ⛔ | ⛔ native HDR: Flutter textures are 8-bit (§3); tone mapping passes W |
| VID-032 | HDR10+ | B1 | ⛔ | ⛔ | ⛔ | ⛔ | ⛔ no HDR10+ samples (§3) |
| VID-033 | Dolby Vision profile 8.1/8.4 | B1 | ⛔ | ⛔ | ⛔ | ⛔ | ⛔ no DV samples (§3) |
| VID-034 | Dolby Vision profile 5 | B1 | ⛔ | ⛔ | ⛔ | ⛔ | ⛔ no DV samples, libdovi (§3) |
| VID-035 | Dolby Vision profile 7 (MEL/FEL) | B1 | ⛔ | ⛔ | ⛔ | ⛔ | ⛔ no DV samples (§3) |
| VID-036 | Auto frame-rate and resolution matching | C1 | ☑ | — | ☐ | ☐ | Rel. 1.0 (TV UI 1.1) A ☑ device batch 1 (Samsung SM-M176B, main 475f3df): c4a_android_display_test 6/6. |
| VID-037 | Scaling and filters | C1 | ☐ | ☐ | ☐ | ☐ |  |
| VID-038 | User shaders | C1 | ☐ | ☐ | ☐ | ☐ |  |
| VID-039 | Frame interpolation | C1 | ☑ | ☐ | ☐ | ☐ | A ☑ device batch 2 (Samsung SM-M176B, main bd9dc8a): c1_video_player_test 33/33 (smooth motion asks about battery on a phone; a hot device pauses it). |
| VID-040 | ICC / display calibration | C1 | — | — | ☐ | ☐ |  |
| VID-041 | 3D and 360° | C1 | ☐ | ☐ | ☐ | ☐ |  |
| VID-042 | Screenshot, GIF and clip export | C1 | ☐ | ☐ | ☐ | ☐ |  |

### 4.3 Controls and ergonomics

| ID | Feature | Lane | A | I | M | W | Notes |
|---|---|---|:-:|:-:|:-:|:-:|---|
| VID-060 | Gesture set | C1 | ☑ | ☐ | — | — | A ☑ device batch 1 (Samsung SM-M176B, main 475f3df): c1_video_player_test 22/22. |
| VID-061 | Seek bar | C1 | ☑ | ☐ | ☐ | ☐ | A ☑ device batch 1 (Samsung SM-M176B, main 475f3df): c1_video_player_test 22/22. |
| VID-062 | Speed | C1 | ☑ | ☐ | ☐ | ☐ | A ☑ device batch 1 (Samsung SM-M176B, main 475f3df): c1_video_player_test 22/22. |
| VID-063 | Frame step, A-B loop, chapters, bookmarks | C1 | ☑ | ☐ | ☐ | ☐ | A ☑ device batch 1 (Samsung SM-M176B, main 475f3df): c1_video_player_test 22/22. |
| VID-064 | Resume and post-playback | C1 | ☑ | ☐ | ☐ | ☐ | A ☑ device batch 1 (Samsung SM-M176B, main 475f3df): c1_video_player_test 22/22. |
| VID-065 | Audio/subtitle track switching | C1 | ☑ | ☐ | ☐ | ☐ | A ☑ device batch 1 (Samsung SM-M176B, main 475f3df): c1_video_player_test 22/22. |
| VID-066 | Audio delay and volume | C1 | ☐ | ☐ | ☐ | ☐ |  |
| VID-067 | Picture-in-Picture | C1 | ☐ | ☐ | ☐ | ☐ |  |
| VID-068 | Background and audio-only playback | C1 | ☐ | ☐ | ☐ | ☐ |  |
| VID-069 | Sleep timer and auto-off | C1 | ☐ | ☐ | ☐ | ☐ |  |
| VID-070 | Orientation and display | C1 | ☐ | ☐ | — | — |  |
| VID-071 | Second screen / external display | C1 | ☐ | ☐ | ☐ | ☐ |  |
| VID-072 | Info overlay | C1 | ☑ | ☐ | ☐ | ☐ | A ☑ device batch 1 (Samsung SM-M176B, main 475f3df): c1_video_player_test 22/22. |
| VID-073 | Skip intro/credits | C1 | ☐ | ☐ | ☐ | ☐ |  |
| VID-074 | Remote control | C1 | ☐ | ☐ | ☐ | ☐ |  |

### 5. SUB — Subtitles

| ID | Feature | Lane | A | I | M | W | Notes |
|---|---|---|:-:|:-:|:-:|:-:|---|
| SUB-010 | Text formats | B1 → C1 | ☐ | ⛔ | ⛔ | ☐ | A W engine side passes (engine run 39355966616); UI → C1. I M ⛔ bootstrap libmpv (B4b) |
| SUB-011 | Image formats | B1 → C1 | ☐ | ⛔ | ⛔ | ☐ | A W engine side passes (engine run 39355966616); UI → C1. I M ⛔ bootstrap libmpv (B4b) |
| SUB-012 | Embedded and external | B1 → C1 | ☐ | ☐ | ☐ | ☐ | A I M W engine side passes (engine run 39355966616); UI → C1 |
| SUB-013 | Encoding detection | B1 → C1 | ☐ | ☐ | ☐ | ☐ | A I M W engine side passes (A: engine run 39364109420, Windows-1251, Shift-JIS, UTF-8 BOM on android.4; I M W: 39355966616); UI → C1. The A ⛔ is cleared |
| SUB-014 | Styling | B1 → C1 | ☐ | ☐ | ☐ | ☐ | A I M W engine side passes (engine run 39355966616); UI → C1 |
| SUB-015 | Timing | B1 → C1 | ☐ | ☐ | ☐ | ☐ | A I M W engine side passes (engine run 39355966616); UI → C1 |
| SUB-016 | Dual subtitles | B1 → C1 | ☐ | ⛔ | ⛔ | ☐ | A W engine side passes (engine run 39355966616); UI → C1. I M ⛔ bootstrap libmpv (B4b) |
| SUB-020 | Online download | C1 | ☐ | ☐ | ☐ | ☐ |  |
| SUB-030 | Subtitle editor | C1 | ☐ | ☐ | ☐ | ☐ |  |
| SUB-040 | Text-to-speech | C1 | ☑ | ☐ | ☐ | ☐ | A ☑ device batch 2 (Samsung SM-M176B, main bd9dc8a): c4a_android_text_test 2/2 (offline voices, short utterance), c1_video_player_test 33/33, engine_test ADR-031 5/5. |
| SUB-050 | Auto-sync (audio-based) | C1 | ☐ | ☐ | ☐ | ☐ | A ⛔ C1 side merged (#49: VAD + FFT cross-correlation, ±60 s, 8 frame-rate ratios, preview with Undo); waits on B1 decodeAudio (ADR-032). B1 decodeAudio merged (#61); A device batch 2 FAILED (engine_test ADR-032 0/5: PathAccessException opening /proc/self/fd/N on Android 16); B1 fix, re-run in batch 3. |
| SUB-051 | OCR of image subtitles | C1 | ☐ | ☐ | ☐ | ☐ |  |
| SUB-052 | Auto-captions (speech-to-text) | C1 | ☐ | ☐ | ☐ | ☐ |  |
| SUB-053 | Translation | C1 | ☐ | ☐ | ☐ | ☐ |  |

### 6.1 Formats and output

| ID | Feature | Lane | A | I | M | W | Notes |
|---|---|---|:-:|:-:|:-:|:-:|---|
| AUD-001 | Formats | B1 | ⛔ | ⛔ | ⛔ | ⛔ | ⛔ no APE/TAK/MPC/SACD ISO/MIDI samples (§3); all other formats pass A W. I M also bootstrap (B4b) |
| AUD-002 | Gapless | B1 | ☑ | ⛔ | ⛔ | ☑ | A W ☑ engine run 39355966616; I M ⛔ bootstrap libmpv (B4b) |
| AUD-003 | Crossfade | B1 | ☑ | ☑ | ☑ | ☑ | AIMW ☑ engine run 39355966616 (7bc4f9b, merge head).  |
| AUD-004 | Loudness | B1 | ☑ | ⛔ | ⛔ | ☑ | A W ☑ engine run 39355966616; I M ⛔ bootstrap libmpv (B4b) |
| AUD-005 | DSP chain | B1 | ☑ | ⛔ | ⛔ | ☑ | A W ☑ engine run 39355966616; I M ⛔ bootstrap libmpv (B4b) |
| AUD-006 | Output quality indicator | B1 | ☑ | ☑ | ☑ | ☑ | AIMW ☑ engine run 39355966616 (7bc4f9b, merge head).  |
| AUD-040 | Bit-perfect Android | B1 | ⛔ | — | — | — | ⛔ USB DAC device lab (§3) |
| AUD-041 | Bit-perfect Apple | B1 | — | ⛔ | ⛔ | — | ⛔ device lab (§3) |
| AUD-042 | Bit-perfect Windows | B1 | — | — | — | ⛔ | ⛔ ASIO licence; exclusive mode needs device lab (§3) |
| AUD-043 | DSD | B1 | ⛔ | ⛔ | ⛔ | ⛔ | ⛔ native DSD/DoP (§3); DSD→PCM passes W |
| AUD-044 | Bluetooth | B1 | ☐ | ⛔ | ⛔ | ⛔ | ⛔ C4 media session; device lab (§3) A unblocked by #24 (Android focus/noisy/outputs facade passes on Samsung); engine wiring B1. |
| AUD-045 | Audio focus and interruptions | B1 | ☐ | ⛔ | ⛔ | ⛔ | ⛔ C4 audio focus (§3) A unblocked by #24 (Android focus/noisy/outputs facade passes on Samsung); engine wiring B1. |
| AUD-046 | Visualiser | C2 | ☐ | ☐ | ☐ | ☐ | A ⛔ C2 side merged (#37); waits on B1 PlaybackEngine.audioTap (ADR-027; B1's branch lane/b1-adr027 is ready locally). B1 audioTap merged (#55); A device batch 2 FAILED (engine_test AUD-046 0/3: audio tap delivers 0 frames); B1 fix, re-run in batch 3. |

### 6.2 Music library and player UI

| ID | Feature | Lane | A | I | M | W | Notes |
|---|---|---|:-:|:-:|:-:|:-:|---|
| MUS-001 | Library views | C2 | ☑ | ☐ | ☐ | ☐ | A ☐: #26's device run used file paths only; tags from SAF/MediaStore sources were missing (fixed in #34). Re-test in device batch 1. A ☑ device batch 1 (Samsung SM-M176B, main 475f3df): c2_music_test 4/4 (SAF/MediaStore tags after #34). |
| MUS-002 | Tag reading | C2 | ☑ | ☐ | ☐ | ☐ | A ☐: #26's device run used file paths only; tags from SAF/MediaStore sources were missing (fixed in #34). Re-test in device batch 1. A ☑ device batch 1 (Samsung SM-M176B, main 475f3df): c2_music_test 4/4 (after #34). |
| MUS-003 | Tag editing | C2 | ☐ | ☐ | ☐ | ☐ |  |
| MUS-004 | Art | C2 | ☑ | ☐ | ☐ | ☐ | A ☑ PR #26: c2_music_test 4/4 on Samsung SM-M176B (Android 16), tools/check 369. |
| MUS-005 | Lyrics | C2 | ☑ | ☐ | ☐ | ☐ | A ☑ device batch 1 (Samsung SM-M176B, main 475f3df): c2_lyrics_test 2/2. |
| MUS-006 | Now Playing | C2 | ☑ | ☐ | ☐ | ☐ | A ☑ device batch 1 (Samsung SM-M176B, main 475f3df): c2_now_playing_test 2/2. |
| MUS-007 | Queues | C2 | ☑ | ☐ | ☐ | ☐ | A ☑ PR #26: c2_music_test 4/4 on Samsung SM-M176B (Android 16), tools/check 369. |
| MUS-008 | Smart playlists | C2 | ☑ | ☐ | ☐ | ☐ | A ☑ device batch 2 (Samsung SM-M176B, main bd9dc8a): c2_playlists_car_test 2/2 (smart playlist rules on the platform SQLite). |
| MUS-009 | Scrobbling | C2 | ☐ | ☐ | ☐ | ☐ |  |
| MUS-010 | Fingerprinting | C2 | ☐ | ☐ | ☐ | ☐ |  |
| MUS-011 | Sleep timer and alarms | C2 | ☑ | ☐ | ☐ | ☐ | A ☑ device batch 2 (Samsung SM-M176B, main bd9dc8a): c4a_android_car_alarm_test 4/4 (alarm fires into the running app; opening from an alarm delivers its id) and c2_now_playing_test (sleep timer, batch 1). |
| MUS-012 | Widgets and quick controls | C2 | ☑ | ☐ | ☐ | ☐ | A ☑ device batch 2 (Samsung SM-M176B, main bd9dc8a): c4a_android_home_widgets_test 3/3 (widget shows the track, clears on stop, buttons reach the player). |
| MUS-013 | Car | C2 | ☐ | ☐ | — | — |  |
| MUS-014 | Internet radio | C2 | ☐ | ☐ | ☐ | ☐ |  |
| MUS-015 | Watch companion | C2 | 1.1 | 1.1 | — | — | Rel. 1.1 |

### 6.3 Podcasts and audiobooks

| ID | Feature | Lane | A | I | M | W | Notes |
|---|---|---|:-:|:-:|:-:|:-:|---|
| POD-001 | Audiobook/podcast mode | C2 | ☐ | ☐ | ☐ | ☐ |  |
| POD-002 | Podcast feeds | C2 | ☐ | ☐ | ☐ | ☐ |  |
| POD-003 | Audiobookshelf client | C2 | ☐ | ☐ | ☐ | ☐ |  |

### 7. IMG — Images and gallery

| ID | Feature | Lane | A | I | M | W | Notes |
|---|---|---|:-:|:-:|:-:|:-:|---|
| IMG-001 | Formats | C3 | ☐ | ☐ | ☐ | ☐ |  |
| IMG-002 | HDR images | C3 | ☐ | ☐ | ☐ | ☐ |  |
| IMG-003 | Gallery performance | C3 | ☑ | ☐ | ☐ | ☐ | A ☑ device batch 2 (Samsung SM-M176B, main bd9dc8a): c3_photos_test 5/5 (thumbnails through the worker pool and cache; 50 000-item timeline scrolls without dropped frames). |
| IMG-004 | Viewer | C3 | ☑ | ☐ | ☐ | ☐ | A ☑ device batch 2 (Samsung SM-M176B, main bd9dc8a): c3_photos_test 5/5 (regions of a large image decode at 1:1 and reduced). |
| IMG-005 | Organisation | C3 | ☐ | ☐ | ☐ | ☐ |  |
| IMG-006 | Metadata | C3 | ☑ | ☐ | ☐ | ☐ | A ☑ device batch 2 (Samsung SM-M176B, main bd9dc8a): c3_photos_test 5/5 (metadata written to a JPEG reads back). |
| IMG-007 | Map | C3 | ☐ | ☐ | ☐ | ☐ | Map view and online tiles removed by the owner (ADR-041, 2026-10-21); Places tab, offline gazetteer and set/clear location (search or coordinates) remain; C3 removes the map code |
| IMG-008 | Compare | C3 | ☐ | ☐ | ☐ | ☐ |  |
| IMG-009 | Editing | C3 | ☐ | ☐ | ☐ | ☐ |  |
| IMG-010 | Batch | C3 | ☐ | ☐ | ☐ | ☐ |  |
| IMG-011 | Vault | C3 | ☐ | ☐ | ☐ | ☐ |  |
| IMG-012 | Slideshow | C3 | ☐ | ☐ | ☐ | ☐ |  |
| IMG-013 | Duplicates | C3 | ☐ | ☐ | ☐ | ☐ |  |
| IMG-014 | Trash | C3 | ☐ | ☐ | ☐ | ☐ |  |
| IMG-015 | Sharing and output | C3 | ☐ | ☐ | ☐ | ☐ |  |
| IMG-016 | Sources | C3 | ☐ | ☐ | ☐ | ☐ |  |
| IMG-017 | Archives | C3 | ☐ | ☐ | ☐ | ☐ |  |
| IMG-018 | Screensaver / ambient | C3 | 1.1 | — | ☐ | ☐ |  |

### 8. NET — Sources, protocols, servers

| ID | Feature | Lane | A | I | M | W | Notes |
|---|---|---|:-:|:-:|:-:|:-:|---|
| NET-001 | SMB2/3 | B2 | ⛔ | ⛔ | ⛔ | ⛔ | B2: libsmb2 VFS (isolate), mDNS/WS-Discovery/NetBIOS discovery, keychain credentials. ⛔ libsmb2 archive (B4) + network-env CI job (orchestrator). |
| NET-002 | NFS v3/v4 | B2 | ⛔ | ⛔ | ⛔ | ⛔ | B2: libnfs VFS, manual + discovered mounts. ⛔ libnfs archive (B4) + network-env CI job. |
| NET-003 | WebDAV | B2 | ☐ | ☐ | ☐ | ☐ | B2: WebDAV (Basic/Digest, ranges, HTTPS pinning prompt) — unit tests vs local DAV server; Nextcloud in network env. Live servers need the network-env job. |
| NET-004 | FTP/FTPS/SFTP | B2 | ☐ | ☐ | ☐ | ☐ | B2 (ADR-017): plain FTP in Dart on every platform; FTPS (explicit via connectPlain+upgrade, implicit, data channels resuming the control session) in Dart over TlsSocketFacade with SHA-256 pinning; SFTP VFS over SftpFacade (list/read/mkdir/upload/rename/delete) with host-key TOFU, secrets by SecureStorage reference; libssh2+WinCNG bindings for the Windows facade. Tested against a local FTP/FTPS server, vsftpd (network env) and facade fakes. Waits for C4 facades (sequencing). |
| NET-005 | DLNA/UPnP | B2 | ☐ | ☐ | ☐ | ☐ | B2: SSDP + ContentDirectory browse, opt-in renderer (DMR). iOS needs the multicast entitlement (owner) and C4 multicast lock on Android. |
| NET-006 | HTTP(S)/HLS/DASH/RTSP/RTMP | B2 | ☐ | ☐ | ☐ | ☐ | B2: URL open, headers/UA, HTTP range reader; playback of HLS/DASH/RTSP/RTMP is B1 engine. |
| NET-007 | Cloud drives | B2 | ☐ | ☐ | ☐ | ☐ | B2: OAuth PKCE + REST for Google Drive, OneDrive, Dropbox, Box, pCloud, Yandex. ⛔ MEGA, Proton Drive (§3). Needs owner OAuth client IDs; AuthBrowser from C4. |
| NET-010 | Jellyfin | C4 | ☐ | ☐ | ☐ | ☐ |  |
| NET-011 | Emby | C4 | ☐ | ☐ | ☐ | ☐ |  |
| NET-012 | Plex | C4 | ☐ | ☐ | ☐ | ☐ |  |
| NET-013 | Subsonic/OpenSubsonic/Navidrome/Airsonic/Gonic | C4 | ☐ | ☐ | ☐ | ☐ |  |
| NET-014 | Immich | C4 | ☐ | ☐ | ☐ | ☐ |  |
| NET-015 | Nextcloud | C4 | ☐ | ☐ | ☐ | ☐ |  |
| NET-016 | Audiobookshelf | C4 | ☐ | ☐ | ☐ | ☐ |  |
| NET-017 | Mediahro-to-Mediahro | C4 | ☐ | ☐ | ☐ | ☐ |  |
| NET-018 | Offline downloads | B2 | ☐ | ☐ | ☐ | ☐ | B2: downloads with resume, quota, expiry; downloads screen. |
| NET-019 | Connection health | B2 | ☐ | ☐ | ☐ | ☐ | B2: latency/throughput test, cache-size suggestion, metered warning via `NetworkStatus` seam (C4). |

### 9. CAST — Casting and external playback

| ID | Feature | Lane | A | I | M | W | Notes |
|---|---|---|:-:|:-:|:-:|:-:|---|
| CAST-001 | Google Cast | C4 | ☐ | ☐ | ☐ | ☐ |  |
| CAST-002 | AirPlay | C4 | — | ☐ | ☐ | — |  |
| CAST-003 | DLNA renderer push | C4 | ☐ | ☐ | ☐ | ☐ |  |
| CAST-004 | External display | C4 | ☐ | ☐ | ☐ | ☐ |  |
| CAST-005 | Local transcoding | B1 | ☑ | ⛔ | ⛔ | ☑ | A W ☑ engine run 39355966616 (OS H.264: h264_mediacodec, h264_mf); I M ⛔ bootstrap has no encoders (B4b) |

### 10. SYS — Platform integration

| ID | Feature | Lane | A | I | M | W | Notes |
|---|---|---|:-:|:-:|:-:|:-:|---|
| SYS-001 | Media session | C4 | ☑ | ☐ | ☐ | ☐ | A ☑ PR #24: c4a_android_media_test 9/9 on Samsung SM-M176B (Android 16), tools/check 325. |
| SYS-002 | Notifications/lock screen | C4 | ☑ | ☐ | ☐ | ☐ | A ☑ PR #24: c4a_android_media_test 9/9 on Samsung SM-M176B (Android 16), tools/check 325. |
| SYS-003 | Shortcuts/intents | C4 | ☐ | ☐ | ☐ | ☐ |  |
| SYS-004 | Share targets | C4 | ☐ | ☐ | ☐ | ☐ |  |
| SYS-005 | File provider / Files integration | C4 | — | ☐ | 1.1 | 1.1 |  |
| SYS-006 | Foreground service & battery | C4 | ☑ | — | — | — | A ☑ PR #24: c4a_android_media_test 9/9 on Samsung SM-M176B (Android 16), tools/check 325. |
| SYS-007 | Storage access | C4 | ☑ | ☐ | ☐ | ☐ | A ☑ PR #23: c4a_android_storage_test 13/13 on Samsung SM-M176B (Android 16), tools/check 321 pass. |
| SYS-008 | Accessibility services | C4 | ☐ | ☐ | ☐ | ☐ |  |
| SYS-009 | Input | C4 | ☐ | ☐ | ☐ | ☐ |  |
| SYS-010 | TV mode | C4 | 1.1 | — | — | — | Rel. 1.1 |
| SYS-011 | Foldables/large screens | C4 | ☐ | ☐ | — | — |  |

### 11. SUP — Supporter programme (free app; nothing gated)

| ID | Feature | Lane | A | I | M | W | Notes |
|---|---|---|:-:|:-:|:-:|:-:|---|
| SUP-001 | Support page | C5 | ☐ | ☐ | ☐ | ☐ |  |
| SUP-002 | Store rails | C5 | ☐ | ☐ | ☐ | ☐ |  |
| SUP-003 | Web rail | C5 | ☐ | ☐ | ☐ | ☐ |  |
| SUP-004 | Perks (cosmetic only) | C5 | ☐ | ☐ | ☐ | ☐ |  |
| SUP-005 | Ask policy | C5 | ☐ | ☐ | ☐ | ☐ |  |
| SUP-006 | Transparency | C5 | ☐ | ☐ | ☐ | ☐ |  |

### 12. PRIV — Privacy and security

| ID | Feature | Lane | A | I | M | W | Notes |
|---|---|---|:-:|:-:|:-:|:-:|---|
| PRIV-001 | Zero telemetry by default | C5 | ☐ | ☐ | ☐ | ☐ |  |
| PRIV-002 | Opt-in crash reports | C5 | ☐ | ☐ | ☐ | ☐ |  |
| PRIV-003 | Opt-in usage analytics | C5 | ☐ | ☐ | ☐ | ☐ |  |
| PRIV-004 | Network allow-list | C5 | ☐ | ☐ | ☐ | ☐ |  |
| PRIV-005 | Parsing safety | C5 | ☐ | ☐ | ☐ | ☐ |  |
| PRIV-006 | Credentials | C5 | ☐ | ☐ | ☐ | ☐ |  |
| PRIV-007 | Vault | C3 | ☐ | ☐ | ☐ | ☐ |  |
| PRIV-008 | App lock | C5 | ☐ | ☐ | ☐ | ☐ |  |

### 13. B2B — Managed deployment, kiosk, engine

| ID | Feature | Lane | A | I | M | W | Notes |
|---|---|---|:-:|:-:|:-:|:-:|---|
| B2B-001 | Managed configuration | C5 | ☐ | ☐ | ☐ | ☐ |  |
| B2B-002 | Kiosk/signage mode | C5 | ☐ | ☐ | ☐ | ☐ |  |
| B2B-003 | Headless control API | C5 | ☐ | ☐ | ☐ | ☐ |  |
| B2B-004 | Mediahro Engine SDK | C5 | ☐ | ☐ | ☐ | ☐ | Rel. 1.0 (docs/samples 1.1) |
| B2B-005 | Audit and compliance | C5 | ☐ | ☐ | ☐ | ☐ |  |
| B2B-006 | White-label hooks | C5 | ☐ | ☐ | ☐ | ☐ |  |

## 3. Blockers

| Since | Lane | IDs / platforms | Blocker | Needs | Workaround in place |
|---|---|---|---|---|---|
| 2026-10-20 | B3 | CORE-001 mode-switch budget (A I) | Flutter profile mode does not run on emulators or simulators | Device lab profile run of b3_shell_perf_test.dart (§4) | Functional mode-switch tests pass in debug on A I; budget proven in profile on W (18.2 ms) |
| 2026-10-19 | B1 | VID-031 native HDR on HDR displays (A I M W) | Flutter external textures are 8-bit only (Windows `FlutterDesktopGpuSurfaceDescriptor` BGRA/RGBA, Apple `CVPixelBuffer` BGRA, Android `SurfaceProducer` RGBA8), so a 10-bit/PQ frame cannot reach an HDR swap chain through the compositor | ADR: Flutter engine support for 10-bit/FP16 external textures, or an HDR platform-view surface | Tone mapping to SDR on every platform (bt.2390 default, all six curves, peak detection), tested on CI |
| 2026-10-19 | B1 | VID-032…035 (A I M W) | No CC0/CC BY Dolby Vision (P5, P7 MEL/FEL, P8.1/8.4) or HDR10+ samples in `test-media/corpus`; DV P5 reshaping also needs libplacebo built with libdovi | Owner or a D lane: source licensed samples into Git LFS; B4: libdovi in libplacebo | Detection (profile, HDR10+ MaxRGB, P7 notice) unit-tested; suite runs automatically once samples land (`category: hdr-lfs`) |
| 2026-10-19 | B1 | VID-001 ISO images; VID-002 VC-1/VVC/HAP; VID-003 DTS-HD MA/HRA/DTS:X; AUD-001 APE/TAK/MPC/SACD ISO/MIDI (A I M W) | LGPL FFmpeg has no encoders for these, so the generated corpus lacks samples; ISO images need a UDF reader (B1 next); MIDI needs a soundfont synth in the deps build | Licensed samples in `test-media/corpus`; B4: a MIT/LGPL soundfont synth (e.g. TinySoundFont) | Every other container/codec of these rows passes on CI from the generated corpus |
| 2026-10-19 | B1 | VID-004, AUD-040, AUD-041, AUD-042, AUD-044 (hardware paths) | HDMI/SPDIF passthrough, USB DAC bit-perfect, exclusive device modes and Bluetooth codecs need real devices; CI runners have none | Device lab (§4) manual checklists, docs/11 §4 | Engine configuration (audio-spdif, audio-exclusive, rate switching, Android mixer/iOS session requests, BT latency offset) tested on CI |
| 2026-10-19 | B1 | AUD-042 ASIO (W) | mpv has no ASIO output and the Steinberg ASIO SDK is GPLv3 or proprietary | Owner: Steinberg licence agreement decision; then an ASIO AO | WASAPI exclusive and shared via mpv |
| 2026-10-19 | B1 | AUD-043 native DSD/DoP (A I M W) | mpv's audio outputs cannot emit DoP or native DSD | ADR: custom DoP output stage | DSD→PCM with selectable low-pass, tested on CI |
| 2026-10-19 | B1 | AUD-044 metadata/absolute volume, AUD-045 focus and interruptions | Media session, AVRCP and audio focus belong to C4's platform modules | Lane C4 (Phase C) | Engine exposes pause/volume/latency hooks |
| 2026-10-19 | B1 | VID-001/002/003, SUB-010/011, AUD-001/002/004/005 on A I M; SUB-016 on I M | The ADR-004 bootstrap prebuilts for Android and Apple (media_kit, mpv 0.36–0.38) lack libopenmpt, the lavfi audio filters (EQ, limiter, ebur128) and, on Android, all encoders (CAST-005); their gapless join loses ~60 ms; on Apple, libass ignores Matroska font attachments, external PGS (.sup) draws nothing and `secondary-sub-text` stays empty (fine on mpv master and the mediahro-deps Android mpv). Since 2026-10-19 the bootstrap uses the LGPL "full" variants (all decoders/demuxers) instead of "default", which lacked MXF/RealMedia, FFV1/HAP/ProRes/E-AC-3/TrueHD/SAMI | Lane B4: mediahro-deps archives (FFmpeg 8.1 LGPL full config, mpv 0.41+) pinned in deps.lock; the plugin builds pick them up unchanged | Same suites pass on Windows (LGPL build with the full FFmpeg); the A/I/M jobs report each missing component |
| 2026-10-20 | B1 + B4a | SUB-013 (A) | ~~Android bionic iconv converts only UTF-8/16/32, ASCII and Latin-1, so mpv cannot convert cp1251, Shift-JIS, GBK, Big5, EUC-KR subtitles even when uchardet detects them or the user forces a code page~~ **Resolved** by mediahro-deps v2026.10.3-android.4 (libiconv): engine run 39364109420 passes Windows-1251 / Shift-JIS / UTF-8 BOM on Android | B4a: GNU libiconv (LGPL-2.1, shared) in the Android archive, mpv and FFmpeg built against it | UTF-8 and Latin-1 subtitles work; others show mojibake |
| 2026-10-19 | B1 | Bootstrap libmpv (ADR-004) on all platforms | `deps.lock` has no mediahro-deps release yet; the Windows bootstrap release (zhongfly/mpv-winbuild 2026-10-19) is kept upstream for about 30 days | Lane B4 archives pinned in deps.lock | Plugin builds already prefer `.deps-cache/<target>` (lib/*.so, bin/*.dll, *.xcframework) |
| 2026-10-20 | B1 + B4a | All Android cells of PR #3 (install-size budget, docs/11 §5) | APK with all mediahro-deps libraries is 102.3 MB per ABI vs the 40 MB budget | B4a: per-library size table, strip, FFmpeg `--disable-everything` + explicit components, trimmed libvips; B1: no duplicate libraries | None — budget is not relaxed; owner sees the numbers if 40 MB proves impossible |
| 2026-10-19 | B3 | CORE-001 A (API 33–35) | Predictive back below API 36 needs `android:enableOnBackInvokedCallback="true"` in the manifest (app/android, lane C4). API 36 has it by default; the shell does not intercept back | Owner: lane C4 (Phase C): manifest flag | Theme already uses predictive-back page transitions |
| 2026-10-19 | B3 | CORE-007 W | Mica needs the Windows runner to set `DWMWA_SYSTEMBACKDROP_TYPE` and extend the frame (app/windows, lane C4) | Owner: lane C4 (Phase C): runner change, then report it through `platformAppearanceProvider.micaActive` | Shell and sidebar are transparent when Mica is reported; solid surfaces until then |
| 2026-10-19 | Orchestrator (M0) | Local Android | Android SDK licences are not all accepted on this machine (`flutter doctor --android-licenses`) | Owner: accept them (agents do not accept terms) | Debug and release builds still succeed with the installed components |
| 2026-10-19 | B2 | NET-001, NET-002, FILE-004, LIB-014 (chromaprint) — all platforms | Native libraries (libsmb2, libnfs, libarchive, libebur128, chromaprint, uchardet; libssh2 for Windows) are not yet published for every platform (Android pinned) as `mediahro-deps` archives; the ffigen bindings and contract tests skip without them | B4: publish and pin the archives; orchestrator: add the `network-env` CI job (PR #1 "Orchestrator changes needed") | Bindings, VFS clients and contract tests written; `packages/mediahro_ffi/test/network` docker-compose env + build_native.sh build them on Linux CI |
| 2026-10-19 | B2 | LIB-002, FILE-002 (trash/share), CORE-014 (file save), LIB-007 (import/export pickers), LIB-013 (secure storage/biometrics), FILE-005 (Files/USB) — A/I (and M/W pickers) | Native storage, pickers, secure storage, biometrics and auth browser are lane C4's facades | C4: StorageFacade, SecureStorageFacade, BiometricsFacade, AuthBrowser, NetworkStatus, multicast lock | B2 codes against the facades with fakes; `_optional` degrades to "Not available on this device" |
| 2026-10-19 | B2 | NET-007 MEGA, Proton Drive — all platforms | MEGA uses a proprietary client-side-encrypted protocol with no REST API usable without its SDK; Proton Drive has no public API (doc 04: "where API exists") | Upstream: a documented public API | Not offered in the Add cloud list; the other six providers ship |
| 2026-10-19 | B4a | NET-004 (A): SFTP and FTPS | ~~libssh2 needs a crypto backend and curl FTPS needs TLS on Android~~ — **resolved by ADR-017** (2026-10-20): SFTP via sshj over JCA behind `SftpFacade`, FTPS over `TlsSocketFacade`; libssh2 is Windows-only (WinCNG) and curl has no TLS backend on Android/Apple (mediahro-deps#2) | Implementation: C4 / B2 per ADR-017 | — |
| 2026-10-19 | B4a | CAST-001 (FOSS flavour; Open Screen sender on A, M, W) | ~~Open Screen libcast needs GN + BoringSSL~~ — **resolved by ADR-017**: openscreen-libcast removed from mediahro-deps (mediahro-deps#2); a Dart CASTv2 sender over `TlsSocketFacade` replaces it | Implementation: C4 per ADR-017 | — |

## 4. Human-owned tasks (CLAUDE.md §6 — for the owner; never attempted by agents)

| Task | Needed by | Blocks | State |
|---|---|---|---|
| Professional trademark clearance and USPTO ITU filing (classes 9, 42), then EUIPO/UK | Before public beta | Store listings under the name | Open |
| Entity formation; store developer accounts in the entity name (Apple, Google Play incl. D-U-N-S, Microsoft Partner Center); name reservations | Before M7 | All store submissions, IAP products | Open |
| Signing certificates and secrets: Apple distribution + Developer ID (G2 Sub-CA), Fastlane `match` repo, Play upload key, Azure Artifact Signing / OV cert, Sparkle EdDSA key, F-Droid key registration; add to GitHub environments | Before M7 | Signed CI artefacts, TestFlight, notarisation | Open |
| Apple entitlement requests: multicast networking (SSDP/DLNA), CarPlay audio | M1 (request early) | NET-005, CAST-003 on iOS; MUS-013 on iOS | Open |
| *Optional, speeds up Phase C/D:* more macOS CI capacity, either a self-hosted Mac runner (e.g. a Mac mini registered to the repo) or paid GitHub larger macOS runners. GitHub's free tier allows 5 concurrent macOS jobs, and every iOS/macOS proof (C4b, B1, C1–C5) queues for them | Now | Wall-clock time of every Apple-bound PR | Open (owner decision) |
| Counsel: confirm export-compliance answers (App Store `ITSAppUsesNonExemptEncryption`, encryption inventory) given ADR-017 and the BoringSSL embedded in the Flutter engine for dart:io TLS | Before App Store submission | App Store submission | Open |
| Source licensed Dolby Vision (P5, P7 MEL/FEL, P8.1/8.4) and HDR10+ test samples into Git LFS (test-media/), or approve a vendor | Before M3 gate | VID-032…035 on all platforms | Open |
| Decide on a Steinberg ASIO SDK licence (GPLv3 or proprietary agreement) | Before M4 gate | AUD-042 ASIO path (WASAPI exclusive works without it) | Open |
| Third-party API keys and terms acceptance: OpenSubtitles.com, TMDB, TVDB, AcoustID, Last.fm, ListenBrainz, Libre.fm, OSM tile provider, IntroDB, Google Cast receiver app ID | Before beta | SUB-020, LIB-011, MUS-009/010, IMG-007, VID-073, CAST-001 live tests | Open |
| MDM test tenant (Android Enterprise, Apple MDM, Intune) | M7 | B2B-001/002 manual verification | Open |
| Device lab per docs/11 §3 (HDR panels, DACs, receivers, car head units, foldables) | M8 | Manual release checklists | Open |
| Self-hosted Sentry/GlitchTip and Aptabase instances (EU VPS) and their hostnames | M7 | PRIV-002/003 live endpoint | Open |
| Domain `mediahro.com` (site, `/support`, `/privacy`, downloads) and merchant of record (Paddle/Polar), GitHub Sponsors, Liberapay | M7 | SUP-003, PRIV policy URLs | Open |
| Android developer verification registration incl. F-Droid signing key | Before 2027 | Sideload/F-Droid installs in enforced regions | Open |
| EU DSA trader information; export-compliance answers in App Store Connect | Before submission | EU availability, App Store submission | Open |
| Play closed test: recruit 12 testers for 14 continuous days | M7 | Play production access | Open |
| Beta programme recruitment (≥ 500 users across platforms) | M8 | Release gate 5 | Open |
| Final store submissions (agents prepare packs; owner presses submit) and human sign-off at each milestone gate | Each gate / M8 | Release gate 12 | Open |
| OAuth client IDs (and app registrations) for Google Drive, OneDrive, Dropbox, Box, pCloud, Yandex Disk, and Trakt; redirect = loopback | Before beta | NET-007, LIB-010 (Trakt) live tests | Open |
| TMDB and TVDB project API keys (users may still supply their own) | Before beta | LIB-011, LIB-012 live tests | Open |
| ~~Owner: host tiles.mediahro.com serving OSM-derived raster tiles~~ | n/a | IMG-007 | Cancelled — ADR-041 (photo map view removed by the owner, 2026-10-21) |

## 5. Release gates (docs/11 §7)

| # | Gate | State |
|---|---|---|
| 1 | All doc 04 `1.0` AC tests green on all listed platforms | ☐ |
| 2 | Media corpus 100 % pass (nightly report attached) | ☐ |
| 3 | Performance budgets met on reference devices | ☐ |
| 4 | Zero P0/P1 open | ☐ |
| 5 | Crash-free sessions ≥ 99.5 % over beta (≥ 500 beta users) | ☐ (needs owner: beta programme) |
| 6 | Accessibility audit complete; conformance report updated | ☐ |
| 7 | Licence scan and SBOM clean; configure flags verified | ☐ |
| 8 | Store checklists (doc 07 §7) complete; metadata and screenshots reviewed | ☐ |
| 9 | Localisation complete for 12 launch languages | ☐ |
| 10 | Security review of network/parsing code; fuzz targets stable | ☐ |
| 11 | Release notes written; rollback plan noted | ☐ |
| 12 | Human owner sign-off | ☐ (owner) |

## 6. ADR requests (resolved by the orchestrator into docs/05 §12)

| Requested by | Topic | State |
|---|---|---|
| B1 | Apple render path: mpv's OpenGL (ES) render API into IOSurface `CVPixelBuffer`s (mpv exposes no Metal/Vulkan render API), instead of MoltenVK/Metal in docs/05 §4.3 | Accepted, ADR-021 (2026-10-20) |
| B1 | Windows render path uses mpv's D3D11 render API (mpv master after 0.41.0, pinned 6a262d11f6): mediahro-deps must build that mpv or newer | Accepted, ADR-021 (2026-10-20) |
| B1 | Android render path: `vo=gpu-next` drawing into the `SurfaceProducer` Surface (`wid`, Vulkan then GL) instead of `mpv_render_context` | Accepted, ADR-021 (2026-10-20) |
| B1 | VirtualFile stream protocol: a C shim compiled by the engine's Dart build hook (native assets) blocks mpv's demuxer thread while Dart serves reads | Accepted, ADR-021 (2026-10-20) |
| B1 | Engine example app + `.github/workflows/engine.yml` are the per-platform CI proof for the engine (conformance suites shared with desktop FFI tests) | Accepted, ADR-021 (2026-10-20) |
| B1 | CAST-005 transcodes with libmpv's encoding mode and OS H.264 encoders (MediaCodec, VideoToolbox, Media Foundation) + FFmpeg AAC; remux plans transcode until mediahro-deps ships dynamic libavformat | Accepted, ADR-021 (2026-10-20) |
| B1 | VID-007: own IFO/MPLS/CLPI parsers; DVD titles play as a VirtualFile over cell ranges, Blu-ray as EDL files; chapters via `OpenOptions.chapters` | Accepted, ADR-021 (2026-10-20) |
| B1 | AUD-004 scan uses FFmpeg's `ebur128` filter (the libebur128 algorithm) inside a headless mpv core instead of libebur128 FFI | Accepted, ADR-021 (2026-10-20) |
| B1 | SUB-016: mpv has no secondary subtitle size; the engine exposes `secondarySubtitleText` for C1 to draw at an independent size | Accepted, ADR-021 (2026-10-20) |
| B1 | `sub-font-provider=auto` (CoreText, DirectWrite, fontconfig per platform) instead of fontconfig on Windows/Android in docs/05 §4.1 | Accepted, ADR-021 (2026-10-20) |
| B4a | TLS / crypto for native protocol clients on Android (curl FTPS, libssh2 SFTP): one crypto/TLS library on Android only, or SFTP/FTPS through the Android platform module over JCA (§3) | Resolved by ADR-017 (2026-10-20) |
| B4a | TLS stack of the Open Screen Cast sender: libcast requires BoringSSL (§3) | Resolved by ADR-017 (2026-10-20) |
| B4a | The Flutter engine (`libflutter.so`, `Flutter.framework`, `flutter_windows.dll`) statically contains BoringSSL for `dart:io` TLS. docs/05 §4.1 ("no OpenSSL/mbedTLS ships") and the docs/07 rule 12 encryption inventory should state this exception explicitly | Resolved by ADR-017 (2026-10-20) |

## 7. Log

| Date | Event |
|---|---|
| 2026-10-21 | **Owner scope decision, ADR-041:** "Disable photos on the map feature for now… We don't need this feature." The photo map view and online map tiles are removed from 1.0; the offline gazetteer, Places tab and set/clear location by search or coordinates stay. IMG-007 (doc 04) reworded, ADR-041 added, `maptiles` leaves the PRIV-004 allow-list, OSM licence dropped (GeoNames stays), the tiles.mediahro.com owner task is cancelled. C3 removes the code (handoff updated). |
| 2026-10-21 | Merged C3 **#81** (IMG-010 batch tools: rename with tokens, convert/resize to new files only, turn upright, strip metadata losslessly; IMG-015 share with size and strip-metadata options through StorageFacade.share, set as wallpaper, print, copy image through ImagingFacade; IMG-002 HDR photo view through ImagingFacade.openHdrView). Verified at 0aea884 merged on main d5de90a: tools/check 1233 app tests passed, 9 skipped, analyze clean, no flaky tests. Review: no direct MethodChannel, no network, no new dependencies, no frozen or shared files touched; convert never overwrites an original, upright and strip ask first, rename blocks on conflicts; JPEG strip removes EXIF (GPS), XMP and Photoshop/IPTC. **Open issues:** lossless strip of PNG leaves tEXt/zTXt/non-XMP iTXt chunks (for example an ImageMagick `Raw profile type iptc`) and JPEG COM comments stay (pre-existing metadata_codec behaviour); share with strip leaves videos untouched. IMG-010, IMG-015 and IMG-002 Android are built, no new integration test, in device batch 3 as hand checks, not ticked. |
| 2026-10-21 | Merged C4a **#80** (ADR-038 on Android: AccessibilityPrefsFacade SYS-008 via AccessibilityManager.isAudioDescriptionRequested on API 33+, false below, with a change stream; GamepadFacade SYS-009 via MainActivity.dispatchGenericMotionEvent to GamepadModule, 0.15 dead zone, triggers, hat, de-duplication, connect/disconnect from InputManager). Verified at de1a926 merged on main 2bfc528: tools/check 1160 app tests passed, 9 skipped, analyze clean, no flaky tests. Review: the MotionEvent injection hook (`mediahro.test/gamepad`, InputHooks.kt) lives only in the debug source set, is loaded by reflection (`Class.forName`) so release builds do not contain it, and is a BasicMessageChannel on the app's own Flutter engine, not an exported component or intent; no permissions, no dependencies, no network, no frozen files edited (only app/lib/platform/android/), Pigeon only. SYS-008/SYS-009 Android are built, in device batch 3 (`integration_test/c4a_android_input_test.dart`), not ticked. |
| 2026-10-21 | Merged C4a **#78** (SYS-011 manifest guard test: resizeableActivity=true, no screenOrientation or aspect-ratio locks, configChanges covering orientation, screenSize, smallestScreenSize, screenLayout and density; test only, no production code). Verified at 0dee047 merged on main 2b98633: tools/check 1153 app tests passed, 9 skipped, analyze clean, no flaky tests. SYS-011 Android has nothing native; the tabletop layout from MediaQuery.displayFeatures is UI work for the shell and player lanes, so not ticked. |
| 2026-10-21 | **Device batch 2 ran on the Samsung** (SM-M176B, Android 16, main bd9dc8a, 03:40-04:57 IST): 15 of 23 runs pass; 8 fail (TLS NET-017, SFTP test server, MUS-003 test filter, MUS-014 live pause, VID-031 `ready` channel, IMG-009 preview 655 ms vs 400 ms, ADR-032 /proc/self/fd, AUD-046 tap 0 frames). 8 Android cells ticked: IMG-003, IMG-004, IMG-006, MUS-008, MUS-011, MUS-012, SUB-040, VID-039. Batch 3 opened with every failed and hand-check ID carried over. See docs/release/android-batch-2-results.md. |
| 2026-10-21 | Merged C3 **#79** (IMG-009 photo editor: edit recipe as data, pure-Dart pixel engine in the image worker pool, full-screen editor with crop/straighten, light, colour, detail, curves, draw and blur; Save a copy or Replace the original; Copy this look and Apply copied look for many photos). Verified at ae93e0d merged on main 6587f8d: tools/check 1152 app tests passed, 9 skipped, analyze clean, no flaky tests. Review: all pixel work runs through EditJob in the isolate worker pool (UI isolate only handles the debounced preview request); replace writes a .part file then renames over the original (LocalFileSystem writer), aborts and keeps the original on error; no new dependencies, no MethodChannel, no network, no print() outside the integration test, no frozen or shared files touched. **Open issues:** the #76 un-reject bug (un-rejecting with write-back on writes xmp:Rating 0 and wipes an existing star rating, compare_screen.dart `write.rating([p], 0)`) is NOT fixed in this PR; and Replace the original cannot work on SAF sources (the SAF writer's create refuses an existing document). IMG-009 Android is built and in device batch 2 (25 of 25, batch full; integration_test/c3_edit_test.dart), not ticked. |
| 2026-10-21 | Merged C4a **#77** (VID-031 Android native HDR video view, ADR-022: `HdrVideoViewFactory` `mediahro/hdr_video`, a 10-bit SurfaceView registered with MediahroEngineViews on surfaceCreated/surfaceChanged and unregistered on destroy or dispose, window in COLOR_MODE_HDR while a view exists; per-view channel with ready() and a surfaceDestroyed event; Dart `AndroidHdrVideoView` and `AndroidHdrVideoSurface`). Verified at 2ac7785 merged on main 4b3d085: tools/check 1042 passed, 9 skipped, format and analyze clean. Review: five files, all new Android platform-view code plus one factory registration in PlatformModules.kt; no frozen facade changed, no new permissions or dependencies, no network, no MethodChannel outside the platform module. VID-031 Android is built but not complete until C1 wires the view into the player, so nothing is added to batch 2 (still 24 of 25) and nothing is ticked. Device test integration_test/c4a_android_hdr_video_test.dart is queued for the next batch. **C4a #75 (B2B-001/002 managed config and kiosk) and #78 (SYS-011 manifest guard test) were not merged**: #75 (rebased by C4a to head 5222eb3, fixes included: BootReceiver not exported, update_channel informational) now conflicts with main in PlatformModules.kt (adjacent registrations after #77), #78 (head 79803c2) conflicts in android_manifest_test.dart; C4a must rebase and force-push both, then they are verified and merged. |
| 2026-10-21 | Merged C4a **#72** (ImagingFacade on Android, ADR-037: ImageDecoder decode with subsample, region, HEIF frames and Ultra HDR gain map; thumbnails from MediaStore; HEIC encode through HeifWriter; HDR still view; set as wallpaper; system print with layouts; copy image; on-device android.media.FaceDetector faces; no-backup vault directory; `mediahroNativeLibs` list). Verified at b93d759 merged on main b4e6311: tools/check app 1035 passed, 9 skipped, engine 99 passed, analyze clean. Review: decoders are the platform ImageDecoder, HeifWriter and android.media.FaceDetector (no ML Kit); only new dependency androidx.heifwriter 1.1.0 (Apache-2.0); only new permission SET_WALLPAPER (normal, manifest guard test updated); no frozen facade changed, no network, no print(). IMG-001, IMG-002, IMG-003, IMG-005, IMG-010, IMG-011 and IMG-015 Android halves are built but not complete (C3 still has SVG, Live Photo, panorama, multi-page TIFF, people and the batch UI), so nothing is added to batch 2 (still 24 of 25) and nothing is ticked. Device test integration_test/c4a_android_imaging_test.dart is queued for the next batch. **C4a #78 (SYS-011 manifest guard test) and #77 (VID-031 HDR SurfaceView video view) were not merged**: both now conflict with main after #72 (adjacent additions in android_manifest_test.dart and PlatformModules.kt); C4a must rebase and force-push them, then they are verified and merged. |
| 2026-10-21 | Merged C3 **#76** (IMG-008 photo compare: 2 to 4 photos side by side, swipe, overlay or difference with synced pan and zoom; keep, reject and keep-only-this workflow with a Rejected album). Verified at 64fba63 merged on main 86cfd4b: tools/check 1024 app tests passed, 9 skipped, analyze clean, rules 0 violations. Review: reject is stored in the library as rating -1 and written into the file only through the existing OrganisationWriteBack, which returns at once unless photos.writeOrganisationToFiles is on (default off); no new dependencies, no MethodChannel, no network, no frozen or shared files touched. No integration_test (hand check, see PR #76). IMG-008 Android in batch 2 (24 of 25), not ticked. |
| 2026-10-21 | Merged C3 **#73** (photo map with clustering and opt-in map pictures through NetworkGateway only, offline GeoNames place names, Places tab, set or remove a photo's location for one or many, opt-in saving of ratings, labels and tags into photo files). Verified at 153e4e6 merged on main plus the orchestrator changes: tools/check 1002 passed, 9 skipped, analyze clean. Review: map pictures are off by default (the existing `maptiles` switch, enabled only after a confirm dialog), `tiles.mediahro.com` was already in the PRIV-004 allow-list (Endpoints.mapTiles), no request to tile.openstreetmap.org and no other new host, the gazetteer is offline (assets/gazetteer/places.bin 0.9 MB from GeoNames cities15000, CC BY 4.0), write-back is opt-in (default off) and Exiv2-free, no new pub dependencies, no MethodChannel. Orchestrator changes applied: `assets/gazetteer/` in the pubspec, `photoSettingsContributions` in the app root, GeoNames and OpenStreetMap notices in the licence list (registerMapLicences, docs/09 row), docs/05 §9 names the tile host. Side effect: with the asset bundled the details sheet shows the nearest city above the coordinates, so the IMG-006 details test now matches the coordinates with textContaining. IMG-007 A is built and in device batch 2 (23 of 25), IMG-005 places and write-back are built (people still waits on C4a detectFaces); nothing ticked. Human task added: tile host at tiles.mediahro.com. |
| 2026-10-21 | Merged C4a **#71** (Android Auto cold connect, ADR-036: the playback service starts the app's own Flutter engine without a screen, MainActivity adopts it, car browse/search/play wait up to 15 s for Dart; no Dart, pigeon or manifest changes). Verified at 8781230 (merge of 8f07176 on main): tools/check 883 passed, 9 skipped, clean. Review: no second FlutterEngine (startHeadless is guarded by PlatformModules.engineAlive and the engine is cached as `mediahro.app` for MainActivity), no new dependencies, no MethodChannel, no network calls. MUS-013 Android cold-connect part is built and awaiting device batch 2 (still 22 of 25, since MUS-013 was counted from #56); its check needs Android Auto DHU or a car, see PR #71. Nothing ticked. |
| 2026-10-21 | deps.lock → mediahro-deps v2026.10.5-android.1 (#70): FFmpeg movtext/ccaption + lutrgb/blend/v360, Tesseract 5.5.3/Leptonica 1.87.0, CLD3 + Bergamot, libsmb2/libnfs patches, armv7 SIMD patches. Device self-test PASS on the release archives (armv7, arm64); x86_64 link-time only. B1 VID-041 and C1 OCR/lang-ID/translation tests can drop their skips. |
| 2026-10-21 | Merged C3 **#69** (Android photos part 2: JPEG XL decode and encode, AVIF decode, camera RAW developed by LibRaw, QOI/TGA/PNM/PSD/DDS in plain Dart, animated GIF/WebP/APNG, and photo organisation: selection, favourites, ratings, labels, tags, albums, smart albums, folders). Verified at e1874e4: tools/check 883 passed, 9 skipped (the skips are the mediahro_ffi codec tests, which need Windows libraries, and the AVIF still-decode test, which waits for the B4a AV1 encoder). Review: libjxl, libavif and libraw are loaded dynamically through NativeLibraries; LibRaw 0.22.2 is taken under CDDL-1.0 as a shared library with no GPL demosaic packs (the code uses PPG, in the base library); no Exiv2, no MethodChannel, no network calls. IMG-001, IMG-005 and IMG-010 are partially built and none is complete, so nothing is ticked. The device test integration_test/c3_formats_test.dart (3 tests) is queued for the next batch, but these IDs do not count towards the 25 until they are complete. Still open: IMG-001 HEIC, SVG (flutter_svg added to app/pubspec.yaml by the orchestrator, MIT), Live and Motion Photo, panorama, multi-page TIFF; IMG-005 people and places and write-back (needs a Settings row, C3 will ask); IMG-010 the batch UI. |
| 2026-10-21 | Merged C3 **#68** (Android photos: Exiv2-free metadata engine for JPEG/PNG/WebP/TIFF/HEIC/AVIF/JXL with sidecars for RAW, libvips pipeline with thumbnail LRU, timeline with scrubber and pinch density, viewer with 512 px tile pyramid, details sheet and metadata editing, library prober). Verified at 31ceed0 plus the orchestrator wiring: tools/check 809 passed, 9 skipped (libvips tests skip until mediahro-deps libvips exists for Windows). IMG-003, IMG-004, IMG-006 A are built and in device batch 2 (22 of 25), not ticked. Wiring: `photoRoutes` in appRoutesProvider, `openItemByKind` dispatches images to the photo viewer, `KindRoutingProber` (app/lib/app/media_wiring.dart) is ready for the probe queue, but nothing constructs a ProbeQueue in the app yet (B2 must pass it as `prober:` when it does). Follow-ups: HEIC/AVIF decode waits for C4a ImagingFacade (IMG-001/010), AVIF encode for B4a AV1, libraw/libjxl/libavif bindings are C3 next. |
| 2026-10-20 | v2026.10.5-android.1 build: arm64-v8a passed (29.1 MB archive). armeabi-v7a stopped at Bergamot, because Marian's simd_utils/sse2neon uses AArch64-only float64x2_t and vfmaq_f32 (VFPv4). Decision: patch it (guard the AArch64 paths; vmlaq_f32 fallback without FMA). Bergamot is not dropped on 32-bit ARM (no feature narrowing). x86_64 is next. Release and pin wait for all 3 ABIs. |
| 2026-10-20 | Merged mediahro-deps **#12** (FFmpeg component names: movtext and ccaption were silently missing on every platform; added LGPL lutrgb/blend/v360; a configure guard refuses all 33 GPL-only components and stereo3d) and **#14** (CLD3 3.0.13 + Bergamot translator with 8 dependencies, all MIT/Apache/BSD/MPL-2.0, 0 GPL-only files; libcld3 0.66 MB, libbergamot 6.0 MB stripped, exporting only our mh_* API). No workflow ran. B4a is now running the solo clean release build of v2026.10.5-android.1. |
| 2026-10-20 | ADR-036 (Android Auto cold connect reuses the app's single engine) and ADR-037 (`ImagingFacade`, interface on main) accepted. C3 is paused with its pipeline/metadata work committed locally (4bf4f34). The full tools/check for the interface waits until B4a's solo build finishes (dart analyze is clean). |
| 2026-10-20 22:50 IST | Night plan: C4a and C3 are paused (usage-limit stop; no build processes). B4a runs alone: open the CLD3/Bergamot PR, then I merge deps#12 and it, then a clean 3-ABI local build of v2026.10.5-android.1, a GitHub release upload (no workflow), and the mediahro deps.lock pin PR. C4a's cold-car design (reuse the app's single engine headless; no second engine, player or DB writer) is accepted as ADR-036 when C4a resumes. |
| 2026-10-20 | **Owner decision (ADR-035): no Google Cast SDK.** The open CASTv2 sender (C4d, Dart) runs on every platform. Owner also approved running B4a's native release build **alone tonight** (PC left on): C4a and C3 pause for it, then resume. |
| 2026-10-20 | **Owner decision pending: Google Cast SDK (CAST-001 on A/I).** Google's data-safety page says the Cast sender SDK automatically logs discovery and session events, device info and app info, anonymised, with no opt-out for developer or user. That conflicts with PRIV-001, like ML Kit (ADR-034). Recommendation: the open CASTv2 sender (C4d, Dart over TlsSocketFacade, already planned for foss/M/W) on every platform, as VLC does. C4a is skipping the Cast SDK until the owner decides. |
| 2026-10-20 | Merged C4a **#67** (Android TTS only, open Tesseract/CLD3/Bergamot services registered, no ML Kit; tools/check 624; #50 closed as superseded) and B1 **#66** (ADR-033 VideoFilterChain: crop, ICC/LUT, stereo via LGPL crop/lutrgb/blend, 360° via v360; tools/check 624). |
| 2026-10-20 | **Owner: the PC was too slow and K: was filling, so we're down to 2 lanes.** Cause: three lanes plus a WSL C++ compile plus verification builds on a 16 GB PC. All lanes were stopped, WSL was shut down, and 35 GB of rebuildable output was deleted (the 6.6 GB emulator image, the 8.7 GB paused Windows build tree K:\mw, 44 build folders); K: is at 162 GB free. New lanes rule 11: 2 lanes, one heavy build at a time, Dart-level proof for lanes, build folders kept only for active lanes, 30 GB project budget. Resumed with C4a and C3. B4a's native release build (killed by the WSL shutdown) runs alone later. |
| 2026-10-20 | Merged C4a **#65** (Android open-with, share targets, launcher shortcuts and App Actions; deep links reach Dart only through openRequests, never as router routes). Verified at 01895d2: tools/check 622, clean. Batch 2: 19 of 25. B3 needs to wire openRequests and intents into the shell. |
| 2026-10-20 | Merged B1 **#64**: if a hardware-decoded video's position freezes for 3 s, it is rebuilt in software for that item and resumes from the last frame; the next item uses hardware again (the Exynos seek-to-0 stall C1 found). Verified at the PR head: tools/check 618, clean. Licence note from B1 for ADR-033: FFmpeg's stereo3d filter is GPL, so VID-041 uses LGPL crop/lutrgb/blend and v360 (B4a enables them). |
| 2026-10-20 | Merged B1 **#63** (ADR-031 part 1: subtitleText; extractSubtitles to .srt/.ass/.vtt while playing, including MP4 mov_text via stream copy plus a Dart tx3g reader; `out` is a file: Uri, as in export()). Verified at 37860c8: tools/check 618, clean. extractSubtitleImages (OCR) follows as part 2. B4a built CLD3 for Android (659 KB). |
| 2026-10-20 | Merged C4a **#62** (Android now-playing home-screen and lock-screen widget with artwork, labelled 48 dp controls and stored state). Verified at 7218698: tools/check 618, clean. All of C2's Android facades are now merged (MediaBrowse, Alarm, HomeWidgets). Batch 2: 16 of 25. |
| 2026-10-20 | Merged B1 **#61** (ADR-032 decodeAudio: 30 s consumer-paced windows, source opened once, hole-punched PCM; 642× real time on Windows). Verified at 5c8ee73: tools/check 617, clean. SUB-050 A moved from ⛔ to batch 2 (15 of 25). |
| 2026-10-20 | Rotation: C1 paused with its work committed locally; **B4a resumed** for the FFmpeg component-name fix (movtext, ccaption), CLD3 and Bergamot for Android (C1's shims), and v2026.10.5 plus the Android deps.lock pin. Running: C4a, B1, B4a. |
| 2026-10-20 | Merged C1 **#60** (our own film-grain shader under the app licence as the 8th built-in preset; app/assets/shaders/SOURCES.md with source, licence and SHA-256 for every file, both as-downloaded and stored LF hashes). Verified at ee8aea3: tools/check 617, clean. |
| 2026-10-20 | Merged C4a **#59** (Android thermal level + battery saver, ADR-033). Verified at 5ca251b: tools/check 617, clean. |
| 2026-10-20 | Merged C1 **#57** (ADR-034 text services: Tesseract, CLD3 and Bergamot bindings via our C shims, one TextWorker isolate, OpenTextRecognition and OpenTranslation with an English pivot and consent-gated downloads) and **#58** (11 Anime4K v4.0.1 files + FSR.glsl + licences, 788 KB). Wiring: pubspec `assets/shaders/`, `registerShaderLicences()` in main.dart; text_services.dart docs updated to ADR-034. Verified: tools/check 616, clean. Next for B4a: build the CLD3 and Bergamot shims (notes/c1-text-shims.md); for C4a/b/c: add `...openTextServiceOverrides()` to bindings. |
| 2026-10-20 | Merged C4a **#56** (Android Auto browse/search/voice play from C2's tree through the Media3 library session; wake alarms via setAlarmClock with an exact-alarm prompt and a windowed fallback). Verified at 716618c: tools/check 605, clean. Batch 2: 13 of 25. Gap: a cold car connect (app never opened) needs a background Flutter engine with a car entrypoint (ADR-035 request from C4a). |
| 2026-10-20 | Merged B1 **#55** (ADR-027: audioTap through a cache-fed analysis core with s16 PCM in memfd on Android, plus mediaTitle and mediaMetadata). Verified at b887681: tools/check 601, clean. AUD-046 A moved from ⛔ to batch 2 (11 of 25). **For B4a, root cause from B1:** ffmpeg.common.flags uses names configure doesn't know (`mov_text` should be `movtext`, `eia_608` should be `ccaption`; `dvb_teletext` needs libzvbi, licence to check). Configure only warns, so these decoders are missing on every platform. Fix plus a configure-log guard that turns unknown names into errors (B1's note b1-request-b4-ffmpeg-component-names.md). |
| 2026-10-20 | Merged C4a **#46** (Android CaptioningManager, ADR-030; tools/check 601) and C1 **#54** (built-in shader preset mechanism, MIT only, with licence registration; tools/check 598). Owner approved the MIT shader download. Anime4K v4.0.1 and AMD FSR (agyild) were fetched and SHA-256 recorded in K:\Projects\shader-download\SOURCES.md; C1 commits them to app/assets/shaders/. Cleared the CMake caches (packages/mediahro_engine/android/.cxx) that the power cut corrupted. |
| 2026-10-20 | Merged C1 **#53** (closing a video no longer deactivates music's session; subtitle_sources_test and subtitle_style_test made deterministic; tools/check clean twice for C1). tools/check now regenerates l10n before analyze, so generated strings can't go stale after a rebase. Known flake for B2: renderer_test "NET-005 GENA event keys count from 0" fails under load and passes alone 3/3. |
| 2026-10-20 | **Owner decision (ADR-034): no Google ML Kit in any build.** OCR uses Tesseract, language ID uses CLD3, translation uses Mozilla Bergamot, all on-device. C4a's #50 is reduced to TTS only. B4a builds CLD3 and Bergamot at its next slot, and C1 writes the FFI bindings. Only the MIT shaders (Anime4K, FSR) are bundled; the LGPL-3.0 ones stay user-supplied. |
| 2026-10-20 | Merged C1 **#51** (Picture sheet with scalers and filters, shader presets and custom GLSL from a user folder, smooth motion/interpolation with thermal step-down). Verified at da0e34c: tools/check 591, clean. Batch 2: 10 of 25. |
| 2026-10-20 | Merged C2 **#52** (internet radio with user stations and M3U/PLS; opt-in scrobbling to ListenBrainz, Libre.fm and Last.fm with an offline queue; music on the shared session owner; music_player_test flake fixed). Verified at f405e78: tools/check 576, clean. Owner task: LASTFM_API_KEY/SECRET. Batch 2: 7 of 25. **Held: C4a #50 (ML Kit)**, because its usage metrics to Google can't be turned off and conflict with PRIV-001; owner decision pending. **Power cut:** the local .git had zeroed refs/heads/main, refs/remotes/origin/main and ORIG_HEAD plus a corrupt index. A backup was kept, then the repo was repaired from origin; fsck is clean, and all 15 worktrees and the lanes' uncommitted work are intact. Lanes restarted: C4a, C1 and B1 (B1 takes C2's slot for the engine backlog). |
| 2026-10-20 | ADR-033 accepted: VideoFilterChain additions for B1 (crop, ICC/LUT, stereo 3D, 360 projection) and a new `PowerStatusFacade` (thermal level and battery saver; C4a/b/c). **Owner decision pending:** VID-038 shader assets. Anime4K and FSR are MIT. NNEDI3 and SSimSuperRes are LGPL-3.0 GLSL. |
| 2026-10-20 | Merged C1 **#49** (subtitle audio auto-sync: algorithm in mediahro_subtitles in a worker isolate, player UI with progress, cancel, confidence prompt and Undo). Verified at 1e85f3b: tools/check 564, clean run. SUB-050 A is ⛔ on B1's decodeAudio (ADR-032). **B1 now has queued work:** ADR-027 audioTap/metadata (AUD-046, MUS-014), ADR-031 subtitle text/extraction (SUB-040/051/052/053 embedded tracks), ADR-032 decodeAudio (SUB-050/052, MUS-010), the Exynos seek-to-0 stall, and mov_text (with B4a). |
| 2026-10-20 | Merged C2 **#48** (smart playlists with a live match count, widget updates on play/pause, a paged car browse tree with voice search). Verified at a7df5a3: tools/check 558, apart from a C1 caption-style test that is flaky under load (passes alone). Device batch 2: 5 of 25. |
| 2026-10-20 | Merged C1 **#47** (subtitles follow the system caption style live, with auto-on in the user's language when system captions are on; video claims and releases the media session per ADR-029). Verified at f02b7d5: tools/check 549 apart from subtitle_sources_test, which is flaky under full-suite load (passes alone; C1 is fixing it). C4a #46 needs a rebase. |
| 2026-10-20 | Merged C4a **#45** (Android SFTP: sshj 0.41.2 on the platform JCA with BouncyCastle excluded, per ADR-017; host-key check before any credentials; password, keyboard-interactive and key login; OpenSSH, PuTTY and PEM keys). Verified at d8abdb1: tools/check 540 (one C1 subtitle test is flaky under load and passes 3/3 alone), licence scan 0 errors. The Android networking group is complete. Also fixed tools/check hitting the Windows command-line limit in the format step (60218de). |
| 2026-10-20 | Merged C1 **#43** (read subtitles aloud, on-device translation with consent before any language-pack download; tools/check 516) and C2 **#44** (tag editing for ID3v2.4/FLAC/Ogg/MP4/APE/WMA/WAV/AIFF/DSF with verify-then-swap and undo, batch edits, tags from filename, rename from tags; tools/check 539). Device batch 2: 4 of 25. ADR-032 accepted (offline audio decode for SUB-050/052; B1). |
| 2026-10-20 | **Device batch 1 ran on the Samsung**: all 14 functional suites pass, plus library perf (scan 1.95 s, search median 17.5 ms). 13 Android cells ticked. 11 more wait for the owner's manual checklist; sample files are in Download/MediahroTest, and a release build of main 291b894 is installed. The shell perf test (CORE-001) couldn't attach to the VM service over wireless adb; that's a harness fix for B3. |
| 2026-10-20 | Merged C4a **#41** (TLS client 1.2/1.3 with pinning, AUTH TLS upgrade, FTPS session reuse, mutual-TLS server with Keystore identity; tools/check 496) and C1 **#42** (subtitle editor plus SRT/WebVTT/ASS/MicroDVD/LRC/SAMI parsers and writers in isolates with limits, plus a fuzz target; tools/check 507). Both go into device batch 2. ADR-031 accepted (engine subtitle text and extraction; B1 at its next slot). |
| 2026-10-20 | Merged C1 **#40** (subtitle styling with every option defaulting to System, subtitle speed for frame-rate conversion, dual subtitles) and wired subtitleSettingsContributions in root.dart. Verified at 2a20a4e: tools/check 492 with the wiring. **Device batch 1 is full (25 features); running it on the Samsung.** |
| 2026-10-20 | Merged C4a **#39** (Android network status with metered and Data Saver, Wi-Fi multicast lock per lease, Custom Tab sign-in with an RFC 8252 redirect). It also fixes release builds having **no INTERNET permission** (it was only in the debug manifest). Verified at ddf2e5d: tools/check 483, Gradle 6/6. |
| 2026-10-20 | Merged C1 **#38** (subtitle sidecars for videos on shares and SAF folders, add a subtitle file, character encoding remembered per file, format names in the chooser). Verified at 68ee23c: tools/check 479. ADR-030 `CaptionStyleFacade` added (system caption style; Android implementation by C4a). Device batch 1: 22 of 25. |
| 2026-10-20 | Merged C2 **#37**: lyrics (edited > sidecar > embedded > opt-in LRCLIB, with a consent dialog; synced karaoke scroll, tap-to-seek, LRC editor) and the visualiser UI. Verified at 4c49145: tools/check 466. AUD-046 A is ⛔ on B1's audioTap (ADR-027), which goes to B1 at its next slot. Device batch 1: 20 of 25. |
| 2026-10-20 | Merged C4a **#36**: picking a video opened Samsung's Photo Picker (multi-select, media-id names). Only image-only picks use the Photo Picker now; everything else uses the documents picker, with single or multiple selection as requested and real display names. Verified at fbaf960: tools/check 448 and the Gradle unit tests (PickPolicyTest 6/6). |
| 2026-10-20 | Merged C2 **#31** (Now Playing extras: favourite, rating, sound sheet with EQ/levelling/crossfade, output, add to playlist, info; sleep timer and wake alarms through the AlarmFacade, which waits on C4a; music answers lock-screen commands only while it owns the session). Verified at 652c99e: tools/check 448. ADR-029: shared `mediaSessionOwnerProvider` so video and music never both answer one button. Device batch 1: 19 of 25. |
| 2026-10-20 | Merged C1 **#35** (volume boost to 300 % with mute, per-device volume, sleep timer with fade-out). Verified at f1872d5: tools/check 438. Device batch 1: 17 of 25. |
| 2026-10-20 | Merged C2 **#34**: the tag reader's isolate captured an unsendable VirtualFile, so songs from SAF, MediaStore and share sources showed no tags (no albums or artists). Verified at b2993c3: tools/check 429. MUS-001/002 A are **un-ticked** (#26's device run used file paths only) and re-queued in batch 1, now 15 of 25. |
| 2026-10-20 | Merged C4a **#33** (Android secure storage and biometrics: Android Keystore only, AES-256-GCM, StrongBox where present, excluded from backup; vault key wrap per ADR-008; BiometricPrompt with PIN fallback). Verified at 0363a06: tools/check 428. Its device tests are queued in batch 1. |
| 2026-10-20 | Merged C1 **#32** (Android PiP with setAspectRatio, background and sound-only playback, rotation and display, OS media-session controls for video). Verified at 4d4fac6: tools/check 426. Device batch 1: 13 of 25. Also on main: 16fddbf, which turns off Riverpod retry for missing platform facades (found by C2). C2's #31 needs a rebase (conflict in music_test_support.dart). |
| 2026-10-20 | Merged C4a **#29** (Android predictive back; B3's §3 predictive-back row closed, while CORE-001 A stays ⛔ on the device profile budget until the batch run) and **#30** (ADR-028 PipFacade.setAspectRatio with the Android implementation). Local proof: tools/check 404 on both combined. Device batch 1: 12 of 25. |
| 2026-10-20 | Merged C1 **#28** (Android video player: gestures, seek bar, speed, frame step/A-B loop/chapters/bookmarks, resume, track switching, info overlay) and wired videoRoutes, videoOverrides (main.dart) and videoSettingsContributions (root.dart). Local proof: tools/check 402 on the merge result with the wiring. Device batch 1 is at 11 of 25. Device findings from C1, routed: Android FFmpeg lacks the mov_text decoder (MP4 text subtitles; B4a/B1); seek-to-0 while playing stalls the Exynos MediaCodec decoder (B1); the picker opens multi-select and PickedFile.name is the media id (C4a); KPlayerChrome's scroll view swallows touches over the video (B3). |
| 2026-10-20 | Merged C4a **#27** (Android display + picture-in-picture: screen-on, brightness, orientation locks, frame-rate matching, display changes, PiP enter/exit/auto-enter). Local proof: tools/check 373 on the merge result. Its phone tests are queued in device batch 1. ADR-028 accepted (PipFacade.setAspectRatio). |
| 2026-10-20 | Merged C2 **#26** (Android music library, tag reading in an isolate, art, gapless queue through libmpv, mini player and Now Playing) and wired `musicOverrides` in main.dart. Verified before the batch rule: tools/check 369, c2_music_test 4/4 on the Samsung. MUS-001/002/004/007 A ticked. Batch 1 starts empty. |
| 2026-10-20 | **Owner rule: device testing in batches of 25 features.** PRs merge on local proof (`tools/check` plus unit and widget tests, re-run by the orchestrator). Every 25 merged features, all their integration tests run on the Samsung in one go, and cells are ticked only after that run (lanes rule 10; batch table in §1). |
| 2026-10-20 | **Owner decision: the first Play internal-test upload waits until Android has every feature** (177 Android cells for 1.0: 24 ☑, 137 ☐, 16 ⛔). This replaces the plan to upload a partial build today. Slots: C4a (Android platform code) keeps one slot; the other two rotate through the feature lanes C1, C2, C3, C4d, C5, B2, B1, one PR batch each. All Android ⛔ are being re-checked now that a real phone and local test servers exist: CORE-001, FILE-004, NET-001/002 and VID-030 are now testable; the sample-blocked ones go to B1 to generate with permissive tools; VID-004, AUD-040 and AUD-043 need owner hardware (HDMI receiver, USB DAC); VID-031 needs an HDR display. |
| 2026-10-20 | Merged C4a **#25** (release signing from the gitignored key.properties with a debug fallback; kotlin.incremental=false) and **#24** (Media3 session, mediaPlayback foreground service, audio focus/noisy/outputs, POST_NOTIFICATIONS asked on first playback). #24's first Samsung run caught One UI hiding the media notification while POST_NOTIFICATIONS is denied; that's fixed. Verified: tools/check 325, Samsung media 9/9 + storage 13/13. SYS-001/002/006 A ticked; AUD-044/045 A moved from ⛔ to ☐. New owner decision pending: A2DP codec name (no public Android API). |
| 2026-10-20 | Merged C4a **#23**: Android storage and photo library (SAF trees, MediaStore with OS trash and undo, Photo Picker, Motion Photo). Verified locally: `tools/check` on the merge result (321 pass) and c4a_android_storage_test 13/13 on the Samsung. SYS-007 A ticked. This unblocks B2's Android LIB-002/003, FILE-001/002, NET-018, LIB-007, CORE-014 and C3's IMG-016 A, pending their end-to-end runs. |
| 2026-10-20 | **Owner decisions:** (1) the Android test build goes to **Google Play internal testing** today; the owner checklist is docs/release/android-internal-test.md (upload key, Play Console and declarations are owner steps). (2) **No GitHub CI for now:** every workflow is manual-only (164fa62, a364a9c). Proof is local: `tools/check`, plus integration tests on the owner's Samsung SM-M176B (Android 16) over wireless debugging (lanes rule 8). The orchestrator re-runs `tools/check` before each merge. |
| 2026-10-20 | **Owner decision: Android first.** An Android test build ships today; the other platforms follow afterwards. This changes the order of work only: every doc 04 feature still ships on every listed platform. Slots: C4a (Android storage + media session), C1 (video player, Android) and C2 (music, Android). B2 and B4a are paused (the Android engine already runs on mediahro-deps android.4). Testing iterates on the owner's Samsung phone over wireless debugging, one lane at a time under K:\Projects\.device-lock; CI on each PR stays the merge proof. |
| 2026-10-20 | **Owner rule: at most 3 lane sessions run at once.** Paused all eight C lanes plus B4b and B4c (their worktrees and work are kept). Running: B1, B2, B4a. Rotation order is in §1. ADR-027 (engine audio tap and stream metadata, for C2) is accepted; C3's ImagingFacade request is pending until C3's slot. |
| 2026-10-20 | **Phase C started** (owner): eight lane sessions. **Phase B speed review:** 120 of 189 CI runs were cancelled (45 by bookkeeping pushes to main, the rest by lanes pushing over running CI); native-dep rounds take ~2 h (Apple 1 h 45 min) with no per-library cache; app CI is ~35 min (integration-apple long pole); failures were relayed through the orchestrator; network-env needed ~7 rounds because suites stopped at the first failure. Fixes (08330be and briefs): bookkeeping no longer triggers ci; main runs queue instead of cancel; single-platform PRs run only that platform; network-env runs every suite; lanes watch and fix their own CI, reproduce locally (Docker/WSL, Android emulator, Windows) and keep working during CI; B4a adds a per-library deps cache (target < 20 min per library change). Optional owner lever: more macOS CI capacity (§4). |
| 2026-10-20 | Merged mediahro-deps#9 (ac418d9; run 39381101605, all five targets green) and #11 (B4b Apple ICF −0.44 MB; ThinLTO measured +3.6 MB, kept off). B4a is tagging **v2026.10.4** at ac418d9; next are the deps.lock pin PR and B1 dropping its bootstrap skips. Tesseract and the updated libsmb2/libnfs patches ship in v2026.10.5 (#10). |
| 2026-10-20 | Merged B2 #21: SMB guest sessions (guest user first, then NULL session; libsmb2 patch no longer signs guest TREE_CONNECT) and the NFS errno fix (libnfs open-callback patch). network-env is now 16/17; SMB DFS referrals (`STATUS_PATH_NOT_COVERED`) are left to B2. ADR-026 records the VFS error additions. The patches ship in mediahro-deps v2026.10.5 (#10), after v2026.10.4 (#9). |
| 2026-10-20 | **Interface freeze** at a138542 (merged B1 #18: engine API for Phase C). **ADR-025:** new facades (purchases, TTS, OCR, translation, car browse, alarms, mutual-TLS server); B1 stays the engine lane; C4 split into C4a Android / C4b Apple / C4c Windows / C4d servers & casting; Tesseract fallback for SUB-051. Also merged B2 #20 (libarchive callback crash, SMB logon mapping; network-env now 14/17, with SMB NULL-session and NFS NOENT mapping left to B2). **Phase C launched:** C1, C2, C3, C4a–d, C5. |
| 2026-10-20 | **Merged B4c** (mediahro-deps#8: Windows x64 + arm64, 59 libraries; proof run 39370785975 at b26658d, check_pe 91/83 DLLs, 0 errors). All four native-dependency lanes are now merged (B4a Android + shared, B4b Apple, B4c Windows); next is B4a's combined release and the mediahro deps.lock pin. Decided with B4a: libplacebo keeps shared shaderc on Windows, because mpv's D3D11 backend requires it (no feature cut). network-env on B2 #20 now runs every test; the NFS env under sudo was fixed in ci.yml (92e1eaa), and the SMB guest signing, logon-status mapping and ebur128 expectation fixes went to B2. B1 #18 is waiting on integration-apple with the ducking fix (feed1df). |
| 2026-10-20 | **Merged B2 #17** (FTP/SFTP healthchecks; network-env servers now all start; next failure NET-001 SMB guest + a native abort, sent to B2) and **#19** (SAF trees, MediaStore, scoped access, playlist import/export, backup via saveFile, share/open-in; 311 app tests). **B4c opened mediahro-deps#8** (Windows x64 + arm64, 59 libraries, clang-cl with CFG/CET, Schannel/WinCNG/CNG crypto, 0 GPL-only files); merge waits on its build at head b26658d. Windows runtime DLLs are 73.5 MB on x64, so the 70 MB desktop ceiling will be reset from the first full app build (ADR-020); ThinLTO via lld-link and glslang-instead-of-shaderc are queued (B4c, B4a). B1 #18 (API freeze) is green except integration-apple, which is still running. |
| 2026-10-20 | **Merged B1** (PR #3, engine M1: MpvEngine, render bridges on A/I/M/W, VirtualFile streaming, disc folders, audio DSP/gapless/crossfade, casting pipeline; ci + engine green on 7bc4f9b). Ticks re-verified from engine run 39355966616 at the merge head: +36 cells. ADR-021…023 recorded (engine choices, native HDR via platform views, DoP). Also merged B3 #10 (CORE-015 live policy, CORE-001 profile benchmark), B2 #8/#12, B4a deps#3/#4/#6 and mediahro#7/#11 (deps.lock → v2026.10.3-android.4). |
| 2026-10-20 | **Merged B2** (PR #1, library index, scanner, search, sources, file browser; 16/16 CI green on 9971a48) and **B3** (PR #2, design system, shell, settings, themes, l10n tooling, shortcuts, privacy dashboard; 16/16 green on 24d9404). First verified cells: 15 (B3). Bookkeeping (STATUS, CHANGELOG, size baseline) is now orchestrator-only; CI cut to 2 macOS jobs per PR. |
| 2026-10-19 | Phase A started. Read CLAUDE.md order (01, 04, 05, 06, 07, 09, 10, 11; 03, 13 as needed). Flutter 3.47.7 pinned via FVM. |
| 2026-10-20 | Found three stalls: my `--no-dds` CI change broke Android integration on every PR (reverted, 6aa7fad); B1's PR #3 had 9 red jobs including a 102 MB Android APK (budget 40 MB) — B1 and B4a briefed. |
| 2026-10-20 | Owner decided ADR-017: SFTP/FTPS and the open Cast sender use OS crypto only (sshj/JCA, SwiftNIO SSH/CryptoKit, libssh2+WinCNG; OS TLS sockets for FTPS and CASTv2). `TlsSocketFacade` and `SftpFacade` added to app/lib/platform. NET-004 and CAST-001 are unblocked (sequencing: C4 platform modules). |
| 2026-10-19 | Merged B4a: mediahro-deps#1 (pinned sources, Android build, shared scripts, release workflow) and mediahro#4 (deps.lock → v2026.10.0-android.1, native licence scan: 293 components, 243 binaries, 0 errors). CI hardened: per-file integration timeouts + retry (iOS simulator hangs), licence scan now `--require-native`. Owner decision pending: crypto for SFTP/FTPS (NET-004) and the open Cast sender (CAST-001). |
| 2026-10-19 | Phase B running: B1 engine, B2 library & sources, B3 design & shell (Mediahro worktrees), B4a Android + shared, B4b Apple, B4c Windows (mediahro-deps worktrees). Six duplicate lane sessions created during the trust retries were deleted. |
| 2026-10-19 | Repos published (public): github.com/vasandkumar/mediahro, github.com/vasandkumar/mediahro-deps. First CI runs fixed (exec bits, ARB merge order, size-measurement symlink bug); CI fully green on all 16 jobs. **Phase A exit met.** |
| 2026-10-19 | M0 skeleton committed: workspace, 5 packages, app shell, interface stubs, tooling, CI workflows, `mediahro-deps` skeleton. Local proof: `tools/check` green (analyze, lints, l10n, status, manifests, 61 tests); Windows debug build + 3 integration tests pass; Android `foss` APK builds. ADR-011…016 recorded in docs/05 §12. |
