# Video Player Apps: Competitive and Feature Analysis (Android, iOS, macOS, Windows)

*Research date: 2026-10-19. Input for designing a free, high-performance, bloat-free cross-platform media app (video + audio + images).*

## 0. Scope, method and caveats

- Sources: 28 web searches (2025-2026 where available) plus direct reads of official pages (Firecore/Infuse, Just Player and Next Player GitHub, Nova GitHub, mpv-android GitHub, Eltima/Elmedia, nPlayer, Outplayer App Store listing, Movist Pro, KMPlayer mobile page, Wikipedia comparison table).
- Google Play pages could not be fetched directly in this run; Play Store rating/download figures are therefore from aggregators or widely reported install tiers and are marked "approx." Items marked **[unverified]** are commonly reported facts that could not be re-confirmed within the search budget.
- Reddit could not be queried directly (the shared search budget was exhausted before the Reddit-restricted queries ran). User-complaint data comes from App Store/Play Store review aggregators (Kimola, unitQ, marlvel.ai, appfollow), Firecore/Plex/Kodi/VideoHelp forums and Trustpilot.

---

## 1. Per-app profiles

### 1.1 VLC (VideoLAN) - Android, iOS/tvOS, macOS, Windows, Linux
- **Price:** Free, open source (GPL/LGPL), no ads, no tracking.
- **Scale/ratings:** Android: 500M+ installs tier **[unverified]**; iOS App Store US: **3.7/5 from ~6K ratings** (App Store listing). Aggregators show conflicting sentiment (3.7/5 from 5.5K vs a "98% negative" NLP score), so treat sentiment data with caution.
- **Recent releases:** Android 3.6.0 (Jan 2025) added **Remote Access** (control/browse from any device via browser), parental control, favorites, tap-to-fast-play, metered-network warning, PiP improvements, chapter navigation in audio player. Android 3.7.0 (Feb 2026) brought a completely new equalizer and improved settings backup. Desktop 3.0.21 (2024) added NVIDIA TrueHDR (SDR-to-HDR). VLC 4.0 desktop (new UI) still not generally released as of this research **[unverified]**.
- **Strengths:** Plays almost everything (software decode via libavcodec, H.264/HEVC/AV1); streams SMB/FTP/UPnP-DLNA/NFS/HTTP; Chromecast; music/audio library with equalizer and background playback; cloud sync (Dropbox, OneDrive, etc. on iOS); Wi-Fi share; playback speed; advanced subtitle support; huge volunteer community; cross-platform parity.
- **Weaknesses cited in reviews:** Android: hard-to-use volume/brightness gestures, unclear subtitle display, freezes during subtitle synchronization, "too heavy compared to the competition", crashes and Bluetooth problems. iOS: Bluetooth audio cuts off first seconds of tracks, over-sensitive gesture sliders on iPad, no automatic library/metadata management (manual organization), requests for PiP and SRT protocol; a forum user warns VLC "wastes a lot of battery" on iPhone (software decoding). Desktop: interface "hides many advanced settings" (TechRadar 2025); no metadata scraping; dated UI pending VLC 4.
- **Takeaway:** VLC is the compatibility baseline users compare everything against, but it loses on polish, battery (software decode paths), library/metadata and gesture ergonomics.

### 1.2 MX Player / MX Player Pro - Android (iOS listing exists)
- **Price:** Free with ads (banner, interstitial, pre-roll for streaming), plus in-app "online video" content; **MX Player Pro** is a one-time purchase that removes ads and strips the "value-added services" (marketing: "lightweight with only core functionalities").
- **Scale/ratings:** **1B+ downloads**; **~4.0-4.2/5 from ~13-14M reviews** (aggregators). A May 2026 app-intelligence page labels user sentiment "Frustrated" with top complaint "aggressive advertisement frequency during navigation and playback".
- **Strengths:** Hybrid HW+SW decoding ("8K/4K Ultra HD playback", "70% boost in decoding performance"), very broad subtitle formats (SRT, SSA/ASS, VobSub, WebVTT, DVB, etc.), gesture controls (pinch zoom, swipe seek/volume/brightness), PiP, Samba network share, video cutter, kids lock. Still the mainstream mental model for "Android video player" gestures.
- **Weaknesses:** Ads and bloat (streaming content, games, short videos) since the 2018 acquisition; reports of unauthorized carrier charges **[unverified]**; privacy concerns; "online videos" and other features regionally restricted; large app size; HDR/Dolby Vision support not documented.
- **Takeaway:** MX Player is the textbook example of a beloved player whose ratings decayed through bloat and ads. Its free-tier UX (gestures, codec breadth) is the bar a new free player must match without ads.

### 1.3 Infuse 8 (Firecore) - iOS, iPadOS, tvOS, macOS, visionOS
- **Price:** Free download; **Infuse Pro $1.99/mo, $16.99/yr, $99.99 lifetime** (7-day trial). Pro gates: extra formats, lossless HD audio (24-bit), AirPlay/Google Cast, Dolby Vision and Atmos, trailers, advanced iCloud sync, cloud streaming. Prices rose from EUR 9.99 to 14.99/yr in 2024; existing subscribers keep their price.
- **Ratings:** **4.7/5 from 28K ratings** (US App Store). Requires iOS 18+/macOS 15+.
- **Strengths (official feature list):** Containers incl. MKV, TS, M2TS, ISO/BDMV, VOB, WMV, RMVB; codecs **H.264, H.265, H.266 (VVC), AV1, VP8/9, MPEG-1/2, VC-1**; **HDR10, HDR10+, HLG, Dolby Vision Profiles 5 and 8**; audio AC3/E-AC3/TrueHD/DTS/DTS-HD MA/FLAC with Atmos (E-AC3) passthrough; subtitles SRT, ASS/SSA, PGS, VobSub, DVB, SUP, VTT etc. with one-tap OpenSubtitles download; network **SMB, NFS, FTP/FTPS/FTPES, SFTP, HTTP(S), UPnP/DLNA, WebDAV**; **Plex, Emby, Jellyfin** with watched-history sync; cloud: Dropbox, Google Drive, OneDrive, Box, pCloud, MEGA, Yandex, Aliyun, Baidu etc.; TMDB metadata, posters, cast, ratings, trailers; filters, collections, playlists, parental controls, **Trakt scrobbling**, **skip intro/credits (IntroDB)**, **AI video upscaling**; AirDrop/FTP/web transfer; iCloud sync; no ads/tracking.
- **Weaknesses:** Subscription fatigue ("needs a subscription" is the main drawback cited); **Dolby Vision Profile 7 (UHD Blu-ray rips) cannot be played** ("will probably never be possible"; users convert P7 to P8); DV behaviour inconsistent across devices (Dec 2025 forum reports); community complaints that Infuse 8 focused on Vision Pro instead of long-requested features (auto-download subtitles, unwatched filter in direct mode); no Android/Windows version; no 3D/VR180 on visionOS at launch.
- **Takeaway:** Infuse is the benchmark for "beautiful library + plays everything + every network protocol" on Apple platforms, and proves users will pay for that combination. Its gaps (DV P7, subscription, Apple-only) are the opening.

