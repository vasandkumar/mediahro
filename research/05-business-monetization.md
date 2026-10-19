# 05 — Business, Monetization and Go-to-Market Research

**Subject:** A free (no ads, no paywalled features) cross-platform media app (video + audio + images) for Android, iOS, macOS and Windows, funded only by voluntary supporter payments, with a B2B track.
**Date:** 2026-10-19. Sources were pulled in October 2026; 2025–2026 material was preferred.
**How to read the numbers:** figures with a bracketed source number are sourced. Figures marked **[est.]** are the author's estimates. Figures marked **[recalled, unverified]** come from prior knowledge that could not be re-checked in this session because the shared web-search budget ran out part-way through; verify before quoting externally.

---

## 0. Executive summary

- **The "market size" for media player software is small and badly measured; the audience is enormous.** Analyst estimates for "video player software" range from USD 7.3 M (Verified Market Research, 2025) to USD 442 M (360iResearch, 2025) depending on scope [1][2]. The real signal is usage: VLC alone passed 7.0 billion cumulative downloads on 31 Aug 2026, having crossed 6 billion in January 2025, i.e. roughly 650–700 M downloads per year [3][4]. MX Player reported 1.4 B+ Google Play downloads in January 2025 [6]. A free player competes for attention, not for a revenue pool.
- **Donation-only funding works at scale for a handful of projects, and the reference datapoint is Thunderbird:** USD 10.3 M in 2024 (+19 %), from 335,000 donors and 539,000 transactions, average gift USD 18.88, median USD 16.66, 25 % of revenue recurring at USD 6.25/month average [8]. Blender Foundation took in EUR 3.1 M in 2024, more than half from individuals [10]. Signal raised USD 29.4 M in 2024 but spent USD 38.0 M [9]. VideoLAN itself runs with no employees on donations plus Videolabs' commercial services [5].
- **Supporter conversion should be modelled at 0.5–2 % of monthly actives per year, not more.** Thunderbird's ~335 k donors against an installed base in the tens of millions implies roughly 1–2 % **[est.]**; old tip-jar data shows 0.58 % conversion at USD 2.10 average [14]; freemium benchmarks of 2–5 % are for apps that gate features, which this app will not do [14].
- **Store fees are now a three-way split:** Apple Small Business Program 15 % [15]; Google Play 15 % on the first USD 1 M outside the EEA/UK/US/AU/JP, but a new structure (10 %+5 % subscriptions, 20–25 %+5 % one-off purchases) rolls out in those markets from 30 June / 30 Sept 2026 [16]; Apple's EU terms from 1 Oct 2026 are 15 % IAP / 10 % alternative payment / 5 % Core Technology Commission for SBP members [17]. Microsoft now charges no registration fee [18]. Routing supporters to the web through a merchant of record (Paddle, Polar, Lemon Squeezy, all around 5 % + USD 0.50) or direct Stripe is cheaper than in-app purchase everywhere except where the stores forbid steering.
- **B2B is where the sustainable money is likely to be.** Reference pricing: Bitmovin player from ~USD 249/month, THEOplayer ~USD 505/month, JW Player enterprise from ~USD 12 k/year (all weakly sourced) [21]; digital-signage media-player software is a USD 2.3 B (2025) segment growing ~9.5 %/year [23]; the Open Source Pledge has channelled USD 7.4 M to maintainers at >USD 2,000 per developer per year [25]. An AGPL core plus a commercial/OEM licence, support contracts, and a signage/kiosk edition are the realistic lines.
- **Risks that can actually kill the project:** being classed as an IPTV/piracy app (JioStar had 36 IPTV apps with 26 M+ installs removed from Google Play and the App Store in March 2026 [30]); HEVC patent pools consolidating (Access Advance absorbed Via LA's HEVC/VVC pool in Dec 2025 [31]); and four-platform maintenance load with a sub-USD 100 k budget.
- **Financial skeleton:** fixed costs are under USD 1,000/year; the question is purely how many monthly actives can be reached. At 1 % annual conversion and USD 15 average net gift, one full-time salary (USD 75 k) needs ~550 k MAU; at 1.5 % it needs ~370 k MAU **[est.]**. Without B2B, Year 3 is the earliest plausible break-even on one salary.

---

## 1. Market size and trends

### 1.1 Analyst market sizing (treat as directional)

| Source | Scope | 2025 base | Forecast | CAGR |
|---|---|---|---|---|
| 360iResearch | "Video player market" (streaming, e-learning, CTV, telehealth) | USD 441.85 M | USD 589.11 M (2032) | 4.19 % [1] |
| Verified Market Research | "Video player software" (Android/iOS/PC; names VLC as leader; NA ~38 %) | USD 7.30 M | USD 15.90 M (2033) | 10.3 % [2] |
| Market Research Future | Digital-signage media player (hardware + software) | USD 2.28 B | USD 5.66 B (2035) | 9.5 % [23] |
| QYResearch | Digital-signage player + CMS | USD 13.08 B | USD 34.70 B (2032) | 15.0 % [23] |
| MarketsandMarkets | Whole digital-signage market | USD 21.07 B (2026) | USD 30.91 B (2032) | 6.6 % [23] |

The two consumer-player figures differ by 60x because one counts licence revenue for standalone players (almost nothing, because the category is free) and the other counts embedded/streaming player spend. **Takeaway:** there is no consumer revenue pool to "capture"; consumer value is attention and goodwill, and the monetisable pools are B2B (signage, OEM, SDK) and donations.

### 1.2 Download volumes of leading free players

| App | Figure | Date | Note |
|---|---|---|---|
| VLC (all platforms) | 7,035,534,434 cumulative downloads | 31 Aug 2026 | 6 B reached Jan 2025 at CES; the last billion took ~18 months [3][4] |
| VLC iOS | 17.72 M downloads since 1 Apr 2024 | 5 Jan 2025 | ≈ 23 M/year on iOS alone [4] |
| MX Player (Google Play) | 1.4 B+ downloads | Jan 2025 | Stated by Amazon MX Player head Karan Bedi; 1 B milestone was under Times Internet [6] |
| MX Player ownership | Amazon acquired from Times Internet; reported USD 30–40 M | 2024–25 | Times Internet paid USD 140 M in 2018; the Amazon price is unverified trade-press [6] |

Implied annual demand: VLC's ~670 M/year counts reinstalls and upgrades, but even a 10 % share of that would be tens of millions of installs per year **[est.]**. A new entrant that reaches 1 % of VLC's annual volume (~6–7 M installs/year) would be a top-tier indie app.

### 1.3 Platform share

| Measure | Android | iOS | Source |
|---|---|---|---|
| Global mobile web usage, Aug 2026 | 67.45 % | 32.52 % | StatCounter [7] |
| Global smartphone sales, Q2 2026 | 75 % | 20 % (HarmonyOS 5 %) | Counterpoint via 9to5Google [7] |
| India, Aug 2026 | 92.79 % | 7.15 % | StatCounter [7] |
| Brazil, Sep 2026 | 78.78 % | 21.21 % | StatCounter [7a] |
| Indonesia, Sep 2026 | 79.16 % | 20.79 % | StatCounter [7b] |
| 2025 downloads | Google Play ≈ 3x App Store | — | [7] |
| 2025 consumer spend | USD 49.2 B | USD 117.6 B | [7] |

**Implication for a donation model:** Android delivers reach (and is where local-file playback is a mainstream habit: India, Brazil, Indonesia, plus Turkey, Vietnam, Nigeria, Pakistan, Egypt **[est.]**), while iOS/macOS users carry 2–3x the willingness to pay. Expect the majority of installs from Android and the majority of supporter revenue from Apple platforms and Windows desktop **[est.]**. Desktop share of installs for a VLC-like app is historically dominant on Windows [3]; VideoLAN's per-platform table could not be fetched this session (connection reset), so the split is not quantified here.

### 1.4 Trends that favour a local-first player

1. **Self-hosted media.** In the 2024 r/selfhosted survey (~2,100 respondents), Jellyfin held 51.2 % of media-server share versus ~40 % for Plex; Immich was the most-adopted new app [11]. An April 2026 article reports Jellyfin at 50.5 k GitHub stars and 360 M Docker pulls, and Immich at 92–98 k stars [11]. Plex's April 2025 price rise (lifetime pass reported at USD 249.99 and remote streaming moved behind the paywall) pushed users towards open servers [11]; the official Plex pricing page could not be fetched (403), so treat the price as secondary. Jellyfin's official client list already includes many third-party players (Findroid, Finamp, Streamyfin, Fladder, Jellify, Swiftfin) [12], which is proof that "be a great Jellyfin/Navidrome/Immich client" is a recognised route to distribution.
2. **De-Googling / privacy.** Motorola partnered with the GrapheneOS Foundation in March 2026 [13]; Fossify (community fork of Simple Mobile Tools after the original was sold) ships gallery, file manager and calendar on F-Droid [13]; Tuta's 2026 user survey put GrapheneOS at 45 % of preferred alternative-Android choices (self-selected sample) [13]. This audience explicitly rewards ad-free, telemetry-free, FOSS media apps and is over-represented among donors.
3. **Codec and display capability.** HEVC/VVC licensing consolidated in Dec 2025 when Access Advance absorbed Via LA's HEVC/VVC pool (now "VCL Advance") and reported a 100 % renewal rate with 29 new licensees in one quarter [31]. AV1 remains under the AOMedia Patent License 1.0 (W3C-style royalty-free commitments) [32]. Dolby Vision / HDR10+ TV and phone shipment figures could not be sourced in this session; the practical point is that correct HDR tone-mapping on phones and tablets is a differentiator that mainstream free players still get wrong **[est.]**.
4. **Apple Vision Pro is not a market yet.** IDC estimated 390 k units in 2024 and only ~45 k in Q4 2025; Apple cut US/UK digital ad spend on it by >95 % [20]. A visionOS build is a press/featuring play, not a revenue play.
5. **Foldables, tablets, TVs.** No fresh shipment data was retrievable. Treat Android TV / Google TV, Fire TV and tvOS as B2B-adjacent surfaces (hotel, signage, OEM) rather than donation surfaces, since tip jars on TV are impractical **[est.]**.

---

## 2. Supporter-only business models that work

### 2.1 Reference organisations

| Project | Legal form | Latest revenue | Donor data | Notes |
|---|---|---|---|---|
| **Thunderbird (MZLA)** | For-profit subsidiary of Mozilla Foundation; donation-only | USD 10.3 M (2024, +19 %); USD 8.6 M (2023); USD 6.4 M (2022); USD 2.8 M (2021) | 335 k donors, 539 k transactions; avg USD 18.88, median USD 16.66; 25 % recurring (avg USD 6.25/mo); 53 % of gifts ≤ USD 20, 94 % ≤ USD 35; only 17 gifts ≥ USD 1,000; top-10 countries = 83 % of revenue; 43 FTE | [8] |
| **Signal Technology Foundation** | US 501(c)(3) | USD 29.4 M (2024): USD 21.8 M contributions, USD 6.4 M program service, USD 1.2 M investment; expenses USD 38.0 M (deficit USD 8.6 M) | Whittaker's ~USD 50 M/yr cost projection is secondary-sourced | Added a paid backup tier in 2025 (USD 1.99/mo **[recalled, unverified]**) [9] |
| **Blender Foundation** | Dutch stichting | EUR 3.1 M (2024, from EUR 2.55 M); Dev Fund +21 %; donations +20 % | >50 % from individuals; year-end drive: 27 k one-time gifts = 10x a normal month | Posted a loss in 2024; reserves below 3-month target; developer grants EUR 2.15 M; 87 % of spend on people [10] |
| **VideoLAN (VLC)** | French non-profit, no employees | Not published | Donations via Stripe (card/Apple Pay/Google Pay/SEPA), PayPal, bank, Bitcoin | Commercial work routed through Videolabs; added funding.json for floss.fund in March 2026; famously refused multi-million ad deals [5] |
| **Immich** | AGPL; team employed by FUTO since 1 May 2024 | FUTO-funded (FUTO reports >USD 5 M in grants overall) | Sells optional per-user and per-server licences; "all features will be free, forever" | Prices ~USD 25 individual / ~USD 100 server **[recalled, unverified]** [24] |
| **Obsidian** | Private, no investors, "100 % user-supported" | Not published | Free for all use incl. commercial since Feb 2025; Catalyst USD 25 one-time (badge, beta); Commercial USD 50/user/yr optional; Sync USD 4–5/mo; Publish USD 8–10/mo | Closest analogue to a "free + optional supporter licence" app [19] |
| **GrapheneOS Foundation** | Canadian non-profit (Mar 2023), no public financials | Not published | Proton Foundation gave USD 10 k + USD 5 k | Project states recurring expenses exceed regular donations and reserves are held in crypto/fixed income (forum) [13] |
| **KDE e.V.** | German e.V. | 2025 report (Issue 42) exists; figures not extracted | — | Reports page fetched; income tables are in PDFs/German minutes [26] |
| **Fossify, mpv** | Volunteer | Not published | Fossify funded via GitHub Sponsors/Liberapay **[recalled]** | mpv has no donation programme of note **[recalled]** |
| **Bitwarden, Proton** | VC-backed / foundation-owned | Not donation-funded; freemium subscriptions | Proton describes itself as user-funded with no VC [9a] | Useful as "privacy brand" comparables, not as donation models |

**What the successful ones share:**
- A very large installed base (tens of millions) so that ~1 % conversion funds a team.
- A clear, repeated "we are user-supported, there are no investors" message (Obsidian, Proton, Signal, Thunderbird).
- Year-end campaigns (Blender's December drive produced 10x a normal month) [10].
- Small gifts dominate: Thunderbird's median is USD 16.66 and 94 % of gifts are ≤ USD 35; large donors are negligible [8]. Design for many small payments, not patrons.
- Recurring is a minority but valuable: 25 % of Thunderbird revenue at USD 6.25/month average [8].

### 2.2 Conversion and ARPU benchmarks

| Benchmark | Figure | Source / confidence |
|---|---|---|
| Thunderbird donors ÷ installed base | ~1–2 %/yr **[est.]** (335 k donors; MAU in the low tens of millions **[recalled]**) | [8] |
| Legacy in-app tipping (2015 vendor data) | 0.58 % conversion, USD 2.10 average tip | [14], dated |
| Freemium (feature-gated) conversion | 2–5 %, USD 5–50 upgrade | [14], not applicable to a no-paywall app |
| Indie anecdote | "made apps free with a tip jar and revenue tanked" | [14] |
| Thunderbird one-off gift | avg USD 18.88, median USD 16.66 | [8] |
| Thunderbird recurring | avg USD 6.25/mo | [8] |
| Obsidian Catalyst | USD 25 one-time | [19] |
| Immich licence | ~USD 25 / ~USD 100 **[recalled, unverified]** | [24] |

**Planning range:** 0.5 % (pessimistic), 1 % (base), 2 % (optimistic) of average MAU donating per year; blended gross gift USD 12–20 (mix of USD 3–5 in-app tips, USD 15–25 one-off web gifts, and a minority of USD 3–5/month recurring) **[est.]**. The old 0.58 % tip-jar figure is the floor for an app that asks only through a settings-menu tip jar; the Thunderbird-style 1–2 % requires in-product campaigns.

### 2.3 Ethical "supporter perks" that do not become a paywall

Patterns used by Obsidian Catalyst, Immich, Ivory/Tusky/Overcast-style supporter tiers **[recalled; no published conversion data found for those apps]**:
- Cosmetic only: supporter badge in About screen, alternate app icons, a "thank you" theme accent, name in credits (opt-in).
- Early access to beta builds and a supporters' channel (Obsidian's Insider/Supporter/VIP tiers) [19].
- Never: codecs, formats, playback features, sync, or removal of nags gated by payment. The moment a feature is gated, the project is freemium and loses the "truly free" positioning that drives press and community.

### 2.4 How to ask without nagging (UX patterns)

1. **One contextual prompt per quarter**, shown only after demonstrated value (e.g., after the 20th play session or 10 hours watched), dismissible for good. Thunderbird prompts on upgrade; Blender runs a seasonal campaign [8][10].
2. **Permanent, quiet entry point:** "Support" item in settings and About; a heart icon in the desktop menu bar.
3. **Transparent ledger:** publish annual income/spend (Thunderbird's State of the Bird is the model) [8]. Donors respond to seeing 80 % go to engineering.
4. **Year-end campaign** with a visible goal and progress bar, matching Blender's December pattern [10].
5. **Milestone asks:** on the release notes screen of a major version ("v2.0 shipped — fund v3").
6. **No dark patterns:** no "decline" shaming, no countdown timers, no fake scarcity. These matter doubly on Reddit/HN, where the app's reputation will be made.

### 2.5 Store fees and payment rails

| Channel | Fee | Source |
|---|---|---|
| Apple App Store, Small Business Program (<USD 1 M prior-year proceeds) | 15 % on IAP; standard 30 % above threshold | [15] |
| Apple EU (from 1 Oct 2026) | SBP members: 15 % IAP / 10 % alternative payment in-app / 10 % store services on link-outs; 5 % Core Technology Commission for apps distributed outside the App Store; CTF, Initial Acquisition Fee and Store Services Fee eliminated; alternative-payment sales must be reported monthly | [17] |
| Google Play (rest of world) | 15 % on first USD 1 M/yr, 30 % above; subscriptions 15 % | [16] |
| Google Play (EEA/UK/US from 30 Jun 2026; AU/JP from 30 Sep 2026) | Subscriptions 10 % + 5 % billing fee; one-off purchases 20 % + 5 % (new installs) or 25 % + 5 % (existing installs; 20 % if via external web link); Level Up/Apps Experience participants 15 % + 5 % / 20 % + 5 % | [16] |
| Google Play alternative billing (Korea, India) | Standard fee minus 4 % | [16] |
| Microsoft Store | Registration now free via the new onboarding flow (Sept 2025 docs) [18]. Commission 12 % for apps and games, and 0 % for non-game apps using their own or third-party commerce (2021 policy) **[recalled, unverified this session]** |
| Apple Developer Program | USD 99/yr; Enterprise USD 299/yr | [18a] |
| Google Play Console | USD 25 one-time; ID verification required | [18b] |
| Stripe direct (web) | ~2.9 % + USD 0.30 US cards **[recalled]**; Liberapay reports ~3 % average Stripe cost, ~5 % PayPal | [27] |
| Paddle (MoR) | 5 % + USD 0.50 | [22] |
| Lemon Squeezy (MoR, now Stripe-owned) | 5 % + USD 0.50, +1.5 % international, +1.5 % PayPal | [22] |
| Polar.sh (MoR) | Starter 5 % + USD 0.50 after 2026 increase; Pro USD 20–30/mo at 3.8–4.5 % | [22] |
| RevenueCat (IAP backend) | Free to USD 2,500 monthly tracked revenue, then 1 % | [22a] |
| GitHub Sponsors | 0 % for sponsorships from personal accounts; up to 6 % (3 % card + 3 % GitHub) from organisations, card fee waived on invoice | [27a] |
| Patreon | 10 % of earnings + processing/payout fees | [27b] |
| Liberapay | 0 % platform fee; processor fees only | [27] |
| Open Source Collective | 10 % host fee + processor fees | [27c] |
| Ko-fi | 0 % on donations on the free plan per most sources; Ko-fi Gold ~USD 12/mo removes fees on memberships/shop (official page returned 403; secondary sources disagree on a 5 % figure) | [27d] |

**Recommendation:** in-app tip jar via StoreKit/Play Billing (accept the 15 %/15–25 % hit for frictionless mobile tipping), plus a web "Support" page on a merchant of record (handles VAT globally) or direct Stripe, plus GitHub Sponsors (0 % for individuals) and Liberapay (0 %) for the FOSS crowd. In the EU, link-outs from the app cost 10 % (Apple) or 20 % (Google existing installs) of attributed sales within the attribution window [16][17], so web links should be unobtrusive and generic ("Learn how we're funded") rather than hard-steered.

---

## 3. B2B angles for a media player

### 3.1 Menu of B2B lines, ranked by fit

| Line | What is sold | Reference price points | Fit | Notes |
|---|---|---|---|---|
| **Player SDK / engine licensing** | Embeddable playback core (decoding, HDR, subtitles, audio) for other apps | Bitmovin player from ~USD 249/mo; THEOplayer ~USD 505/mo (TrustRadius listings); JW Player "Starter" ~USD 12 k/yr (weak source); enterprise deals are quote-only [21] | High if the core is AGPL | AGPL forces proprietary integrators to buy a commercial licence (Qt-style dual licensing). Target: education LMS vendors, NAS vendors, kiosk vendors, in-house corporate apps. |
| **White-label / OEM** | Branded player for Android TV boxes, projectors, car infotainment, hotel TV | Per-device royalty USD 0.10–1.00 or annual flat fee USD 10–50 k **[est.]** | Medium | Needs a sales motion and certification work (Google TV, Android Automotive). Chinese TV-box OEMs are high-volume, low-margin; projector brands (XGIMI, Anker Nebula class) and hospitality TV integrators are better targets **[est.]**. |
| **Digital signage / kiosk edition** | Locked-down playlist player with remote config, MDM support | Segment: USD 2.28 B (2025) media-player hardware+software growing 9.5 %/yr; player+CMS USD 13 B [23] | High | A free signage-capable player with managed-config support undercuts BrightSign/IAdea-class per-seat licences; monetise via support contracts and a commercial licence for resellers. |
| **Enterprise support contracts** | SLA, security patches, priority fixes, custom builds | USD 5–25 k/yr per customer **[est.]** | High | Standard for Thunderbird-/Jellyfin-adjacent commercial users; low marginal cost once the product is stable. |
| **Education** | Classroom media playback, offline lecture capture playback, MDM-deployed | Per-seat or per-school site licence USD 1–3 k/yr **[est.]** | Medium | Pair with Apple School Manager / Android Enterprise zero-touch. Accessibility compliance is the selling point. |
| **Corporate training playback** | Intranet/NAS sources, DRM-free, offline | Support + licence | Medium | Most corporate video is behind DRM/SaaS (Kaltura, Vimeo, Panopto); the DRM-free niche is manufacturing floors, ships, mines, hospitals with air-gapped networks **[est.]**. |
| **Museums / exhibits** | Looping playback, multi-screen sync, kiosk | Project-based USD 2–20 k **[est.]** | Low–medium | Often integrators' choice; win via signage edition. |
| **Hospitality (hotel TV)** | In-room player on Android TV/LG webOS/Samsung Tizen | Per-room per-month USD 0.5–2 **[est.]** | Low | Dominated by vertical vendors; only via OEM partner. |
| **Healthcare** | Patient-education video, waiting-room signage | Via signage edition | Low | **DICOM/medical imaging is out of scope** (regulated as a medical device in most jurisdictions; different codebase and QA regime). |
| **NAS vendor integration** | Native app in Synology/QNAP/UGREEN/TrueNAS app centres | Co-marketing; possible paid integration | Medium | UGREEN has opened a developer portal for UGOS apps (email submission, manual review) [28]; Android Authority notes UGREEN's app catalogue lags Synology/QNAP, so UGREEN has an incentive to court third-party apps [28]. Synology/QNAP developer programmes could not be verified this session. |
| **Self-hosted server partnerships** | Being a first-class client for Jellyfin, Navidrome, Immich | Non-monetary; drives installs | High | Jellyfin lists third-party clients on its official downloads page [12]; getting listed is the single cheapest distribution channel into r/selfhosted. |
| **Corporate OSS sponsorship** | GitHub Sponsors (org), thanks.dev, Open Source Pledge | Open Source Pledge: USD 7.42 M raised, USD 3 M+ in the last year, members pay >USD 2,000/dev/yr; Sentry USD 750 k/yr; Canonical USD 120 k via thanks.dev; VoidZero USD 48 k [25] | Medium | thanks.dev allocates by dependency usage, so publishing reusable libraries (e.g., an HDR tone-mapping or subtitle library) increases the share. |
| **Bounties** | Paid feature/bug bounties from companies | Typically USD 500–5,000 per item **[est.]** | Low | Useful as a signal of B2B demand, poor as revenue. |

### 3.2 Licensing structure

- **AGPL-3.0 core + commercial licence** is the established pattern (Immich is AGPL and sells optional licences [24]; Plausible, Grafana, MongoDB-before-SSPL used it; Qt is GPL/LGPL + commercial) [29]. AGPL's network clause deters SaaS re-hosting; for a client app the main lever is that OEMs and proprietary integrators cannot ship a modified closed build without a commercial licence.
- **Alternatives:** Sentry's Functional Source License permits everything except undermining the producer and converts each version to Apache/MIT after two years [29a]; SSPL (MongoDB, Redis 2024) is not OSI-approved and is widely rejected by distributions [29]. For a consumer app that wants F-Droid listing, Debian packaging and community trust, FSL/SSPL are counter-productive; stay with AGPL (or GPL) and keep a contributor licence agreement (or DCO plus copyright assignment for the core team) so dual licensing remains possible.
- **Trademark separate from code:** keep the name and logo under a trademark policy (the VLC cone and the Firefox model) so forks cannot ship under the same brand into stores.

### 3.3 Managed deployment as a B2B feature

- **Apple:** Apple Business Manager / School Manager with Custom Apps distribution, managed app configuration via MDM (`com.apple.configuration.managed`); App Store Small Business Program is unaffected by B2B custom-app sales **[recalled]**.
- **Android:** Android Enterprise managed configurations (restrictions XML) plus zero-touch enrolment; a signage build can be a dedicated-device (kiosk/lock-task) app **[recalled]**.
- **Windows:** Microsoft Store for Business is retired; Intune now adds apps through the new Microsoft Store (winget-backed) experience, and non-Store apps are deployed as Win32/LOB packages (MSIX or MSI) [18c]. Shipping an MSIX in the Store plus a winget manifest covers both paths.
- **Accessibility:** the European Accessibility Act covers "access to audiovisual media services" and consumer TV equipment, e-commerce and OS/smartphones [33]; it has applied to new products/services since 28 June 2025 **[recalled]**. Full screen-reader support, captions, audio description tracks and keyboard navigation become procurement checkboxes for public-sector and education buyers.

---

## 4. Go-to-market and growth for a free app

### 4.1 Launch channels (zero budget)

| Channel | What works | Evidence / notes |
|---|---|---|
| **Reddit** (r/androidapps, r/iosapps, r/selfhosted, r/DataHoarder, r/jellyfin, r/degoogle) | Dev posts with a candid "no ads, no paywall, here is how it's funded" framing; AMA-style replies | r/selfhosted's own survey drives the Jellyfin>Plex narrative [11]; the 2024 "newly adopted" poll is effectively a launch leaderboard |
| **Hacker News** ("Show HN") | FOSS + privacy + no-VC story; technical depth (HDR pipeline, codec choices) | Thunderbird's donation page hit the HN front page in 2026 [8a] |
| **Product Hunt** | Weak for utilities on Android; useful for macOS/iOS press pickup | No quantitative 2025 data found this session |
| **F-Droid** | Credibility with the de-Google audience; F-Droid publishes no download counts [34] | Requires reproducible builds and no proprietary blobs; plan a separate F-Droid flavour |
| **AlternativeTo, XDA, Android Police, 9to5Mac, MacStories, Windows Central, The Verge** | Category pages ("VLC alternative", "MX Player alternative"); exclusive on a visible feature (e.g., Dolby Vision profile 8 on Android) | Press covers VLC milestones reliably [3][4]; a new player gets coverage for a hook, not for existing |
| **YouTube reviewers** | Linux/self-hosting and Android channels; NAS reviewers | NAS/Jellyfin channels are the most receptive for a local-first player **[est.]** |
| **App Store featuring** | Apple weighs UX, design, innovation, uniqueness, accessibility, localisation, product page; nominate in App Store Connect at least two weeks ahead, up to three months for wider consideration | [35] |
| **Jellyfin/Navidrome/Immich client lists** | Get on the official "clients" page | Jellyfin lists ~15 third-party clients [12] |

### 4.2 ASO for a media player

Keyword clusters (English; replicate per locale): "video player", "media player", "HDR video player", "MKV player", "subtitle player", "music player offline", "FLAC player", "gallery", "photo viewer", "play from NAS / SMB / DLNA", "Jellyfin client", "no ads video player". Long-tail intent ("mkv player with subtitles", "hdr player android") converts better than head terms owned by VLC and MX Player **[est.]**.

### 4.3 Localisation

The oft-cited Distimo study found +128 % downloads in the week after adding a native-language version and +26 % revenue, with the largest effect in China and Japan; AutoScout24 saw +38 % within six weeks from localisation [36]. The studies are old but remain the only quantified ones. Priority order for this app, by Android reach and donation propensity **[est.]**: English, Portuguese (BR), Spanish, Hindi, Indonesian, German, French, Japanese, Russian, Turkish, with Simplified Chinese added if distributing outside Google Play.

### 4.4 Community and transparency

- Public roadmap (GitHub Projects) and open issue tracker; monthly dev notes; a Matrix space bridged to Discord.
- Annual transparency report modelled on Thunderbird's State of the Bird (income, spend, headcount) [8].
- Open source as marketing: GitHub stars are the proxy that sites like F-Droid Insights rank by [34]; Jellyfin's star and Docker-pull counts are quoted in every "Jellyfin vs Plex" article [11].
- How the incumbents built communities: VLC through 20+ years of being the default answer to "what plays this file" plus conference presence (FOSDEM) [5]; Plex through a polished family-sharing product (ranked first for family/friends use in the 2024 poll) and then eroded goodwill with the 2025 price rise [11]; Jellyfin through forking Emby under GPL and winning r/selfhosted [11].

### 4.5 Retention and rating benchmarks

| Metric | Cross-industry | Utility/productivity | Source |
|---|---|---|---|
| Day 1 | 25–30 % | similar | [37] |
| Day 7 | 10–15 % | — | [37] |
| Day 30 | 5–7 % | 10–18 % | [37] |
| iOS vs Android D1 → D30 | iOS 25.4 % → 5.3 %; Android 20.2 % → 3.8 % | — | [37] |

Targets **[est.]**: D1 ≥ 35 %, D7 ≥ 20 %, D30 ≥ 12 % for a player that is set as the default handler for video files (defaults drive habitual retention). Store rating target ≥ 4.6 on both stores; VLC and MX Player sit around 4.3–4.5 on Google Play **[recalled]**, and reviews frequently cite ads (MX Player) and UI (VLC), both of which are attack surfaces.

### 4.6 Referral and share features

Native share sheets ("open with"), a "send to TV" cast flow, and exportable playlists are the only share surfaces that do not feel like growth hacks. Avoid referral rewards; they are incompatible with the no-perks positioning and look like a dark pattern to the FOSS audience.

---

## 5. Risks

| Risk | Likelihood | Impact | Evidence | Mitigation |
|---|---|---|---|---|
| **Classification as an IPTV/piracy app** | Medium | Fatal (store removal) | JioStar had 36 IPTV apps (26 M+ downloads) pulled from Google Play and the App Store in March 2026; Albania's AMA had "One IPTV Player" removed; Argentina ordered Google to uninstall MagisTV from devices; Perfect Player was removed in 2019 on a complaint TorrentFreak called bogus [30] | Do not bundle any playlist/channel sources, EPG directories or "add-on" marketplaces; support M3U/HLS as plain URL/file playback only; no "IPTV" in store metadata or screenshots; no torrent client; publish a DMCA/abuse policy and respond fast; keep a counter-notice template ready |
| **Codec patents** | Medium | High (cost or feature loss) | HEVC/VVC pools consolidated under Access Advance in Dec 2025 with rate changes and a Multi-Codec Bridging Agreement; the Video Distribution pool also lists VP9/AV1 "for streaming services" [31]; AV1's own licence is royalty-free under AOMedia Patent License 1.0 [32] | Prefer hardware decoders exposed by the OS (MediaCodec, VideoToolbox, Media Foundation) so the platform carries the licence; ship software HEVC/AC-3/DTS decoders only in builds distributed outside the stores (F-Droid/direct download), as VLC does; consult counsel before any OEM deal because OEM shipments are where pools collect |
| **Store policy changes** | High | Medium | Google's 2026 fee restructuring and Apple's October 2026 EU terms both changed within 12 months [16][17] | Keep web and GitHub Sponsors channels so revenue is not single-store; avoid features that depend on store-specific steering rules |
| **Competitive response** | Medium | Medium | VLC is adding platforms ("new screens") [4]; Amazon owns MX Player and can bundle it with Fire TV [6] | Differentiate on HDR correctness, unified video+audio+photo library, NAS/self-hosted integration, and desktop parity, none of which incumbents do well across all four platforms |
| **Trademark / naming** | Medium | Medium | The VLC cone and name are trademarked; generic names ("Player", "Media") are unregistrable and squattable | Clear a distinctive name in EUIPO/USPTO and in the four stores before launch; register the mark early; publish a trademark policy for forks |
| **Four-platform maintenance burden** | High | High | Thunderbird needed 43 staff for one product line [8]; VideoLAN relies on Videolabs for paid engineering [5] | Shared core (C++/Rust) with thin native shells; CI on all four; feature flags per platform; no backend to run |
| **Support load** | High | Medium | Free apps generate review-driven support; donation models invite "I paid, fix this" | Public issue tracker, FAQ, community moderators; supporter perks explicitly exclude support SLAs (sell those B2B) |
| **Donation fatigue / revenue volatility** | Medium | High | Blender posted a 2024 loss with reserves under a 3-month buffer; Signal ran an USD 8.6 M deficit [9][10] | Target a 6-month reserve before hiring; run one campaign per year; add B2B revenue by Year 2 |
| **Abuse of the name by clones** | Medium | Low–medium | Stores host look-alike players with ads | Trademark policy; report clones; signed builds and reproducible F-Droid builds |

---

## 6. KPIs and 3-year financial model skeleton

### 6.1 KPIs to track

Acquisition: installs by store and country; organic vs referred; store conversion rate (page views → installs). Activation: % of installs that play a file in session 1; % that set the app as default handler. Retention: D1/D7/D30; monthly actives (MAU) per platform. Quality: crash-free sessions ≥ 99.5 %, store rating ≥ 4.6. Monetisation: supporters per 1,000 MAU, gross and net ARPS (average revenue per supporter), recurring share, campaign lift, refund rate. Community: GitHub stars, contributors, issues closed, Matrix/Discord actives. B2B: qualified leads, pilots, contract value, renewals.

### 6.2 Operating cost baseline (no backend)

| Item | Annual cost | Source |
|---|---|---|
| Apple Developer Program | USD 99 | [18a] |
| Google Play Console | USD 25 once | [18b] |
| Microsoft Partner Center | USD 0 (new flow; previously USD 19 individual / USD 99 company) | [18] |
| Windows code signing (Azure Trusted Signing / "Artifact Signing" Basic, 5,000 signatures/mo) | ~USD 120 (USD 9.99/mo **[recalled, unverified]**; pricing page shows placeholders) | [18d] |
| macOS notarisation | included in Apple membership | — |
| Domain + static site hosting | USD 15–60 | **[est.]** |
| Crash reporting | USD 0–300 (Sentry free tier or self-hosted; Firebase Crashlytics free) | **[est.]** |
| CI minutes beyond free tiers | USD 0–600 | **[est.]** |
| Translation platform (Weblate/Crowdin OSS plans) | USD 0 | **[est.]** |
| Merchant-of-record / payment fees | variable (5 % + USD 0.50 per web transaction; 15 % store IAP) | [15][22] |
| **Total fixed** | **≈ USD 300–1,200/yr** | |

The model is therefore almost entirely people cost. One senior developer at a blended USD 75 k/yr (contractor, non-US) to USD 180 k/yr (US employee) is the unit of break-even.

### 6.3 Three-year skeleton (base case)

Assumptions **[est.]**: installs grow through store ranking, press and self-hosted communities; MAU ≈ 20 % of cumulative installs in Year 1 falling to 15 % by Year 3 as churned installs accumulate; 1.0 % of average MAU donate per year (base), with 0.5 % and 2.0 % as bear/bull; gross average gift USD 15; blended platform/processing fee 12 % (mix of 15 % store IAP and ~5–6 % web); B2B starts in Year 2.

| Metric | Year 1 | Year 2 | Year 3 |
|---|---|---|---|
| Cumulative installs | 400 k | 2.0 M | 5.0 M |
| Average MAU | 50 k | 250 k | 650 k |
| Supporters (1.0 %) | 500 | 2,500 | 6,500 |
| Gross donations @ USD 15 | USD 7.5 k | USD 37.5 k | USD 97.5 k |
| Net after 12 % fees | USD 6.6 k | USD 33 k | USD 85.8 k |
| Corporate OSS sponsorship (GitHub Sponsors/thanks.dev/Pledge) | USD 0 | USD 5 k | USD 15 k |
| B2B (support contracts, commercial licences, signage edition) | USD 0 | USD 20 k (2 contracts) | USD 75 k (5–6 contracts + 1 OEM/SDK deal) |
| **Total net revenue** | **USD 6.6 k** | **USD 58 k** | **USD 176 k** |
| Fixed costs | USD 1 k | USD 1.2 k | USD 1.5 k |
| People cost (1 FTE Y1–Y2, 2 FTE Y3 at USD 75 k) | USD 75 k | USD 75 k | USD 150 k |
| **Net result** | **−USD 69 k** | **−USD 18 k** | **+USD 24 k** |

Bear case (0.5 % conversion, no OEM deal): Year 3 revenue ≈ USD 95 k, still short of two salaries. Bull case (2 % conversion, Apple-heavy audience lifting average gift to USD 20, two OEM/SDK deals): Year 3 revenue ≈ USD 330 k.

### 6.4 Break-even arithmetic

Supporters needed for one USD 75 k salary at USD 15 gross and 12 % fees: 75,000 ÷ 13.2 ≈ **5,700 supporters/year**. Required average MAU: 1.14 M at 0.5 %, **570 k at 1 %**, 285 k at 2 %. For context, VLC iOS alone adds ~23 M downloads per year [4]; reaching 570 k MAU means capturing roughly 1–2 % of the addressable "non-default player" audience on the four platforms **[est.]**. The B2B line is what moves break-even from Year 3+ to Year 2 in the base case; without it, donation-only break-even for one developer arrives when MAU crosses ~0.5 M.

### 6.5 Decision rules

- If D30 retention < 8 % after six months, fix product before growth spend.
- If supporters per 1,000 MAU < 5 after the first year-end campaign, revisit the ask UX before concluding the model fails (Thunderbird's prompt-on-upgrade pattern is the benchmark) [8].
- If one B2B pilot has not converted by month 18, narrow to the signage/kiosk edition and the Jellyfin-client positioning, which are the two B2B paths with external evidence of demand [12][23].

---

## 7. Gaps in this research (search budget exhausted)

Not verified this session and worth a follow-up: Microsoft Store commission percentages (12 % / 0 % with third-party commerce); Signal's 2025 paid backup price; KDE e.V. income tables; VideoLAN's per-platform download split (site timed out); Plex's official 2025 price list; Immich licence prices; Ko-fi's official fee table; HDR/Dolby Vision and foldable shipment statistics; Synology/QNAP developer programme terms; any published supporter-tier conversion data from Overcast, Apollo, Ivory or Tusky (none was found; the only quantified tip data is the 2015 0.58 % figure).

---

## Sources

1. 360iResearch, Video Player Market Global Forecast (via GII) — https://www.giiresearch.com/report/ires2100341-video-player-market-global-forecast.html
2. Verified Market Research, Video Player Software Market — https://www.verifiedmarketresearch.com/product/video-player-software-market/
3. Mezha, "VLC surpasses 7 billion downloads" (Aug/Sep 2026) — https://mezha.ua/en/news/vlc-surpasses-7-billion-downloads-314737/ ; Ground News roundup — https://ground.news/article/vlc-crosses-7-billion-downloads
4. VideoLAN www-doc list, iOS download stats update (Jan 2025) — https://mailman.videolan.org/pipermail/www-doc/2025-January/008715.html ; Clubic, "VLC dépasse les 7 milliards… nouveaux écrans" — https://www.clubic.com/actualite-627781-vlc-depasse-les-7-milliards-de-telechargements-et-s-installe-sur-de-nouveaux-ecrans.html
5. VideoLAN contribute/donate page — https://images.videolan.org/contribute.html ; VideoLAN funding.json commit for floss.fund (Mar 2026) — https://mailman.videolan.org/pipermail/www-doc/2026-March/008766.html ; Mein-MMO on refused ad offers — https://mein-mmo.de/en/the-developer-rejected-several-million-dollar-offers-so-that-everyone-can-use-his-program-ad-free-thus-creating-one-of-the-most-famous-music-players-in-the-world%2C1485033/
6. Variety, Amazon MX Player India slate (2025) — https://variety.com/2025/global/news/amazon-mx-player-india-slate-1236292723 ; afaqs, MX Player 1B Play downloads — https://www.afaqs.com/companies/mx-player-hits-the-1-billion-downloads-mark-on-google-play-store ; TechCrunch on Times Internet/Amazon — https://techcrunch.com/?p=2483551 ; sci-tech-today stats — https://www.sci-tech-today.com/stats/mx-player-statistics
7. StatCounter mobile OS share worldwide — https://gs.statcounter.com/os-market-share/mobile/worldwide ; Quashbugs 2026 iOS vs Android stats (Counterpoint, download/spend figures) — https://quashbugs.com/blog/ios-vs-android-market-share-statistics
7a. StatCounter Brazil — https://gs.statcounter.com/os-market-share/mobile/brazil
7b. StatCounter Indonesia — https://gs.statcounter.com/os-market-share/mobile/indonesia
8. Thunderbird blog, "State of the Bird 2024/25" (Oct 2025) — https://blog.thunderbird.net/2025/10/state-of-the-bird-2024-25/ ; Chipp.in on 2023 figures — https://chipp.in/news/thunderbird-financials-doing-really-well/ ; Forbes on 2021 figure — https://www.forbes.com/sites/jasonevangelho/2025/04/01/finally-mozilla-thunderbird-takes-on-gmail-with-new-email-service/
8a. Hacker News, "Help Keep Thunderbird Alive" thread (2026) — https://news.ycombinator.com/item?id=47700388 ; MZLA CEO comment — https://news.ycombinator.com/item?id=47709082
9. Signal Technology Foundation Form 990 summary (2024) — https://philanthropy.org/990/report/824506840/signal-technology-foundation ; SQ Magazine Signal statistics (secondary) — https://sqmagazine.co.uk/signal-statistics/ ; RevenueMemo, "Who owns Signal" — https://www.revenuememo.com/p/who-owns-signal
9a. TechRadar on Proton's user-funded model — https://www.techradar.com/vpn/vpn-services/proton-vpn-reveals-black-friday-sales-are-directly-paying-for-server-expansion
10. CGPress, Blender Foundation 2024 annual report coverage (Sep 2025) — https://cgpress.org/archives/blender-foundation-reports-higher-donations-but-warns-of-low-reserves-in-2024-annual-report.html ; Blender devfund posts — https://hackers.pub/tags/devfund
11. Jellywatch, "Jellyfin surpasses Plex" (2026) — https://jellywatch.app/blog/jellyfin-surpasses-plex-self-hosting-market-share-2026 ; r/selfhosted 2024 survey results — https://redlib.groet-infra.nl/r/selfhosted/comments/1fqlfki/selfhosted_survey_2024_results/ ; Tech-Insider Jellyfin vs Plex 2026 — https://www.tech-insider.org/jellyfin-vs-plex-2026/ ; Jellywatch Plex alternatives — https://jellywatch.app/blog/best-plex-alternatives-2026-jellyfin-emby-immich-comparison
12. Jellyfin official clients list — https://jellyfin.org/downloads/clients/all
13. It's FOSS, Motorola–GrapheneOS partnership (Mar 2026) — https://itsfoss.com/news/motorola-grapheneos-team-up.md ; Tuta de-Google list/survey 2026 — https://tuta.com/de/blog/degoogle-list ; GrapheneOS donate page — https://grapheneos.org/donate ; GrapheneOS history — https://grapheneos.org/history/ ; GrapheneOS forum on financial reports — https://discuss.grapheneos.org/d/12408-plans-for-the-financial-report ; Proton Foundation donation — https://discuss.grapheneos.org/d/21033-second-donation-to-grapheneos-by-the-proton-foundation ; Fossify fork discussion — https://old.lemmy.dbzer0.com/comment/6830565
14. TechCrunch on tipping conversion (0.58 %, USD 2.10) — https://techcrunch.com/2017/06/09/in-app-tips/ ; TechCrunch on Apple tipping rules — https://techcrunch.com/?p=1501713 ; Asohack indie monetisation guide 2026 — https://asohack.com/blog/mobile-app-monetization-guide-2026 ; Convopage indie thread — https://convopage.com/c/1269349151483011072
15. Apple App Store Small Business Program — https://developer.apple.com/app-store/small-business-program/
16. Google Play service fees help page — https://support.google.com/googleplay/android-developer/answer/112622
17. Apple, "Update on apps distributed in the European Union" (terms effective 1 Oct 2026) — https://developer.apple.com/support/dma-and-apps-in-the-eu/
18. Microsoft Learn, open a developer account (no registration fee, Sept 2025) — https://learn.microsoft.com/en-us/windows/apps/publish/partner-center/open-a-developer-account
18a. Apple Developer Program (USD 99/yr; Enterprise USD 299/yr) — https://developer.apple.com/programs/
18b. Google Play Console registration fee (USD 25) — https://support.google.com/googleplay/android-developer/answer/6112435
18c. Microsoft Learn, Microsoft Store for Business & Intune — https://learn.microsoft.com/en-GB/hololens/app-deploy-store-business ; Tech Community FAQ — https://techcommunity.microsoft.com/discussions/windows-management/faq-supporting-microsoft-store-experiences-on-managed-devices/3585286/replies/3829691
18d. Azure Trusted Signing / Artifact Signing pricing — https://azure.microsoft.com/en-us/pricing/details/trusted-signing/
19. Obsidian pricing — https://obsidian.md/pricing ; Obsidian licence overview — https://obsidian.md/eula ; Catalyst licence help — https://help.obsidian.md/Licenses+and+payment/Catalyst+license
20. 9to5Mac on Vision Pro sales (Jan 2026) — https://9to5mac.com/2026/01/02/m5-vision-pro-launch-likely-made-minimal-sales-impact-report/ ; Slashdot/IDC 45k estimate — https://apple.slashdot.org/story/26/01/01/189219/idc-estimates-apple-shipped-just-45000-vision-pros-last-quarter ; Tom's Guide — https://www.tomsguide.com/computing/vr-ar/apple-reducing-vision-pro-spending-after-underwhelming-sales-heres-what-we-know
21. TrustRadius Bitmovin vs THEOplayer pricing — https://tr-web.dev.trustradius.com/compare-products/theoplayer-vs-bitmovin ; G2 JW Player pricing — https://www.g2.com/products/jw-player/pricing ; Subger JW Player overview — https://subger.com/en/service/jwplayer
22. Dodo Payments, cheapest MoR 2026 — https://dodopayments.com/blogs/cheapest-merchant-of-record ; Fungies Polar.sh review 2026 — https://fungies.io/?p=40299 ; Alex Cloudstar, MoR in 2026 — https://alexcloudstar.com/blog/merchant-of-record-indie-saas-2026/
22a. RevenueCat pricing — https://www.revenuecat.com/pricing/
23. MarketsandMarkets digital signage — https://www.marketsandmarkets.com/Market-Reports/education-technology-market-513.html ; Market Research Future digital signage media player — https://www.marketresearchfuture.com/de/reports/digital-signage-media-player-market-28381 ; Kitcast (Grand View figures) — https://kitcast.tv/blog/new-digital-signage-trends ; QYResearch via Foriio — https://foriio.com/works/2381109
24. Linuxiac, Immich team goes full-time with FUTO (2024) — https://linuxiac.com/immich-team-goes-full-time/ ; Immich docs, Support the project — https://docs.immich.app/overview/support-the-project ; FUTO grants — https://futo.org/grants
25. Open Source Pledge — https://opensourcepledge.com/ ; Sentry USD 750k — https://blog.sentry.io/another-year-another-750-000-to-open-source-maintainers ; VoidZero 2025 pledge — https://voidzero.dev/posts/oss-pledge-2025 ; Keygen 2025 — https://keygen.sh/blog/keygen-continues-osspledge/ ; It's FOSS on Canonical/thanks.dev — https://itsfoss.com/news/major-boost-open-source-2025.md
26. KDE e.V. reports — https://ev.kde.org/reports/
27. Liberapay FAQ (0 % fee; ~3 % Stripe, ~5 % PayPal) — https://liberapay.com/about/faq
27a. GitHub Sponsors fees — https://docs.github.com/en/sponsors/getting-started-with-github-sponsors/about-github-sponsors
27b. Patreon pricing (10 %) — https://www.patreon.com/pricing
27c. Open Source Collective fees (10 % host fee) — https://docs.oscollective.org/how-it-works/fees
27d. Schoolmaker Patreon alternatives (Ko-fi fee ranges, secondary) — https://schoolmaker.com/blog/cheaper-alternatives-to-patreon
28. Deskmodder on UGREEN developer portal — https://www.deskmodder.de/blog/?p=212943 ; Android Authority best NAS brands 2026 — https://androidauthority.com/best-nas-brands-2026-3694228
29. RedMonk, "OSS forward, back" (May 2025) — https://redmonk.com/sogrady/2025/05/06/oss-forward-back/ ; OneUptime on Redis SSPL/AGPL — https://oneuptime.com/blog/post/2026-03-31-redis-licensing-sspl-agplv3-explained/view ; Goodwin on licensing trends — https://www.goodwinlaw.com/en/insights/publications/2024/09/insights-practices-moving-away-from-open-source-trends-in-licensing
29a. Functional Source License — https://fsl.software/
30. Storyboard18, JioStar removes 36 IPTV apps (Mar 2026) — https://www.storyboard18.com/ott-news/google-play-ios-purge-36-iptv-apps-with-26-million-downloads-taken-down-amid-t20-world-cup-91220.htm ; AMA Albania on One IPTV Player — https://ama.gov.al/at-amas-request-the-one-iptv-player-application-was-removed-from-google-play-for-the-illegal-streaming-of-albanian-television-channels/?lang=en ; TorrentFreak on Perfect Player (2019) — https://torrentfreak.com/google-play-removes-perfect-player-after-bogus-copyright-complaint-191019/ ; Cord Cutters News on MagisTV order — https://cordcuttersnews.com/court-orders-google-to-uninstall-pirate-iptv-app-from-android-devices/
31. Access Advance, record 2025 quarter / 100 % renewals (Jan 2026) — https://www.businesswire.com/news/home/20260121430948/en/Access-Advance-Closes-2025-with-Record-Quarter-Eight-Major-Licensees-100-Renewal-Rate-Litigations-Resolved ; rate-increase deadline — https://www.businesswire.com/news/home/20260126799824/en/Access-Advance-Extends-HEVC-Advance-Rate-Increase-Deadline ; new licensees H1 2026 — https://secure.businesswire.com/news/home/20260707864649/en/Access-Advance-Welcomes-Wave-of-New-Licensees-to-the-HEVC-Advance-Patent-Pool ; ipfray on Via LA pool transfer — https://ipfray.com/access-advance-reports-100-hevc-patent-agreement-renewal-rate-google-among-licensees-that-opted-to-extend/
32. AOMedia legal / patent licence — https://aomedia.org/about/legal/
33. European Commission, European Accessibility Act — https://commission.europa.eu/strategy-and-policy/policies/justice-and-fundamental-rights/disability/union-equality-strategy-rights-persons-disabilities-2021-2030/european-accessibility-act_en
34. F-Droid forum on download stats — https://f-droid.org/forums/topic/download-stats ; F-Droid Insights (GitHub-based ranking) — https://awesome.ecosyste.ms/projects/github.com%2Fdbeley%2Ffdroid-insights
35. Apple, Getting featured on the App Store — https://developer.apple.com/app-store/getting-featured/
36. Distimo localisation study via PocketGamer — https://www.pocketgamer.biz/distimo-90-of-the-top-apps-delivered-in-english-but-localisation-increasingly-important/ ; Smartling (AutoScout24 +38 %) — https://www.smartling.com/blog/seeking-quick-roi-theres-a-localized-app-for-that ; App Developer Magazine (Dec 2025 recap) — https://appdevelopermagazine.com/localizing-your-app-to-drive-store-rankings-and-global-growth/
37. Enable3 app retention benchmarks 2025 — https://enable3.io/blog/app-retention-benchmarks-2025 ; Pushwoosh retention benchmarks 2026 — https://www.pushwoosh.com/blog/increase-user-retention-rate ; Panto retention statistics — https://www.getpanto.ai/blog/mobile-app-retention-statistics ; Phiture benchmarks — https://phiture.com/mobilegrowthstack/managing-retention-rate-benchmarks-and-expectations/
