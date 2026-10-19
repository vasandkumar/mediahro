# Competitive & Feature Analysis: Audio Players and Image Viewers/Galleries

**Date:** 2026-10-19
**Purpose:** Input for the design of a free, high-performance, bloat-free cross-platform media app (video + audio + images) targeting Android, iOS, macOS and Windows, shipped as a complete product (no MVP).
**Method:** Web search (standard mode) plus direct fetches of vendor/project pages. Sources dated 2025-2026 were preferred; where only older material exists this is flagged. Pricing is regional and changes often; treat figures as indicative.

**Coverage caveat:** the shared web-search budget was exhausted partway through Part B. Photomator pricing, digiKam platform details, Honeyview's successor (BandiView), Xee and Lyn therefore rely on vendor pages or pre-2025 coverage rather than fresh independent reviews. A follow-up session can close those gaps.

---

## PART A: AUDIO / MUSIC PLAYERS

### A1. Market landscape (2025-2026)

The local-file music player market is mature and fragmented by platform:

- **Android** has the richest ecosystem: paid audiophile players (Poweramp, Neutron, USB Audio Player PRO), free ad-free players (Musicolet with 20M+ downloads, AIMP), FOSS Material players (Auxio, Phonograph Plus, Retro Music/Vinyl, Oto Music) and server-first clients (Symfonium, Finamp).
- **iOS** is constrained by sandboxing and Apple Music integration. Local-file players (Doppler, Flacbox, Evermusic, foobar2000, Neutron, VOX) must import files or stream from cloud/NAS; Apple-Music clients (Marvis Pro, Cs Music) re-skin the MediaPlayer framework and cannot delete library items.
- **Windows** is dominated by free library managers (MusicBee, foobar2000, AIMP). Microsoft's Media Player app (Groove successor) is widely criticised for RAM use and sluggishness.
- **macOS** is served by Swinsian (paid, iTunes-style), VOX (freemium/subscription), foobar2000 (free), and Audirvana (audiophile reference, subscription or one-time).
- **Cross-platform players remain rare.** Only foobar2000 (Win/Mac/iOS/Android) and Neutron (Android/iOS/Windows) span three or more platforms; neither covers all four with a consistent UI. This is the primary gap the new app can fill.

### A2. Per-app profiles

