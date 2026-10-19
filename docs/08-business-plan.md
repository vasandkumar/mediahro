# 08 — Business Plan (B2C and B2B)

Version 1.0 · 2026-10-19 · Synthesises `research/05`. Sourced figures are cited there; estimates are marked *(est.)*.

## 1. Business model in one paragraph

Mediahro is free for everyone, forever, with no ads and no feature gates. Revenue comes from (a) **voluntary supporter payments** from individuals (in-app tips and subscriptions, web donations, GitHub Sponsors/Liberapay), (b) **B2B licensing and services** built on the same codebase (commercial licence for the AGPL engine, signage/kiosk edition, support contracts, OEM/white-label builds, NAS and server-vendor partnerships), and (c) **corporate open-source sponsorship**. Fixed costs are under USD 1.5 k/year because there is no backend; the entire cost base is people.

## 2. B2C: the supporter model

### 2.1 Reference points

| Project | Model | Result |
|---|---|---|
| Thunderbird | Donation-only, prompt on upgrade, year-end campaign | USD 10.3 M in 2024 from 335 k donors; median gift USD 16.66; 25 % recurring at USD 6.25/month; 94 % of gifts ≤ USD 35 |
| Blender Foundation | Dev Fund + donations | EUR 3.1 M (2024); December drive = 10× a normal month |
| VideoLAN (VLC) | Donations, no employees, Videolabs for paid work; refused multi-million ad deals | 7 B downloads; the trust benchmark |
| Obsidian | Free incl. commercial; Catalyst USD 25 one-time (badge, beta) | "100 % user-supported", profitable, no investors |
| Immich (FUTO) | AGPL, optional licence (~USD 25/user, ~USD 100/server) | Fastest-growing self-hosted app |

### 2.2 Offer

| Rail | What | Where shown | Fee |
|---|---|---|---|
| In-app tip (consumable IAP) | USD 2.99 / 6.99 / 14.99 (+ custom on Apple/Google where supported) | Settings → Support Mediahro on all store builds | Apple 15 % (Small Business Program), Google 15 % → regional changes 2026, Microsoft via third-party checkout ~5 % |
| In-app subscription | USD 1.99/month or 14.99/year "Mediahro Supporter" | Same page | Same |
| Web (merchant of record: Paddle or Polar) | Any amount one-time or monthly; handles VAT | mediahro.com/support; in-app link only where allowed (US storefront, EU under terms, Windows, direct, F-Droid) | ~5 % + USD 0.50 |
| GitHub Sponsors | Individuals 0 %, orgs ≤ 6 % | README, site, FOSS flavour | 0–6 % |
| Liberapay | 0 % platform fee | FOSS flavour, site | processor only |
| Open Collective | For fiscal hosting if a foundation is not formed | Site | 10 % |

Perks are cosmetic only (SUP-004). Nothing is ever gated. Supporters are told exactly that.

### 2.3 Ask policy (SUP-005)

- Permanent quiet entry points: Settings → Support Mediahro; About; a heart in the desktop menu bar.
- One contextual prompt per quarter after demonstrated value (≥ 20 sessions or ≥ 10 hours), dismissible forever.
- Prompt on major-version release notes ("1.0 shipped. Help fund 1.1.").
- One year-end campaign with a public goal and progress (opt-in banner).
- Annual transparency report (income, spend, headcount) published on mediahro.com and in-app.
- No dark patterns: no decline-shaming, no countdowns, no fake scarcity, no "most popular" badges.

### 2.4 Conversion assumptions

| Scenario | Supporters per year as % of average MAU | Blended gross gift |
|---|---|---|
| Bear | 0.5 % | USD 12 |
| Base | 1.0 % | USD 15 |
| Bull | 2.0 % | USD 20 |

Rationale: Thunderbird implies ~1–2 % with in-product campaigns; the only quantified passive tip-jar figure is 0.58 % at USD 2.10 (2015); freemium 2–5 % benchmarks do not apply because nothing is gated. Apple/Windows desktop users lift the average gift; Android volume lowers it.

## 3. B2B

### 3.1 Lines, ranked by fit