### 1.4 nPlayer / nPlayer Plus - iOS (Android version exists but undocumented on official site)
- **Price:** nPlayer Lite (free, ads), nPlayer paid, **nPlayer Plus $8.99** (adds DTS/Dolby licences). US rating **~4.7/5 from ~2.5K** (aggregator, Mar 2026).
- **Strengths:** DTS-HD and Dolby AC3/E-AC3 officially licensed, **Dolby/DTS HDMI bitstream passthrough**; H.264/MPEG4 HW accel (listing also claims AV1/HEVC HW accel); speed 0.5-4.0x; A-B repeat; subtitles SMI/SRT/SSA/ASS/IDX+SUB/LRC with multi-track, sync, styling; network **WebDAV, FTP, SFTP, HTTP, SMB/CIFS, UPnP/DLNA (NFS listed in store copy)**; cloud Box/Dropbox/Google Drive/OneDrive/Yandex; download-to-device; Files app integration ("choose save or play").
- **Weaknesses:** Confusing three-SKU pricing; Lite has ads; no library/metadata scraping; UI dated; HDR/Dolby Vision not advertised; Android version neglected.
- **Takeaway:** nPlayer is the "technical control" option (audio passthrough, protocol breadth) rather than a library experience.

### 1.5 KMPlayer - Windows, macOS (alpha), Android, iOS
- **Price:** Free; mobile "Premium" features on Android (3-day trial); donations. Desktop historically adware/bundled installers (SnapFiles: "adware-laden ... ads appear at random"); AlternativeTo users report ads reduced in some versions and "forced upgrade prompts and adware in the latest version" in others.
- **Scale/ratings:** Play Store **~4.1/5 from ~390K**; App Store ~4.2-4.3 from 2-3K. Top complaint per aggregator: frequent crashes/freezes during playback.
- **Strengths (mobile page):** 4K/UHD with HW accel, speed 0.25-4x, section repeat, zoom, flip/rotate, subtitles SRT/SSA/ASS/WebVTT/VobSub with styling and **subtitle search/download**, network FTP/FTPS/SFTP/UPnP/SMB/WebDAV/NFS, cloud Dropbox/OneDrive, YouTube playback "without ads"; desktop: 4K/8K, VR/360, customizable skins.
- **Weaknesses:** Ad/bundleware history on desktop, crash reports, stability; HDR not documented.

### 1.6 PotPlayer (Kakao/Daum) - Windows only
- **Price:** Free, proprietary. Began bundling third-party software and showing corner ads in 2019; Wikipedia claims (citation needed) no adware/ads as of 2022; comparison sites still list "occasional bundled software and ads".
- **Strengths:** Extremely deep settings; hardware decoding (DXVA/CUDA/QuickSync); **madVR renderer support** (HDR-to-SDR tone mapping regarded as best-in-class, though needs tuning); 3D and 360 playback; optimized HEVC/AV1 decoding; screen recorder, simple editing; FTP and URL streaming; bookmarks, chapters; skins. VideoHelp reviewers (late 2025) rate it highly; builds from Sep/Nov 2025 confirm active maintenance.
- **Weaknesses:** Complexity ("overwhelming settings"), Windows only, closed source, occasional bugs (missing DLL, AAC decoder issues), Dolby Vision support not confirmed, past adware reputation.

### 1.7 mpv / IINA / mpv-android
- **mpv** (Windows/macOS/Linux/Android, GPL/LGPL, free): reference-quality renderer (libplacebo, scalers, debanding, interpolation, **GLSL user shaders incl. Anime4K/FSR/NNEDI3**), HDR tone mapping, libass (gold-standard ASS rendering), HTTP/HLS/DASH/FTP/RTSP streaming (no RTMP, no DLNA), scriptable (Lua/JS). Weakness: no GUI/library, config-file driven; too technical for store audiences.
- **IINA** (macOS, free, open source): mpv wrapped in a native macOS UI. **IINA 1.4.0 (public beta Sep 2025, then 1.4.1 bug-fix)** added a **JavaScript plugin system** (built-in plugins for online media, **OpenSubtitles**, user scripts), ReplayGain, WebP/JPEG-XL HDR screenshots, Core Audio or AVFoundation audio driver choice, mpv 0.38. Anime4K shaders work because it is mpv, but there is no official plugin. Weakness: macOS only, no library, occasional critical bugs at major releases.
- **mpv-android** (free, GPL; Play, F-Droid, GitHub; 3.6K stars): HW/SW decoding, gesture seek/volume/brightness, **libass styled subtitles, dual subtitles**, scalers/debanding/interpolation, Open URL, background playback, PiP, keyboard. Dec 2025 release added multi-file open from share menus and better scoped-storage support; earlier releases fixed document-picker crashes. Weaknesses: shaders/config require manual mpv.conf (users report Play build cannot load shaders due to Android 11+ scoped storage, APK works), Android TV only via F-Droid/APK, bare-bones file picker, no library. Community fork **mpv-android-anime4k** (447 stars, pushed May 2026) bundles Anime4K upscaling.

### 1.8 Plex (player apps) - all platforms
- **Price:** Server free; mobile apps require a **one-time ~$5 mobile unlock** (or Plex Pass) for full local playback; **remote streaming of personal libraries became paid on 29 Apr 2025** (Plex Pass or Remote Watch Pass). Lifetime Plex Pass price also rose in 2025 **[unverified]**.
- **Strengths:** Best-in-class library/metadata, continue watching, multi-user, transcoding, offline downloads, Dolby Vision direct play (sends MKV to client and lets ExoPlayer fall back DV->HDR10), wide device coverage.
- **Weaknesses (Trustpilot 2025, forums):** forced account sign-in even for home LAN, ads for Plex's own streaming content ("intrusive ads interrupting playback"), crashes on iOS/tvOS, choppy video, subtitle issues, server connection drops, paywall confusion ("asking for subscription on home network"), "Quality has really, really gone down" threads; many users report moving to Jellyfin.
- **Takeaway:** Plex shows the ceiling for library UX and the floor for trust: monetization changes and bundled streaming content are the dominant complaint themes.

### 1.9 Kodi - Windows, macOS, iOS, Android, Linux, webOS
- **Price:** Free, GPL. **Kodi 21 "Omega"** (Apr 2024; 21.3 Dec 2025): FFmpeg 6, **Android Dolby Vision profile conversion**, native macOS windowing; 21.x point releases are "bugfixes, not features". **Kodi 22 "Piers"** RC1 (Oct 2026): FFmpeg 8, **HDR overlays incl. UHD PGS subtitles**, HEIF/HEIC, RetroPlayer shaders/cheats/RetroAchievements.
- **Strengths:** Library scraping (TMDB/TVDB), skins, add-ons, PVR, SMB/NFS/UPnP/WebDAV, remote apps, 10-foot UI.
- **Weaknesses:** Heavy, 10-foot UI awkward on phones, add-on ecosystem reputational baggage, DV Profile 7 FEL "very hard to achieve" on Android, slow release cadence; not a store-friendly consumer app (iOS build requires sideloading).

