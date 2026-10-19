# CLAUDE.md — Build brief for Mediahro

You are building **Mediahro**, a free, supporter-funded, bloat-free media app (video player, music player, image viewer/gallery) for Android, iOS/iPadOS, macOS and Windows from one Flutter codebase with a libmpv playback engine. This folder is the app's home. The documents in `docs/` are the contract; this file tells you how to execute it.

## 1. Non-negotiables

1. **No MVP.** The full scope of `docs/04-feature-specification.md` (every row marked 1.0) ships in 1.0 on every platform listed for it. Milestones in `docs/10` sequence the work; they never cut it. If something is blocked, finish everything else, record the blocker in `STATUS.md`, and continue; never silently narrow a feature.
2. **No ads, no accounts, no feature gates, no telemetry by default.** Supporter perks are cosmetic only.
3. **Licence policy is absolute** (`docs/09`): no GPL code in any binary; LGPL only dynamically linked; FFmpeg/mpv built without `--enable-gpl`/`--enable-nonfree`/`-Dgpl=true`; no Exiv2, x264, x265, rubberband, libdvdcss, libpostproc-GPL, smbclient, torrent. The CI licence scan must pass.
4. **Store policy is absolute** (`docs/07`): no `MANAGE_EXTERNAL_STORAGE`; `READ_MEDIA_*` with declarations and picker fallbacks; tips via platform IAP; external links storefront-gated; privacy manifest; sandbox entitlements on Mac App Store; no IPTV lists/EPG/add-ons; no competitor or codec trademarks in metadata; no Dolby/DTS/Chromecast marks outside permitted uses.
5. **Performance budgets are tests** (`docs/11 §5`). A change that regresses a budget by more than 5 % does not merge.
6. **Every platform, every feature.** A feature is done only when its acceptance criteria pass on each platform listed in doc 04. Do not merge a feature that works on three platforms.
7. **Native code only in the platform modules** listed in `docs/05 §8`, reached through typed facades. Feature code never calls `MethodChannel` directly. All C libraries are reached through `ffigen`-generated bindings in `packages/mediahro_ffi`.
8. **Accessibility is part of done:** labels, focus order, 44 pt targets, contrast, reduced motion, Dynamic Type to 200 %, captions honouring system styles.
9. **Strings are externalised** from the first commit (ARB files, Weblate-ready). No concatenated sentences.
10. **Security:** parsers run in isolates with limits; credentials only in OS secure storage; no secrets in the repo.

## 2. Reading order (do this before writing code)

1. `README.md` → this file.
2. `docs/01-product-vision-and-strategy.md` (principles, quality bars).
3. `docs/04-feature-specification.md` (the contract; note the ID scheme).
4. `docs/05-technical-architecture.md` (stack, repo layout, engine, data model, ADRs).
5. `docs/06-ux-and-design-system.md` (IA, screens, tokens, gestures, shortcuts, accessibility).
6. `docs/07-platform-and-store-compliance.md` and `docs/09-legal-and-licensing.md` (constraints).
7. `docs/10-development-plan-and-roadmap.md` (milestones, DoD, CI) and `docs/11-qa-and-testing-strategy.md` (tests, corpus, budgets, gates).
8. `docs/03`, `docs/08`, `docs/12`, `docs/13` as needed (brand assets, supporter copy, store listing generation, security model).
9. `research/*` only when a doc cites it and you need the evidence.

## 3. How to work