| Line | Offer | Pricing anchor | Year |
|---|---|---|---|
| **Mediahro Engine commercial licence** | The AGPL playback core (B2B-004) under a commercial licence for proprietary integrators: LMS vendors, NAS vendors, kiosk vendors, in-house corporate apps, projector/TV-box makers | Bitmovin ~USD 249/mo, THEOplayer ~USD 505/mo as market anchors; Mediahro: USD 199/mo per app or USD 1,990/yr; OEM per-device royalty USD 0.10–1.00 or flat USD 10–50 k/yr *(est.)* | 2 |
| **Mediahro Kiosk (signage edition)** | Managed-config + kiosk mode (B2B-001/002) with remote status; commercial licence + support for resellers and multi-site deployments | USD 49/device/yr or site licences USD 2–10 k/yr *(est.)*; segment USD 2.3 B growing 9.5 %/yr | 2 |
| **Enterprise support contracts** | SLA, security patches, priority fixes, custom builds | USD 5–25 k/yr per customer *(est.)* | 2 |
| **Education** | Classroom playback, MDM-deployed, accessibility report | USD 1–3 k/yr per school *(est.)* | 2–3 |
| **White-label / OEM** | Branded builds (B2B-006) for Android TV boxes, projectors, hospitality TV, automotive | Per-device royalty or flat fee; needs certification work | 3 |
| **NAS / server partnerships** | Native listing in Synology/QNAP/UGREEN/TrueNAS app centres; co-marketing; first-class client listing on Jellyfin, Navidrome, Immich, Audiobookshelf pages | Non-monetary → installs; paid integration where offered | 1 |
| **Corporate OSS sponsorship** | GitHub Sponsors (org tier), thanks.dev, Open Source Pledge (USD 7.4 M channelled; > USD 2 k/dev/yr members) | Publish reusable libraries (subtitle auto-sync, HDR pipeline wrapper) to increase dependency-based allocation | 1–2 |
| Bounties | Company-funded features/bugs | USD 500–5,000 per item *(est.)* | any |

Out of scope: medical imaging (DICOM), hospitality verticals without an OEM partner, anything requiring DRM.

### 3.2 Licensing structure

- **AGPL-3.0** for the app and engine; **commercial licence** (`LICENSE-COMMERCIAL.md`) for proprietary use; contributor agreement (DCO + copyright assignment to the Mediahro entity for core contributors) so dual licensing stays possible.
- Trademark separate from code (doc 09 §5) so forks cannot ship as "Mediahro".
- Engine packaged with C, Dart, Kotlin and Swift APIs; sample apps and docs in 1.1.

### 3.3 Managed deployment features as sales enablers

Android Enterprise managed config, Apple MDM managed app configuration, Windows policy keys, kiosk/lock-task, auto-start playlists, multi-screen sync, local control API, SBOM per release, accessibility conformance report. These are in the 1.0 spec (B2B-001…006) so sales can start the month after launch.

### 3.4 Sales motion

- Inbound from the site ("Mediahro for business" page), the Engine docs and the kiosk edition page; a contact form, not a CRM-heavy funnel.
- Partner outreach list (year 1): Jellyfin, Navidrome, Immich, Audiobookshelf (client listings); UGREEN, Synology, QNAP, TrueNAS (app centres); XGIMI/Nebula-class projector brands and hospitality TV integrators (OEM pilots, year 2).
- Pricing published for Engine and Kiosk; enterprise support quote-based.

## 4. Go-to-market summary (detail in doc 12)

- Zero-budget channels: r/androidapps, r/iosapps, r/selfhosted, r/DataHoarder, r/jellyfin, r/degoogle; Hacker News "Show HN"; XDA, Android Police, 9to5Mac, MacStories, Windows Central, The Verge with a hook (DV profile 8 on Android, auto subtitle sync, one app on four OSes); YouTube NAS/self-hosting channels; F-Droid; Jellyfin/Navidrome/Immich client pages; App Store featuring nomination.
- ASO long-tail: "mkv player with subtitles", "hdr video player", "flac player", "jellyfin client", "no ads video player", "photo viewer raw".
- Localisation: 12 languages at launch (en, pt-BR, es, hi, id, de, fr, ja, ru, tr, zh-Hans, it).

## 5. KPIs