### 1.10 Just (Video) Player (moneytoo) - Android, Android TV
- **Price:** Free, open source (Media3/ExoPlayer + FFmpeg audio extension), no ads/tracking/excessive permissions; distributed on Play, F-Droid, Galaxy Store, AppGallery, Amazon. Play install tier ~1M+ **[unverified]**.
- **Strengths:** HDR10+ and **Dolby Vision on compatible hardware; plays DV Profile 7 as HDR HEVC**; a Jellyfin issue notes DV triggers correctly across profiles in Just Player where Jellyfin's own ExoPlayer fell back to HDR10; **auto frame-rate matching on Android TV**, tunneled playback, audio focus/media session, Bluetooth A/V sync, touch lock, volume boost, PiP, gestures, post-playback actions, third-party EQ hook, external subtitle auto-load with chosen root folder.
- **Weaknesses (README):** no AVI/WMV/Theora (upstream ExoPlayer), most devices cannot decode 10-bit AVC, audio-only playback unsupported, no URL entry field, network storage only via Android document providers (not on Android TV), **limited SSA/ASS styling**, Android 16 orientation quirk, no library.

### 1.11 Next Player (anilbeesetti) - Android, Android TV
- **Price:** Free, GPL-3, no ads; Kotlin + Jetpack Compose + Media3; ~4.6K GitHub stars; F-Droid 0.14.1 (Nov 2025); README: "still in development and is expected to have bugs".
- **Strengths:** Material 3 UI, software H.264/HEVC decoders, FFmpeg audio (AC-3, E-AC-3, DTS, DTS-HD, TrueHD, etc.), subtitle track selection/delay, gestures, speed, zoom, PiP, background playback, tree/folder/file views with SAF, **URL and network storage (SMB, FTP, SFTP, WebDAV)**, DASH/HLS/RTSP, Android TV.
- **Weaknesses:** limited ASS styling, no external audio yet, **no online subtitle download yet** (planned), beta-quality.

### 1.12 Nova Video Player (fork of Archos Video) - Android, Android TV, Amazon
- **Price:** Free, Apache-2.0, 4.7K stars; Play/Amazon/F-Droid/IzzyOnDroid; v6.4.3 (May 2025).
- **Strengths:** FFmpeg/dav1d engine; **TMDB scraping with posters/backdrops and Trakt scrobbling**; FTP/SFTP/WebDAV/SMB/UPnP; integrated subtitle download; leanback Android TV UI; HW accel on most devices.
- **Weaknesses:** small volunteer project; users must bring their own TMDB/Trakt API keys when building; dated phone UI; sparse documentation.

### 1.13 Outplayer - iOS, iPadOS, visionOS
- **Price:** Free, no ads, no playback restrictions; **Outplayer Advanced $7.99** one-time. **4.6/5 from 507 ratings**; iOS 17+; 41 MB; built on **mpv**.
- **Strengths:** 4K HDR with instant seeking, 10-bit HEVC HW decode, spatial audio with head tracking, dual-language subtitles with secondary delay/position, PiP, Files-app integration (SMB and external drives through Files), chapters, playlists, shuffle, pinch zoom, screenshot gesture, Wi-Fi transfer, auto-rotate, volume boost.
- **Weaknesses:** "only major deficiency is inability to cast or AirPlay", no library folder choice, no batch rename, restore-purchase glitch in v2025.16; no library/metadata.

### 1.14 PlayerXtreme - iOS (Android exists)
- **Price:** Free with in-app purchases (functionality unlocked piecemeal); aggregator shows 4.7 **[unverified]**.
- **Strengths:** poster library UI and Finder-like browser, SMB/UPnP/Wi-Fi transfer, broad codec claims.
- **Weaknesses:** 2012 review already criticized IAP nagging, black-screen streaming, slow downloads; little recent coverage, suggesting stagnation.

### 1.15 Elmedia Player (Eltima) - macOS
- **Price:** Free; **PRO from $19.95** (Mac App Store version differs from direct version); v8.24 (Dec 2025); macOS 10.13+.
- **Strengths:** AVI/MKV/FLV/WMV/SWF etc.; **AirPlay, DLNA and Google Cast streaming (Full HD/4K)**; subtitles SRT/ASS/SSA/SMIL with delay, styling, **OpenSubtitles.com search with auto-search**, burning; 10-band EQ, speed, audio delay, AC3/DTS output and channel selection; playlists (M3U); brightness/saturation/contrast/gamma; deinterlacing; screenshot automation; A-B loop; PiP; timeline preview; Touch Bar.
- **Weaknesses:** no HDR mention, no encrypted Blu-ray, limited DVD, macOS only, some features MAS-only vs direct-only confusion.

### 1.16 Movist Pro - macOS
- **Price:** paid (direct and Mac App Store; included in Setapp $9.99/mo).
- **Strengths:** FFmpeg or QuickTime decoder choice, HEVC HW decoding, 10-bit, HDR tone mapping on SDR monitors (Setapp reviewers say it handles Dolby Vision HDR when VLC does not), multi-language simultaneous subtitles with per-track style, letterbox subtitle placement, 3D subtitles, **subtitle text-to-speech**, AC3/DTS passthrough over USB, EQ, per-device channel/delay, Pro: SMB/SFTP/FTP/WebDAV streaming, Safari extension, playlists.
- **Weaknesses:** "colors a bit dull vs VLC at defaults", many options need configuring, macOS only.

### 1.17 Windows Media Player (new, Windows 11) and Films & TV
- **Price:** Free, bundled. **HEVC requires the $0.99 "HEVC Video Extensions"**; Windows 11 24H2 **removed built-in AC-3 (Dolby Digital)**. Mid-2026 reviews: new app uses **377 MB vs 103 MB** for legacy WMP, launches slower, lacks online subtitle search and metadata fetching; June 2026 Insider build improved captions and codec error messages. Microsoft says focus is startup speed, memory, more formats. Films & TV (Movies & TV) is the older UWP player with the same codec limitations (basic MKV, no ASS).
- **Takeaway:** Stock Windows players lose on codecs (HEVC paywall, AC-3 removal), weight and features; this is why MPC/PotPlayer/VLC persist.

### 1.18 Media Player Classic HC (clsid2 fork) / MPC-BE - Windows
- **Price:** Free, GPL. MPC-HC fork last updated Oct 2025; MPC-BE 1.8.3 (Feb 2025).
- **Strengths:** minimal resources, fast start, "no unnecessary bloat"; LAV Filters; madVR/MPC Video Renderer with HDR; broad streaming (HTTP/HLS/DASH/RTSP/RTMP); YouTube support in BE; AV1/HEVC.
- **Weaknesses:** Windows only, 2000s-era UI, confusion over which fork is maintained, no library.

### 1.19 Stock players - what they lack
| Stock player | Known gaps |
|---|---|
| **Android Google Photos** | Primarily a gallery; errors on WMV/MOV/WebM/Theora and other formats; no external subtitles, no audio-track switching, no network sources, no speed/gesture controls, cloud-upload nag. |
| **Samsung Video Player / Gallery** | Community likes 60 fps smoothness; but Samsung players (TV and mobile) lack image subtitles (PGS/VobSub) and SSA/ASS, limited embedded MKV subtitle handling, no network browsing; Samsung-only. |
| **iOS Photos / Apple TV app / Files** | AVFoundation only: MP4/M4V/MOV; **no MKV**, no AVI/WMV; hev1-tagged HEVC fails (hvc1 only), 4:2:2 10-bit fails; no external subtitles (.srt) or ASS; no SMB browsing in player; Apple TV app is a storefront, not a local file player. |
| **macOS QuickTime** | Same AVFoundation limits: no MKV, AV1 only on Apple silicon with HW decoder **[unverified]**, no ASS/PGS, no network protocols, no audio passthrough control. |
| **Windows Media Player (new)** | HEVC paid, AC-3 removed in 24H2, heavy, no subtitle search/metadata. |

