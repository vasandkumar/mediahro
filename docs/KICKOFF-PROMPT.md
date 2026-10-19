# Kickoff prompt for the build session (Claude Opus 5.5)

Open a Claude Code session in `K:\Projects\Mediahro`, set the model to Opus 5.5, and paste the prompt below. The word "ultracode" at the start opts the session into multi-agent orchestration (it may use the Workflow tool to run lanes as parallel agents); if you prefer plain subagents, delete that word and keep the rest.

---

ultracode

Read CLAUDE.md and follow its reading order completely before writing any code. You are building Mediahro end to end; there is no MVP and no feature in docs/04 may be dropped or deferred on any platform.

Execute the build according to docs/10 section 8 "Parallel execution plan":

1. Phase A yourself: milestone M0 (repo skeleton, CI matrix, flavours, design tokens, l10n pipeline, STATUS.md with every feature ID from docs/04 and per-platform checkboxes, interface stubs for PlaybackEngine, ImagePipeline, ServerLibrary, VirtualFile and the platform facades, and the mediahro-deps skeleton). Commit when the shell builds and CI is green.

2. Then become the orchestrator. Launch the four Phase B lanes in parallel (B1 Engine, B2 Library and sources, B3 Design system and shell, B4 Native deps with one sub-lane per platform), each as its own agent in its own git worktree owning only the folders listed for it in docs/10 section 8. Wait for all four to meet their exit criteria, merge them, and declare the interface freeze.

3. Launch the five Phase C lanes in parallel (C1 Video and subtitles, C2 Music and podcasts, C3 Photos, C4 Servers, casting and platform modules, C5 Supporter, privacy, B2B and store metadata). Each lane writes the acceptance tests for its feature IDs first, implements core then bindings then platform modules then UI, proves every platform through the CI matrix, and ticks its IDs in STATUS.md through PRs. A lane that is blocked records the blocker in STATUS.md and continues with its next ID.

4. Launch the Phase D QA lanes (one per platform plus localisation and store submission packs), merge fixes back through the owning lanes, and stop only when every doc 11 release gate passes and 1.0 is tagged.

Rules for you as orchestrator: during Phases B to D you merge, review milestone gates against the exit criteria in docs/10 section 3, resolve ADR requests in docs/05 section 12 and unblock lanes; you do not write feature code yourself. Lanes never edit each other's folders. Human-owned tasks in CLAUDE.md section 6 are listed in STATUS.md for me, never attempted. Report progress by updating STATUS.md; I will read that file, not chat.

Start now with Phase A.