- **Start at M0** in `docs/10 §3` and proceed milestone by milestone. Inside a milestone follow `docs/10 §4`: tests for the ACs first, then core → bindings → platform modules → UI.
- **Create `STATUS.md`** at the root on day one: a checklist of every feature ID from doc 04 with columns per platform (☐/☑) and a blockers section. Update it in every PR. It is the single progress view the owner reads.
- **Repository layout** exactly as `docs/05 §3`. Create `mediahro-deps` as a sibling folder/repo with the build scripts for the native libraries and the exact configure flags from `docs/05 §4.1` and `§10`; publish archives with SHA-256 and pin them in `deps.lock`. During M0 you may bootstrap with media_kit's prebuilt libmpv packages, but ADR-004 requires the app's own `dart:ffi` wrapper over `mpv_render_context` and replacement of the prebuilts by `mediahro-deps` before M1 exits.
- **Toolchain pins:** Flutter via FVM (`.fvmrc`), NDK r28+, Xcode 26+, Windows App SDK 2.5+, Dart matching Flutter. Record versions in `TOOLCHAIN.md`.
- **Flavours:** `store`, `direct`, `foss`, `enterprise` via `--dart-define=MEDIAHRO_FLAVOR=` plus Gradle/Xcode configurations; feature code reads capabilities through the `Capabilities` service only.
- **Commits:** conventional commits with the feature ID in the scope, e.g. `feat(VID-067): system PiP on iOS via sample-buffer layer`. DCO sign-off on every commit.
- **Tests:** `dart test`, `flutter test` (widgets and goldens per platform family), `integration_test` on emulator/simulator/desktop, the media-corpus harness, perf harness, fuzz targets. Add tests with the feature, not after.
- **Docs:** user help in `docs/help/` (rendered in-app offline and on the site); API docs for `mediahro_engine`; keep `CHANGELOG.md` and `STATUS.md` current.
- **When a doc is ambiguous,** choose the interpretation that preserves full scope and platform parity, record the choice in `docs/05 §12` as a new ADR, and continue. Do not stop to ask unless the choice is irreversible or legally sensitive.
- **When an upstream library blocks a feature,** implement the fallback named in the docs (e.g. Apple native engine fallback in `docs/05 §2`, Open Screen Cast on desktop, Photo Picker on Android) and record it; never drop the feature.
- **Never** add analytics, crash reporting, update checks or any network call that is not listed in the privacy dashboard allow-list (`docs/05 §9`, `PRIV-004`).

## 4. Conventions

- Dart: `very_good_analysis`-level lints plus project rules (no `print`, no direct `MethodChannel`, no string concatenation for UI, no `dynamic` in public APIs); feature-first folders; Riverpod (or equivalent) for state with immutable models (`freezed`); `drift` for SQLite; `go_router` for navigation; `ffigen` for bindings; `pigeon` for platform channels.
- Kotlin: Media3, coroutines, no Java; Swift: async/await, no Objective-C except bridging; C++/WinRT for Windows modules.
- Naming: feature IDs in test names (`test('VID-062 speed presets persist per item', ...)`).
- Golden files per platform family and theme; update only with intent.
- Performance: nothing heavy on the UI isolate; viewport-priority queues for scans and thumbnails.
- Errors: user-facing messages per `docs/06 §8`; engine errors mapped to actionable copy.

## 5. Definition of done (per feature ID)

Code + tests on every listed platform · AC verified · docs/help updated · strings externalised · accessibility checked · performance budgets unaffected · licence scan clean · `STATUS.md` ticked · feature flag removed by milestone gate.

## 6. Human-owned tasks (do not attempt; flag in `STATUS.md` when needed)

Trademark clearance and filings; entity formation; store developer accounts and name reservations; signing certificates and secrets; multicast/CarPlay entitlement requests; third-party API keys and terms acceptance; MDM test tenant; device lab; final store submissions (prepare everything, the owner presses submit).

## 7. Parallel execution

Follow `docs/10 §8`. Phase A (M0 skeleton and interface stubs) is done by you alone. After that you are the **orchestrator**: launch the Phase B lanes in parallel, each as its own agent in its own git worktree owning only the folders listed for it; freeze the shared interfaces; launch the five Phase C lanes; then the Phase D QA lanes. During B–D you merge PRs, review milestone gates against the exit criteria, resolve ADR requests and unblock lanes; you do not write feature code yourself. Lanes never share files; a lane that is blocked records it in `STATUS.md` and moves to its next feature ID.

## 8. Deliverable for 1.0

A tagged release where: every doc 04 `1.0` row is ☑ on every listed platform in `STATUS.md`; all doc 11 release gates pass; store packages, direct installers, F-Droid metadata, winget and Homebrew manifests are generated; and the owner has a one-page submission checklist per store with nothing left but credentials.
