# 12 — Launch and Marketing Plan

Version 1.0 · 2026-10-19 · Zero paid acquisition. Growth comes from being the honest answer to "what plays this file" on every platform, and from the communities that already reject ads and paywalls.

## 1. Messaging

| Audience | Headline | Proof points |
|---|---|---|
| Everyone | Every file. Every screen. Nothing in the way. | Plays MKV/HEVC/AV1/FLAC/DSD/JPEG XL/RAW; Android, iPhone, iPad, Mac, Windows; no ads, no account, free |
| Switchers from MX/VLC/Plex | The player you wanted MX/VLC/Plex to be. | Gestures done right, HDR and Dolby-Vision-profile-8 correct, library with posters, casting free, no sign-in |
| Self-hosters | A first-class client for Jellyfin, Navidrome and Immich — and your plain SMB share. | Direct play, progress sync, offline downloads, one app for video/music/photos |
| Audiophiles | Bit-perfect where the OS allows, honest about it where it doesn't. | Fidelity indicator, parametric EQ + AutoEq, DSD, gapless, LRCLIB lyrics, scrobbling |
| Photographers | A real viewer: RAW, XMP, map, compare, batch — on your phone and your desktop. | Tiled 100 MP viewing, 4-up compare, vault, duplicates |
| Privacy community | Open source, telemetry off by default, reproducible builds, F-Droid. | Privacy dashboard listing every endpoint |
| IT buyers | Managed, lockable, accessible. | MDM config, kiosk mode, control API, EN 301 549 report, SBOM |

Never say "best", "#1", "fastest" in store metadata (featuring rules); say what it does.

## 2. Store listings

### 2.1 Copy (English master; localised to 12 languages)

- **Name:** Mediahro
- **Apple subtitle (30):** Video, music & photo player
- **Google short description (80):** Free player for every video, song and photo. No ads, no account, no limits.
- **Promotional/long description (structure):** 1) one-paragraph promise; 2) "Plays everything" list (containers, codecs, HDR, subtitles); 3) "Your sources" (local, SD/USB, SMB/NFS/WebDAV/FTP/SFTP/DLNA, Jellyfin/Emby/Plex/Navidrome/Immich/Nextcloud/Audiobookshelf — factual compatibility statements only); 4) Music (gapless, EQ, lyrics, bit-perfect, Auto/CarPlay); 5) Photos (RAW, HEIC, JXL, places, compare, vault, batch); 6) Casting; 7) Privacy and funding ("Free for everyone. Supported by people who choose to tip."); 8) Open source link; 9) Required disclosures (Windows: optional HEVC extension for hardware decoding).
- **Keywords (Apple, 100 chars):** video player,mkv,hevc,hdr,subtitles,music player,flac,gallery,photo viewer,raw,smb,nas,dlna,cast,jellyfin
- **What's New:** specific per release (Apple rejects generic notes).

### 2.2 Visual assets (generated from the running app by the integration harness; localised)

| Order | Screenshot | Platforms |
|---|---|---|
| 1 | Video playing with styled subtitles and a format badge strip (MKV · HEVC 10-bit · HDR · DTS-HD · ASS) | All |
| 2 | Sources screen: Files/SD/NAS/Jellyfin/Immich tiles | All |
| 3 | Music Now Playing with synced lyrics and EQ | All |
| 4 | Photos timeline + viewer with RAW/EXIF/map | All |
| 5 | Casting/external display | Mobile |
| 6 | "Free. No ads. No account. Supported by tips." with privacy dashboard | All |
| 7 | Desktop: sidebar library with posters (Mac/Windows), keyboard shortcut sheet | M W |
| 8 | Tablet/foldable layouts (Google featuring requires ≥ 4 tablet shots at 1920×1080) | A I |