---

## 2. Feature matrix

Legend: Y = yes, P = partial/paid/platform-dependent, N = no/not documented, ? = not confirmed in this research, n/a = not applicable. Players: VLC, MX, Infuse (Inf), nPlayer (nP), KMPlayer (KMP), PotPlayer (Pot), mpv/IINA/mpv-android (mpv), Plex (Plx), Kodi (Kdi), Just Player (JP), Next Player (NP), Nova (Nva), Outplayer (Out), Elmedia (Elm), Movist Pro (Mov), MPC-HC/BE (MPC), new WMP (WMP).

### 2.1 Decoding, codecs, HDR
| Feature | VLC | MX | Inf | nP | KMP | Pot | mpv | Plx | Kdi | JP | NP | Nva | Out | Elm | Mov | MPC | WMP |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| H.264/HEVC | Y | Y | Y | Y | Y | Y | Y | Y | Y | Y | Y | Y | Y | Y | Y | Y | P (HEVC paid) |
| AV1 | Y | ? | Y | P | ? | Y | Y | Y | Y | Y (HW) | Y (HW) | Y (dav1d) | ? | ? | ? | Y | Y (ext.) |
| VVC/H.266 | N | N | **Y** | N | N | ? | P (FFmpeg) | N | P (FFmpeg 8) | N | N | N | N | N | N | ? | N |
| 10-bit | Y | Y | Y | Y | Y | Y | Y | Y | Y | P (HEVC yes, AVC no) | P | Y | Y | ? | Y | Y | P |
| HDR10/HLG | Y | ? | Y | ? | ? | Y | Y | Y | Y | Y | Y (HW) | ? | Y | N | Y (tone-map) | Y | Y |
| HDR10+ | ? | ? | Y | ? | ? | ? | P | Y | ? | Y | ? | ? | ? | N | ? | ? | ? |
| Dolby Vision P5/P8 | N | ? | Y (Pro) | ? | ? | ? | N | Y | P (Android conv.) | Y | P | ? | ? | N | P | N | N |
| Dolby Vision P7 | N | N | **N** | N | N | N | N | P | P (no FEL) | P (as HDR HEVC) | N | N | N | N | N | N | N |
| HW acceleration | Y | Y (hybrid) | Y | Y | Y | Y (DXVA/CUDA/QS) | Y | Y | Y | Y | Y | Y | Y | Y | Y | Y | Y |
| SDR->HDR / AI upscale | Y (TrueHDR, NVIDIA) | N | Y (AI upscale) | N | N | N | Y (shaders) | N | N | N | N | N | N | N | N | N | N |
| 3D / 360 / VR | P | N | N (visionOS no 3D) | N | Y (desktop) | Y | P | N | Y | N | N | N | N | N | Y (3D subs) | Y | N |

### 2.2 Audio
| Feature | VLC | MX | Inf | nP | KMP | Pot | mpv | Plx | Kdi | JP | NP | Nva | Out | Elm | Mov | MPC |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| Dolby AC3/E-AC3, DTS, TrueHD decode | Y | Y | Y | Y (licensed) | Y | Y | Y | Y | Y | Y | Y | Y | Y | Y | Y | Y |
| Passthrough/bitstream | Y | ? | Y (Atmos E-AC3) | Y | ? | Y | Y | Y | Y | P (tunneled) | ? | ? | N | Y (AC3/DTS) | Y (USB) | Y |
| Multichannel downmix/select | Y | Y | Y | Y | Y | Y | Y | Y | Y | Y | Y | Y | Y (spatial) | Y | Y | Y |
| Equalizer | Y (new 2026) | Y | N | N | Y | Y | Y | N | Y | P (3rd-party) | N | ? | N | Y (10-band) | Y | Y |
| Audio delay | Y | Y | Y | Y | Y | Y | Y | N | Y | N | N | Y | N | Y | Y | Y |
| Volume boost | Y | Y | N | Y | Y | Y | Y | N | Y | Y | Y | ? | Y | N | ? | Y |
| Spatial audio / head tracking | N | N | N | N | N | N | N | N | N | N | N | N | **Y** | N | N | N |
| ReplayGain / audio-only library | Y | Y | N | N | Y | Y | P (IINA) | Y | Y | N | N | N | N | Y | N | N |

### 2.3 Subtitles
| Feature | VLC | MX | Inf | nP | KMP | Pot | mpv | Plx | Kdi | JP | NP | Nva | Out | Elm | Mov | MPC |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| SRT/VTT | Y | Y | Y | Y | Y | Y | Y | Y | Y | Y | Y | Y | Y | Y | Y | Y |
| Full ASS/SSA styling (libass) | Y | P | Y | Y | Y | Y | **Y** | P | Y | P (limited) | P (limited) | ? | Y (mpv) | P | ? | Y |
| PGS/VobSub (image) | Y | Y | Y | Y (IDX/SUB) | Y (VobSub) | Y | Y | Y | Y (HDR PGS in v22) | P (DVB only) | P (DVB only) | ? | Y | N | ? | Y |
| Online download (OpenSubtitles) | Y (ext.) | N (Pro strips online) | **Y** (one tap) | N | Y | Y | Y (IINA plugin) | Y | Y | N | N (planned) | Y | N | **Y** (auto) | N | Y |
| Manual sync/delay | Y | Y | Y | Y | Y | Y | Y | Y | Y | Y | Y | Y | Y | Y | Y | Y |
| Auto-sync (audio-based) | N | N | N | N | N | N | N | N | N | N | N | N | N | N | N | N |
| OCR of image subs | N | N | N | N | N | N | N | N | N | N | N | N | N | N | N | N |
| Dual/secondary subtitles | N | Y | N | Y | N | Y | Y | N | N | N | N | N | **Y** | N | **Y** | Y |
| Text-to-speech subtitles | N | N | N | N | N | N | N | N | N | N | N | N | N | N | **Y** | N |

