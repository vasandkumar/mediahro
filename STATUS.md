# Mediahro — STATUS

The single progress view for the owner. Every PR updates the rows it touches. Generated once from `docs/04` by `tools/status/gen_status.py`; CI (`tools/status/check_status.py`) fails if a doc 04 ID is missing or a 1.0 platform cell is narrowed.

**Legend:** ☐ to do · ☑ done (AC verified on that platform through the CI matrix) · ⛔ blocked (see Blockers) · — not applicable on that platform (doc 04) · 1.1/1.2 later release per doc 04 · Platforms: A Android · I iOS/iPadOS · M macOS · W Windows.

_Last updated: 2026-10-19 by the orchestrator._

## 1. Phase and milestone gates

| Phase / milestone | Lanes | State | Exit criteria (docs/10 §3, §8) |
|---|---|---|---|
| **A — Skeleton (M0)** | orchestrator | ☑ done 2026-10-19 (deps archives → B4 per Phase B exit) | Shell builds on all platforms; stubs compile; CI green; deps archives published with SHA-256; licence scan passes |
| **B — Foundations (M1, M2)** | B1 Engine · B2 Library & sources · B3 Design system & shell · B4 Native deps (Android / Apple / Windows) | in progress | M1 + M2 exit criteria; B3 goldens green; deps archives published and pinned; **interface freeze** |
| **C — Experiences (M3–M7)** | C1 Video & subtitles · C2 Music & podcasts · C3 Photos · C4 Servers, casting, platform modules · C5 Supporter, privacy, B2B, store metadata | not started | Each lane's IDs ☑ on every platform; integration branch builds daily |
| **D — Hardening (M8)** | D1 Android · D2 iOS/iPadOS · D3 macOS · D4 Windows · D5 Localisation · D6 Store submission packs | not started | All doc 11 §7 release gates pass; 1.0 tagged |

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
| B1 Engine | `app/lib/engine`, `packages/mediahro_engine` (whole package in Phase B, incl. bundling the `mediahro-deps` libraries into the plugin's Gradle/podspec/CMake builds), `packages/mediahro_ffi` (mpv part: `lib/src/mpv/`, `ffigen/mpv.yaml`) |
| B2 Library & sources | `app/lib/core`, `app/lib/features/sources`, `app/lib/features/library`, `packages/mediahro_ffi` (smb2/nfs/curl/archive/ebur128/chromaprint/uchardet parts, `lib/src/vfs/`) |
| B3 Design system & shell | `packages/mediahro_design`, `app/lib/app`, `app/lib/ui`, `app/lib/features/settings`, `app/lib/features/onboarding`, `tools/l10n` |
| B4 Native deps | `../mediahro-deps` (sub-lanes `android/`, `apple/`, `windows/`), `deps.lock`, `tools/deps`, `tools/licence_scan` |
| C1 Video & subtitles | `app/lib/features/video`, `packages/mediahro_subtitles`, `packages/mediahro_engine/lib/src/mpv/` + `lib/src/bridge/` + the plugin's native folders (Phase C: video/subtitle engine features) |
| C2 Music & podcasts | `app/lib/features/music` |
| C3 Photos | `app/lib/features/photos`, `app/lib/images`, `packages/mediahro_ffi` (vips/jxl/avif/raw parts) |
| C4 Servers, casting, platform | `packages/mediahro_servers`, `app/lib/features/servers`, `app/lib/features/cast`, `app/lib/platform`, `app/pigeons`, `app/android`, `app/ios`, `app/macos`, `app/windows` |
| C5 Supporter, privacy, B2B, store | `app/lib/features/supporter`, `app/lib/features/b2b`, `app/lib/features/privacy` (telemetry opt-in, app lock; the dashboard screen CORE-015 is B3's), `packages/mediahro_engine/sdk/` and `capi/` (Phase C: SDK packaging, C/Kotlin/Swift APIs, samples), `fastlane/` |

Shared files (`STATUS.md` own rows only, `CHANGELOG.md` own entries, `docs/05 §12` via ADR PRs, `app/pubspec.yaml`, `app/lib/main.dart` via the orchestrator) are merged by the orchestrator. Each lane keeps its UI strings in its own ARB fragment `<owned folder>/l10n/<module>_<locale>.arb`; `tools/l10n/merge_arb.dart` merges fragments before `gen-l10n`.

## 2. Feature checklist (every doc 04 ID)

### 1. CORE — App shell, settings, onboarding

| ID | Feature | Lane | A | I | M | W | Notes |
|---|---|---|:-:|:-:|:-:|:-:|---|
| CORE-001 | Three-mode shell (Video, Music, Photos) with a shared Sources and Settings area | B3 | ☐ | ☐ | ☐ | ☐ |  |
| CORE-002 | First-run without walls | B3 | ☐ | ☐ | ☐ | ☐ |  |
| CORE-003 | Open-with / default handler | C4 | ☐ | ☐ | ☐ | ☐ |  |
| CORE-004 | Drag-and-drop | C4 | — | ☐ | ☐ | ☐ |  |
| CORE-005 | URL/stream open | B2 | ☐ | ☐ | ☐ | ☐ | B2: URL validation, headers/UA, history of 50, Open URL dialog. Playback hand-off is the `openUrlActionProvider` seam (C1 wires it). |
| CORE-006 | Settings model | B3 | ☐ | ☐ | ☐ | ☐ |  |
| CORE-007 | Themes | B3 | ☐ | ☐ | ☐ | ☐ |  |
| CORE-008 | Localisation | B3 | ☐ | ☐ | ☐ | ☐ |  |
| CORE-009 | Keyboard shortcuts | B3 | ☐ | ☐ | ☐ | ☐ |  |
| CORE-010 | Window management | C4 | — | ☐ | ☐ | ☐ |  |
| CORE-011 | Crash resilience | B1 | ☐ | ☐ | ☐ | ☐ |  |
| CORE-012 | Updates | C5 | ☐ | ☐ | ☐ | ☐ |  |
| CORE-013 | About and licences | C5 | ☐ | ☐ | ☐ | ☐ |  |
| CORE-014 | Backup/restore | B2 | ☐ | ☐ | ☐ | ☐ | B2: MHROBK1 file (PBKDF2-SHA256 + AES-256-GCM), cross-device restore by hash→path→name+size; backup screen. Saving/picking the file on A/I needs C4 StorageFacade. |
| CORE-015 | Privacy dashboard | B3 | ☐ | ☐ | ☐ | ☐ |  |

### 2. LIB — Library, indexing, search

| ID | Feature | Lane | A | I | M | W | Notes |
|---|---|---|:-:|:-:|:-:|:-:|---|
| LIB-001 | Unified index | B2 | ☐ | ☐ | ☐ | ☐ | B2: drift index (docs/05 §6 tables, FTS5), scanner isolate pool, viewport probe queue. Codec/duration fields fill from B1 through the `MediaProber` seam. |
| LIB-002 | Local sources | B2 | ☐ | ☐ | ☐ | ☐ | B2: local sources via StorageFacade grants (fakes in tests); Win32 fast path. ⛔ C4 StorageFacade (SAF/MediaStore, bookmarks, pickers). |
| LIB-003 | Scan performance | B2 | ☐ | ☐ | ☐ | ☐ | B2: 10 k files 1.0–2.5 s initial / 0.2–0.55 s incremental (desktop); pause/resume/cancel; manual/on-open/watch. Phone budget: device lab. |
| LIB-004 | Folder mode and library mode | B2 | ☐ | ☐ | ☐ | ☐ | B2: folder browser + `ViewModeToggle` persisted per mode; C1–C3 place them in each mode. |
| LIB-005 | Search | B2 | ☐ | ☐ | ☐ | ☐ | B2: FTS5 prefix search, bm25, all doc 04 filters; 50 k items median 9.5 ms (desktop CI). |
| LIB-006 | Continue watching / recently added / recently played | B2 | ☐ | ☐ | ☐ | ☐ | B2: `HomeRow` continue/recently added/played/unwatched queries + widgets; C1–C3 place them; resume thumbnails from B1/C3. |
| LIB-007 | Playlists | B2 | ☐ | ☐ | ☐ | ☐ | B2: manual + smart playlists (rule builder, AND/OR, limit, sort), M3U/M3U8/PLS/XSPF/CUE parse (isolate, limits) and export. File import/export pickers → C4. |
| LIB-008 | Multiple queues | B2 | ☐ | ☐ | ☐ | ☐ | B2: named audio queues + one video queue, persisted, repeat/shuffle; queues screen. |
| LIB-009 | Tags and labels | B2 | ☐ | ☐ | ☐ | ☐ | B2: tags, colour labels, bulk apply; tag editor sheet. |
| LIB-010 | Watched/unwatched state and progress sync | B2 | ☐ | ☐ | ☐ | ☐ | B2: per-item progress/watched; `ProgressSyncTarget` seam for Jellyfin/Emby/Plex (C4 servers) and Trakt (needs owner client ID). |
| LIB-011 | Metadata scraping (video) | B2 | ☐ | ☐ | ☐ | ☐ | B2: filename parser, TMDB/TVDB clients through NetworkGateway, NFO, artwork cache, manual match. Live tests need owner API keys (§4). |
| LIB-012 | Collections | B2 | ☐ | ☐ | ☐ | ☐ | B2: series/season, albums/artists/genres/years/composers, TMDB collections; photo people/places come from C3. |
| LIB-013 | Parental PIN and hidden items | B2 | ☐ | ☐ | ☐ | ☐ | B2: PBKDF2 PIN (isolate), lockout, biometrics, locked sources/folders, hidden items excluded. Needs C4 SecureStorage/Biometrics facades on device. |
| LIB-014 | Duplicate finder | B2 | ☐ | ☐ | ☐ | ☐ | B2: exact hash, pHash (images), duration+size (video), chromaprint (audio) review UI; never deletes. ⛔ chromaprint native lib (B4). |
| LIB-015 | Statistics | B2 | ☐ | ☐ | ☐ | ☐ | B2: play counts, time played, top items, storage by type/source; statistics screen. |

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
| VID-001 | Containers | B1 | ☐ | ☐ | ☐ | ☐ |  |
| VID-002 | Video codecs | B1 | ☐ | ☐ | ☐ | ☐ |  |
| VID-003 | Audio codecs in video | B1 | ☐ | ☐ | ☐ | ☐ |  |
| VID-004 | Audio passthrough | B1 | ☐ | — | ☐ | ☐ |  |
| VID-005 | Playback edge cases | B1 | ☐ | ☐ | ☐ | ☐ |  |
| VID-006 | Network playback | B1 | ☐ | ☐ | ☐ | ☐ |  |
| VID-007 | DVD/Blu-ray folder playback | B1 | ☐ | ☐ | ☐ | ☐ |  |

### 4.2 Rendering, HDR, quality

| ID | Feature | Lane | A | I | M | W | Notes |
|---|---|---|:-:|:-:|:-:|:-:|---|
| VID-030 | GPU renderer | B1 | ☐ | ☐ | ☐ | ☐ |  |
| VID-031 | HDR10 / HLG | B1 | ☐ | ☐ | ☐ | ☐ |  |
| VID-032 | HDR10+ | B1 | ☐ | ☐ | ☐ | ☐ |  |
| VID-033 | Dolby Vision profile 8.1/8.4 | B1 | ☐ | ☐ | ☐ | ☐ |  |
| VID-034 | Dolby Vision profile 5 | B1 | ☐ | ☐ | ☐ | ☐ |  |
| VID-035 | Dolby Vision profile 7 (MEL/FEL) | B1 | ☐ | ☐ | ☐ | ☐ |  |
| VID-036 | Auto frame-rate and resolution matching | C1 | ☐ | — | ☐ | ☐ | Rel. 1.0 (TV UI 1.1) |
| VID-037 | Scaling and filters | C1 | ☐ | ☐ | ☐ | ☐ |  |
| VID-038 | User shaders | C1 | ☐ | ☐ | ☐ | ☐ |  |
| VID-039 | Frame interpolation | C1 | ☐ | ☐ | ☐ | ☐ |  |
| VID-040 | ICC / display calibration | C1 | — | — | ☐ | ☐ |  |
| VID-041 | 3D and 360° | C1 | ☐ | ☐ | ☐ | ☐ |  |
| VID-042 | Screenshot, GIF and clip export | C1 | ☐ | ☐ | ☐ | ☐ |  |

### 4.3 Controls and ergonomics

| ID | Feature | Lane | A | I | M | W | Notes |
|---|---|---|:-:|:-:|:-:|:-:|---|
| VID-060 | Gesture set | C1 | ☐ | ☐ | — | — |  |
| VID-061 | Seek bar | C1 | ☐ | ☐ | ☐ | ☐ |  |
| VID-062 | Speed | C1 | ☐ | ☐ | ☐ | ☐ |  |
| VID-063 | Frame step, A-B loop, chapters, bookmarks | C1 | ☐ | ☐ | ☐ | ☐ |  |
| VID-064 | Resume and post-playback | C1 | ☐ | ☐ | ☐ | ☐ |  |
| VID-065 | Audio/subtitle track switching | C1 | ☐ | ☐ | ☐ | ☐ |  |
| VID-066 | Audio delay and volume | C1 | ☐ | ☐ | ☐ | ☐ |  |
| VID-067 | Picture-in-Picture | C1 | ☐ | ☐ | ☐ | ☐ |  |
| VID-068 | Background and audio-only playback | C1 | ☐ | ☐ | ☐ | ☐ |  |
| VID-069 | Sleep timer and auto-off | C1 | ☐ | ☐ | ☐ | ☐ |  |
| VID-070 | Orientation and display | C1 | ☐ | ☐ | — | — |  |
| VID-071 | Second screen / external display | C1 | ☐ | ☐ | ☐ | ☐ |  |
| VID-072 | Info overlay | C1 | ☐ | ☐ | ☐ | ☐ |  |
| VID-073 | Skip intro/credits | C1 | ☐ | ☐ | ☐ | ☐ |  |
| VID-074 | Remote control | C1 | ☐ | ☐ | ☐ | ☐ |  |

### 5. SUB — Subtitles

| ID | Feature | Lane | A | I | M | W | Notes |
|---|---|---|:-:|:-:|:-:|:-:|---|
| SUB-010 | Text formats | B1 → C1 | ☐ | ☐ | ☐ | ☐ |  |
| SUB-011 | Image formats | B1 → C1 | ☐ | ☐ | ☐ | ☐ |  |
| SUB-012 | Embedded and external | B1 → C1 | ☐ | ☐ | ☐ | ☐ |  |
| SUB-013 | Encoding detection | B1 → C1 | ☐ | ☐ | ☐ | ☐ |  |
| SUB-014 | Styling | B1 → C1 | ☐ | ☐ | ☐ | ☐ |  |
| SUB-015 | Timing | B1 → C1 | ☐ | ☐ | ☐ | ☐ |  |
| SUB-016 | Dual subtitles | B1 → C1 | ☐ | ☐ | ☐ | ☐ |  |
| SUB-020 | Online download | C1 | ☐ | ☐ | ☐ | ☐ |  |
| SUB-030 | Subtitle editor | C1 | ☐ | ☐ | ☐ | ☐ |  |
| SUB-040 | Text-to-speech | C1 | ☐ | ☐ | ☐ | ☐ |  |
| SUB-050 | Auto-sync (audio-based) | C1 | ☐ | ☐ | ☐ | ☐ |  |
| SUB-051 | OCR of image subtitles | C1 | ☐ | ☐ | ☐ | ☐ |  |
| SUB-052 | Auto-captions (speech-to-text) | C1 | ☐ | ☐ | ☐ | ☐ |  |
| SUB-053 | Translation | C1 | ☐ | ☐ | ☐ | ☐ |  |

### 6.1 Formats and output

| ID | Feature | Lane | A | I | M | W | Notes |
|---|---|---|:-:|:-:|:-:|:-:|---|
| AUD-001 | Formats | B1 | ☐ | ☐ | ☐ | ☐ |  |
| AUD-002 | Gapless | B1 | ☐ | ☐ | ☐ | ☐ |  |
| AUD-003 | Crossfade | B1 | ☐ | ☐ | ☐ | ☐ |  |
| AUD-004 | Loudness | B1 | ☐ | ☐ | ☐ | ☐ |  |
| AUD-005 | DSP chain | B1 | ☐ | ☐ | ☐ | ☐ |  |
| AUD-006 | Output quality indicator | B1 | ☐ | ☐ | ☐ | ☐ |  |
| AUD-040 | Bit-perfect Android | B1 | ☐ | — | — | — |  |
| AUD-041 | Bit-perfect Apple | B1 | — | ☐ | ☐ | — |  |
| AUD-042 | Bit-perfect Windows | B1 | — | — | — | ☐ |  |
| AUD-043 | DSD | B1 | ☐ | ☐ | ☐ | ☐ |  |
| AUD-044 | Bluetooth | B1 | ☐ | ☐ | ☐ | ☐ |  |
| AUD-045 | Audio focus and interruptions | B1 | ☐ | ☐ | ☐ | ☐ |  |
| AUD-046 | Visualiser | C2 | ☐ | ☐ | ☐ | ☐ |  |

### 6.2 Music library and player UI

| ID | Feature | Lane | A | I | M | W | Notes |
|---|---|---|:-:|:-:|:-:|:-:|---|
| MUS-001 | Library views | C2 | ☐ | ☐ | ☐ | ☐ |  |
| MUS-002 | Tag reading | C2 | ☐ | ☐ | ☐ | ☐ |  |
| MUS-003 | Tag editing | C2 | ☐ | ☐ | ☐ | ☐ |  |
| MUS-004 | Art | C2 | ☐ | ☐ | ☐ | ☐ |  |
| MUS-005 | Lyrics | C2 | ☐ | ☐ | ☐ | ☐ |  |
| MUS-006 | Now Playing | C2 | ☐ | ☐ | ☐ | ☐ |  |
| MUS-007 | Queues | C2 | ☐ | ☐ | ☐ | ☐ |  |
| MUS-008 | Smart playlists | C2 | ☐ | ☐ | ☐ | ☐ |  |
| MUS-009 | Scrobbling | C2 | ☐ | ☐ | ☐ | ☐ |  |
| MUS-010 | Fingerprinting | C2 | ☐ | ☐ | ☐ | ☐ |  |
| MUS-011 | Sleep timer and alarms | C2 | ☐ | ☐ | ☐ | ☐ |  |
| MUS-012 | Widgets and quick controls | C2 | ☐ | ☐ | ☐ | ☐ |  |
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
| IMG-003 | Gallery performance | C3 | ☐ | ☐ | ☐ | ☐ |  |
| IMG-004 | Viewer | C3 | ☐ | ☐ | ☐ | ☐ |  |
| IMG-005 | Organisation | C3 | ☐ | ☐ | ☐ | ☐ |  |
| IMG-006 | Metadata | C3 | ☐ | ☐ | ☐ | ☐ |  |
| IMG-007 | Map | C3 | ☐ | ☐ | ☐ | ☐ |  |
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
| CAST-005 | Local transcoding | B1 | ☐ | ☐ | ☐ | ☐ |  |

### 10. SYS — Platform integration

| ID | Feature | Lane | A | I | M | W | Notes |
|---|---|---|:-:|:-:|:-:|:-:|---|
| SYS-001 | Media session | C4 | ☐ | ☐ | ☐ | ☐ |  |
| SYS-002 | Notifications/lock screen | C4 | ☐ | ☐ | ☐ | ☐ |  |
| SYS-003 | Shortcuts/intents | C4 | ☐ | ☐ | ☐ | ☐ |  |
| SYS-004 | Share targets | C4 | ☐ | ☐ | ☐ | ☐ |  |
| SYS-005 | File provider / Files integration | C4 | — | ☐ | 1.1 | 1.1 |  |
| SYS-006 | Foreground service & battery | C4 | ☐ | — | — | — |  |
| SYS-007 | Storage access | C4 | ☐ | ☐ | ☐ | ☐ |  |
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
| 2026-10-20 | B1 + B4a | All Android cells of PR #3 (install-size budget, docs/11 §5) | APK with all mediahro-deps libraries is 102.3 MB per ABI vs the 40 MB budget | B4a: per-library size table, strip, FFmpeg `--disable-everything` + explicit components, trimmed libvips; B1: no duplicate libraries | None — budget is not relaxed; owner sees the numbers if 40 MB proves impossible |
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
| Counsel: confirm export-compliance answers (App Store `ITSAppUsesNonExemptEncryption`, encryption inventory) given ADR-017 and the BoringSSL embedded in the Flutter engine for dart:io TLS | Before App Store submission | App Store submission | Open |
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
| B4a | TLS / crypto for native protocol clients on Android (curl FTPS, libssh2 SFTP): one crypto/TLS library on Android only, or SFTP/FTPS through the Android platform module over JCA (§3) | Resolved by ADR-017 (2026-10-20) |
| B4a | TLS stack of the Open Screen Cast sender: libcast requires BoringSSL (§3) | Resolved by ADR-017 (2026-10-20) |
| B4a | The Flutter engine (`libflutter.so`, `Flutter.framework`, `flutter_windows.dll`) statically contains BoringSSL for `dart:io` TLS. docs/05 §4.1 ("no OpenSSL/mbedTLS ships") and the docs/07 rule 12 encryption inventory should state this exception explicitly | Resolved by ADR-017 (2026-10-20) |

## 7. Log

| Date | Event |
|---|---|
| 2026-10-19 | Phase A started. Read CLAUDE.md order (01, 04, 05, 06, 07, 09, 10, 11; 03, 13 as needed). Flutter 3.47.7 pinned via FVM. |
| 2026-10-20 | Found three stalls: my `--no-dds` CI change broke Android integration on every PR (reverted, 6aa7fad); B1's PR #3 had 9 red jobs including a 102 MB Android APK (budget 40 MB) — B1 and B4a briefed. |
| 2026-10-20 | Owner decided ADR-017: SFTP/FTPS and the open Cast sender use OS crypto only (sshj/JCA, SwiftNIO SSH/CryptoKit, libssh2+WinCNG; OS TLS sockets for FTPS and CASTv2). `TlsSocketFacade` and `SftpFacade` added to app/lib/platform. NET-004 and CAST-001 are unblocked (sequencing: C4 platform modules). |
| 2026-10-19 | Merged B4a: mediahro-deps#1 (pinned sources, Android build, shared scripts, release workflow) and mediahro#4 (deps.lock → v2026.10.0-android.1, native licence scan: 293 components, 243 binaries, 0 errors). CI hardened: per-file integration timeouts + retry (iOS simulator hangs), licence scan now `--require-native`. Owner decision pending: crypto for SFTP/FTPS (NET-004) and the open Cast sender (CAST-001). |
| 2026-10-19 | Phase B running: B1 engine, B2 library & sources, B3 design & shell (Mediahro worktrees), B4a Android + shared, B4b Apple, B4c Windows (mediahro-deps worktrees). Six duplicate lane sessions created during the trust retries were deleted. |
| 2026-10-19 | Repos published (public): github.com/vasandkumar/mediahro, github.com/vasandkumar/mediahro-deps. First CI runs fixed (exec bits, ARB merge order, size-measurement symlink bug); CI fully green on all 16 jobs. **Phase A exit met.** |
| 2026-10-19 | M0 skeleton committed: workspace, 5 packages, app shell, interface stubs, tooling, CI workflows, `mediahro-deps` skeleton. Local proof: `tools/check` green (analyze, lints, l10n, status, manifests, 61 tests); Windows debug build + 3 integration tests pass; Android `foss` APK builds. ADR-011…016 recorded in docs/05 §12. |
