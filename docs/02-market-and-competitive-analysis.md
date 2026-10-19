# 02 — Market and Competitive Analysis

Version 1.0 · 2026-10-19 · Synthesises `research/01`, `research/02`, `research/05`. Figures are sourced there; items the research could not verify are marked *(unverified)*.

## 1. Market reality

- **There is no consumer revenue pool to capture; there is an enormous audience.** Analyst sizing of "video player software" ranges from USD 7 M to USD 442 M for 2025 depending on scope, which says the category is free. Usage is the signal: VLC passed **7.0 billion cumulative downloads** on 31 Aug 2026 (about 650–700 M per year); VLC iOS alone adds ~23 M/year; MX Player reports **1.4 B+** Play downloads.
- **Android is reach, Apple is revenue.** Android holds 67–75 % globally and 79–93 % in India, Brazil and Indonesia; iOS carries ~2.4× the consumer spend. Plan for most installs on Android and most supporter revenue from Apple platforms and Windows desktop.
- **Self-hosting is the strongest tailwind.** Jellyfin 51 % vs Plex 40 % in the r/selfhosted survey; Plex's April 2025 paywall on remote streaming pushed users to open servers; Immich is the fastest-growing new self-hosted app. Being an official third-party client is a recognised distribution channel.
- **Privacy/de-Google is a donor-rich niche.** Motorola partnered with GrapheneOS in 2026; Fossify forks thrive on F-Droid; this audience rewards ad-free, telemetry-free, FOSS apps.
- **HDR correctness is now mainstream.** Dolby Vision profile handling is the most-discussed technical topic in player forums (Firecore DV thread ~2,000 posts). Mainstream free players still get tone mapping wrong on phones.
- **Vision Pro is not a market** (IDC ~45 k units in Q4 2025). visionOS compatibility is a press/featuring play only.

## 2. Competitive landscape

### 2.1 Video players

| App | Platforms | Model | Why users love it | Why users leave |
|---|---|---|---|---|
| VLC | All | Free, FOSS | Plays everything; SMB/NFS/UPnP/FTP; Chromecast; huge trust | Heavy; software decode drains iPhone battery; awkward gestures; no library/metadata; iOS rating 3.7 |
| MX Player | Android | Free + ads, Pro unlock | Gestures, codec breadth, 1 B+ installs | Aggressive ads, bloat (streaming, games), privacy concerns; sentiment "Frustrated" |
| Infuse 8 | Apple only | Pro USD 1.99/mo, 16.99/yr, 99.99 lifetime | Every codec incl. VVC, HDR10+/DV P5/P8, every protocol, Plex/Jellyfin/Emby, TMDB library, Trakt, skip-intro; 4.7★/28 k | Subscription fatigue; no DV P7; Apple-only; casting gated behind Pro |
| nPlayer Plus | iOS | USD 8.99 | Licensed DTS/Dolby, passthrough, protocol breadth | Three confusing SKUs, dated UI, no library |
| Plex | All | Free + Pass; remote streaming paywalled Apr 2025 | Best library UX, multi-user | Forced sign-in, house promos, crashes, paywall surprises; migration to Jellyfin |
| Kodi | All (iOS sideload) | Free, GPL | Scrapers, skins, add-ons, 10-foot UI | Heavy, awkward on phones, add-on piracy baggage, slow cadence |
| Just Player / Next Player / Nova | Android | Free, FOSS | No ads/tracking; DV correctness (Just); Material 3 (Next); TMDB (Nova) | Media3 limits: limited ASS styling, no AVI/WMV, no online subtitles (Next), SAF friction, no library (Just) |
| mpv / IINA / mpv-android | Desktop, Android | Free, FOSS | Reference rendering: libplacebo, Anime4K shaders, libass; IINA plugins | Config-file driven; no library; no polished mobile store app with shaders |
| Outplayer | iOS/visionOS | Free + USD 7.99 | mpv-based, spatial audio, dual subtitles, 4.6★ | No casting/AirPlay (its single biggest complaint); no library |
| PotPlayer / MPC-HC/BE | Windows | Free | madVR-class rendering, deep settings, tiny footprint (MPC) | Adware history (Pot), 2000s UI, Windows-only |
| Elmedia / Movist Pro | macOS | Free + Pro / paid | AirPlay+Cast+DLNA (Elmedia), OpenSubtitles auto-search, dual subs + TTS (Movist) | macOS-only; no HDR (Elmedia); needs tuning (Movist) |
| Stock players | — | Bundled | Ubiquitous | Apple: no MKV/ASS/PGS; Windows: HEVC paid, AC-3 removed, 377 MB RAM; Android: no subtitles/sources |

### 2.2 Audio players