### 2.4 Playback controls
| Feature | VLC | MX | Inf | nP | KMP | Pot | mpv | Plx | Kdi | JP | NP | Nva | Out | Elm | Mov | MPC |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| Swipe gestures (seek/vol/bright) | Y | Y | Y | Y | ? | n/a | Y | Y | n/a | Y | Y | Y | Y | n/a | n/a | n/a |
| Pinch zoom / crop | Y | Y | Y | Y | Y | Y | Y | Y | Y | Y | Y | ? | Y | Y | Y | Y |
| Speed control | Y | Y | Y | Y (0.5-4x) | Y (0.25-4x) | Y | Y | Y | Y | Y | Y | Y | Y | Y | Y | Y |
| Frame step | Y | N | N | N | Y | Y | Y | N | Y | N | N | N | N | Y | Y | Y |
| A-B loop / section repeat | Y | Y | N | Y | Y | Y | Y | N | N | N | N | N | N | Y | N | Y |
| Chapters | Y | N | Y | Y | ? | Y | Y | Y | Y | N | N | ? | Y | ? | ? | Y |
| Bookmarks | Y | N | N | Y | Y | Y | P (scripts) | N | Y | N | N | N | N | N | N | Y |
| Resume / continue watching | Y | Y | Y (synced) | Y | Y | Y | Y | Y | Y | Y | Y | Y | Y | Y | Y | Y |
| Touch lock | Y | Y | N | Y | Y | n/a | N | N | n/a | Y | ? | ? | ? | n/a | n/a | n/a |
| Auto frame-rate match (TV) | N | N | Y (tvOS) | N | N | N | N | Y | Y | **Y** | N | Y | N | N | N | N |
| Skip intro/credits | N | N | **Y** | N | N | N | P (plugin) | Y | N | N | N | N | N | N | N | N |
| Parental control | Y (3.6) | Y (kids lock) | Y | N | N | N | N | Y | Y | N | N | N | N | N | N | N |

### 2.5 Network sources, casting, library
| Feature | VLC | MX | Inf | nP | KMP | Pot | mpv | Plx | Kdi | JP | NP | Nva | Out | Elm | Mov | MPC |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| SMB/CIFS | Y | Y | Y | Y | Y | N | N | n/a | Y | P (via Files/SAF) | Y | Y | P (Files app) | N | Y (Pro) | N |
| NFS | Y | N | Y | P | Y | N | N | n/a | Y | N | N | N | N | N | N | N |
| FTP/SFTP | Y | N | Y | Y | Y | P (FTP) | P (FTP) | n/a | Y | N | Y | Y | N | N | Y | N |
| WebDAV | N (desktop P) | N | Y | Y | Y | N | N | n/a | Y | N | Y | Y | N | N | Y | N |
| DLNA/UPnP browse | Y | N | Y | Y | Y | Y | N | n/a | Y | N | N | Y | N | N | N | N |
| Plex/Jellyfin/Emby | N | N | **Y** (all 3) | N | N | N | N | Plex | Add-ons | N | N | N | N | N | N | N |
| Cloud drives | Y (iOS) | N | Y (Pro, 12+) | Y (5) | Y (2) | N | N | N | P | N | N | N | N | N | N | N |
| HTTP/HLS/DASH/RTSP | Y | Y | Y | Y | Y | Y | Y | n/a | Y | Y | Y | Y | ? | Y (HLS) | ? | Y |
| Torrent streaming | N | N | N | N | N | N | N | N | Add-on | N | N | N | N | N | N | N |
| Chromecast | Y | Y | Y (Pro) | P | ? | N | N | Y | N | N | N | N | **N** | Y | N | N |
| AirPlay | Y | n/a | Y (Pro) | Y | ? | n/a | Y (mac) | Y | N | n/a | n/a | n/a | **N** | Y | Y | n/a |
| DLNA renderer out | Y | N | N | Y | N | Y | N | Y | Y | N | N | N | N | Y | N | N |
| PiP | Y | Y | Y | Y | Y | Y | Y | Y | N | Y | Y | Y | Y | Y | Y | Y |
| Background / audio-only | Y | Y | N | Y | Y | Y | Y | Y | Y | N | Y | ? | ? | Y | ? | Y |
| TMDB/TVDB scraping, posters | N | N | **Y** | N | N | N | N | **Y** | **Y** | N | N | **Y** | N | N | N | N |
| Watched status / Trakt | N | P | Y | N | N | N | N | Y | Y | Y | N | Y | N | N | N | N |
| Playlists | Y | Y | Y | Y | Y | Y | Y | Y | Y | N | N | ? | Y | Y | Y | Y |
| Private/secure folder | N | Y | N | N | N | N | N | N | N | N | N | N | N | N | N | N |
| Remote access / web remote | **Y** (3.6) | N | N | N | N | N | P (IPC) | Y | Y | N | N | N | N | Y (remote) | N | Y (web UI) |

### 2.6 Rendering, files, misc
| Feature | VLC | MX | Inf | nP | KMP | Pot | mpv | Plx | Kdi | JP | NP | Nva | Out | Elm | Mov | MPC |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| Deinterlace | Y | Y | Y | ? | Y | Y | Y | ? | Y | N | N | ? | N | Y | ? | Y |
| Sharpen/colour adjust | Y | N | N | N | Y | Y | Y | N | Y | N | N | N | N | Y | Y | Y |
| Shader upscaling (Anime4K/FSR) | N | N | P (AI upscale) | N | N | P (madVR NGU) | **Y** | N | N | N | N | N | P (mpv core, no UI) | N | N | P (madVR) |
| Frame interpolation | N | N | N | N | N | Y (3rd party SVP) | Y | N | N | N | N | N | N | N | N | Y (SVP) |
| Screenshot | Y | N | N | Y | Y | Y | Y | N | N | N | N | N | Y (gesture) | Y | Y | Y |
| File manager (rename/delete/move) | Y | Y | N | Y (download mgr) | Y | N | N | N | Y | P (delete after play) | P | Y | P | N | N | N |
| External display / second screen | Y | Y | Y | Y | ? | Y | Y | Y | Y | ? | ? | ? | ? | Y (monitor pick) | Y | Y |
| Keyboard shortcuts | Y | Y | Y | ? | Y | Y (fully custom) | Y | Y | Y | Y (TV) | ? | Y (TV) | Y (iPad) | Y | Y | Y (fully custom) |
| Accessibility (VoiceOver/TalkBack, captions prefs) | P | P | Y | Y (AppleVis listed) | ? | P | P | Y | P | Y (system caption prefs) | ? | ? | Y | P | Y (TTS subs) | P |
| Android TV / tvOS / car mode | Y (TV) | Y (TV) | Y (tvOS) | N | ? | n/a | P (TV via APK) | Y (TV, Android Auto) | Y (TV) | Y (TV) | Y (TV) | Y (TV leanback) | N | n/a | n/a | n/a |
| Plugin/script system | Y (Lua ext.) | N | N | N | N | N | **Y** (Lua/JS; IINA JS plugins) | N | Y (add-ons) | N | N | N | N | N | N | N |
| Ads | N | **Y** | N | Lite only | desktop hist. | hist. corner ads | N | Y (content promos) | N | N | N | N | N | N | N | N |

---

## 3. What differentiates the top-rated players; why users pay or switch

**Highest-rated in-store:** Infuse (4.7, 28K), nPlayer Plus (~4.7), Outplayer (4.6), KMPlayer (4.1-4.3), MX Player (4.0-4.2 on enormous volume), VLC iOS (3.7). Observations:

