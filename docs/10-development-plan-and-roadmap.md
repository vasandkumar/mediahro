# 10 — Development Plan and Roadmap

Version 1.0 · 2026-10-19 · The plan sequences the full 1.0 scope (doc 04); it does not reduce it. Milestones are engineering gates, not release tiers.

## 1. Ways of working

- **Monorepo** per doc 05 §3; trunk-based with short-lived branches; every PR runs the full CI matrix; conventional commits; CHANGELOG generated from PR labels.
- **Definition of Done (per feature ID):** code + tests (unit, widget/golden, integration where the AC needs a device), AC verified on every listed platform, docs updated (user help + API docs), strings externalised, accessibility checked (labels, focus, contrast), performance budget unaffected (CI perf job), licence scan clean, feature flag removed.
- **Feature flags:** every milestone's features ship behind `Flags` (local JSON + optional remote static JSON) until the milestone gate passes; flags are deleted before 1.0.
- **Toolchain pins:** Flutter via FVM (`.fvmrc`), NDK r28.x, Xcode 26.x, Windows App SDK 2.5.x, Dart SDK matched to Flutter; `mediahro-deps` release hash pinned in `deps.lock`.
- **Issue hygiene:** every bug references a feature ID; every PR references issues; release notes are grouped by feature area.

## 2. Workstreams

| Workstream | Scope | Primary docs |
|---|---|---|
| W1 Foundation | Repo, CI, flavours, design system, routing, settings, l10n, index DB, scanner, sources framework | 05, 06 |
| W2 Playback engine | libmpv FFI, render path per platform, PlaybackEngine, HDR, shaders, audio DSP, casting pipeline | 05 §4, 04 VID/AUD/CAST |
| W3 Video experience | Player UI, gestures, subtitles (all SUB-*), library/metadata, continue watching | 04, 06 |
| W4 Music experience | Library, Now Playing, queues, lyrics, tags, scrobbling, podcasts/audiobooks, car, widgets | 04 MUS/POD |
| W5 Photos experience | Image pipeline, gallery, viewer, metadata, map, compare, editor, vault, duplicates, slideshow | 04 IMG |
| W6 Sources and servers | SMB/NFS/WebDAV/FTP/SFTP/DLNA/cloud, Jellyfin/Emby/Plex/Subsonic/Immich/Nextcloud/Audiobookshelf, downloads | 04 NET |
| W7 Platform integration | Media sessions, PiP, storage/permissions, file associations, share targets, widgets, intents, foldables, external display | 04 SYS, 07 |
| W8 Supporter, privacy, B2B | IAP rails, web rail, privacy dashboard, telemetry opt-in, managed config, kiosk, control API, Engine packaging | 04 SUP/PRIV/B2B, 08 |
| W9 Quality and release | Test corpus, device matrix, perf harness, fuzzing, store assets, submissions, F-Droid, winget, Homebrew | 11, 12, 07 |

## 3. Milestones

Each milestone ends with a gate review against its exit criteria; nothing is deferred out of 1.0 at a gate, only re-sequenced.