| App | Platforms | Model | Strength | Weakness |
|---|---|---|---|---|
| Poweramp | Android | One-time | 768 kHz/32-bit, DSD1024, 64-band EQ, polish | Android-only, dense settings |
| Musicolet | Android | Free, Pro IAP | No internet permission, multiple queues, LRC creator, 20 M+ installs | Crossfade/ReplayGain/Cast behind IAP |
| Neutron | Android/iOS/Windows | One-time | Deepest engine (1.536 MHz, DSD native, 4–130-band parametric EQ, AutoEq, SMB/WebDAV/Subsonic) | Dated UI (3.9–4.0★) |
| USB Audio Player PRO | Android | Paid + add-ons | Bit-perfect USB driver, MQA | Nickel-and-diming |
| foobar2000 | 4 OS | Free | Low CPU, gapless, UPnP/SMB | Stark UI, mobile lacks CarPlay/smart playlists |
| Symfonium | Android | One-time | Every server (Plex/Jellyfin/Navidrome/OpenSubsonic/Audiobookshelf), AutoEQ, smart filters | Server-centric, no desktop |
| Auxio / Oto / Retro | Android | Free | Material 3, FOSS | Weak art fetching; EQ gated (Oto+) |
| Doppler / Marvis / Flacbox / VOX | Apple | Paid or subscription | Native feel; cloud/NAS (Flacbox) | Subscription fatigue (Flacbox USD 69.99 lifetime), import friction |
| MusicBee / AIMP | Windows | Free | WASAPI/ASIO, library management, 25–70 MB RAM | Windows-only, dated UI |
| Stock | — | — | — | iOS Music refuses FLAC; Files has no queue; Windows Media Player 377 MB idle |

### 2.3 Image viewers and galleries

| App | Platforms | Model | Strength | Weakness |
|---|---|---|---|---|
| Fossify Gallery | Android | Free, GPL | JXL/AVIF/SVG/RAW, vault, recycle bin, 500 k+ | No batch tools, no cloud, slow cadence |
| Aves | Android | Free, BSD (Flutter) | Metadata explorer, motion photos, map, GeoTIFF | Flutter overhead on low-end, JXL/AVIF unclear |
| F-Stop | Android | Free + IAP | XMP tags/ratings compatible with Lightroom | Older UI, slowing development |
| Google Photos | Android/iOS | Free + storage | ML search, sharing | Albums are links, folders don't sync, cloud push, uncontrolled duplicate merging |
| Apple Photos | Apple | Stock | Live Photos, iCloud | Two redesigns in 12 months, no folder browsing, removed slideshow speed |
| XnView MP / FastStone / IrfanView / ImageGlass | Desktop | Free | 500+ formats, EXIF/IPTC/XMP edit, batch, duplicate finder, 4-up compare, HDR viewing | Dense UIs, desktop-only, no vault/map/motion photos |
| Honeyview | Windows | Free | Archive (ZIP/CBZ) browsing | Discontinued 2024 |
| Immich | Server + mobile | AGPL + optional licence | Local-first + optional server, faces, Free-Up-Space | Needs own server |
| Microsoft Photos / Preview | Stock | — | Rebuilt 2026 (Photos) | Years of 20–25 s launches; paid HEIC; Preview has no folder next/previous |

## 3. Feature consensus

### 3.1 Table stakes (missing any yields one-star reviews)

**Video:** hardware H.264/HEVC/VP9/AV1 with software fallback; 10-bit; HDR10/HLG displayed correctly; HDR10+ and DV P5/P8 on capable hardware; all containers (MKV, MP4, MOV, TS/M2TS, AVI, WMV, WebM, FLV); AAC/AC-3/E-AC-3/DTS(-HD)/TrueHD/FLAC/Opus decode with a dialogue-safe downmix; SRT/VTT/ASS/SSA with libass styling, PGS/VobSub/DVB, external auto-load, encoding detection, delay, styling, multiple tracks, online download; gestures (seek, volume, brightness, pinch, double-tap), speed 0.25–4× with pitch correction, resume, touch lock, PiP, background/audio-only, media session/Bluetooth controls, headphone-unplug pause; local browser with folder tree, sort, search, thumbnails, continue watching; file operations; SAF/scoped storage, SD/USB-OTG; Files-app provider on iOS; SMB2/3, NFS, FTP/SFTP, WebDAV, DLNA, HTTP/HLS/DASH/RTSP; Chromecast and AirPlay; Plex/Jellyfin/Emby; no ads/account/telemetry; small, fast, stable with multi-GB files.

**Audio:** FLAC/ALAC/Opus/AAC/MP3/WavPack/APE/AIFF/WAV/DSF/DFF; gapless; crossfade; ReplayGain and R128; 10-band graphic plus parametric EQ with limiter/balance/tempo/pitch; embedded + LRC + online synced lyrics; tag editing (single/batch) with art fetch; folder and library modes; smart playlists; multiple queues; sleep timers; Android Auto/CarPlay; widgets; AVRCP; Cast/AirPlay; SMB/WebDAV/FTP; Subsonic/Navidrome/Jellyfin/Plex; podcast/audiobook mode with chapters, speed, resume; Last.fm/ListenBrainz; visualiser; theming.