1. **"Plays everything, no transcoding, looks like a streaming service."** Infuse's rating and willingness-to-pay come from combining exhaustive codec/protocol coverage with TMDB artwork, watched-state sync across devices (Plex/Jellyfin/Emby/Trakt), skip-intro and parental controls. Forum posters pay $17/yr or $100 lifetime mainly for Dolby Vision/Atmos, cloud streaming and casting (the Pro gates).
2. **Licensed audio and passthrough** (nPlayer Plus, Infuse Pro, Plex) is a stated purchase reason for home-theatre users: DTS-HD/TrueHD decoding and HDMI bitstreaming.
3. **Dolby Vision correctness** is the most-discussed technical differentiator in 2025-2026 forums (Firecore DV P7/P8 megathread with ~2,000 posts; Kodi, Jellyfin and XDA threads). Just Player earned a loyal niche purely by "DV triggers correctly where Jellyfin/ExoPlayer falls back to HDR10". Users convert, retag or switch apps to get DV to light up.
4. **Zero ads and zero accounts.** The single most frequent reason users cite for leaving MX Player and Plex is ads/forced sign-in; the most frequent reason for choosing Just Player, Next Player, Nova, VLC, Outplayer is "no ads, no tracking, no playback restrictions".
5. **Rendering quality and shaders** differentiate mpv/IINA/PotPlayer+madVR on desktop (tone-mapping, debanding, Anime4K); on mobile there is still no polished store app with these - only mpv-android forks with manual config.
6. **Ergonomics:** reviewers repeatedly praise Outplayer and MX gestures and criticize VLC's; Outplayer's only knocked feature is missing cast/AirPlay. Small, fast, native UIs (Compose/SwiftUI) are praised; "heavy" apps (VLC Android, new WMP at 377 MB RAM) are penalized.
7. **Subtitle convenience:** one-tap OpenSubtitles download (Infuse, Elmedia, KMPlayer) and dual subtitles (Outplayer, Movist, mpv) are cited as switch reasons; Next Player's top planned feature is online subtitle download.
8. **Network breadth** (SMB + NFS + WebDAV + SFTP + Plex/Jellyfin + cloud) is expected from any paid player; Just Player's reliance on Android document providers (and absence on Android TV) is called out as a limitation.

## 4. Table stakes vs delighters for 2026

**Table stakes (missing any of these yields 1-star reviews):**
- Hardware HEVC/H.264/VP9/AV1 decode with software fallback; 10-bit; HDR10/HLG displayed correctly (no washed-out colours); HDR10+ and Dolby Vision P5/P8 on capable hardware.
- All common containers (MKV, MP4, MOV, TS/M2TS, AVI, WMV, WebM, FLV) and audio (AAC, AC3/E-AC3, DTS incl. HD, TrueHD, FLAC, Opus) - at least decode-to-PCM; downmix to stereo/headphones that does not lose dialogue.
- Subtitles: SRT/VTT/ASS/SSA with libass-grade styling, PGS/VobSub/DVB, external file auto-load, encoding detection, delay, size/position/colour, multiple tracks; online download (OpenSubtitles) inside the player.
- Gesture controls (seek, volume, brightness, pinch-zoom, double-tap seek), speed 0.25-4x with pitch correction, resume position, touch lock, orientation handling, PiP, background/audio-only playback, media-session/Bluetooth controls, headphone-unplug pause.
- Local file browser with folder tree, sort, search, thumbnails, recent/continue watching; file operations (rename, delete, move, share); SAF/scoped-storage, SD card and USB-OTG support; Files-app provider on iOS.
- Network: SMB (v2/v3), NFS, FTP/SFTP, WebDAV, DLNA/UPnP, HTTP/HLS/DASH/RTSP URLs; Chromecast and AirPlay casting; Plex/Jellyfin/Emby login.
- No ads, no account required, no telemetry, small APK/IPA, fast cold start, low battery (HW decode paths, no wake-locks after playback), stability on 4K/80 Mbps and multi-GB files.
- Platform conventions: Android TV leanback + D-pad, tvOS focus engine, macOS menu bar/keyboard shortcuts, Windows drag-drop/file associations, accessibility labels, system caption preferences.

