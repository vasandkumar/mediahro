# Lane briefs (docs/10 §8)

Each lane is one agent session working in **its own git worktree on its own folders** (ownership table: `STATUS.md` §1). The orchestrator merges, reviews gates, resolves ADRs and unblocks; it writes no feature code during Phases B–D.

## Rules for every lane

1. **Branch** `lane/<id>-<topic>` from `main` in your own worktree; rebase on `main` daily. Merge only through PRs to `vasandkumar/mediahro` (or `vasandkumar/mediahro-deps` for B4). The orchestrator merges.
2. **Read first:** `CLAUDE.md`, then the docs named in your brief, then this file.
3. **Tests first** for every feature ID (doc 11), named with the ID: `test('VID-062 speed presets persist per item', ...)`. Then core → bindings → platform modules → UI (docs/10 §4).
4. **Shared bookkeeping files are orchestrator-only (from 2026-10-20):** `STATUS.md`, `CHANGELOG.md` and `tools/perf/baseline.json` are not edited in lane PRs, because every lane touching them made each merge conflict the others and forced full CI re-runs. Put your ticks (with the evidence table), blockers, ADR requests, changelog lines and new baseline values in the PR description under **Bookkeeping**; the orchestrator applies them in the merge commit.
   **Never edit another lane's folders.** Each lane may add and edit its own user-help pages in `docs/help/` (one file per topic, front matter `ids:` listing your IDs). Shared files: `STATUS.md` (your rows and your Blockers/ADR-request rows only), `CHANGELOG.md` (your entries only). `app/pubspec.yaml` and `app/lib/main.dart` are the orchestrator's: put the dependency or wiring you need in the PR description under "Orchestrator changes needed" and the orchestrator applies it.
5. **Interfaces** in `packages/mediahro_engine/lib/src/api`, `app/lib/images/image_pipeline.dart`, `packages/mediahro_servers/lib/src/server_library.dart`, `packages/mediahro_ffi/lib/src/vfs`, `app/lib/platform/*.dart`, `app/lib/core/net/network_policy.dart` freeze at the end of Phase B. Until then the owning lane may extend them; afterwards changes need an ADR PR against docs/05 §12.
6. **Proof is CI**, not a local build (docs/10 §8 rule 4). This machine is Windows: iOS/macOS are proven only by the `macos-26` CI jobs on your PR.
7. **Tick** a STATUS.md cell ☑ only when that ID's AC pass on that platform in CI. A blocked cell becomes ⛔ with a row in STATUS.md §3; then continue with your next ID. Never narrow scope, never set a 1.0 cell to "—". Tests for a ⛔ cell are **skipped, never left failing**, with the blocker in the reason (`skip: 'blocked: STATUS §3 — libiconv for SUB-013 (B4a)'`); remove the skip in the PR that ticks the cell. A PR merges only with all CI green (every workflow it triggers), and its description carries an evidence table (ID · platform · run/job · passing test names) for every cell it ticks.
8. **Commits:** conventional, feature ID as scope, DCO sign-off (`git commit -s`), e.g. `feat(VID-062): speed presets with per-item memory`.
9. **Strings** only in your ARB fragment `<your folder>/l10n/<module>_en.arb`, keys prefixed with the module name (ADR-013). No concatenated sentences.
10. **Run `tools/check` before every push** (format, analyze, project lint rules, l10n, STATUS guard, manifest guard, all tests).
11. **Never** add analytics, crash reporting, update checks or any network call outside `NetworkGateway` and the PRIV-004 allow-list; never add GPL code; never attempt human-owned tasks (CLAUDE.md §6) — list them in STATUS.md §4 if you discover a new one.
12. Fan out read-only helpers (research, test-writing, review) freely; only you write to your folders.

## Phase B

| Lane | Brief |
|---|---|
| B1 Engine | [B1-engine.md](B1-engine.md) |
| B2 Library & sources | [B2-library-sources.md](B2-library-sources.md) |
| B3 Design system & shell | [B3-design-shell.md](B3-design-shell.md) |
| B4 Native deps (Android + shared / Apple / Windows) | [B4-native-deps.md](B4-native-deps.md) |

## Phase C (from 2026-10-20, ADR-025)

The interfaces froze at a138542. From here, changing anything in rule 5's files, or adding a facade, needs an ADR request. B1 stays the engine lane, and B2 and B3 stay as maintainers of their folders. B4a/b/c keep `mediahro-deps`.

| Lane | Brief |
|---|---|
| C1 Video & subtitles | [C1-video-subtitles.md](C1-video-subtitles.md) |
| C2 Music, podcasts & audiobooks | [C2-music-podcasts.md](C2-music-podcasts.md) |
| C3 Photos | [C3-photos.md](C3-photos.md) |
| C4a Android · C4b Apple · C4c Windows · C4d Servers & casting | [C4-servers-cast-platform.md](C4-servers-cast-platform.md) |
| C5 Supporter, privacy, B2B, engine packaging, store metadata | [C5-supporter-privacy-b2b.md](C5-supporter-privacy-b2b.md) |

### Speed rules (owner, 2026-10-20)

Phase B lost most of its time waiting rather than working. Of 189 CI runs, 120 were cancelled; each native-library round took about 2 hours; and failures went lane → CI → orchestrator → lane before anyone fixed them. From now on:

