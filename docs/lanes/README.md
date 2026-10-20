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

Shared CI capacity is the bottleneck, especially the macOS runners. Batch your work into one push per PR round, never push while your CI runs, and run `tools/check` locally first.