| App | Platforms | Pricing | Strengths | Weaknesses (from reviews) | Scale / notes |
|---|---|---|---|---|---|
| **Poweramp** | Android | 15-day trial, then one-time unlock (historically $3.99-$7.99 regionally) | Hi-res up to 768 kHz / 32-bit float; DSD64-1024 native/DoP plus "DSD remastering"; 64-band parametric EQ; ReplayGain; crossfade/gapless; tag editor; Chromecast; Android Auto; skins; HTTP radio; tracker modules | Dense settings UI; per-device output quirks; hi-res only "where supported by device/ROM"; Android-only | Consistently the top paid Android pick in 2026 roundups |
| **Musicolet** | Android | Free, ad-free; optional Pro IAP (crossfade, Chromecast, ReplayGain) | No internet permission; multiple queues (unique); embedded + LRC lyrics with LRC creator; batch tag editing; two folder modes; dual sleep timers; Android Auto; widgets; 20M+ downloads, 4.7 rating | Crash reports during playback and tagging issues (Play-review analysis); users request a desktop version | Lightweight benchmark for "no bloat" |
| **Neutron** | Android, iOS, Windows (Store), BlackBerry | One-time purchase, ~$12.99 US on iOS (regional variance) | Own 32/64-bit engine bypassing OS audio API; USB DAC up to 32-bit / 1.536 MHz; DSD native/DoP plus PCM-to-DSD; parametric EQ 4-130 bands; crossfeed, compressor/limiter, independent pitch/tempo; 5,000+ AutoEq presets; SMB/UPnP/SFTP/FTP/WebDAV/Subsonic/Navidrome; CarPlay + Android Auto; LRC lyrics | Dated, hard-to-learn UI (3.9-4.0 stars); marketing claims largely unverified by independent reviews | Only true multi-platform audiophile player |
| **USB Audio Player PRO (UAPP)** | Android | ~$6.99-$8 one-time plus paid add-ons (MQA Core ~€3.49, ToneBoosters parametric EQ ~€1.99, MorphIt ~€3.29) | Custom USB driver, bit-perfect 32-bit / 384 kHz; DSD via DoP; MQA decoder; Tidal/Qobuz integration; Samba + UPnP | Add-on nickel-and-diming; utilitarian UI; Android-only; MQA relevance waning | Reference for bit-perfect USB on Android |
| **foobar2000** | Windows, macOS, iOS, Android (mobile v2.26) | Free | Very low CPU; gapless; ReplayGain; UPnP/SMB/FTP; skins; CUE; plugins + VST (desktop); Opus/Musepack/WavPack | Mobile lacks CarPlay, Siri, smart playlists, cloud drives; desktop layout system absent on mobile; stark UI | Desktop v2.25 (Sep 2025); mobile iOS 12+ still supported |
| **AIMP** | Windows, Android | Free | 32-bit processing; ASIO/WASAPI exclusive; smart playlists; CUE; radio; alarm; tag editor; karaoke voice remover; WavPack 32-bit float converter (5.40) | Fewer library-management features than MusicBee; Android version thinly documented | Long-running (v5.40 builds through 2025-26) |
| **MusicBee** | Windows | Free (donations) | WASAPI/ASIO; 10/15-band EQ + DSP; auto-tagging; device sync; podcasts; Last.fm; skins; Winamp plugin compatibility; 25-70 MB RAM | Windows-only; dated .NET UI; occasional "player, not manager" critique | Most-recommended free Windows library manager |
| **Symfonium** | Android | Free trial, one-time purchase (also via PayPro without Play) | Plex/Emby/Jellyfin/Kodi/Audiobookshelf/Subsonic/OpenSubsonic/Navidrome plus cloud drives and SMB/WebDAV; offline cache; Chromecast/DLNA/Sonos/Plex casting; parametric EQ + AutoEQ (APO import); smart filters; synced lyrics; Android Auto | Google Play account expected; server-centric; no desktop | Called "best music player on any platform" by Jellyfin users |
| **Auxio** | Android (F-Droid/Play) | Free, GPL-3.0 | Media3/ExoPlayer; ReplayGain; gapless; Android Auto; fully offline; ~3.7k GitHub stars | Weak album-art fetching, mis-grouping; no smart playlists; shuffle-state loss; F-Droid lag (resolved by 4.0.10, Nov 2025) | FOSS Material-3 benchmark |
| **Phonograph / Phonograph Plus / Retro Music / Vinyl** | Android | Free (Retro "Pro" IAP; Vinyl unlocks all) | Material design; Last.fm art; lyrics; Phonograph Plus 1.12.1 (Mar 2026) active | Original Phonograph archived 2023; Retro Music activity unclear in 2025-26 | Visual benchmarks, not engineering ones |
| **Oto Music** | Android | Free; Oto+ IAP (Material You theme, 10-band EQ) | Gapless; synced lyrics; ReplayGain; Chromecast; Android Auto + Assistant; gestures | Core EQ gated behind Oto+; cadence slowed (4.0.8, Feb 2025) | Popular "clean UI" pick |
| **Doppler** | iOS (Mac companion) | Free download; Doppler 3 ~$9 IAP (prior $6.99) | iTunes-style local player; FLAC; Wi-Fi/Files transfer; CarPlay; iOS 26 Liquid Glass support (v3.2, Oct 2025) | Cannot import Apple Music library; past FLAC-skip bugs (2023) | Best-liked iOS local player |
| **Marvis Pro** | iOS/iPadOS | Paid app plus one-time "advanced" IAP | Apple Music/iTunes library client; smart rules; Last.fm; 40+ icons; MacStories App of the Year 2022; v10.1.1 (Jul 2025) | Requires Music app; cannot delete items (iOS limit); no local-file playback | Reference for iOS customisation ceiling |
| **Cs Music (Cesium)** | iOS | ~$2.99 (tips optional) | Gestures; Classical mode; night mode; listening history | Little 2025 coverage; gains over stock "modest" | Niche |
| **Evermusic / Evermusic Pro** | iOS | Lifetime ~$29.99, monthly $0.99, yearly $9.99 | Dropbox/GDrive/OneDrive/Box/MEGA/Proton/WebDAV/SMB/DLNA; Pro adds Plex/Subsonic/Navidrome/Jellyfin/Emby | Glitchy cloud connections; ads in free tier; FLAC not prominently listed | Same developer as Flacbox |
| **Flacbox** | iOS/macOS | Lifetime $69.99, monthly $2.99, yearly $19.99 | Hi-res FLAC; cloud plus WebDAV/SMB/DLNA; EQ/bass; 4.6 stars, ~8.2k reviews | Steep lifetime price (users note it rose to ~£60); ads in free tier | Subscription-fatigue example |
| **VOX** | macOS, iOS | Free plus VOX Premium subscription (~$5/mo region-dependent) | FLAC/hi-res; AirPlay; radio; cloud locker | Premium wall (cloud, hi-quality radio); confusing UI; historic bug reports; Apple-only | Cautionary case for subscription lock-in |
| **Swinsian** | macOS | $34.95 (v3, Aug 2025; 40% upgrade discount); 30-day trial | Native Apple Silicon; FLAC/Opus/DSF/APE etc.; smart playlists; duplicate finder; ReplayGain; AirPlay; iTunes XML export; handles 900k-track libraries; strong VoiceOver | Mac-only; paid major upgrade | Reference for large-library performance |
| **Audirvana (Origin/Studio)** | macOS, Windows (plus remote apps) | Origin one-time; Studio ~US$69.99/yr | Exclusive/bit-perfect device access; EISA 2025-26 award; Qobuz/Tidal (Studio); optional DSP suite | "A complete pain to deal with", early bugs; subscription for Studio | Audiophile ceiling, not a mainstream model |
| **Winamp (2024-25 mobile)** | iOS, Android (plus legacy Windows) | Free | Nostalgia brand; EQ; CarPlay; cloud; Hotmix radio; no sign-in required | Crashes on large libraries (11k songs); "generic player" verdict; Fanzone upsell | Brand-driven, engineering-light |
| **Apple Music / Files (iOS)** | iOS | Stock | ALAC lossless; CarPlay; Watch | No FLAC in Music (Mac Music silently rejects FLAC imports); Files plays FLAC one track at a time with no queue/playlist; subscription can disrupt local sync | Primary iOS gap |
| **Windows Media Player (2022+) / Groove** | Windows 11 | Stock | FLAC/ALAC ripping; migrated Groove library | ~377 MB idle RAM vs ~103 MB legacy; slower file opening; paid codec packs; video-as-audio bugs (Apr 2025) | Primary Windows gap |

### A3. Audio feature matrix

Legend: Y = yes, P = partial / add-on, N = no, ? = not confirmed in sources, OS = limited by OS mixer.

