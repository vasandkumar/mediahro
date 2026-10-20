# 01 — Product Vision and Strategy

Version 1.0 · 2026-10-19 · Status: approved for build

## 1. One-line vision

**Mediahro plays everything you own, everywhere you are, with nothing in the way.**

A single free app for video, music and photos on Android, iOS/iPadOS, macOS and Windows that is faster and more capable than the stock players, carries no ads, no account, no tracking and no paywalled features, and is funded by the people who love it and by the businesses that build on it.

## 2. The problem

Every platform ships a stock media experience that is deliberately limited:

- **Apple** (Photos, TV, QuickTime, Music, Files): no MKV, no ASS/PGS subtitles, no FLAC in Music, Files plays one track at a time, no network shares in the player, no folder browsing of photos.
- **Android** (Google Photos, OEM players): a gallery that is cloud-first and pushes uploads, no external subtitles, no audio-track switching, no NAS sources; music defaults to a streaming service.
- **Windows** (Media Player, Photos): HEVC behind a paid extension, AC-3 removed in 24H2, 377 MB idle RAM versus 103 MB for the 17-year-old legacy player, no subtitle search, a Photos app that took 20–25 s to launch for years.
- **macOS** (QuickTime, Preview, Music): no MKV, no next/previous across a folder in Preview, FLAC silently rejected by Music.

The third-party alternatives each fix part of this and break something else: MX Player decayed into ads and bloat; Plex paywalled remote streaming and forces sign-in; Infuse is excellent but Apple-only and subscription-gated; VLC plays everything but is heavy, battery-hungry on iPhone and has no library; the open-source Android players lack ASS styling and online subtitles; audio players gate crossfade, ReplayGain and EQ behind "Pro"; no gallery combines FOSS trust, metadata depth, vault, map and desktop-class batch tools. **No app on the market covers video, audio and images on all four platforms with one consistent UI.** (Evidence: `docs/02-market-and-competitive-analysis.md`.)

## 3. Who it is for

| Persona | Situation | What they need from Mediahro |
|---|---|---|
| **The collector** (primary) | Has terabytes of films, series, music and photos on phone storage, SD cards, a NAS or a Jellyfin/Navidrome/Immich server. Often in India, Brazil, Indonesia, Turkey or the DIY/self-hosted community in the US/EU. | Plays every file (MKV, HEVC 10-bit, Dolby Vision profile 8, DTS-HD, FLAC, DSD, JPEG XL, RAW) from any source with correct HDR, styled subtitles, gapless audio and a real library. No ads. |
| **The switcher** | Fed up with MX Player ads, Plex paywalls, VLC's gestures, or Google Photos nagging about cloud. | A drop-in default player/gallery that feels native, is fast, and never asks for an account. |
| **The listener** | Wants a serious offline music player with EQ, lyrics, scrobbling, bit-perfect USB DAC output, podcasts/audiobooks with chapters, Android Auto/CarPlay. | Poweramp/Neutron-class audio with Musicolet's "no internet needed" trust and a modern UI, free. |
| **The photographer** | Shoots RAW/HEIC on phone or camera; wants a folder-based viewer with EXIF/XMP, map, compare mode, batch rename and a locked vault. | XnView/FastStone capabilities on phone and desktop, with Immich/Nextcloud as optional sources. |
| **The privacy-minded** | Uses F-Droid, GrapheneOS, de-Googled devices; donates to FOSS. | No telemetry by default, reproducible builds, FOSS flavour, open roadmap. |
| **The IT buyer** (B2B) | Deploys media playback on managed devices: signage, kiosks, classrooms, hotel TVs, factory floors, NAS app catalogues. | Managed configuration, kiosk mode, SDK licence, support contract, accessibility compliance. |

## 4. Product principles (non-negotiable)

1. **Plays everything.** If FFmpeg can demux and decode it, Mediahro plays it. Platform hardware decoders are used first for speed, battery and patent safety; software decoding is the fallback, never the default.
2. **Nothing in the way.** No ads, no account, no onboarding walls, no feature gates, no upsell interstitials. The only commercial surface is a quiet, honest supporter page.
3. **Fast on purpose.** Cold start to first frame under 1.5 s on a 2022 mid-range phone; idle RAM under 150 MB on desktop; 120 Hz UI; thumbnails that never block scrolling. Performance budgets are tested in CI (doc 11).
4. **Native where it matters, identical where it counts.** One codebase, one feature set, but each platform's conventions for navigation, typography, share sheets, file pickers, media sessions and keyboard shortcuts are respected (doc 06).
5. **Local-first, server-optional.** The library lives on the device and reads from local storage, SMB/NFS/WebDAV/FTP, DLNA, cloud drives and self-hosted servers (Jellyfin, Emby, Plex, Subsonic/Navidrome, Immich, Nextcloud). Nothing requires an internet connection except features whose purpose is online (subtitle download, metadata, lyrics, scrobbling), and each is an explicit opt-in.
6. **Private by default.** No telemetry unless the user turns it on. No network permission use until a network feature is used. No crash report leaves the device without consent.
7. **Trust is the moat.** Open source (AGPL-3.0 core, see doc 09), reproducible F-Droid builds, published trademark policy, annual transparency report, no dark patterns.
8. **Complete, not minimal.** 1.0 ships the full specification (doc 04). Sequencing is for engineering order, not for scope reduction.

## 5. Positioning

