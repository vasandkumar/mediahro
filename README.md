# Mediahro — Design and Build Documentation

**Mediahro** is a free, supporter-funded, bloat-free media app that plays video, plays music, and browses images on **Android, iOS/iPadOS, macOS and Windows** from one codebase, with feature parity that out-does the stock players on every platform.

This repository holds the **complete product, design, technical, business and legal plan** and the app being built from it by a coding agent following `CLAUDE.md`. Progress: [`STATUS.md`](STATUS.md). Code layout: `app/` (Flutter app), `packages/` (engine, FFI bindings, servers, subtitles, design system), `tools/` (lints, l10n, licence scan, status), sibling repo `mediahro-deps` (native libraries).

> Scope rule: there is **no MVP**. Every feature in `docs/04-feature-specification.md` is in scope for the 1.0 release. The development plan sequences the work; it does not cut it.

## Document map

| # | Document | What it answers |
|---|---|---|
| — | [CLAUDE.md](CLAUDE.md) | Instructions for the coding agent that will build the app: reading order, conventions, definition of done, non-negotiables. |
| 01 | [Product vision and strategy](docs/01-product-vision-and-strategy.md) | Why Mediahro exists, who it is for, principles, goals, success metrics. |
| 02 | [Market and competitive analysis](docs/02-market-and-competitive-analysis.md) | Synthesised research: competitors, gaps, table stakes, failure modes. |
| 03 | [Brand and naming](docs/03-brand-and-naming.md) | The name, clearance results, identity system, trademark path. |
| 04 | [Feature specification](docs/04-feature-specification.md) | Every feature with an ID, acceptance criteria and platform parity matrix. |
| 05 | [Technical architecture](docs/05-technical-architecture.md) | Stack decision, layers, engines, data model, performance budgets, decision log. |
| 06 | [UX and design system](docs/06-ux-and-design-system.md) | Information architecture, screens, gestures, tokens, platform adaptation, accessibility. |
| 07 | [Platform and store compliance](docs/07-platform-and-store-compliance.md) | Permissions, entitlements, privacy, payments and per-store submission checklists. |
| 08 | [Business plan](docs/08-business-plan.md) | B2C supporter model, B2B lines, pricing, financial model, KPIs. |
| 09 | [Legal and licensing](docs/09-legal-and-licensing.md) | Open-source licence policy, codec patents, trademark policy, privacy policy, terms. |
| 10 | [Development plan and roadmap](docs/10-development-plan-and-roadmap.md) | Repository layout, workstreams, milestones, CI/CD, release process. |
| 11 | [QA and testing strategy](docs/11-qa-and-testing-strategy.md) | Test pyramid, media corpus, device matrix, performance gates, release gates. |
| 12 | [Launch and marketing plan](docs/12-launch-and-marketing-plan.md) | Store listings, ASO, launch sequence, community, press. |
| 13 | [Operations, support and security](docs/13-operations-support-and-security.md) | Release cadence, support, telemetry policy, incident response, security model. |

## Research inputs

The `research/` folder holds the six sourced research reports (October 2026) that the documents above synthesise. They are reference material, not specifications; where they disagree with a `docs/` document, the `docs/` document wins.

| File | Topic |
|---|---|
| `research/01-video-players.md` | 19 video players profiled, feature matrix, failure modes |
| `research/02-audio-and-image-apps.md` | 24 audio players and 23 image viewers profiled |
| `research/03-store-compliance.md` | Apple, Google, Microsoft and alternative store policies |
| `research/04-tech-stack.md` | Frameworks, media engines, licences, platform constraints |
| `research/05-business-monetization.md` | Market, supporter models, B2B, GTM, financial skeleton |
| `research/06-naming-trademark.md` | 54 names screened, trademark filing path |

## Status

| Item | State |
|---|---|
| Research | Complete (2026-10-19) |
| Design documents | Complete, v1.0 |
| Name | **Mediahro** selected; professional trademark clearance still required before filing (see doc 03) |
| Code | Phase A (M0 bootstrap) in progress — progress is tracked in [`STATUS.md`](STATUS.md) |