1. **Watch and fix your own CI.** After a push, run `gh pr checks <n> --watch` in the background. When it finishes, read the failures with `gh run view <run> --log-failed` and fix all of them in one batch. Don't wait for the orchestrator to relay them.
2. **Never idle while CI runs.** Keep working locally on your next IDs, on a new branch or PR if you like. Don't push to a PR whose CI is still running, because a push cancels it.
3. **Reproduce locally before pushing.**
   - Everyone: `tools/check`.
   - Windows: `flutter test integration_test -d windows`.
   - Android: the local emulator.
   - network-env: Docker Desktop and WSL Ubuntu are on this machine, so run `docker compose` in `packages/mediahro_ffi/test/network` locally.
   - Only iOS and macOS need CI to prove them.
4. **Small PRs** of 2–4 IDs or 1–2 facades. A PR touching only one platform's folders runs only that platform's jobs.
5. **Message the orchestrator only** when a PR is green and ready to merge, when you are blocked, or when you need an ADR. It merges green PRs as soon as it has checked the evidence.
6. **Disk: C: is nearly full, so nothing large goes there.** Your scratchpad lives under `C:\Users\...\Temp\claude`, so use it only for small notes and logs.
   - Put build output, downloaded archives, generated media and caches inside your worktree on K:, under a gitignored `build/` or `.cache/` folder.
   - A test file meant to be sparse must really be sparse: create it with `fsutil sparse setflag` and set its length, never by writing zeros, and check that its size on disk is near zero.
   - Android emulators live on K: (`ANDROID_AVD_HOME=K:\Projects\.android-avd` in your shell).
   - Delete large artefacts as soon as their test is done.
   - Before any step that writes more than 1 GB, check free space and stop if C: has less than 10 GB.
7. **At most 3 lane sessions run at once (owner).** The orchestrator schedules them. Never message another lane directly, because that wakes a paused session; send anything for another lane to the orchestrator.
8. **No GitHub CI for now (owner, 2026-10-20).** ci.yml and engine.yml run only on manual dispatch. **Proof is local:**
   - `tools/check` on your branch rebased on main.
   - The integration tests for your IDs on the owner's Android test device, a Samsung SM-M176B on Android 16 paired over wireless debugging. It's shared: take `K:\Projects\.device-lock` first, as in rule 6.
   - The Windows integration tests on this machine, if you touched shared Dart.

   Paste the commands and their pass lines into the PR's evidence table, with the device serial and the commit. The orchestrator re-runs `tools/check` on the merge result before merging. Never push in order to test, and never start a workflow.
9. **Samsung only, never an emulator (owner, 2026-10-20).** The test device is the owner's Samsung SM-M176B (Android 16, arm64), serial `adb-RZGL225BN7H-KoTKDF._adb-tls-connect._tcp`. Lanes share it through a lock kept on the phone, which replaces the `K:\Projects\.device-lock` folder from rule 6:
   - Take: `adb -s <serial> shell mkdir /data/local/tmp/mediahro-lock`. It fails if the lock is held, so retry after 60 s.
   - Mark: write `<lane> <epoch>` to `/data/local/tmp/mediahro-lock/owner`.
   - Release: `adb -s <serial> shell rm -rf /data/local/tmp/mediahro-lock`. Release even on failure.
   - Stale: a lock older than 30 minutes is stale.
   Hold it only while installing and testing. The orchestrator takes the same lock when it verifies PRs.
   In Git Bash, put `export MSYS_NO_PATHCONV=1` before these commands. Otherwise Git Bash rewrites `/data/...` into a Windows path and mkdir fails with a misleading error.
10. **Device testing in batches of 25 features (owner, 2026-10-20).**
    - A PR merges on local proof: `tools/check` plus unit and widget tests, re-run by the orchestrator on the merge result.
    - Its features are then "built, awaiting the device batch" (STATUS §1, *Android device batch*). They are not ☑ yet.
    - When 25 features are waiting, the orchestrator runs every listed integration test on the Samsung in one go. It ticks what passes and sends each lane its failures as one list.
    - Lanes don't wait for batch results: keep building. Fix batch failures first when they arrive.
11. **This PC has 16 GB RAM: be light (owner, 2026-10-20).** This replaces the 3-lane cap with 2.
    - **At most 2 lane sessions run at once.**
    - **Only one heavy build at a time across all sessions.** Heavy means Gradle/APK builds, desktop app builds, native C/C++ compiles or `flutter test integration_test`. Before starting one, check that no other `java`/Gradle, `clang`/`cmake` or WSL compile is running (`Get-Process java,cmake,ninja,clang` / `tasklist`). If one is, wait or do Dart-only work meanwhile.
    - **Lane proof is Dart-level:** `tools/check` plus unit and widget tests. Only the Android platform lane (C4a) builds APKs, to compile its Kotlin. Device runs and release builds are the orchestrator's.
    - **Keep your build folders while you are active** (fast incremental builds); they're deleted when your lane is paused or if the project goes over its 30 GB budget on K:.
    - **Never start an emulator, never start a GitHub workflow, nothing large on C:** (rules 6, 8, 9).
12. **Models (owner, 2026-10-20).** Lanes run on **Sonnet 5.5**; the orchestrator stays on Opus.
    - No session changes model mid-flight, because the cache would be lost.
    - For a genuinely hard sub-problem, a Sonnet lane hands that piece to an **Opus subagent** (Agent tool, `model: "opus"`) and continues with the result.
    - Every lane has a handoff file in `docs/lanes/handoff/` saying where it stands.

