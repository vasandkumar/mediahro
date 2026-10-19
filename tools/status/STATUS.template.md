# Mediahro — STATUS

The single progress view for the owner. Every PR updates the rows it touches. Generated once from `docs/04` by `tools/status/gen_status.py`; CI (`tools/status/check_status.py`) fails if a doc 04 ID is missing or a 1.0 platform cell is narrowed.

**Legend:** ☐ to do · ☑ done (AC verified on that platform through the CI matrix) · ⛔ blocked (see Blockers) · — not applicable on that platform (doc 04) · 1.1/1.2 later release per doc 04 · Platforms: A Android · I iOS/iPadOS · M macOS · W Windows.

_Last updated: {{DATE}} by the orchestrator._

## 1. Phase and milestone gates

| Phase / milestone | Lanes | State | Exit criteria (docs/10 §3, §8) |
|---|---|---|---|
| **A — Skeleton (M0)** | orchestrator | in progress | Shell builds on all platforms; stubs compile; CI green; deps archives published with SHA-256; licence scan passes |
| **B — Foundations (M1, M2)** | B1 Engine · B2 Library & sources · B3 Design system & shell · B4 Native deps (Android / Apple / Windows) | not started | M1 + M2 exit criteria; B3 goldens green; deps archives published and pinned; **interface freeze** |
| **C — Experiences (M3–M7)** | C1 Video & subtitles · C2 Music & podcasts · C3 Photos · C4 Servers, casting, platform modules · C5 Supporter, privacy, B2B, store metadata | not started | Each lane's IDs ☑ on every platform; integration branch builds daily |
| **D — Hardening (M8)** | D1 Android · D2 iOS/iPadOS · D3 macOS · D4 Windows · D5 Localisation · D6 Store submission packs | not started | All doc 11 §7 release gates pass; 1.0 tagged |

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

{{FEATURES}}

## 3. Blockers

| Since | Lane | IDs / platforms | Blocker | Needs | Workaround in place |
|---|---|---|---|---|---|

## 4. Human-owned tasks (CLAUDE.md §6 — for the owner; never attempted by agents)

| Task | Needed by | Blocks | State |
|---|---|---|---|
| Professional trademark clearance and USPTO ITU filing (classes 9, 42), then EUIPO/UK | Before public beta | Store listings under the name | Open |
| Entity formation; store developer accounts in the entity name (Apple, Google Play incl. D-U-N-S, Microsoft Partner Center); name reservations | Before M7 | All store submissions, IAP products | Open |
| Signing certificates and secrets: Apple distribution + Developer ID (G2 Sub-CA), Fastlane `match` repo, Play upload key, Azure Artifact Signing / OV cert, Sparkle EdDSA key, F-Droid key registration; add to GitHub environments | Before M7 | Signed CI artefacts, TestFlight, notarisation | Open |
| Apple entitlement requests: multicast networking (SSDP/DLNA), CarPlay audio | M1 (request early) | NET-005, CAST-003 on iOS; MUS-013 on iOS | Open |
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

## 7. Log

| Date | Event |
|---|---|