| Feature | Poweramp | Musicolet | Neutron | UAPP | foobar2000 | AIMP | MusicBee | Symfonium | Auxio | Doppler | Swinsian | Stock iOS Music | Win Media Player |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| FLAC / ALAC | Y | Y | Y | Y | Y | Y | Y | Y | Y | Y | Y | ALAC only | Y |
| DSD (DSF/DFF) | Y native + DoP | N | Y native/DoP/ISO | Y DoP | P (plugin) | P | P (plugin) | N | N | N | DSF read | N | N |
| Opus | Y | Y | Y | ? | Y | Y | Y | Y | Y | ? | Y | N | ? |
| MQA | N | N | N | P (paid) | N | N | N | N | N | N | N | N | N |
| Hi-res ceiling | 768 kHz / 32f | OS | 1.536 MHz / 32 | 384 kHz / 32 | OS | OS (32-bit proc.) | WASAPI/ASIO | OS | OS | OS | Device control | OS | OS |
| Bit-perfect / USB DAC | Y (device-dep.) | N | Y | Y (own driver) | Desktop Y | ASIO / WASAPI-ex | ASIO / WASAPI | N | N | N | Y | N | N |
| Gapless | Y | Y | Y | Y | Y | Y | Y | Y | Y | Y | Y | Y | ? |
| Crossfade | Y | P (Pro) | Y | Y | Y | Y | Y | Y | ? | ? | Y | Y | N |
| ReplayGain / normalisation | Y | P (Pro) | Y | Y | Y | Y | Y | Y | Y | ? | Y (v3) | Sound Check | N |
| Parametric EQ 10+ bands | 64-band | "powerful EQ" | 4-130 bands | P (paid TB) | Y (plugin) | Y | 10 / 15 | Y + AutoEQ | N | ? | N | N | N |
| Limiter / balance / tempo / pitch | Limiter, balance | ? | Y all | ? | Plugins | Y | DSP | ? | N | N | N | N | N |
| Lyrics: embedded / LRC / synced / online | Y / Y / Y / ? | Y / Y / Y (creator) / N | Y / Y / Y / N | ? | N | ? | Plugin | Y / Y / Y / server | N | ? | N | Apple Music only | N |
| Tag editing | Y | Y batch | Y | ? | Y | Y | Y + auto-tag | N (server) | N | ? | Y | N | N |
| Folder mode | Y | Y (2 modes) | Y | Y | Y | Y | Y | Y | Y | N | N | N | N |
| Album art fetch | Y | N (offline) | ? | ? | ? | Y | Y | Server | Weak | ? | Y | Y | ? |
| Smart playlists | P | ? | ? | ? | Desktop only | Y | Y | Y (rules) | N | ? | Y | Mac only | N |
| Sleep timer | Y | Y (2 types) | Y | Y | ? | Y | ? | Y | Y | Y | ? | Via Clock | N |
| Android Auto / CarPlay | Y | Y | Y / Y | ? | N / N | ? | n/a | Y | Y | CarPlay | n/a | CarPlay | n/a |
| Wear / Watch | N | N | N | N | N | N | n/a | N | N | N | n/a | Y | n/a |
| Widgets | Y | Y | Y | ? | ? | Y | n/a | Y | Y | Y | n/a | Y | N |
| Chromecast / AirPlay | Cast | P (Pro) | Cast + UPnP | ? | UPnP | ? | UPnP | Cast/DLNA/Sonos/Plex | N | AirPlay | AirPlay | AirPlay | N |
| Network: SMB / WebDAV | N | N | Y / Y | SMB / UPnP | SMB/FTP/UPnP | ? | ? | Y / Y | N | N | N | N | N |
| Subsonic / Navidrome / Jellyfin / Plex | N | N | Subsonic, Navidrome | N | N | N | N | All | N | N | N | N | N |
| Podcasts / audiobooks (chapters, speed, resume) | P | P | P (tempo) | ? | N | ? | Podcasts Y | Audiobookshelf Y | N | ? | N | Separate apps | N |
| Scrobbling (Last.fm / ListenBrainz) | Via 3rd-party | Via 3rd-party | ? | ? | Plugin | Plugin | Last.fm | ? | N | ? | Last.fm | N | N |
| Visualizer | Y | N | Y | N | Plugin | Y | Y | N | N | N | N | N | N |
| Themes / skins | Y | Y | P | N | Y | Y | Y | Material You | Material 3 | N | N | N | N |

Key observations:

1. **No single app ships the full matrix.** Neutron comes closest on engine depth but fails on UI; Symfonium wins on sources but is server-first; Poweramp wins on Android polish but is single-platform.
2. **Lyrics are a differentiator.** Musicolet's built-in LRC creator and Symfonium's server lyrics are praised; online synced-lyrics fetching via LRCLIB (~3M entries, free, FOSS-friendly, no account) is now common in FOSS players and should be standard.
3. **Scrobbling is almost always outsourced** to Simple Last.fm Scrobbler / Pano Scrobbler on Android or plugins on desktop. Native Last.fm plus ListenBrainz support is a cheap, visible win.
4. **Watch / Wear support is nearly absent** outside stock apps.
5. **Podcast / audiobook handling is weak everywhere** except dedicated apps; chapters (MP4/M4B/ID3 CHAP), speed and per-item resume are rarely combined with a music library.
6. **Paywalls on basics** (EQ bands in Oto+, crossfade/ReplayGain/Chromecast in Musicolet Pro, parametric EQ and MQA as UAPP add-ons) are a recurring irritation in reviews.

### A4. Stock-app gaps and common complaints (audio)

- **iOS:** Music app refuses FLAC (ALAC only); Files app previews FLAC with no queue, no playlists, one track at a time; FLAC skipping reports on wired playback; Apple Music subscription historically interfered with local syncing. Third-party apps cannot delete Music-library items.
- **Android:** No consistent stock player (Pixel defaults to YouTube Music; Samsung Music is OEM-only). Users complain about ads, "Pro" paywalls for EQ/crossfade/ReplayGain, and hi-res output silently resampled by the OS mixer.
- **Windows 11:** Media Player uses roughly 3.7x the RAM of the 17-year-old legacy player, opens local files more slowly, needs paid codec packs for some formats, and had video-plays-as-audio bugs in 2025.
- **macOS:** Music.app silently rejects FLAC imports; Swinsian/VOX fill the gap but are paid or subscription-gated.

---

## PART B: IMAGE VIEWERS / GALLERIES

### B1. Market landscape (2025-2026)