**Delighters (cited as reasons to pay or switch):**
- Dolby Vision Profile 7 (FEL/MEL) handling or graceful conversion; VVC/H.266 decode; AV1 film-grain synthesis.
- Audio passthrough/bitstream (Atmos/TrueHD/DTS-HD) and per-device audio settings; spatial audio with head tracking; volume boost/normalization; EQ with presets.
- Library mode with TMDB/TVDB metadata, posters, cast, trailers, collections, watched sync (Trakt), multi-device progress sync, skip intro/recap/credits, parental PIN, private/hidden folders.
- Auto frame-rate and resolution matching on TV; HDR-to-SDR tone-mapping quality; GPU shaders (Anime4K, FSR/NIS-style upscalers, debanding, deinterlacing) exposed with a simple toggle; frame interpolation.
- Dual subtitles, auto subtitle sync (audio-based, e.g. ffsubsync/alass approach), OCR of PGS/VobSub to text, subtitle TTS, Whisper-based auto-captions (no player in this set offers OCR or auto-sync - a clear opening).
- Remote access/web remote (VLC 3.6), keyboard/remote fully remappable, second-screen/AirPlay with subtitles preserved, screenshots and GIF/clip export, A-B loop, chapters and bookmarks, frame step.
- Casting and AirPlay included free (Outplayer's single most-requested feature; Infuse gates it behind Pro).
- Cloud drives (Google Drive, OneDrive, Dropbox, pCloud, MEGA) and torrent/magnet streaming (currently add-on-only in Kodi; absent from stores because of policy risk - treat carefully for app-store compliance).
- Plugin/script system (mpv/IINA) for power users; portable config export (VLC settings backup).

## 5. Common failure modes (why media players get bad reviews)

1. **Ads and bloat** - MX Player (aggressive interstitials during navigation and playback), Plex (promos for its own streaming content), KMPlayer/PotPlayer (bundled installers, corner ads). The word "bloat" appears as a purchase driver for MX Player Pro ("only core functionalities").
2. **Monetization surprises** - paywalling previously free features (Plex remote streaming Apr 2025, mobile unlock confusion), subscription price hikes (Infuse EUR 9.99 to 14.99), lifetime purchasers reporting lost access, fragmented SKUs (nPlayer Lite/paid/Plus; PlayerXtreme piecemeal IAP), restore-purchase glitches (Outplayer).
3. **Forced accounts/sign-in** for local playback (Plex) and privacy concerns (MX Player data collection).
4. **Codec gaps and paid codecs** - no MKV (Apple stock), HEVC paid extension and AC-3 removal (Windows 11), DTS/AC3 silent unless an audio setting is changed (Just Player), 10-bit AVC unsupported on most devices, DV showing as HDR10 or washed-out, hev1 vs hvc1 tagging failures.
5. **Crashes and freezes** - on large files/4K, during SMB scans, document-picker crashes (mpv-android), freezing during subtitle sync (VLC), iOS/tvOS crashes (Plex), KMPlayer top complaint "frequent crashes and freezing".
6. **Battery drain and heaviness** - VLC on iPhone "wastes a lot of battery" (software decoding), VLC Android "too heavy", new WMP using 3.6x the RAM of the legacy app and slower launch.
7. **Subtitle problems** - unclear rendering, no sync, limited ASS styling (ExoPlayer-based apps), subtitles forcing transcodes (Plex), language resetting every episode (Stremio), image subs unsupported (Samsung).
8. **Audio problems** - Bluetooth first-seconds cut-off (VLC iOS), A/V desync over Bluetooth (Just Player note), audio drift (Stremio), no passthrough.
9. **Poor file/network browsing** - Android scoped-storage confusion (shaders not loadable from Play builds; root-folder prompts), no URL entry field, network storage only via document providers and unavailable on Android TV, no folder choice for library (Outplayer).
10. **Gesture and UI ergonomics** - over-sensitive sliders (VLC iPad), hard-to-adjust volume/brightness, dated UIs (nPlayer, MPC, Kodi on phones), hidden settings (VLC desktop, PotPlayer complexity).
11. **Missing casting/AirPlay** - the single big knock on Outplayer; Infuse gating it behind Pro.
12. **Stagnation and neglected platforms** - PlayerXtreme, nPlayer Android, MPC-HC fork confusion, VLC 4 delay, Kodi point releases "bugfixes, not features", Infuse prioritizing Vision Pro over long-requested features.
13. **Security** - malicious subtitle files (a 2025 campaign claim affecting VLC/Kodi was reported but unverified); a new player must sandbox subtitle parsing and network share handling.

## 6. Implications for the new app (brief)

- Ship a single free tier with no ads, no account, no telemetry; if monetizing, use a one-time "supporter" purchase that gates nothing essential (Outplayer model) rather than subscriptions (Infuse fatigue) or ads (MX decline).
- Build on mpv/libplacebo (desktop and iOS, as Outplayer does) and Media3 with FFmpeg extension plus a libass renderer on Android, so that ASS styling, shader upscaling, HDR tone-mapping and DV P8 are solved once; add explicit DV P7 handling (play as HDR10/HEVC like Just Player, or convert like Kodi).
- Include out of the box: SMB/NFS/WebDAV/SFTP/DLNA, Plex/Jellyfin/Emby, cloud drives, Chromecast and AirPlay (free), OpenSubtitles one-tap, dual subtitles, auto-sync and OCR (currently unoffered), TMDB library mode that can be turned off, Android TV/tvOS/macOS/Windows native conventions, auto frame-rate matching, audio passthrough, remote access/web remote.
- Keep cold start, memory and APK size as measured KPIs; reviewers now benchmark RAM (WMP 377 MB vs 103 MB) and battery.

---

## Sources

### VLC
- VideoLAN news: VLC for Android 3.6.0 (Jan 2025) - https://www-test.videolan.org/news/2025-01-13-vlc-for-android-3-6-0/
- VideoLAN news index (3.7.0, 3.0.21 TrueHDR) - https://images.videolan.org/news.html
- VLC Android 3.6 beta changelog (F-Droid build) - https://www.apkmirror.com/?p=7437089
- VLC iOS App Store listing (3.7, 6K ratings) - https://apps.apple.com/us/app/vlc-media-player/id650377962
- Kimola VLC for Android review analysis - https://kimola.com/reports/vlc-for-android-feedback-analysis-insights-solutions-google-play-tr-147995
- unitQ VLC for Android scorecard - https://www.unitQ.com/unitq-scorecards/vlcforandroid/
- Marlvel VLC iOS report (May 2026) - https://marlvel.ai/apps/org-videolan-vlc-ios
- justuseapp VLC reviews - https://justuseapp.com/en/app/650377962/vlc-for-mobile/reviews
- TechRadar best free video players 2025 - https://www.techradar.com/best/free-video-player?artc_pg=2

### MX Player
- Marlvel MX Player report (May 2026) - https://marlvel.ai/apps/mx-player-video-player
- DeleteMe: is MX Player safe - https://joindeleteme.com/is-site-safe/is-mx-player-safe/
- FlashGet MX Player features/ads - https://parental-control.flashget.com/mx-player-features
- MX Player Pro listing/changelog - https://www.apkmirror.com/apk/mx-media-entertainment-pte-ltd/mx-player-pro/

### Infuse
- Infuse official feature page and pricing - https://firecore.com/infuse
- Infuse App Store listing (4.7, 28K) - https://apps.apple.com/us/app/infuse-video-player/id1136220934
- Infuse 8 announcement - https://firecore.com/blog/infuse-8-coming-this-fall
- heise Infuse 8 review - https://heise.de/-9985923
- Firecore forum: Infuse 8 thread (feature complaints) - https://community.firecore.com/t/infuse-8-coming-this-fall-2024/49497
- Firecore forum: pricing increase - https://community.firecore.com/t/infuse-pricing-is-going-up/46726
- Firecore forum: DV Profile 7 and 8 support megathread - https://community.firecore.com/t/dolby-vision-profile-7-8-support-ts-mkv-files/19713/316
- Firecore forum: Same file Plex plays DV, Infuse doesn't - https://community.firecore.com/t/same-file-plex-plays-dv-infuse-doesnt/38977.md
- Firecore forum: Understanding DV possibilities - https://community.firecore.com/t/understanding-dolby-vision-possibilities-with-infuse/36149/5
- Firecore forum: H.266 VVC support - https://community.firecore.com/t/h-266-vvc-support/46651.md

### nPlayer, Outplayer, PlayerXtreme
- nPlayer official features - https://nplayer.com/
- nPlayer Plus listing data (price, rating) - https://apps.appfollow.io/ios/nplayer-plus/539397400?country=us
- AppleVis nPlayer description - https://applevis.com/comment/22005
- Outplayer App Store listing (4.6, $7.99 Advanced) - https://apps.apple.com/us/app/outplayer/id1449923287
- Outplayer reviews (casting complaint) - https://apps.appfollow.io/ios/outplayer/1449923287?country=mx
- PlayerXtreme listing - https://appfollow.io/ios/playerxtreme-media-player-pro/440488550?country=us
- iPhone Life PlayerXtreme review (2012) - https://www.iphonelife.com/blog/87/review-multimedia-player-playerxtreme
- MacMyths / iGeeksBlog best iPhone/iPad video players - https://macmyths.com/best-iphone-and-ipad-video-player-apps/ ; https://www.igeeksblog.com/best-ipad-apps-that-let-you-play-mkv-hd-videos-on-your-ipad/
- MacRumors forum: best iPad video player - https://spy.macrumors.com/threads/best-ipad-video-player.2203503

### KMPlayer, PotPlayer, MPC
- KMPlayer mobile official page - https://kmplayer.com/mobile
- KMPlayer App Store listing - https://apps.apple.com/KR/app/id835776444
- Marlvel KMPlayer report - https://marlvel.ai/api/llm/apps/entertainment/kmplayer
- SnapFiles KMPlayer adware review - https://www.snapfiles.com/users/631025/myreviews.html
- AlternativeTo KMPlayer comments - https://www.alternativeto.net/software/the-kmplayer/about/
- Wikipedia PotPlayer (ads/bundling history) - https://www.wikipedia.com/wiki/PotPlayer
- VideoHelp PotPlayer reviews (2025) - https://www.videohelp.com/software/PotPlayer/reviews
- SourceForge PotPlayer mirror (features) - https://sourceforge.net/app/potplayer/
- Elgato: PotPlayer + madVR HDR setup - https://help.elgato.com/hc/zh-cn/articles/360034170411
- VideoHelp forum: PotPlayer madVR HDR tone mapping - https://forum.videohelp.com/showthread.php?p=2662127
- Gumlet best video player for PC - https://www.gumlet.com/learn/best-video-player-for-pc/
- VideoHelp MPC-BE (1.8.3 notes) - https://videohelp.com/tools/MPC-BE
- VideoHelp MPC-HC reviews/update date - https://videohelp.com/software/Media-Player-Classic-Home-Cinema/reviews
- TechSpot MPC FAQ - https://www.techspot.com/news/92136-media-player-classic-like-old-windows-media-player.html

### mpv, IINA, mpv-android, Anime4K
- mpv-android GitHub README - https://github.com/mpv-android/mpv-android
- mpv-android 2025-12-27 release notes - https://newreleases.io/project/github/mpv-android/mpv-android/release/2025-12-27
- IINA 1.4.0 release notes - https://iina.io/release-note/1.4.0.html
- heise: IINA plugin system - https://heise.de/-10350790
- Anime4K GLSL instructions - https://github.com/bloc97/Anime4K/blob/v2.1a/GLSL_Instructions.md
- mpv-android-anime4k fork - https://gittrend.io/repo/azxcvn/mpv-android-anime4k
- SVP forum: shaders on Android / scoped storage - https://www.svp-team.com/forum/viewtopic.php?id=6624
- Aiarty Anime4K guide - https://www.aiarty.com/ai-video-enhancer/anime4k.htm

### Plex, Kodi
- Plex forum: local streaming and subscription - https://forums.plex.tv/t/plex-streaming-to-ios-device-locally/916798.md
- Plex forum: quality has gone down - https://forums.plex.tv/t/quality-has-really-really-gone-down/808186
- Plex forum: lifetime Pass performance issues - https://forums.plex.tv/t/lifetime-plex-pass-user-ongoing-performance-and-reliability-issues/940208
- Trustpilot Plex reviews - https://www.trustpilot.com/review/plex.tv?page=5
- Jellyfin issue: Plex direct play DV P7 behaviour - https://github.com/jellyfin/jellyfin-androidtv/issues/5303
- Jellyfin issue: DV not working in ExoPlayer, Just Player works - https://github.com/jellyfin/jellyfin-android/issues/1810
- BetaNews Kodi 22 Piers RC1 - https://betanews.com/article/kodi-22-piers-rc-1-features/
- BetaNews Kodi 22 alpha 2 - https://betanews.com/2025/12/19/kodi-22-piers-alpha-2-is-out-with-new-features-and-fixes-download-it-now/
- BetaNews Kodi 21.3 - https://betanews.com/2025/12/15/kodi-21-3-omega-has-arrived-and-you-should-download-it-now/
- Kodi forum: DV Profile 7 FEL explained - https://forum.kodi.tv/showthread.php?tid=382903
- Kodi forum: Android DV MKV build - https://forum.kodi.tv/showthread.php?tid=360018&page=34

### Just Player, Next Player, Nova
- Just (Video) Player GitHub README - https://github.com/moneytoo/Player
- Just Player APKMirror listing - https://www.apkmirror.com/?p=13799370
- XDA: is Dolby Vision working (Just Player) - https://xdaforums.com/t/is-dolby-vision-working.4258579/
- Next Player GitHub - https://github.com/anilbeesetti/nextplayer
- Next Player F-Droid - https://f-droid.org/de/packages/dev.anilbeesetti.nextplayer/
- Next Player F-Droid RFP (codec notes) - https://gitlab.com/fdroid/rfp/-/issues/2480
- Nova Video Player GitHub - https://github.com/nova-video-player/aos-AVP
- Nova F-Droid listing - https://www.f-droid.org/packages/org.courville.nova/
- Nova IzzyOnDroid listing - https://apt.izzysoft.de/fdroid/index/apk/org.courville.nova?repo=main
- AlternativeTo Just Player - https://alternativeto.net/software/just-video-player/?p=2

### macOS: Elmedia, Movist Pro, QuickTime
- Elmedia official features/pricing - https://mac.eltima.com/media-player.html
- Macworld Elmedia Pro review - https://www.macworld.com/article/227298/elmedia-player-pro-review-better-stronger-faster-than-quicktime-player.html
- Eltima VLC alternatives (Elmedia pricing) - https://mac.eltima.com/vlc-media-player-review
- Movist Pro official - https://movistprime.com/
- Setapp Movist Pro reviews - https://setapp.com/apps/movist-pro/customer-reviews
- Setapp best MKV players for Mac 2025 - https://setapp.com/how-to/best-mkv-players-for-mac
- Apple discussion: hvc1 vs hev1, 10-bit 4:2:2 - https://discussions-kr-prz.apple.com/thread/255344702
- TidBITS: MKV and HEVC - https://talk.tidbits.com/t/mkv-and-hevc/24106
- Cococonvert: MKV not playing in QuickTime - https://cococonvert.com/blog/mkv-not-playing-quicktime

### Windows stock players
- Digital Citizen: WMP update trails classic app - https://www.digitalcitizen.life/windows-media-player-update-improves-stability-but-still-trails-the-classic-app/
- Digital Trends: new Media Player worse than 17-year-old version - https://www.digitaltrends.com/computing/windows-11s-new-media-player-is-somehow-worse-than-the-version-from-17-years-ago/
- PCWorld: WMP updated, old app still better - https://www.pcworld.com/article/3168210/windows-media-player-is-being-updated-but-the-old-app-is-still-better.html
- WindowsForum: higher RAM, missing AC-3, Store HEVC - https://windowsforum.com/windows-news.4/windows-11-media-player-criticized-higher-ram-use-missing-ac-3-store-hevc.427793/
- Gigazine: WMP more RAM (June 2026) - https://gigazine.net/gsc_news/en/20260622-windows-media-player-more-ram

### Stock mobile players, codecs
- Guiding Tech: Google Photos not playing video - https://www.guidingtech.com/fix-google-photos-not-playing-video/
- Softorino: play MKV on iPhone - https://cn.softorino.com/blog/how-to-play-mkv-on-iphone
- Plex forum: Samsung player limits (tracks, PGS/ASS) - https://forums.plex.tv/t/samsung-tv-app-tizen-5-and-hdr10/433541
- Samsung Community: top video player apps (Oct 2025) - https://r1.community.samsung.com/t5/others/top-video-player-apps/m-p/35260711/highlight/true
- Android Authority: Qualcomm AV1 - https://androidauthority.com/qualcomm-av1-encoding-3271556
- Faceofit: VVC native support - https://www.faceofit.com/h-266-vvc-versatile-video-coding-native/amp
- Sports Video Group: VVC smartphone timeline - https://www.sportsvideo.org/?p=323365
- Wikipedia: Comparison of video player software - https://en.wikipedia.org/wiki/Comparison_of_video_player_software

### Subtitles tooling
- ALLPlayer OpenSubtitles integration - https://www.allplayer.org/features/subtitles
- AutoSubSync (ffsubsync/alass) 2025 guide - https://blog.brightcoding.dev/2025/11/23/autosubsync-the-ultimate-python-tool-for-automatic-subtitle-synchronization-2025-guide
- Subtitle Edit 5.10 (PGS/VobSub OCR, Whisper) - https://www.neowin.net/software/subtitle-edit-510/