**Images:** JPEG/PNG/GIF/WebP/AVIF/HEIC/JXL/SVG/TIFF/BMP/PSD-preview/RAW; animated formats; Live/Motion Photos; EXIF/IPTC/XMP view and edit; GPS map; folders and albums; biometric vault; slideshow; crop/rotate/flip/adjust/draw; batch rename/convert/resize; duplicate finder with user control; tiled rendering for 100 MP+; 2/4-up compare; metadata search; favourites/ratings; recycle bin; SMB/WebDAV/Immich/Nextcloud; wallpaper; share; print; archive browsing.

### 3.2 Delighters (cited as reasons to pay or switch)

DV P7 graceful handling, VVC decode, AV1 film grain; audio passthrough and per-device settings; spatial audio; TMDB/TVDB library with Trakt, skip-intro, parental PIN; auto frame-rate matching on TV; shader upscaling (Anime4K/FSR) with one toggle; frame interpolation; dual subtitles; **audio-based auto subtitle sync and PGS/VobSub OCR (offered by no player today)**; subtitle TTS; web remote; remappable keyboard/remote; screenshot/GIF/clip export; A-B loop, chapters, bookmarks, frame step; free casting + AirPlay; cloud drives; plugin system; bit-perfect output on every OS with a fidelity indicator; mobile compare mode; Watch/Wear companion.

### 3.3 Failure modes to design against

1. Ads and bloat (MX, Plex promos, KMPlayer bundleware).
2. Monetisation surprises (Plex paywall, Infuse price hikes, fragmented SKUs, restore-purchase bugs).
3. Forced accounts.
4. Codec gaps and paid codecs (no MKV on Apple, HEVC paid on Windows, DTS silent, DV washed out, hev1/hvc1 tagging).
5. Crashes on large files, SMB scans, document pickers; freezes during subtitle sync.
6. Battery drain and heaviness (software decode, 377 MB RAM).
7. Subtitle problems (styling, sync, language reset per episode).
8. Audio problems (Bluetooth first-seconds cut-off, A/V desync, no passthrough).
9. Poor file/network browsing (scoped-storage confusion, no URL field, no library folder choice).
10. Gesture and UI ergonomics (over-sensitive sliders, hidden settings).
11. Missing casting/AirPlay.
12. Stagnation and neglected platforms.
13. Security (malicious subtitle files, hostile network shares).

## 4. Where Mediahro wins

| Gap in the market | Mediahro's answer | Spec reference |
|---|---|---|
| No app does video + audio + images on all four OSes | One codebase, one feature set, three first-class modes | doc 04 all |
| HDR/DV correctness on phones | libplacebo tone mapping, DV P5 reshaping, P8 as HDR10, P7 base-layer playback, auto frame-rate on TV | VID-030…036 |
| ASS styling and image subtitles on Android | libass everywhere; PGS/VobSub/DVB; OCR to text | SUB-010…040 |
| Nobody offers auto subtitle sync or OCR | Audio-fingerprint sync (alass/ffsubsync approach) and on-device OCR | SUB-050, SUB-051 |
| Casting gated or missing | Chromecast, AirPlay, DLNA renderer free on every platform that allows it | CAST-* |
| Paywalled audio basics | EQ, crossfade, ReplayGain, Cast, lyrics all free | AUD-* |
| Bit-perfect only on single platforms | Exclusive/hog/USB paths on all four with a fidelity indicator | AUD-040…046 |
| Galleries: mobile lacks batch/compare, desktop lacks vault/map/motion | All of it everywhere | IMG-* |
| Self-hosted clients are fragmented | First-class Jellyfin, Emby, Plex, Subsonic/Navidrome, Immich, Nextcloud, WebDAV, SMB, NFS, FTP/SFTP, DLNA | NET-* |
| Trust | FOSS, no telemetry by default, reproducible builds, published trademark and funding policy | doc 09, doc 13 |
| Performance | Measured budgets in CI: start time, RAM, scroll jank, battery | doc 11 |

## 5. Threats and responses

| Threat | Response |
|---|---|
| VLC 4 ships a modern UI and library | Mediahro's edge stays: HDR pipeline, native feel, audio depth, gallery, servers. Keep shipping monthly. |
| Amazon bundles MX Player on Fire TV | Irrelevant to Mediahro's audience (ad-averse). Compete on Android TV quality in 1.1. |
| Store policy shifts on media permissions or payments | Photo Picker/SAF fallbacks and multi-rail funding are designed in (doc 07, doc 08). |
| Patent pool pressure on software HEVC/AV1 | Hardware-first decode policy; software decoders are fallbacks; counsel before OEM deals (doc 09). |
| Being mistaken for an IPTV app | No channel lists, no EPG, no add-ons, plain URL playback only, "IPTV" never in metadata (doc 07). |
| Clone apps using the name | Trademark registration and policy; store takedowns (doc 03, doc 09). |