| Area | Metric | Target |
|---|---|---|
| Acquisition | Installs by store/country; store page conversion | 400 k / 2 M / 5 M cumulative (Y1/Y2/Y3) |
| Activation | % of installs that play a file in session 1; % set as default handler | ≥ 70 %; ≥ 25 % |
| Retention | D1/D7/D30 | ≥ 35 % / 20 % / 12 % |
| Quality | Crash-free sessions; store rating; Android vitals | ≥ 99.5 %; ≥ 4.6; crash < 1.09 %, ANR < 0.47 % |
| Monetisation | Supporters per 1,000 MAU; net ARPS; recurring share; refund rate | ≥ 5 after first campaign; USD 13; 25 %; < 1 % |
| Community | GitHub stars; contributors; Weblate languages; Matrix/Discord actives | 10 k; 50; 25; 2 k |
| B2B | Qualified leads; pilots; contracts; renewals | 2 contracts Y2; 5–6 + 1 OEM Y3 |

## 6. Costs

| Item | Annual |
|---|---|
| Apple Developer Program | USD 99 |
| Google Play Console | USD 25 once |
| Microsoft Partner Center | USD 0 (new flow) |
| Windows code signing (Azure Artifact Signing basic) | ~USD 120 |
| Domains (4) + DNS | ~USD 80 |
| Static site hosting (GitHub Pages/Cloudflare) | USD 0 |
| Self-hosted Sentry + Aptabase (small VPS) | USD 240–480 |
| CI beyond free tier (public repo → free) | USD 0–600 |
| Weblate (OSS hosted) | USD 0 |
| Merchant of record / payment fees | variable |
| Trademark (USPTO 2 classes + counsel; EUIPO year 1) | USD 2–5 k one-time |
| **Fixed total** | **≈ USD 0.6–1.5 k/yr** plus trademark one-time |

People: 1 FTE equivalent in years 1–2 (USD 75 k blended), 2 in year 3.

## 7. Three-year model (base case)

| Metric | Year 1 | Year 2 | Year 3 |
|---|---|---|---|
| Cumulative installs | 400 k | 2.0 M | 5.0 M |
| Average MAU | 50 k | 250 k | 650 k |
| Supporters (1 %) | 500 | 2,500 | 6,500 |
| Gross donations @ USD 15 | USD 7.5 k | USD 37.5 k | USD 97.5 k |
| Net after 12 % blended fees | USD 6.6 k | USD 33 k | USD 85.8 k |
| Corporate OSS sponsorship | 0 | USD 5 k | USD 15 k |
| B2B (support, Engine, Kiosk, OEM) | 0 | USD 20 k | USD 75 k |
| **Total net revenue** | **USD 6.6 k** | **USD 58 k** | **USD 176 k** |
| Fixed costs | USD 1 k | USD 1.2 k | USD 1.5 k |
| People | USD 75 k | USD 75 k | USD 150 k |
| **Net** | **−USD 69 k** | **−USD 18 k** | **+USD 24 k** |

Bear (0.5 %, no OEM): Y3 ≈ USD 95 k. Bull (2 %, USD 20 gift, two OEM/SDK deals): Y3 ≈ USD 330 k.

Break-even arithmetic: one USD 75 k salary needs ≈ 5,700 supporters/yr at USD 15 gross and 12 % fees → 570 k average MAU at 1 %. B2B is what moves break-even from year 3+ to year 2.

## 8. Decision rules

- D30 < 8 % after six months → fix product before growth spend.
- Supporters per 1,000 MAU < 5 after the first year-end campaign → revisit ask UX (Thunderbird prompt-on-upgrade pattern) before concluding the model fails.
- No B2B pilot converted by month 18 → narrow to Kiosk edition and Jellyfin-client positioning.
- Reserve target: 6 months of people cost before hiring a second person.

## 9. Legal entity

Form a single-member company (or a non-profit association later, VideoLAN/KDE-style) that owns the trademark, the commercial licence and the store accounts; contributors sign a DCO; a foundation can be spun up once revenue exceeds USD 150 k/yr. Store developer accounts are opened in the entity's name from day one so that B2B contracts and the Apple Small Business Program align.

## 10. Risks

| Risk | Mitigation |
|---|---|
| IPTV/piracy classification | No lists/EPG/add-ons/torrent; abuse policy; counter-notice template ready (doc 09) |
| Store fee/policy changes | Multi-rail funding; no feature depends on store steering rules |
| Donation volatility | 6-month reserve; one campaign per year; B2B from year 2 |
| Four-platform maintenance load | Single codebase; CI on all four; monthly release train; community contributions |
| Support load | Public tracker, FAQ, community moderators; SLAs sold only B2B |
| Codec patents | Hardware-first; counsel before OEM deals |
| Name clones | Trademark + policy + takedowns |