**For** people who keep their own media, **Mediahro** is the free all-in-one player and gallery **that** plays every format on every device with a native-feeling, ad-free UI, **unlike** VLC (heavy, no library), MX Player (ads), Infuse (Apple-only, subscription) or the stock apps (limited formats), **because** it is built on a single high-performance engine (libmpv/libplacebo, libass, libvips) wrapped in one adaptive UI and funded by supporters rather than by advertisers or paywalls.

Tagline (store and site): **"Every file. Every screen. Nothing in the way."**

## 6. Strategic bets

| Bet | Why we believe it | How we de-risk it |
|---|---|---|
| A unified video + audio + image app beats three single-purpose apps | Users already juggle 3–5 apps; no incumbent does all three on four OSes; shared library/sources/thumbnail infrastructure makes the combination cheaper than it looks | The three modes are separate top-level tabs with their own IA, so each is as good as a dedicated app (doc 06) |
| Free + supporter-funded can sustain a team | Thunderbird: USD 10.3 M from 335 k donors in 2024; VLC: 7 B downloads, zero ads; Obsidian/Immich: free forever with optional licences | Target 0.5–2 % supporter conversion; add B2B from year 2; keep fixed costs under USD 1.5 k/yr (doc 08) |
| HDR/Dolby Vision correctness and subtitle quality are the technical differentiators of 2026 | Firecore's DV megathread has ~2,000 posts; Just Player won a niche purely on DV correctness; ExoPlayer apps lose on ASS styling | libmpv + libplacebo tone mapping and libass are solved problems; we expose them with one toggle (doc 05) |
| Self-hosted communities are the cheapest distribution channel | Jellyfin 51 % vs Plex 40 % in r/selfhosted; Jellyfin lists third-party clients officially; Immich is the fastest-growing new app | Ship first-class Jellyfin/Navidrome/Immich clients at 1.0 and get listed (doc 12) |
| B2B pays the bills | Signage media-player software is a USD 2.3 B segment; SDK anchors at USD 249–505/month; NAS vendors court third-party apps | AGPL core + commercial licence, managed-config and kiosk mode built into 1.0 (doc 04 §B2B, doc 08) |

## 7. Goals and success metrics

### 7.1 Launch goals (first 12 months after 1.0)

| Metric | Target | Source of truth |
|---|---|---|
| Store rating | ≥ 4.6 on App Store, Google Play, Microsoft Store | Store consoles |
| Crash-free sessions | ≥ 99.5 % | Opt-in crash reports + store vitals |
| Android vitals | User-perceived crash rate < 1.09 %, ANR < 0.47 % | Play Console |
| Cumulative installs | 400 k (year 1), 2 M (year 2), 5 M (year 3) | Store consoles + F-Droid estimates |
| Retention | D1 ≥ 35 %, D7 ≥ 20 %, D30 ≥ 12 % | Opt-in analytics (Aptabase) with store-level proxies |
| Supporter conversion | ≥ 1 % of average MAU per year; ≥ 5 supporters per 1,000 MAU after first campaign | Store IAP reports + web MoR |
| B2B | 2 paying contracts in year 2, 5–6 in year 3 plus one SDK/OEM deal | CRM |
| Community | 10 k GitHub stars in year 1; listed on Jellyfin, Navidrome and Immich client pages | GitHub, partner pages |
| Localisation | 12 languages at launch, 25 by year 2 | Weblate |

### 7.2 Quality bars (every release)

- Cold start to interactive: ≤ 1.0 s desktop, ≤ 1.5 s mid-range phone.
- Open-to-first-frame for a local 4K HEVC file: ≤ 500 ms.
- Library scan: 10 k files indexed in ≤ 30 s on phone, incremental rescans ≤ 2 s.
- Gallery scroll: 60/120 fps with no dropped frames while thumbnails load.
- Idle RAM: ≤ 150 MB desktop, ≤ 120 MB mobile; video playback ≤ 350 MB for 4K.
- Install size: ≤ 75 MB Android (per ABI, ADR-019), ≤ 80 MB iOS (thinned, ADR-024), ≤ 175 MB macOS universal (ADR-024), ≤ 70 MB Windows; Play download size per ABI is reported every build.
- Battery: 4K HEVC playback at or below the platform stock player's drain on the same device.
- Accessibility: every control labelled, full keyboard/D-pad operation, captions honour system styles.

## 8. Non-goals

- No streaming service, no content catalogue, no IPTV channel lists, no EPG, no "add-on marketplace", no torrent client. These are the fastest route to store removal (doc 07, doc 09).
- No cloud storage of user media operated by us. No accounts.
- No video editing beyond trim/screenshot/GIF export; no photo editing beyond adjust/crop/rotate/draw.
- No medical imaging (DICOM) or regulated verticals.
- No ads, ever, including "house ads".
- No Linux desktop at 1.0 (the Flutter/libmpv stack makes it a cheap 1.x addition; it is tracked, not promised).

## 9. Release definition

**Mediahro 1.0** ships simultaneously on the App Store (iOS/iPadOS), Mac App Store and direct notarised macOS download, Google Play, F-Droid (FOSS flavour), Microsoft Store (MSIX) and direct Windows installer plus winget. It contains every feature in doc 04 marked `1.0` for its platform, meets every quality bar above, and passes every release gate in doc 11.

Android TV, tvOS and Apple Vision compatibility are **1.0 platforms in compatibility mode** (the phone/tablet app runs there and is usable with a remote); dedicated 10-foot UIs and a Wear/Watch companion are **1.1**. Linux desktop is **1.2**.
