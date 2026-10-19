# Lane briefs (docs/10 §8)

Each lane is one agent session working in **its own git worktree on its own folders** (ownership table: `STATUS.md` §1). The orchestrator merges, reviews gates, resolves ADRs and unblocks; it writes no feature code during Phases B–D.

## Rules for every lane

1. **Branch** `lane/<id>-<topic>` from `main` in your own worktree; rebase on `main` daily. Merge only through PRs to `vasandkumar/mediahro` (or `vasandkumar/mediahro-deps` for B4). The orchestrator merges.
2. **Read first:** `CLAUDE.md`, then the docs named in your brief, then this file.
3. **Tests first** for every feature ID (doc 11), named with the ID: `test('VID-062 speed presets persist per item', ...)`. Then core → bindings → platform modules → UI (docs/10 §4).
4. **Never edit another lane's folders.** Each lane may add and edit its own user-help pages in `docs/help/` (one file per topic, front matter `ids:` listing your IDs). Shared files: `STATUS.md` (your rows and your Blockers/ADR-request rows only), `CHANGELOG.md` (your entries only). `app/pubspec.yaml` and `app/lib/main.dart` are the orchestrator's: put the dependency or wiring you need in the PR description under "Orchestrator changes needed" and the orchestrator applies it.
5. **Interfaces** in `packages/mediahro_engine/lib/src/api`, `app/lib/images/image_pipeline.dart`, `packages/mediahro_servers/lib/src/server_library.dart`, `packages/mediahro_ffi/lib/src/vfs`, `app/lib/platform/*.dart`, `app/lib/core/net/network_policy.dart` freeze at the end of Phase B. Until then the owning lane may extend them; afterwards changes need an ADR PR against docs/05 §12.
6. **Proof is CI**, not a local build (docs/10 §8 rule 4). This machine is Windows: iOS/macOS are proven only by the `macos-26` CI jobs on your PR.
7. **Tick** a STATUS.md cell ☑ only when that ID's AC pass on that platform in CI. A blocked cell becomes ⛔ with a row in STATUS.md §3; then continue with your next ID. Never narrow scope, never set a 1.0 cell to "—".
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