Sizes per doc 07 (Apple 6.9"/6.5"/13" iPad/Mac 16:10; Google phone/7"/10"/TV banner 1280×720, feature graphic 1024×500, icon 512; Microsoft 1366×768+ screenshots, 300×300 tile, 1920×1080 super-hero art, trailer ≤ 60 s). App preview videos: 15–30 s, three per platform (play anything · sources · music/photos), captions burned in, no voice-over.

### 2.3 Ratings and reviews

In-app review prompt only after a success moment (third completed playback or first server connected), never on launch or during playback; Settings has a plain "Rate Mediahro" deep link. Reply to every store review in the first 90 days.

## 3. Website (mediahro.com, static)

Pages: Home (download buttons per platform with store badges + direct links), Features, Formats (full matrix), Servers & NAS, For business (Engine, Kiosk, support), Support Mediahro (MoR checkout, GitHub Sponsors, Liberapay), Transparency (annual report), Privacy, Trademark, Abuse/DMCA, Help (docs/help rendered), Blog (dev notes), Press kit (logo, screenshots, facts, founder bio). No analytics beyond server logs; Plausible optional.

## 4. Launch sequence

| Phase | When | Actions |
|---|---|---|
| **Pre-launch** | M7 | Name reserved everywhere; site live with "coming soon" and newsletter (Buttondown/Listmonk, double opt-in); GitHub repo public from M2 (build in the open: stars accrue early); dev notes monthly; TestFlight/Play closed test recruitment on r/androidapps, r/iosapps, r/selfhosted, Jellyfin/Navidrome/Immich forums, Matrix |
| **Beta** | M8 | Open beta on all platforms; F-Droid test repo; press embargo briefings (XDA, Android Police, 9to5Mac, MacStories, Windows Central, The Verge, Ars) with a hook: "one free app, four OSes, Dolby-Vision-profile-8 correct on Android, auto subtitle sync and OCR nobody else ships"; App Store featuring nomination 6–8 weeks ahead; Google Play "Promote" submission |
| **Launch day** | 1.0 | Simultaneous store availability; Show HN; Reddit posts (dev voice, candid funding story); Product Hunt (macOS/iOS angle); YouTube review units to NAS/self-hosting channels two weeks prior; Jellyfin/Navidrome/Immich/Audiobookshelf client-list PRs merged; AlternativeTo listings; winget/Homebrew PRs merged same day |
| **Launch +30** | — | Reply to every review; publish "what we learned" dev note; first transparency numbers; localisation push with Weblate volunteers |
| **Launch +90** | — | 1.1 (TV/Watch) press beat; first B2B page push to NAS vendors; year-end supporter campaign if timing fits |

## 5. Community

- GitHub Discussions + public roadmap (Projects); issue templates with device/codec fields; "Report a playback problem" from the app pre-fills them (no telemetry).
- Matrix space bridged to Discord; moderation guidelines; code of conduct.
- Weblate for translations; translator credits in-app.
- Monthly dev notes; annual State of Mediahro report.
- Contributor ladder: good-first-issues, review SLAs, DCO.

## 6. Partnerships

- Client listings: Jellyfin, Navidrome/OpenSubsonic, Immich, Audiobookshelf, Emby.
- NAS app centres: UGREEN (open developer portal), Synology, QNAP, TrueNAS — package the direct builds and a NAS-side "Mediahro server hints" guide.
- Communities: r/selfhosted, r/DataHoarder, r/jellyfin, r/degoogle, XDA, Lemmy.
- Open-source funds: register with thanks.dev, Open Source Pledge, floss.fund (`funding.json`).

## 7. Localisation priorities

Launch: en, pt-BR, es, hi, id, de, fr, ja, ru, tr, zh-Hans, it. Next: ko, zh-Hant, ar, vi, pl, nl, uk, fa, th, ms, he, cs, sv, fi. Store metadata localised alongside the app (Apple supports 50 locales).

## 8. Measurement

Store console metrics (page views, conversion, installs, ratings), opt-in Aptabase events (activation, retention, feature usage, supporter funnel), GitHub stars/contributors, Weblate coverage, press mentions, partner listings. Dashboard in the transparency report.