| Milestone | Content | Exit criteria |
|---|---|---|
| **M0 Bootstrap** | Repo, CLAUDE.md conventions, Flutter app shell on 4 platforms, CI matrix green, flavours, design tokens, l10n pipeline, `mediahro-deps` repo building FFmpeg/mpv/libplacebo/libass/dav1d/libvips/libjxl/libavif/LibRaw/libsmb2/libnfs/libarchive/libebur128/chromaprint/libopenmpt/whisper.cpp/uchardet for all targets with licence scan | Hello-world app launches on A/I/M/W from CI artefacts; deps archives published with SHA-256; licence scan passes |
| **M1 Engine** | `MpvEngine` FFI + render path on all four; hwdec verified; HDR passthrough and tone mapping; libass; audio output backends incl. exclusive modes; gapless; DSP chain; casting server + remux/transcode | Test corpus (doc 11) plays on all platforms with AC for VID-001…007, VID-030…035, SUB-010…016, AUD-001…006, AUD-040…045 met; first-frame ≤ 500 ms |
| **M2 Library and sources** | Index DB, scanner, local sources (SAF/PhotoKit/bookmarks), file browser and ops, archives, search, playlists/queues, SMB/NFS/WebDAV/FTP/SFTP/DLNA/cloud, Wi-Fi transfer | LIB-*, FILE-*, NET-001…007, NET-018/019 AC met; 10 k-file scan ≤ 30 s |
| **M3 Video experience** | Player UI and gestures, side sheets, PiP, background, external display, speed/frame/loop/chapters/bookmarks, online subtitles, subtitle editor, auto-sync, OCR, auto-captions, translation, local metadata library (filename parser, NFO; no online scraper, ADR-048), skip-intro, web remote, screenshots/GIF/clip, 3D/360, shaders UI | All VID-* and SUB-* AC met on all platforms |
| **M4 Music experience** | Library views, tags read/write, art, lyrics (incl. LRCLIB, editor), Now Playing, queues, smart playlists, scrobbling (ListenBrainz), sleep/alarm, widgets, Android Auto/CarPlay, radio, podcasts/audiobooks, Audiobookshelf, visualiser, bit-perfect paths with indicator | All MUS-*, POD-*, AUD-046 AC met |
| **M5 Photos experience** | Image pipeline (OS-first + vips/jxl/avif/raw), gallery performance, viewer with tiling, organisation incl. people/places, metadata edit, map, compare, editor, batch, vault, slideshow, duplicates, trash, sharing/print/wallpaper, archives/comics, screensaver, Immich/Nextcloud/PhotoPrism sources | All IMG-* AC met; 50 k-item scroll jank-free |
| **M6 Servers and platform integration** | Jellyfin, Emby, Plex, Subsonic family, Nextcloud, Mediahro-to-Mediahro, offline downloads; media sessions, notifications/Live Activities, intents, share targets, Files provider, foldables, input devices; Cast SDK/AirPlay/DLNA push | NET-010…017, CAST-*, SYS-001…009, SYS-011 AC met |
| **M7 Supporter, privacy, B2B, compliance** | IAP rails per store, web rail gating, perks, ask policy, privacy dashboard, opt-in Sentry/Aptabase, vault/app lock, managed config, kiosk, control API, Engine packaging + C API, SBOM, accessibility report; store listings and metadata; closed test on Play (12 × 14 days) started | SUP-*, PRIV-*, B2B-* AC met; all doc 07 checklists green in a dry run |
| **M8 Hardening and release** | Full regression on device matrix, performance gates, fuzzing, battery tests, localisation QA (12 languages), beta programmes (TestFlight, Play closed/open, Windows Insider-style direct beta, F-Droid test repo), bug burn-down to zero P0/P1 | Release gates in doc 11 §7 pass; submissions accepted on all stores; 1.0 tagged |

Post-1.0 train (monthly): **1.1** Android TV Leanback + tvOS native UI, Wear/watchOS companion, Quick Look/Explorer handlers, Engine docs/samples; **1.2** Linux desktop, Flathub/Snap/AUR; **1.3+** community roadmap.

## 4. Build order inside each milestone (for the coding agent)

1. Read the feature IDs in scope; write the acceptance tests first (unit + integration stubs).
2. Implement domain/core (Dart) → engine/pipeline bindings → platform modules → UI.
3. Run the full CI matrix; fix platform divergences before adding the next feature.
4. Update user help (`docs/help/`), release notes and the feature-ID checklist in `STATUS.md`.
5. Never leave a platform behind: a feature is not merged until it passes on every platform listed in doc 04.

## 5. CI/CD

| Job | Runner | What |
|---|---|---|
| `analyze` | ubuntu | `dart analyze`, `dart format --set-exit-if-changed`, custom lints (no direct MethodChannel, no `print`, strings externalised) |
| `test-unit` | ubuntu | Dart unit + widget + golden tests (per platform family theme) |
| `build-android` | ubuntu | AAB (store), APK (foss, direct); `zipalign -c -P 16`; size report |
| `build-ios` | macos-26 | Archive (store), TestFlight upload via Fastlane; privacy manifest check |
| `build-macos` | macos-26 | MAS archive + direct notarised DMG; Sparkle appcast |
| `build-windows` | windows | MSIX (store) + signed installer (direct); WACK |
| `integration-android` | ubuntu + emulator (API 36, 16 KB image) | integration_test suite; media corpus playback |
| `integration-ios` | macos-26 simulator + device farm (optional) | same |
| `integration-macos` / `integration-windows` | native runners | same |
| `perf` | all four | cold start, first frame, scroll jank, memory, binary size vs budgets; fails on regression > 5 % |
| `fuzz` | ubuntu (nightly) | subtitle/playlist/metadata/image parsers (libFuzzer via deps + Dart fuzz harness) |
| `licence-sbom` | ubuntu | SBOM, licence scan, configure-flag verification |
| `l10n` | ubuntu | Weblate sync, missing-string check |
| `release` | all | tag → artefacts, checksums, SBOM, GitHub Release, store uploads (manual approval), winget PR, Homebrew PR, F-Droid metadata bump |

Secrets: Fastlane `match` for Apple; Play upload key; Azure Artifact Signing; all in GitHub environments with required reviewers for release.

## 6. Release process

