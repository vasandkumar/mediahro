# 13 — Operations, Support and Security

Version 1.0 · 2026-10-19

## 1. Operating principles

No backend to run, no accounts to manage, no user media stored by us. Operations are: shipping builds, answering people, watching quality signals, and keeping the three small self-hosted services (crash intake, analytics intake, website) alive.

## 2. Infrastructure

| Service | Choice | Notes |
|---|---|---|
| Website, help, downloads | Static site (GitHub Pages or Cloudflare Pages) at mediahro.com; release artefacts on GitHub Releases | No server-side code |
| Feature flags / remote config | Static JSON on the site (`/config/flags.json`, signed) | Read only when the user enabled "check for configuration updates"; defaults bundled |
| Crash reports (opt-in) | Self-hosted Sentry (FSL) or GlitchTip (MIT) on a small VPS in the EU | PII scrubbing server-side too; 90-day retention |
| Analytics (opt-in) | Self-hosted Aptabase (AGPL server) on the same VPS | No identifiers; daily rotating hash; 12-month aggregates |
| Translations | Hosted Weblate (OSS plan) | |
| Payments | Store IAP; MoR (Paddle/Polar) for web; GitHub Sponsors; Liberapay | No card data touches our systems |
| Email | Transactional only (support@, legal@, security@) via a privacy-respecting provider | No marketing automation beyond the opt-in newsletter |
| Backups | Nightly VPS snapshot; GitHub is the source of truth for everything else | |

Monthly cost under USD 50 at launch scale.

## 3. Release operations

- Monthly train (doc 10 §6); hotfix path with the same gates minus beta duration.
- Store rollouts staged; direct builds keep N−1 installers available; Sparkle/own-updater feeds signed.
- Every release: changelog, SBOM, checksums, signed artefacts, store metadata diff, F-Droid metadata bump, winget/Homebrew PRs, post in Discussions/Matrix.
- Deprecation policy: OS minimums reviewed yearly; announced two trains ahead.

## 4. Support

| Channel | Use | Target |
|---|---|---|
| In-app Help (offline docs) | First line: formats, sources, troubleshooting, FAQ | Covers 80 % of questions |
| "Report a playback problem" | Pre-filled GitHub issue (device, OS, codec string, hwdec path) — user reviews before sending | — |
| GitHub Issues | Bugs and feature requests; templates; triage labels by feature ID | Triage within 3 business days |
| GitHub Discussions / Matrix | Community Q&A | Community-moderated |
| support@mediahro.com | Store-review follow-ups, payment questions, B2B | 2 business days |
| Store review replies | Every review in first 90 days, then all ≤ 3★ | 3 days |
| B2B support contracts | SLA per contract (P0 4 h, P1 1 day) | Contract |

Support never asks for media files; reproduction uses the public test corpus or a user-provided sample stripped of personal content.

## 5. Quality monitoring

- Store vitals (crash/ANR, ratings), opt-in crash dashboard, nightly corpus results, perf trend charts, GitHub issue inflow by feature ID.
- Weekly quality review; monthly State of Quality note in dev notes.
- Alerting: crash-free sessions < 99.5 % or any P0 → hotfix process.

## 6. Security model

### 6.1 Threats

Hostile media files (containers, codecs, subtitles, images, archives, playlists), hostile network shares/servers, hostile URLs, local attackers (vault), supply chain (dependencies, build), impersonation (clones).

### 6.2 Controls

- **Parsing in sandboxes:** subtitle/playlist/XMP/M3U/archive listing in Dart isolates with size/time limits; native decoders run inside the engine process with hardened builds (`-D_FORTIFY_SOURCE=2`, stack protector, CFI where supported, PIE/ASLR, no executable stack); fuzzing nightly (doc 11).
- **Network:** TLS via OS; self-signed certs only after fingerprint confirmation; no credential reuse across servers; credentials in OS secure storage; local control API bound to loopback unless explicitly exposed with a token; web remote/transfer pages use random per-session tokens and are off by default.
- **Vault:** AES-256-GCM with per-file keys wrapped by a master key held in Secure Enclave/StrongBox/Keystore/DPAPI; biometric unlock; no cloud backup of vault keys; export requires passphrase.
  - Crypto runs through OS APIs behind `VaultCryptoFacade`, and the vault window is excluded from screenshots and recents by `SecureWindowFacade` (ADR-039). The decoy vault is indistinguishable from the real one on entry and on disk (ADR-040).
- **Updates:** store-signed or EdDSA-signed appcasts; installers signed; checksums and SBOM published; reproducible F-Droid builds.
- **Supply chain:** pinned dependency hashes (`deps.lock`, pub lockfile, Gradle verification metadata, SPM resolved); Dependabot/Renovate; SBOM diff review; `mediahro-deps` built from tagged upstream sources with verified signatures where available; GitHub Actions pinned by SHA; release environment with required reviewers.
- **Secrets:** none in the repo; no publisher-held API keys, app keys or OAuth client IDs (ADR-048); users supply their own tokens (ListenBrainz) and store them in the OS keystore; app never holds user passwords in memory longer than needed.
- **Privacy:** telemetry opt-in; PII scrubbing; data map in PRIVACY.md; access to the VPS limited to the owner with hardware keys.
- **Permissions:** least privilege per doc 07; no all-files access; no location; no contacts.

### 6.3 Vulnerability handling

`SECURITY.md`: report to security@mediahro.com (PGP key published); acknowledge within 2 business days; fix target 30 days (7 days for actively exploited); coordinated disclosure; credits; CVE requested via GitHub. Security fixes ship as hotfixes on all platforms the same day.

## 7. Business continuity

- Everything needed to rebuild the project is in Git (code, deps scripts, docs, store metadata as fastlane files, site).
- Store accounts, domains, signing keys and MoR accounts are owned by the entity; recovery codes in a hardware-key-protected password manager with a documented successor.
- If funding fails, the app remains buildable and forkable under AGPL with the trademark policy allowing clearly-labelled unofficial builds.

## 8. Annual transparency report

Published each January: income by rail, spending by category, headcount, installs/MAU estimates, support volume, security incidents, roadmap delivered vs planned. Linked from the Supporter page in-app.