- **Android galleries** split into stock (Google Photos cloud-first; Samsung Gallery; Google's little-known offline Gallery app), FOSS (Fossify Gallery, ex-Simple Gallery, 500k+ installs, 4.6 stars, GPL-3.0; Aves, BSD-3, Flutter, metadata explorer) and photographer tools (F-Stop with XMP tags/ratings). QuickPic's 2015 sale to Cheetah Mobile, subsequent adware, 2018 Play Store removal for click fraud and degraded 2019 return remain the cautionary tale that drives distrust of acquired gallery apps.
- **iOS** is effectively Apple Photos plus editors (Photomator/Pixelmator, now Apple-owned) and self-hosted clients (Immich). No mainstream folder-based viewer exists because of sandboxing; Files app previews are the fallback.
- **Windows** has a deep freeware bench: IrfanView (freeware personal, $18 commercial), FastStone 8.5 (Jun 2026: JXL/HEIC/SVG/PDF, 4-way compare), XnView MP 1.12.2 (500+ formats, EXIF/IPTC/XMP editing, duplicate finder; Win/Mac/Linux), ImageGlass (open source; v10 RC adds HDR for AVIF/JXL/EXR), Honeyview (discontinued Jun 2024, replaced by BandiView), nomacs 3.22 (GPL, synchronised multi-window compare), qView (GPL, minimalist). Microsoft Photos was rebuilt in 2026 to remove Copilot/OneDrive/Clipchamp clutter and speed up loads after years of "20-25 s startup" complaints.
- **macOS** has Preview (no proper next/previous folder browsing, Sonoma-era slowdowns), Photos (library-only), Lyn (~$20, photographer-oriented, RAW, basic adjustments), Xee ($3.99, semi-abandoned), XnView MP and nomacs.
- **Self-hosted:** Immich (AGPL; native iOS/Android apps with selective upload, local-only browsing, one-way album sync, Free-Up-Space; optional $100 server licence) is winning over PhotoPrism (PWA only, face recognition behind Plus tier) for mobile users.

### B2. Per-app profiles

| App | Platforms | Pricing | Strengths | Weaknesses | Notes |
|---|---|---|---|---|---|
| **Fossify Gallery** | Android | Free, GPL-3.0, no ads/trackers | JPEG, JPEG XL, PNG, GIF, SVG, AVIF, RAW, MP4/MKV; crop/resize/rotate/flip/draw/filters; EXIF stripping; PIN/pattern/fingerprint lock per item or app; recycle bin; Material You; 500k+ installs, 4.6 stars, updated Feb 2026 | Slow new-feature cadence (Simple Gallery Pro frozen Oct 2023); no cloud; no metadata editing beyond strip; limited HEIC/AVIF encode | De-facto FOSS benchmark |
| **Aves** | Android (KitKat to 14, TV) | Free, BSD-3 | Metadata explorer; motion photos, panoramas, 360 video, GeoTIFF, multi-page TIFF, SVG, old AVI; map plus reverse geocoding; tags; widgets/screensaver; 1.14.9 (Jul 2026) | Flutter overhead on low-end devices; no PRs accepted; JXL/AVIF not advertised | Best metadata/map UX on Android |
| **F-Stop Gallery** | Android | Free plus IAP ($0.99-$12.99) | Reads EXIF/XMP/IPTC; writes tags/ratings as XMP (Lightroom/digiKam-compatible); smart albums; map; password hiding; metadata search | Older UI; development slowed (5.5.126 crash-fix release) | Only Android gallery with a pro XMP workflow |
| **QuickPic** | Android | Free | Historically fast, minimal | Cheetah Mobile adware/spyware, click-fraud removal (2018), degraded return (2019) | Avoid; brand-trust lesson |
| **Google Photos** | Android, iOS, web | Free plus storage plans | ML search, faces, sharing, Locked Folder, Magic Editor | Albums are links not folders; device albums don't sync; slow local view; un-hideable "People & pets"/"Documents" collections; dumbed-down editor; no desktop app; shared-album 500 errors (2025); duplicates auto-merged without control | Google's offline "Gallery" app is lighter but obscure |
| **Samsung Gallery** | Samsung Android | Free | Delete-duplicates tool; Secure Folder; One UI 8.5 Private Album (biometric); Google Photos sync option | Secure Folder workflow (move out to edit/share) until 8.5; OEM-locked | Sets the OEM bar |
| **Apple Photos** | iOS, macOS | Stock | Live Photos, ProRAW, iCloud, faces, Visual Look Up | iOS 18 redesign backlash forced tabs back in iOS 26 ("second redesign in 12 months"); slideshow transition-speed control removed (Oct 2025); no folder-based browsing; limited third-party deletion | Primary iOS gap |
| **Photomator / Pixelmator** | macOS, iOS, iPadOS, visionOS | Historically one-time or subscription; Apple-owned since Nov 2024 | 750+ RAW formats incl. ProRAW; non-destructive curves/wheels; ML masks, denoise, super-resolution; LUTs; batch | Apple-only; future uncertain post-acquisition; editor not viewer | Reference for editing quality bar |
| **XnView MP** | Windows, macOS 11.3+, Linux | Free personal; €29 commercial | 500+ read / 70 write formats incl. HEIC, AVIF, JPEG XL, RAW; EXIF/IPTC/XMP edit; batch rename/convert (XnConvert engine); duplicate finder; 4-way compare; face detection; contact sheets | Dated, dense Qt UI; GPS map not in feature list; large install | Feature ceiling for desktop viewers |
| **IrfanView** | Windows (x86/x64/ARM64) | Freeware personal; $18 commercial | Tiny, fast; plugins (PSD filters, shell extension); batch convert, lossless JPG ops, EXIF date change, IPTC edit; slideshow to MP4/EXE | Windows-only; dated UI; plugin pack needed for many formats | Longevity benchmark |
| **FastStone Image Viewer** | Windows | Free personal/educational | v8.5 (Jun 2026): JXL, HEIC (via WIC), SVG, PDF, PSD, 17 RAW types; 4-image compare; EXIF plus histogram; clone/heal; 150+ slideshow transitions with music; portable | HEIC depends on Windows codec; Windows-only | Strong compare and batch |
| **ImageGlass** | Windows | Free, open source (Patreon) | 90+ formats via Magick.NET/SkiaSharp/Svg.Skia; JXL/AVIF read+write; HEIC/PSD/60+ RAW read; codec plugin system with trust gating; v10 RC adds HDR viewing | Windows-only; no library/album; v9 in maintenance | Modern-UI benchmark on Windows |
| **Honeyview** | Windows | Free | Archive browsing (ZIP/RAR/7Z/CBZ); fast; RAW; EXIF plus GPS | Discontinued (last 5.53, Jun 2024); no JXL/AVIF | Replaced by BandiView |
| **nomacs** | Windows, macOS, Linux | Free, GPL-3 | Synchronised multi-window pan/zoom compare; RAW/PSD; basic edit; v3.22 | Sparse metadata features; plain UI | Compare-mode benchmark |
| **qView** | Windows, macOS, Linux | Free, GPL-3 | Instant open, preloading, low RAM, GIF controls | bmp/gif/jpg/png/tiff/webp only; no library | Minimalism benchmark |
| **Lyn** | macOS | ~$20 | Photographer browser; RAW; exposure/temperature/contrast adjustments; GIF | Little 2025 coverage; price unverified | |
| **Xee** | macOS | $3.99 | Folder plus archive browsing; more formats than Preview | Semi-abandoned | |
| **Preview.app** | macOS | Stock | Ubiquitous; PDF | No next/previous across a folder without multi-select; progressive slowdowns (Sonoma); limited formats | Primary macOS gap |
| **Microsoft Photos** | Windows 11 | Stock | 2026 rebuild: Copilot button removed, multi-process loading ~2x faster, HEIC 30% faster, HEIC edit without re-encode | Years of 20-25 s "Getting things ready" startups; HEIC/HEVC paid-extension confusion; stumbles on high-res | Primary Windows gap |
| **digiKam** | Windows, macOS, Linux | Free, GPL | LibRaw RAW; similarity DB for duplicate/fuzzy search; face recognition (OpenCV); geolocation editor/map search; Batch Queue Manager (DNG, rename, G'MIC) | Heavy, complex; database setup | Reference for DAM depth |
| **Immich** | Server plus iOS/Android | AGPL; optional $100 server licence | Native apps, selective upload, local-only browsing with storage indicator, read-only mode, one-way album sync, Free-Up-Space, faces, search | Needs own server (4 GB RAM); album deletions not mirrored | Model for "local plus optional server" UX |
| **PhotoPrism** | Server (PWA) | AGPL; Plus tier | Strong indexing/search, Ollama captions | No native app; faces behind Plus; backup needs PhotoSync/WebDAV | |

### B3. Image feature matrix

Legend: Y = yes, P = partial, N = no, ? = not confirmed, R/W = read and write, R = read only, OS = delegated to OS trash.

| Feature | Fossify | Aves | F-Stop | Google Photos | Samsung Gallery | Apple Photos | XnView MP | IrfanView | FastStone | ImageGlass | nomacs | qView | MS Photos | Preview |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| JPEG/PNG/GIF/BMP/TIFF | Y | Y (multi-page TIFF) | Y | Y | Y | Y | Y | Y | Y | Y | Y | Y | Y | Y |
| WebP | Y | Y | Y | Y | Y | Y | Y | Plugin | Y | Y | Y | Y | Y | Y |
| AVIF | Y | ? | ? | Y | Y | Y (iOS 17+) | R/W | Plugin | ? | R/W | ? | N | P | Y |
| HEIC/HEIF | Y | Y | Y | Y | Y | Y | Y | Plugin | Via WIC | R | ? | N | Paid ext. (pre-2026) | Y |
| JPEG XL | Y | ? | ? | N | N | Y (iOS 17+) | R/W | Plugin | Y | R/W | ? | N | N | Y (Sequoia+) |
| SVG | Y | Y | ? | N | N | N | Y | Plugin | Y | Y (Svg.Skia) | ? | N | N | Y |
| PSD preview | ? | ? | N | N | N | N | Y | Plugin | Y | Y (PSD/PSB) | Y | N | N | Y (flattened) |
| RAW (CR2/CR3/NEF/ARW/DNG) | Y (basic) | ? | ? | Y (DNG etc.) | Y | Y (ProRAW+) | Y | Plugin | 17 types | 60+ ext. | Y | N | Partial (Raw ext.) | Y |
| Animated GIF/WebP/APNG | Y | Y | Y | Y | Y | Y | Y | Y | Y | GIF/APNG + plugins | ? | GIF | Y | GIF |
| Live Photos / Motion Photos | Motion P | Motion Y | ? | Y | Y | Live Y | N | N | N | N | N | N | N | N |
| EXIF/IPTC/XMP view / edit | View; strip | Rich view; edit ? | View; XMP write | Basic | Basic | Basic; edit date/location | Full edit | EXIF date, IPTC edit | View; JPEG comment | View | ? | N | View; limited edit | View (Inspector) |
| GPS map | ? | Y + reverse geocode | Y | Y | Y | Y | ? | N | N | N | N | N | Y | N |
| Folders vs albums | Folders | Both | Both + smart | Albums (links) | Albums (folders) | Albums only | Folders | Folders | Folders | Folders | Folders | Folders | Folders + collections | n/a |
| Hidden / locked vault | PIN/pattern/bio | ? | Password | Locked Folder | Secure Folder / Private Album | Hidden + Face ID | N | N | N | N | N | N | N | N |
| Slideshow | Y | Y | Y | Y (Memories) | Y | Y (speed control removed iOS 26) | Y | Y (export MP4/EXE) | 150+ transitions + music | Y | Y | N | Y | Y |
| Basic editing (crop/rotate/flip/adjust) | Y + draw/filters | Rotate/flip | Y | Y (ML) | Y | Y | Y | Y | Y + clone/heal | Y | Y | Rotate/mirror | Y (rebuilt 2026) | Y |
| Batch rename / convert | Rename | ? | ? | N | N | N | Y / Y | Y / Y | Y / Y | Y (limited) | N | N | N | N |
| Duplicate detection | N | N | N | Auto-merge (no control) | Y tool | Duplicates album | Y | N | N | N | N | N | N | N |
| Fast thumbnail cache | Y | Y | Y | Cloud | Y | Y | Y | Y | Y | Y | Y | Preload | Rebuilt 2026 | Lazy (slow) |
| Huge-image (100 MP) zoom | OK | OK | OK | OK | OK | OK | OK | OK | OK | OK (Skia) | OK | OK | "stumbles" | OK |
| Comparison mode | N | N | N | N | N | N | 4-up | N | 4-up | N | Synced windows | N | N | N |
| Sort / filter / metadata search | Y | Y (tags, map, type) | Y (tags, rating, camera) | ML search | Y | ML search | Y | Y | Y | Y | Y | N | Y | N |
| Favorites | Y | Y | Rating | Y | Y | Y | Rating | N | Tag | N | N | N | Y | N |
| Trash / recycle | Y | Y | Y | 60-day | 30-day | 30-day | OS | OS | OS | OS | OS | OS | OS | OS |
| Cloud / network sources | N | N | N | Google | OneDrive/Google sync | iCloud | Network paths | Network paths | Network paths | N | N | N | OneDrive | N |
| Set wallpaper | Y | Y | Y | Y | Y | Y | n/a | Y | Y | Y | N | N | Y | N |
| Sharing | Y | Y | Y | Y | Y | Y | Email | Email | Email | Y | N | N | Y | Y |
| Print | N | N | N | Y | Y | Y | Y (contact sheets) | Y | Y (contact sheets) | Y | Y | N | Y | Y |

Key observations:

1. **No mobile gallery combines FOSS trust (Fossify), metadata depth (Aves/F-Stop) and desktop-class batch tools (XnView/IrfanView).** Desktop viewers have batch, compare and metadata editing; mobile galleries have vaults, motion photos and maps. A cross-platform app can unify both.
2. **Comparison mode exists only on desktop** (XnView, FastStone, nomacs). Photographers on phones and tablets have nothing.
3. **Format breadth is uneven.** JPEG XL and AVIF write support exist in XnView MP and ImageGlass; stock apps (Google Photos, Microsoft Photos) still skip JXL. HEIC on Windows historically needed a paid extension. Bundling libjxl/libavif/libheif decode on all four OSes is a visible differentiator.
4. **Duplicate detection is rare and badly implemented** (Google auto-merges without control; Samsung has a manual tool; XnView and digiKam are desktop-only).
5. **Honeyview's archive browsing** (ZIP/RAR/CBZ) is a loved niche capability now orphaned by its discontinuation.

### B4. Stock-app gaps and common complaints (images)

- **Android (Google Photos):** albums are links; device folders don't sync; slow offline view; forced ML collections; dumbed-down editor; cloud push. Google's offline Gallery app exists but is "a surprise" to most users (Android Authority, May 2025).
- **iOS (Photos):** two redesigns in 12 months; no folder browsing; feature removals (slideshow speed); the Files preview is the only folder-based viewer.
- **Windows (Photos):** chronic slowness ("Getting things ready" 20-25 s), Copilot/OneDrive/Clipchamp upsell clutter (removed only in the Sept 2026 rebuild), paid HEVC/HEIC extension confusion, poor handling of very large images.
- **macOS (Preview):** no folder navigation, progressive slowdowns, limited format set; Photos is library-only.

---

## PART C: IMPLICATIONS FOR THE NEW APP

### C1. Table stakes (must ship at v1 to be "complete")

**Audio:** FLAC/ALAC/Opus/AAC/MP3/WavPack/APE/AIFF/WAV/DSF/DFF decode; gapless; crossfade; ReplayGain plus loudness normalisation (EBU R128); 10-band graphic and parametric EQ with limiter, balance, independent tempo/pitch; embedded plus sidecar LRC plus online synced lyrics (LRCLIB, no account); full tag editing (single and batch) with cover-art fetch (MusicBrainz / Cover Art Archive); folder mode and library mode; smart playlists; multiple queues (Musicolet's signature); sleep timers (time and track count); Android Auto and CarPlay; widgets; Bluetooth AVRCP metadata; Chromecast and AirPlay; SMB/WebDAV/FTP; Subsonic/OpenSubsonic/Navidrome/Jellyfin/Plex clients; podcast/audiobook mode with chapters, speed, per-item resume; native Last.fm and ListenBrainz scrobbling; visualizer; theming (Material You / Liquid Glass / Fluent).

**Images:** JPEG, PNG, GIF, WebP, AVIF, HEIC/HEIF, JPEG XL, SVG, TIFF, BMP, PSD flattened preview, RAW via LibRaw (CR2/CR3/NEF/ARW/DNG and more); animated GIF/WebP/APNG/AVIF; Live Photos and Motion Photos playback; EXIF/IPTC/XMP view and edit (XMP sidecar for RAW); GPS map with reverse geocoding; folders and albums both; biometric-locked vault; slideshow with transitions and music; crop/rotate/flip/adjust/draw; batch rename/convert/resize; perceptual-hash duplicate finder with user control; persistent thumbnail cache with tile-based rendering for 100 MP+ images; 2/4-up compare with synced pan/zoom; sort/filter/search on metadata; favourites/ratings; recycle bin; SMB/WebDAV/Immich/PhotoPrism/Nextcloud sources; wallpaper; share; print; archive (ZIP/CBZ) browsing.

### C2. Differentiators the market leaves open

1. **One codebase, four platforms, identical feature set.** None of the 40-plus apps surveyed does this for both audio and images.
2. **Bit-perfect output everywhere:** USB DAC / AAudio exclusive on Android, CoreAudio hog mode on macOS/iOS, WASAPI exclusive / ASIO on Windows, with a visible fidelity indicator (Poweramp's approach) so users trust the signal path.
3. **No paywall for basics.** EQ, crossfade, ReplayGain and Chromecast are gated behind IAP in Musicolet/Oto; subscription fatigue around VOX/Flacbox/Audirvana is palpable in reviews.
4. **Trust signals:** no internet permission unless a network feature is enabled (Musicolet's selling point), reproducible builds, F-Droid/IzzyOnDroid availability, open metadata policy. The QuickPic/Cheetah history shows how fast trust evaporates.
5. **Performance budget:** target the low RAM/CPU profile of MusicBee (25-70 MB), foobar2000 and qView rather than Windows Media Player (377 MB idle) or Flutter-heavy galleries.
6. **Watch/Wear companion** and **comparison mode on mobile** have no incumbent.
7. **Local-first with optional servers** (Immich's "On this device" and storage-indicator model) rather than cloud-first (Google Photos).

### C3. Risks to design around

- iOS sandbox: local-file ingestion must be seamless (Files provider, Wi-Fi transfer, USB-C drive support) because Doppler/Flacbox reviews hinge on this.
- Large libraries: Winamp mobile crashed at 11k tracks; Swinsian is praised for 900k. Index asynchronously and incrementally with a persistent SQLite cache.
- Apple review: a player that mimics Apple Music too closely or tries to delete library items will be constrained; Marvis Pro documents these limits.
- Android 15/16 hi-res output changes (per Poweramp changelogs) mean the audio HAL path must be tested per OS version.
- Format licensing: HEIC/HEVC on Windows needs bundled decoders (libheif plus libde265 or an alternative) to avoid the paid-extension complaint.

---

## Sources

### Audio
- Poweramp official: https://powerampapp.com/
- Poweramp changelog (APKMirror): https://www.apkmirror.com/apk/max-mp/poweramp/
- Poweramp Android Auto (XDA): https://www.xda-developers.com/poweramp-android-auto-support-improved-google-assistant/
- Musicolet official: https://krosbits.in/musicolet/
- Musicolet user-feedback analysis (Kimola): https://kimola.com/reports/musicolet-user-feedback-analysis-drive-music-app-innovation-google-play-en-us-154135
- Musicolet changelogs (APKMirror): https://www.apkmirror.com/apk/krosbits/musicolet-music-player-free-no-ads/
- Neutron Player page: https://neutroncode.com/apps/player
- Neutron App Store listing: https://apps.apple.com/il/app/id766858884
- Neutron (AppleVis): https://applevis.com/apps/ios/music/neutron-music-player
- USB Audio Player PRO official: https://www.extreamsd.com/index.php/products/usb-audio-player-pro/
- UAPP add-ons listing: https://www.bluestacks.com/campaign/com.extreamsd.usbaudioplayerpro/en
- UAPP Roon community thread: https://community.roonlabs.com/t/high-res-audio-on-andriod-phone-usb-audio-player-pro/66280
- foobar2000 news: https://www.foobar2000.org/news
- foobar2000 Android: https://www.foobar2000.org/android
- foobar2000 iOS (AppleVis): https://www.applevis.com/apps/ios/music/foobar2000
- Symfonium official: https://symfonium.app/
- Symfonium Jellyfin client roundup: https://en.xiaoz.org/post/20552
- Auxio (IzzyOnDroid): https://apt.izzysoft.de/fdroid/index/apk/org.oxycblt.auxio?repo=main
- Auxio review (Open Source Musings): https://opensourcemusings.com/posts/android.html
- Auxio F-Droid thread: https://forum.f-droid.org/t/auxio-in-fdroid/30929
- Phonograph Plus: https://github.com/eku/Phonograph_Plus and https://apt.izzysoft.de/fdroid/index/apk/player.phonograph.plus?repo=main
- Retro Music Player (AlternativeTo): https://alternativeto.net/software/retro-music-player/about
- Oto Music changelogs (APKMirror): https://www.apkmirror.com/apk/piyush-m/oto-music/oto-music-3-8-0-release/
- Best Android music players 2026 (Beebom): https://beebom.com/best-music-players-android/amp/
- Android Authority best music players: https://www.androidauthority.com/best-music-player-apps-android-208990/
- Doppler App Store: https://apps.apple.com/il/app/id1468459747
- Doppler review (TapSmart): https://www.tapsmart.com/apps/doppler-review/?amp=1
- Marvis Pro App Store: https://apps.apple.com/sg/app/id1447768809
- Cesium / Cs Music (Macworld): https://www.macworld.com/article/226537/alternatives-to-apple-s-ios-music-app.html
- Cesium (iPhone-Ticker): https://www.iphone-ticker.de/alternative-zur-musik-app-cesium-aktuell-kostenlos-117371/
- Flacbox App Store: https://apps.apple.com/us/app/-/id1097564256
- Flacbox pricing tracker: https://apppricinglab.com/app/apple/1097564256
- Evermusic listing: https://mwm.ai/apps/id/885367198
- VOX Mac App Store: https://apps.apple.com/app/id461369673
- VOX vs WMP (SaaSHub): https://www.saashub.com/compare-vox-music-player-vs-windows-media-player
- Swinsian 3 release: https://www.x-cmd.com/blog/250822
- Swinsian (AppleVis): https://www.applevis.com/apps/mac/music/swinsian
- MusicBee official: https://getmusicbee.com/
- Best free music players 2026 (TechRadar): https://techradar.com/news/the-best-free-music-player
- AIMP 5.40 builds (Neowin): https://www.neowin.net/software/aimp-540-build-2721/
- Audirvana Origin vs Studio: https://help.audirvana.com/en/support/solutions/articles/202000056197
- Audirvana bit-perfect thread: https://community.audirvana.com/t/is-audirvana-origin-bit-perfect/38153
- Audirvana reseller pricing / EISA: https://www.heynowhifi.com.au/pages/audirvana
- Winamp mobile (Lowyat): https://lowyat.net/2024/326536/winamp-ios-android-app
- Winamp mobile (Gigazine): https://www.gigazine.net/gsc_news/en/20240712-winamp-mobile-app
- Winamp user reviews (JustUseApp): https://justuseapp.com/en/app/1664497725/winamp/reviews
- Windows 11 Media Player worse than legacy (Digital Trends): https://www.digitaltrends.com/computing/windows-11s-new-media-player-is-somehow-worse-than-the-version-from-17-years-ago/
- Windows 11 Media Player video-as-audio (Microsoft Answers): https://answers.microsoft.com/en-us/windows/forum/all/windows-11-media-player-not-playing-video/2053e4a4-566a-4883-a699-11c82a586718
- Files app FLAC limits (MacRumors): https://forums.macrumors.com/threads/files-app-doesnt-appear-to-support-flac-files.2070587/
- FLAC skipping (Apple Discussions): https://discussions.apple.com/thread/252387507
- Mac Music rejects FLAC (Apple Discussions): https://discussions.apple.com/thread/256136220
- LRCLIB-using apps (AlternativeTo): https://alternativeto.net/browse/all/?tag=lrclib
- Local Player with LRC/TTML (F-Droid): https://f-droid.org/packages/com.cvc953.localplayer

### Images
- Fossify Gallery GitHub: https://github.com/FossifyOrg/Gallery
- Fossify Gallery overview (tuapppara): https://tuapppara.com/aplicaciones/fossify-gallery/
- Aves GitHub: https://github.com/deckerst/aves
- Aves changelogs (APKMirror): https://www.apkmirror.com/apk/thibault-deckers/aves-gallery
- F-Stop Gallery (APKMirror): https://apkmirror.com/apk/seelye-engineering/f-stop-gallery/f-stop-gallery-5-5-126-release
- Best gallery apps (Android Authority): https://www.androidauthority.com/BEST-GALLERY-APPS-ANDROID-687764/
- QuickPic / Cheetah (MobileSyrup): https://mobilesyrup.com/2019/04/29/quickpic-photo-gallery-app-play-store/
- QuickPic / Cheetah (TuttoAndroid): https://www.tuttoandroid.net/news/quickpic-ceetah-sparito-play-store-635467/
- Google Photos complaints (Smartprix): https://www.smartprix.com/bytes/dear-google-please-fix-the-google-photos-app/
- Google Gallery app (Android Authority): https://androidauthority.com/google-gallery-app-existence-surprise-3555934
- Google Photos shared-album errors (Android Authority): https://www.androidauthority.com/p-3475643
- Samsung albums not syncing (Samsung Community): https://us.community.samsung.com/t5/Galaxy-S24/Albums-missing-from-Google-Photos-app/td-p/3291133
- Samsung Gallery vs Google Photos (MakeTechEasier): https://maketecheasier.com/samsung-gallery-vs-google-photos/
- Samsung Delete Duplicates (WebProNews): https://www.webpronews.com/the-samsung-gallery-tool-that-google-photos-still-wont-match/
- Samsung Private Album (NextPit): https://nextpit.com/samsung-gallery-private-album-hide-photos-videos-feature
- Apple Photos tabs return in iOS 26 (TechCrunch): https://techcrunch.com/2025/06/09/after-user-backlash-apple-brings-back-tabs-to-the-photos-app-in-ios-26/
- iOS 26 Photos overhaul (Tom's Guide): https://www.tomsguide.com/phones/iphones/ios-26-has-brought-yet-another-photos-app-overhaul-for-your-iphone-heres-how-its-different
- Slideshow speed removed (Apple Discussions): https://discussions.apple.com/thread/256173567
- Photomator official: https://www.pixelmator.com/photomator/
- XnView MP official: https://www.xnview.com/en/xnviewmp/
- XnView FAQ: https://www.xnview.com/en/faq/
- IrfanView features: https://www.irfanview.com/main_what_is_engl.htm
- FastStone Image Viewer: https://www.faststone.org/FSViewerDetail.htm
- ImageGlass supported formats: https://imageglass.org/docs/supported-formats
- ImageGlass AVIF/JXL (ComputerBase): https://www.computerbase.de/2024-05/imageglass-9-0-11-502-open-source-bildbetrachter-speichert-auch-im-avif-format/
- ImageGlass roadmap (Patreon): https://www.patreon.com/d2phap
- Honeyview (discontinued): https://www.bandisoft.com/honeyview/
- nomacs: https://nomacs.org/
- qView: https://interversehq.com/qview/
- Lyn / Xee overview (GuidingTech): https://www.guidingtech.com/best-image-viewer-apps-mac/
- Xee (AlternativeTo): https://alternativeto.net/software/xee/about
- Preview slowdown, Sonoma (Apple Discussions): https://discussions-kr-prz.apple.com/thread/255847489
- Preview no-next-button complaint (AppleInsider): https://forums.appleinsider.com/discussion/34200
- Microsoft Photos rebuild (Windows Report): https://windowsreport.com/microsoft-photos-cuts-copilot-onedrive-and-clipchamp-clutter-from-its-interface/
- Microsoft Photos faster (Windows Latest): https://www.windowslatest.com/2026/09/04/microsoft-just-made-windows-11s-photo-viewer-less-annoying-and-its-noticeably-faster/
- Microsoft Photos slow load (Windows Report): https://windowsreport.com/windows-11-photos-app-takes-longer-to-load-blame-the-latest-changes/
- Microsoft Photos native editing (TechSpot): https://techspot.com/news/114223-new-windows-photos-app-goes-native-editing-viewing.html
- HEIC paid extension (Microsoft Learn): https://learn.microsoft.com/en-us/answers/a/7546336
- digiKam features: https://www.digikam.org/about/features/
- Immich mobile docs: https://docs.immich.app/features/mobile-app
- Immich vs PhotoPrism (Elestio): https://blog.elest.io/immich-vs-photoprism-which-self-hosted-photo-manager-for-your-family/
- Immich vs PhotoPrism vs Ente (Contabo): https://contabo.com/blog/immich-vs-photoprism-vs-ente/