- Monthly train after 1.0: feature freeze day 1, beta day 7 (TestFlight/Play open testing/direct beta), release day 21 if gates pass; hotfix any time.
- Versioning: `MAJOR.MINOR.PATCH` with build numbers per platform; same version across stores on the same day.
- Release notes: user-facing, grouped, specific (Apple rejects generic notes); F-Droid changelogs per versionCode.
- Rollback: staged rollout on Play (10 → 50 → 100 %), phased release on App Store, Store flighting on Microsoft; direct builds keep the previous installer available.

## 7. External deadlines to track

| Date | Item |
|---|---|
| Now | Xcode 26 / iOS 26 SDK for uploads; API 36 for Play |
| 2026-11-01 | Play API 36 extension deadline |
| 2027-02-01 | Google 16 KB hard block; Apple Developer ID G2 Sub-CA requirement |
| 2027-04 | iOS 27 SDK minimum; iPhone Duo screenshots |
| 2027 | Android developer verification global |
| macOS 27 | Apple-silicon-only (ship arm64; universal until then) |

## 8. Parallel execution plan (for an agent-driven build)

The milestones in §3 are gates, not a single queue. Once the skeleton exists, most work is independent and must run in parallel lanes. Each lane is one agent (a subagent, a workflow step or a separate session) working in **its own git worktree on its own folders**; lanes never edit the same files. Shared interfaces are frozen at the end of Phase B and changed only through an ADR.

| Phase | Mode | Lanes (worktree · folders owned) | Exit |
|---|---|---|---|
| **A — Skeleton** | Serial (one agent) | M0: repo, CI, flavours, tokens, l10n, `STATUS.md`, interface stubs (`PlaybackEngine`, `ImagePipeline`, `ServerLibrary`, `VirtualFile`, platform facades), `mediahro-deps` skeleton | Shell builds on all platforms; stubs compile; CI green |
| **B — Foundations** | Parallel, 4 lanes | B1 Engine · `app/lib/engine`, `packages/mediahro_ffi` (mpv part) · M1 scope. B2 Library & local/network sources · `app/lib/core`, `packages/mediahro_ffi` (smb2/nfs/curl/archive/ebur128/chromaprint parts), `app/lib/features/sources` · M2 scope. B3 Design system, shell, settings, onboarding, privacy dashboard · `packages/mediahro_design`, `app/lib/app`, `app/lib/ui`, `app/lib/features/settings`, `app/lib/features/onboarding`. B4 Native deps · `mediahro-deps` (one sub-lane per platform: Android, Apple, Windows) producing pinned archives and the licence scan | M1 + M2 exit criteria; B3 goldens green; deps archives published and pinned; **interface freeze** |
| **C — Experiences** | Parallel, 5 lanes | C1 Video + subtitles · `app/lib/features/video`, `packages/mediahro_subtitles` · M3. C2 Music + podcasts · `app/lib/features/music` · M4. C3 Photos · `app/lib/features/photos`, `app/lib/images`, image parts of `mediahro_ffi` · M5. C4 Servers, casting, platform modules · `packages/mediahro_servers`, `app/lib/features/servers`, `app/lib/features/cast`, `app/lib/platform`, `app/android`, `app/ios`, `app/macos`, `app/windows` · M6. C5 Supporter, privacy, B2B, Engine packaging, store metadata · `app/lib/features/supporter`, `app/lib/features/b2b`, `packages/mediahro_engine`, `fastlane/` · M7 | Each lane's feature IDs ☑ on every platform in `STATUS.md`; integration branch builds daily |
| **D — Hardening** | Parallel QA lanes, serial release | D1–D4 one lane per platform running the doc 11 matrix, corpus, perf and accessibility audits; D5 localisation QA; D6 store submission packs. Fixes go back to the owning C lane's folders | All doc 11 release gates pass; 1.0 tagged |

Rules for every lane:

1. Work in a worktree branched from `main`; rebase daily; merge through PRs that update `STATUS.md` for your IDs only.
2. Write the acceptance tests for your feature IDs first (doc 11), then implement core → bindings → platform modules → UI.
3. Never edit another lane's folders. If you need an interface change, open an ADR PR against `docs/05 §12` and wait for it to merge.
4. Every platform listed for an ID must pass before the ID is ticked; use the CI matrix, not a local build, as the proof.
5. Inside a lane you may fan out read-only subagents (research, test-writing, review) freely; only one writer per folder.
6. A lane that is blocked records the blocker in `STATUS.md` and continues with its next ID; it does not idle and it does not narrow scope.

The orchestrating agent owns Phase A, launches Phase B lanes, waits for the interface freeze, launches Phase C, then Phase D, and never writes feature code itself during B–D; its job is merging, gate reviews and unblocking.

## 9. Staffing model for the build

The initial build is executed by a coding agent (Claude Opus 5.5) following `CLAUDE.md`, with a human owner reviewing milestone gates, holding secrets and store accounts, and handling the legal/registration tasks in doc 09 §7. Human review is mandatory at each gate and before any store submission.
