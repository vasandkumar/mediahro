# 04 — Technology Stack Evaluation

**Scope:** a free, high-performance, low-bloat media app (video player + audio player + image viewer/gallery) for Android, iOS/iPadOS, macOS and Windows, built end-to-end by an AI coding agent in 2026.
**Date of research:** 2026-10-19. Versions and dates below were checked against project pages on that day; where a page omitted the year (GitHub omits it for current-year dates) the year is 2026 unless noted. Items marked *(unverified)* could not be confirmed from a primary source in this pass.

**Research note:** the web-search budget for this session was exhausted part-way through; the second half of the research relied on direct fetches of project pages (GitHub, pub.dev, vendor docs). Sections 6 and 7 are therefore thinner on third-party commentary than sections 1–3. Gaps are called out explicitly rather than filled from memory.

---

## 0. Executive recommendation

| | Choice | Why |
|---|---|---|
| **Primary** | **Flutter (Dart) single codebase + libmpv (LGPL build) as the video *and* audio engine on all four platforms + platform-native gallery/thumbnail providers via FFI/plugins** | One toolchain the agent can drive on all four OSes; libmpv/libplacebo is the only engine that delivers HDR/Dolby Vision tone-mapping, libass subtitles, user shaders (Anime4K), gapless audio, WASAPI/CoreAudio exclusive output and MKV/every-container support identically everywhere; Impeller gives 120 Hz UI; binary overhead is a few MB per ABI, far below JVM- or .NET-based alternatives. |
| **Fallback** | **Kotlin Multiplatform + Compose Multiplatform (1.12.x) with libmpv bound via cinterop/JNI on each target** | Android becomes first-class native (Media3 session, Material 3 Expressive for free); iOS is stable since CMP 1.8; desktop ships a JVM (bigger, but acceptable for Windows/macOS). Choose this if the team values Android-native fidelity over Windows/macOS size. |
| **Ceiling (not recommended for a solo AI agent)** | Fully native shells (SwiftUI / Jetpack Compose / WinUI 3) over a Rust core (UniFFI) + libmpv | Maximum per-platform fidelity, but four UI codebases, three toolchains and one pre-1.0 binding generator; WinUI 3 tooling is the weakest link for an agent. |

Reasoning and evidence follow.

---

## 1. App frameworks

### 1.1 State of each option (2026)

| Framework | Latest stable (date) | Status on the 4 targets | Media story | Size/startup evidence | Licence |
|---|---|---|---|---|---|
| **Flutter** | 3.47 (2026; 3.29→3.47 shipped across 2025–26, roughly quarterly) [S1] | Android, iOS, macOS, Windows all stable. Impeller is default on iOS and Android API 29+ since 3.27; the Skia opt-out was deprecated in 3.38 *(vendor blog, unverified)* [S2][S3] | **media_kit** (MIT) wraps libmpv on Android/iOS/macOS/Windows/Linux; 1.8k stars, 2,068 commits, **340 open issues / 20 open PRs**; the most recent tags (`media_kit-v1.1.10`, `media_kit_video-v1.2.3`, Android libs 1.3.6) are dated 16–19 Oct [S4][S5]. **just_audio** 0.10.6 (Apache/MIT, ryanheise) uses ExoPlayer/AVPlayer and needs `just_audio_media_kit` on Windows/Linux [S6]. **photo_manager** 3.12.0 (Apache-2.0, fluttercandies) exposes MediaStore buckets / `PHAssetCollection`, thumbnails cached via Glide [S7]. mpv_audio_kit 0.4.2 (June 2026) ships libmpv-r12 builds, showing the libmpv-for-Flutter ecosystem is alive beyond media_kit [S8] | Impeller adds ≈100 KB per architecture incl. precompiled shaders (engine FAQ) [S3]. Third-party "50 % raster time / 70 % fewer dropped frames" claims are unverified marketing [S2] | BSD-3 |
| **Kotlin Multiplatform + Compose Multiplatform** | CMP 1.12.2 (15 Oct 2026); 1.8.0 (May 2025) made iOS stable; 1.10 moved Skia to M138, added common `@Preview`, Navigation 3 on non-Android, bundled Hot Reload [S9][S10][S11] | Android native; iOS stable; desktop = JVM (Windows/macOS) via Skiko. No native Fluent/Liquid-Glass widgets — Compose draws everything with Skia. | No first-party player. **ComposeMediaPlayer** (kdroidFilter, MIT, 504 stars, last Maven release 5 Mar 2026) uses Media3 on Android, AVPlayer on iOS/macOS, Media Foundation on Windows, GStreamer on Linux; WASM target broken since 0.8.3 [S12][S13]. Chaintech's player needs a separately installed VLC on desktop [S12]. vlcj historically cannot composite Composables over the video surface [S12]. jellyfin-sdk-kotlin is JVM+Android only (LGPL-3.0) — no iOS target [S14] | JetBrains claims "significantly faster and smoother on iOS" since 1.7 but publishes no numbers [S9]. Desktop bundles a jlink'd JRE (tens of MB) — this is the main bloat concern. | Apache-2.0 |
| **React Native** (+ Expo) | RN 0.82 active, 0.88 due 12 Oct 2026 [S15]. **react-native-windows 0.82 (17 Mar 2026) removed Paper — New Architecture only; 0.83 (4 Jun), 0.84 (30 Jun 2026)** [S16][S17]. **react-native-macos** last release 23 Apr 2026, npm shows 0.78.x line [S18] | Mobile excellent; Windows real (WinAppSDK Win32 default, XAML islands); macOS lags upstream by several minors. | **expo-video**: Android (ExoPlayer) / iOS (AVKit) / tvOS / web only — no Windows or macOS; subtitles only via `availableSubtitleTracks`, no external-file API documented; LRU cache 1 GB [S19]. **react-native-video** v7 (beta, Nitro modules, full New-Arch) MIT 7.7k stars; Windows/tvOS not listed, visionOS "TODO" [S20] | JS bundle + Hermes per platform; no media engine on desktop beyond what you write yourself. | MIT |
| **Avalonia** | 12.1.4 (9 Oct 2026); 11.3.22 LTS (11 Sep) [S21] | Desktop first-class; iOS/Android exist but recent release notes contain no mobile fixes. | **LibVLCSharp.Avalonia 3.10.1 lists only Windows/macOS/Linux**; mobile LibVLCSharp is offered through MAUI/Uno packages instead [S22] | Avalonia's own page claims 3–6× faster and ~½ the memory of MAUI on Windows (vendor benchmark) [S23] | MIT |
| **.NET MAUI** | .NET 10 line | Windows/macOS(Catalyst)/iOS/Android. | LibVLCSharp.MAUI exists (3.9.7-alpha for XDev fork) [S22] | Competitor-published "3–5 s Android cold start" claim; no neutral numbers found [S23] | MIT |
| **Uno Platform** | 6.0 GA May 2025; 6.6 adds Native AOT on all targets [S24] | WinUI-API-compatible on all 6 OSes, Skia renderer or native. | `MediaPlayerElement` maps to AVPlayer (iOS) / AndroidMediaPlayer (Android); docs list MKV/AVI as *not* supported on iOS; implementation pages last updated Nov 2023 [S25] | — | Apache-2.0 |
| **Tauri 2** | 2.10 (Feb 2026), 2.12 runtime [S26] | Desktop + mobile, but **mobile is webview-only: no supported way to place native views beside the webview** (PR discussion) [S26]. Verso (Servo webview) archived Oct 2025. | HTML5 `<video>` only → codec/HDR/subtitle support is whatever the OS webview offers. 2.10 fixed Android external-storage video 500 errors [S26] | Small binaries, but webview fragmentation across WebKitGTK/WKWebView/WebView2 | MIT/Apache |
| **Electron** | desktop only | Not applicable to mobile; ~100 MB+ Chromium runtime. Rejected on the "low-bloat" criterion alone. | | | MIT |
| **Qt 6 / QML** | 6.9/6.10 | All four. | mpv/VLC Qt integrations are mature on desktop; mobile needs static linking. | — | **LGPL-3 with explicit warning that "online application stores may have rules that conflict with the LGPL"; static linking "may mean the application is no longer a work that uses the library"; The Qt Company steers doubtful cases to the commercial licence** [S27]. GPL-only modules exist (list not on the obligations page). |
| **Fully native** | SwiftUI (Xcode 26), Jetpack Compose (Material 3 Expressive), WinUI 3 on **Windows App SDK 2.5.1 (16 Sep 2026; 2.0 GA 29 Apr 2026)** [S28] | Best fidelity. | AVFoundation/VLCKit/MPVKit on Apple; Media3 + libmpv on Android; **FFmpegInteropX** (Apache-2.0) feeds FFmpeg into `MediaPlayerElement` with D3D11 hwdec for H.264/HEVC/AV1/VP9/VC-1/MPEG-2 and auto-loads embedded subtitles [S29] | Smallest binaries. | per-platform |
| **Rust core + native shells** | **UniFFI 0.32.0** (pre-1.0; "advanced features may break during upgrades") [S30]; **crux** pre-1.0, Apache-2.0, 2.8k stars, Elm-style core with Swift/Kotlin/TS shells [S31] | Core shared; UI still ×4. | Engines as "fully native". | Smallest. | Apache/MIT |

### 1.2 Scoring against the brief

Criteria weights reflect the brief: *performance* and *bloat* are engine-dominated for a media app (decode, render, tone-map), so the framework mostly needs to (a) composite a GPU texture at 120 Hz without copies, (b) stay out of the way, and (c) be something one agent can build and test on four OSes.

| Criterion (weight) | Flutter | KMP/CMP | RN+Expo | Avalonia/.NET | Uno | Tauri | Qt | Native ×4 | Rust core + native |
|---|---|---|---|---|---|---|---|---|---|
| Single codebase for all 4 (25) | 5 | 4 (desktop = JVM) | 3 (macOS lag, no expo-video desktop) | 4 | 4 | 3 (webview media) | 4 | 1 | 2 |
| Zero-copy video texture path (20) | 4 (Texture widget; media_kit proven) | 4 (SwiftUI/UIKit interop; desktop AWT heavy) | 3 | 3 | 3 | 1 | 5 | 5 | 5 |
| Binary bloat (15) | 4 | 2 (JRE on desktop) | 3 | 3 | 3 | 5 | 3 | 5 | 5 |
| Engine ecosystem maturity (15) | 4 (media_kit, 340 open issues) | 2 | 2 | 3 (LibVLCSharp not on Avalonia mobile) | 2 | 1 | 4 | 5 | 4 |
| AI-agent maintainability / toolchain simplicity (15) | 5 | 4 | 4 | 3 | 2 | 3 | 2 | 2 | 2 |
| Licence friction for a free, store-distributed app (10) | 5 | 5 | 5 | 5 | 5 | 5 | 2 | 5 | 5 |
| **Weighted /5** | **4.5** | **3.5** | **3.2** | **3.4** | **3.1** | **2.9** | **3.5** | **3.4** | **3.5** |

Flutter wins not because it is the fastest UI toolkit but because it is the only option where *one* repository, *one* build system and *one* already-packaged libmpv binding cover all four targets, and the agent can run `flutter test`, `flutter build` and integration tests on every platform from GitHub Actions without hand-maintained native projects.

### 1.3 Why not the others, in one line each

- **KMP/CMP**: excellent Android, good iOS, but Windows/macOS ship a JVM and no maintained libmpv/libVLC binding exists for CMP desktop that supports overlaying Composables; it is the fallback because Kotlin is the lingua franca of Android media (Media3, MediaSession, Android Auto).
- **React Native**: no desktop video engine; expo-video explicitly excludes Windows/macOS; react-native-macos trails upstream.
- **Avalonia/.NET**: LibVLCSharp has no Avalonia-mobile package; libVLC lacks libplacebo-grade HDR/DV tone-mapping.
- **Uno**: `MediaPlayerElement` delegates to the OS player → no MKV on iOS, no ASS, no HDR tone-mapping.
- **Tauri**: no native video view on mobile; `<video>` cannot do MKV/ASS/HDR.
- **Qt**: licence friction on stores and static linking; agent tooling (qmake/CMake + QML + Qt Creator) is heavier.
- **Native ×4 / Rust core**: best ceiling, but four UIs is the single biggest schedule and quality risk for one agent, and UniFFI/crux are pre-1.0.

---

## 2. Media (video) engines

### 2.1 Comparison

| Engine | Version / date | Licence | Containers/codecs | HDR / Dolby Vision | Subtitles | Mobile status | Verdict |
|---|---|---|---|---|---|---|---|
| **libmpv** | **0.41.0 (Dec 2025)**: libplacebo `gpu-next` is now the default VO; Vulkan hwdec preferred where available; **new native AAudio backend on Android**; `vo_mediacodec_embed` no longer default; needs FFmpeg ≥ 6.1 and libplacebo ≥ 6.338.2 [S32][S33] | LGPL-2.1+ when built with `-Dgpl=false` (mpv's LGPL relicensing); becomes GPL if GPL FFmpeg components are enabled | Everything FFmpeg demuxes/decodes | **libplacebo**: dynamic tone mapping with scene histogram, DV profile 5 → PQ/SDR, reads DV side data and does reshaping (base layer only), ICC/3DLUT, film-grain synthesis for AV1/H.274, mpv-style user shaders (RAVU, FSRCNNX, **Anime4K**) [S34] | **libass** (ISC) built in; 0.17.x line (0.17.5 latest), aarch64 assembly since 0.17.2, CoreText (Apple) and DirectWrite (Windows) font providers [S35][S36] | Android: mpv-android (MIT, 3.6k stars, 152 open issues) ships 2026-04-25 release [S37][S38]. iOS/macOS/tvOS/visionOS: **MPVKit** bundles mpv 0.41.0 + FFmpeg n9.0.2 as SPM xcframeworks; LGPL by default, GPL variant adds Samba; Metal is an unofficial patch; README says it is "not maintained very frequently" and points to "AetherEngine" (page returned 404 on 2026-10-19 — treat as unverified) [S39]. media_kit maintains its own `libmpv-darwin-build` / Android / Windows builds [S4][S40] | **Primary engine on all four platforms** |
| **FFmpeg** | **8.0 "Huffman" (22 Aug 2025)**: Vulkan VP9 hwdec, VVC decoder improvements, Vulkan AV1 encode, APV/ProRes RAW decoders. **8.1 "Hoare" (16 Mar 2026)**: Vulkan compute ProRes/DPX, D3D12 encode, EXIF parsing, MPEG-H via libmpeghdec [S41] | LGPL-2.1+ by default. **`--enable-gpl` flips to GPL-2+**: internal GPL parts are libpostproc, `flac_dsp_gpl.asm`, `idct_mmx.c`, `vf_removegrain.asm`; external GPL libs include libx264, libx265, libxvid, librubberband, libvidstab, frei0r, libcdio, avisynth; `--enable-version3` for LGPL-3/Apache deps (gmp, libaribb24, VMAF, mbedTLS); smbclient needs both [S42] | — | hwaccel: MediaCodec, VideoToolbox, D3D11VA/D3D12VA/DXVA2, Vulkan | — | Decode layer under libmpv | **Build LGPL: no x264/x265/rubberband/postproc/smbclient.** Use `scaletempo2` (built-in) instead of rubberband for tempo. |
| **libVLC / VLCKit** | VLCKit **4.0.0a18 (Dec 2025)** tracks libvlc HEAD (no stable libvlc 4); adds visionOS/watchOS and PiP. **MobileVLCKit stuck at 4.0.0a2 (Mar 2023)** [S43] | LGPL-2.1+ | Broad | libplacebo is only an optional Vulkan VO; no DV reshaping path comparable to mpv | libass via VLC's module | Mature on iOS/Android but alpha for 4.x | Fallback engine only |
| **ExoPlayer / Media3** | 1.8.0 (Aug 2025); 1.9.0 at alpha [S44] | Apache-2.0 | MP4/MKV/WebM/TS/FLV/Ogg; **no AVI/WMV/Theora**; "most devices can't decode 10-bit AVC" (Just Player README) [S45] | HDR10+/DV only when the SoC decoder supports it; no tone-mapping to SDR beyond what the display pipeline does | **SSA/ASS styling is limited** (long-standing ExoPlayer issue cited by both Just Player and NextPlayer) [S45][S46] | Android only. **FFmpeg extension is audio-only** (`FfmpegAudioRenderer`), must be built from source against FFmpeg `release/6.0` with NDK r26b, not on Maven [S47] | Use only for Android Auto/Wear session plumbing (MediaSession), not as the player |
| **AVFoundation / AVPlayer** | iOS 26 | Apple | MP4/MOV/HLS; no MKV, limited audio codecs | DV profile 5/8.1 natively on Apple silicon; HDR passthrough | Only CEA/WebVTT/TTML-style sidecars | Native | PiP/AirPlay fallback path for Apple-native formats |
| **Media Foundation / MediaPlayerElement + FFmpegInteropX** | WinAppSDK 2.5.1 [S28]; FFmpegInteropX 1.x [S29] | Apache-2.0 (FFmpegInteropX) | FFmpeg demux; D3D11 hw decode for H.264/HEVC/AV1/VP9/VC-1/MPEG-2 | Windows HDR via MF only; no tone mapping control | Embedded subs auto-loaded; no libass | Windows only | Not needed when libmpv is used |
| **GStreamer** | 1.26 line | LGPL-2.1 | Plugin-dependent | — | — | Android/iOS SDKs exist but heavy | No |
| **dav1d** | **1.5.4 (14 Jul 2026)**; 1.5.0 was "fastest release ever" with x86/ARM/PPC/RISC-V/LoongArch SIMD [S48][S49] | BSD-2-Clause | AV1 | — | — | All | AV1 software decoder inside FFmpeg (`--enable-libdav1d`) |
| **vvdec** | master, 698 commits, © 2018-2026 Fraunhofer | BSD-3-Clause-Clear (no patent grant) | H.266/VVC Main10; Android/iOS/arm64 listed in support matrix [S50] | — | — | Yes | Optional; VVC content is rare and patent exposure is real |
| **libplacebo** | 7.x line (mpv needs ≥ 6.338.2) | LGPL-2.1+ | — | see libmpv row; Vulkan (incl. MoltenVK), OpenGL ≥ 3.0/ES 3.0, D3D11 ≥ 9_1 [S34] | — | Vulkan on Android; MoltenVK on Apple | Comes with libmpv |

### 2.2 HEVC / Dolby Vision / patents

- **HEVC pools consolidated.** Access Advance's HEVC Advance pool now claims 30,000+ patents and in Dec 2025 acquired Via LA's HEVC/VVC pool (renamed "VCL Advance"); a rate increase was postponed to 2026 and current rates are lockable to 2030 [S51]. The older public statement that HEVC Advance "will not seek royalties on application-layer software … where decoding is fully executed in software on a general-purpose CPU" dates from several years ago and **could not be re-confirmed in a 2025 document** — treat as unverified [S51]. Access Advance also opened an **AV1/AV2 device-and-software pool exploration in Aug 2026** [S51], so AV1 is no longer automatically "royalty-free in practice".
- **Practical stance for a free app:** route HEVC/HEIC/DV through **platform hardware decoders** wherever they exist (MediaCodec, VideoToolbox, D3D11VA) — the OEM/OS vendor carries the licence — and keep software HEVC (FFmpeg's native `hevc`) as a fallback. libmpv does this automatically with `hwdec=auto-safe`.
- **Dolby Vision:** profile 8.1 (HDR10-compatible base layer) plays everywhere as HDR10. Profile 5 (IPT-PQ-C2) needs reshaping: libplacebo does it in GLSL from the RPU side data (base layer only) [S34]; Apple hardware does it natively; Android MediaCodec DV decoders exist only on licensed SoCs. The libplacebo path is unsigned by Dolby — no licence is required to *decode* DV metadata in software, but the app must not claim Dolby certification or use Dolby marks.
- **HEIC/HEIF:** libheif (LGPL-3) + libde265 (LGPL-3) have no patent problem *themselves*; the HEVC codec does. On iOS/macOS use ImageIO; on Android use the platform `ImageDecoder` (HEIF supported since API 28); on Windows rely on the HEVC Video Extension being present, otherwise show a one-time "install HEVC extension" prompt. Do not ship libde265 on Windows.

### 2.3 Subtitles

libass (ISC) is the only renderer that handles full ASS/SSA typesetting (karaoke, animated tags, embedded fonts). Platform renderers (Media3 `SubtitleView`, AVPlayer legible output, MF timed text) cannot. libass on mobile needs font fallback configured: pass a bundled default font plus the system font directory to `ass_set_fonts()`; on iOS use the CoreText provider that libass ships [S36].

---

## 3. Audio engines, DSP, metadata, services

| Component | Version / date | Licence | Notes |
|---|---|---|---|
| **libmpv as audio engine** | 0.41.0 | LGPL | Gapless by default (`--gapless-audio`), ReplayGain, `--af=lavfi=[…]` for EQ/loudnorm, `scaletempo2` for tempo/pitch, **`--ao=wasapi --audio-exclusive=yes`** and **`--ao=coreaudio --audio-exclusive=yes`** give bit-perfect on Windows/macOS, `ao_aaudio` new in 0.41 on Android [S32]. DSD plays via FFmpeg's `dsd_*` decoders (converted to PCM; native DoP needs a custom AO). Using one engine for video and audio removes a second decode stack. |
| **miniaudio** | **0.11.25 (3 Mar 2026)**; CVE-2026-32837 (WAV BEXT OOB read) fixed only in post-0.11.25 commits; 0.12 will split into `.c/.h` [S52] | MIT-0 / public domain | Only needed if you build your own audio pipeline (e.g., Android bit-perfect path). |
| **Oboe / AAudio** | Apache-2.0; AAudio on API 27+, OpenSL ES on 16+ [S53] | Apache-2.0 | Android low-latency output. |
| **Android bit-perfect USB** | `AudioManager.setPreferredMixerAttributes()` + `AudioMixerAttributes.MIXER_BEHAVIOR_BIT_PERFECT` (API 34, Android 14) lets an app bypass AudioFlinger resampling on USB devices [S54]. Field reports (Symfonium users on Pixel 8 Pro / FiiO) show 44.1 kHz sometimes still forced to 48 kHz while ≥ 88.2 kHz passes [S54]. UAPP's pre-Android-14 approach is a user-space USB driver (`UsbManager` bulk transfers) — large effort, OEM-specific. | — | Implement the Android-14 API first; treat a user-space USB driver as a later, optional module. |
| **AVAudioEngine / AVAudioSession** | iOS 26 | Apple | Background audio category, Now Playing, AirPlay routing. libmpv's `ao_avfoundation`/`ao_audiounit` sit under it. |
| **WASAPI** | — | — | Exclusive mode through mpv; SMTC via `SystemMediaTransportControls` from the host app. |
| **SoundTouch** | 2.x | **LGPL-2.1+** (no commercial exemption found) [S55] | Redundant when using mpv's `scaletempo2`. |
| **libebur128** | 1.2.x | MIT | For loudness scanning of a library (ReplayGain 2.0 / R128) during indexing. *(Licence from project knowledge; not re-fetched.)* |
| **TagLib** | **2.1.1 (30 Jun 2025)** | **LGPL-2.1-only OR MPL-1.1** (SPDX disagreement between distros; upstream header offers the choice; Yocto chose LGPL-2.1-only) [S56] | Reference tagger; C++ → needs FFI. Auxio uses it through native code [S57]. |
| **lofty-rs** | active (1,998 commits, MSRV 1.89) | MIT OR Apache-2.0 | Rust; MP3/FLAC/MP4/OGG/Opus/WAV/AIFF/APE/WavPack/AAC/MPC/Speex [S58]. Preferable to TagLib licence-wise if a Rust core exists. |
| **mutagen** | — | GPL-2+ | Python only; not applicable. |
| **Chromaprint / AcoustID** | **1.6.2 (15 Oct 2026)**; needs raw PCM input (decode yourself) [S59] | LGPL-2.1+ (library) | AcoustID web service requires a free app key; non-commercial use is free *(terms page not fetched)*. |
| **LRCLIB** | beta API; **no API key, no rate limit** stated; breaking changes possible [S60] | public service | Send a descriptive `User-Agent`. |
| **ListenBrainz** | token in `Authorization: Token …`; ≤ 1 req/s; `User-Agent` with app name/version/contact mandatory [S61] | GPL-2 server, open API | Also offers a Last.fm-compatible submission endpoint *(not fetched)*. Last.fm scrobbling needs an API key/secret and user auth (web flow). |

---

## 4. Image engines and gallery

| Component | Version / date | Licence | Evidence / notes |
|---|---|---|---|
| **libvips** | **8.18 (4 Dec 2025)** | LGPL-2.1+ | 2025 Southampton preprint: "at least twice as fast as any other system tested, typically 5–10× less memory" (libvips 8.16 ≈ 91 MB peak RSS vs ImageMagick 6.9.12 ≈ 2 GB on the same task). Shrink-on-load for JPEG/WebP/HEIF/JXL makes thumbnailing cheap. Loads JPEG, JPEG XL, TIFF, PNG, WebP, HEIC/AVIF (via libheif), SVG, GIF, PDF, OpenEXR; no RAW without ImageMagick/LibRaw plug-in [S62][S63]. No official mobile builds — must be cross-compiled (Meson). |
| **ImageMagick** | 7.x | ImageMagick (Apache-2-like) | Slowest/most memory in every benchmark found [S63]; avoid. |
| **Skia** | via Flutter/CMP | BSD-3 | Fine for decode of PNG/JPEG/WebP/GIF but no JXL/AVIF/HEIF/RAW, no tiled pyramid loader. |
| **libjxl** | **0.12.0 (1 Jul 2026)**; 0.11.2 (Feb 2026) [S64] | BSD-3 | Only way to view JPEG XL on Android/Windows; Apple ImageIO decodes JXL natively since iOS 17/macOS 14. |
| **libavif + dav1d** | **1.4.2 (26 May 2026)** [S65] | BSD-2 | Android 12+ decodes AVIF natively; Windows via AV1 Video Extension; Apple since iOS 16. |
| **libheif / libde265** | 1.2x | LGPL-3 | See §2.2 — patents live in the codec, not libheif. Prefer platform decoders. |
| **LibRaw** | **0.22.2** | LGPL-2.1 OR CDDL-1.0; site warns licensing may change and advises against anonymous public-service use [S66] | RAW thumbnails + full decode for CR2/CR3/NEF/ARW/DNG. |
| **Exiv2** | 0.28.9 (page updated 30 Aug 2026) | **GPL-2.0-or-later** (commercial licence historically available) *(licence not stated on homepage; from project knowledge)* [S67] | **GPL — do not link into a store-distributed binary unless the whole app is GPL.** Use platform EXIF (ImageIO, `ExifInterface`, WIC) + a small MIT XMP parser, or `kamadak-exif`/`little_exif` (Rust, MIT/Apache). |
| **Coil 3** | 3.6.3, Apache-2.0, Android + Compose Multiplatform [S68] | Apache-2.0 | Relevant only on the KMP fallback. |
| **Glide** | 4.x | BSD/Apache | What photo_manager uses for Android thumbnails [S7]. |
| **Platform frameworks** | ImageIO/PhotoKit (Apple), MediaStore + `ImageDecoder`/`ThumbnailUtils` (Android), WIC/`StorageItemThumbnail` (Windows) | OS | Always first choice for thumbnails: the OS already caches them. |

**Fast gallery scrolling:** (1) ask the OS for its cached thumbnail first (`PHCachingImageManager`, `ContentResolver.loadThumbnail`, `StorageFile.GetThumbnailAsync`); (2) keep a disk LRU of 256 px/512 px WebP thumbs keyed by (path, mtime, size) generated with libvips shrink-on-load; (3) prefetch ±2 screens; (4) decode on a worker isolate/thread, never on the UI thread.
**100 MP images:** build an on-demand pyramid: decode at 1/8, 1/4, 1/2 scale via `vips_thumbnail` (`JPEG shrink-on-load` is free), tile the full-res level in 512 px tiles, and let the viewer request tiles for the visible rect at the current zoom (the approach of `subsampling-scale-image-view` on Android and `CATiledLayer` on Apple). libvips' `dzsave` produces this pyramid directly.

**Precedent formats support:** Fossify Gallery (GPL-3, 3.8k stars) lists JPEG XL, RAW, SVG, GIF, AVIF, MP4/MKV [S69]; Aves (BSD-3, Flutter + Kotlin, 5.4k stars) handles multi-page TIFF, SVG, motion photos, panoramas, GeoTIFF and is the closest architectural precedent for a Flutter gallery [S70].

---

## 5. Network and protocol libraries

| Protocol | Library | Licence | Mobile/desktop | Notes |
|---|---|---|---|---|
| **SMB2/3** | **libsmb2** (C) | LGPL-2.1 | Android, iOS, macOS, Windows, Linux [S71] | AMSMB2 (Swift wrapper, MIT, 4.0.3 Aug 2025) states that static linking makes the whole project LGPL and that **App Store distribution requires dynamic linking** [S71]. smbj/jcifs-ng (Apache-2/LGPL) are JVM-only — only relevant on the KMP fallback. |
| **NFS** | **libnfs** | repo sidebar says GPL-3.0 but LGPL-2.1 and BSD files are also present — the library is LGPL-2.1, the utilities GPL-3; verify per file before linking | Android, iOS, Windows, macOS; NFSv3 default, v4.0/v4.2 selectable [S72] | |
| **WebDAV / HTTP** | Dart `http`/`dio`, or libcurl | MIT/BSD | all | mpv itself streams HTTP(S) directly. |
| **FTP/SFTP** | libssh2 (BSD-3) / libcurl | BSD | all | sshj is JVM-only. |
| **DLNA/UPnP** | **jUPnP** (Java, CDDL-1.0, fork of unmaintained Cling) [S73]; libupnp (BSD) / GUPnP (LGPL) for C | — | jUPnP only on JVM/Android | For a Dart app: implement SSDP + SOAP in Dart (small) or bind libupnp. |
| **Chromecast** | Official Cast SDK is **Android/iOS/web only** [S74]. Chromium's **Open Screen `libcast`** is an open-source C++ sender/receiver implementation of the Cast protocols [S74] | BSD (Open Screen) | Desktop: Open Screen, or a Dart port of the (reverse-engineered) CASTV2 protocol | Google Play policy requires the official SDK for Cast on Android. |
| **AirPlay** | Apple-only sender API (`AVRoutePickerView`, `AVPlayer.allowsExternalPlayback`). Open implementations (shairport-sync, UxPlay) are *receivers*; AirPlay 2 sender is encrypted/undocumented | — | Apple only | No legal non-Apple sender. |
| **Jellyfin / Emby / Plex / Subsonic** | REST; jellyfin-sdk-kotlin (LGPL-3, JVM+Android, OpenAPI-generated) [S14]; for Dart generate from `openapi.json` | — | all | Finamp (Flutter, MPL-2.0, 4.3k stars) proves a Flutter Jellyfin client on Android/iOS/Windows/macOS/Linux [S75]. |
| **Cloud drives** | Vendor SDKs vs. plain OAuth2 + REST | — | all | Prefer plain REST (Google Drive v3, Microsoft Graph, Dropbox v2) to avoid heavy SDKs. |
| **Torrent** | libtorrent-rasterbar (BSD-3) | BSD | — | **Excluded**: store policy risk and legal exposure; app ships BitTorrent-free. |

---

## 6. Platform constraints (2025–2026)

| Platform | Constraint | Source |
|---|---|---|
| **iOS/iPadOS** | Uploads must be built with **Xcode 26 / iOS 26 SDK from 28 Apr 2026**; minimum deployment target **iOS 13+ from 9 Sep 2026** [S76]. Liquid Glass is the iOS 26 design language — a Flutter app renders its own chrome, so adopt it via `CupertinoNavigationBar`-style translucency rather than UIKit. Background audio = `audio` background mode + `AVAudioSession(.playback)`; PiP via `AVPictureInPictureController` (needs an `AVSampleBufferDisplayLayer` or `AVPlayerLayer`; with libmpv use the sample-buffer path). | |
| **Android** | **Target API 36 (Android 16) required for new apps/updates from 31 Aug 2026** (extension to 1 Nov 2026) [S77]. **16 KB page size:** all apps targeting API 35+ must ship 16 KB-aligned `.so`; **updates blocked from 1 Feb 2027**; NDK r28+ aligns by default, r27 and older need `-Wl,-z,max-page-size=16384`; AGP ≥ 8.5.1 with uncompressed JNI libs [S78]. Every prebuilt (libmpv, FFmpeg, libvips, libsmb2) must be rebuilt with NDK r28+. Media3 `MediaSessionService` is required for Android Auto/Wear/Assistant integration even if libmpv does playback. Material 3 Expressive is the Android 16 look *(details page not readable in this pass)*. | |
| **macOS** | macOS 26; same Xcode 26 requirement; notarisation via `notarytool`; "Now Playing" via `MPNowPlayingInfoCenter`/`MPRemoteCommandCenter`. Hardened runtime + sandbox: a libmpv build with LuaJIT statically linked crashes under the Mac App Store sandbox unless JIT entitlements are handled — disable Lua/JS scripting in the LGPL build [S79]. | |
| **Windows** | Windows App SDK 2.x (2.0 GA Apr 2026, 2.5.1 Sep 2026) [S28]; SMTC via `Windows.Media.SystemMediaTransportControls` (usable from Win32/Flutter via WinRT interop); HDR output needs the swap chain in `R16G16B16A16_FLOAT`/`R10G10B10A2` with the display in HDR mode — libmpv's D3D11/Vulkan VO handles this. MSIX for Store, plus an unpackaged installer. | |
| **120 Hz UI** | Flutter/Impeller renders at display refresh; on iOS add `CADisableMinimumFrameDurationOnPhone=true` to Info.plist for ProMotion. Video is composited at its own cadence via the texture; enable mpv `video-sync=display-resample` only on desktop. | |
| **Thermal/battery** | Always prefer hwdec (`hwdec=auto-safe`), `vd-lavc-dr=yes`, avoid `gpu-next` HQ scalers on mobile by default, cap `--vo` to 60 Hz presentation for 24/30 fps content, suspend render when backgrounded (`--vo=null` swap). | |
| **App size target** | Flutter base ≈ 4–6 MB per ABI; libmpv+FFmpeg (LGPL, no encoders, hw-first) ≈ 15–25 MB per ABI; libvips+libjxl+libavif ≈ 6–8 MB. Ship Android as AAB with ABI splits; iOS thinning does the rest. Expect **~35 MB installed on mobile, ~60 MB desktop**. *(Estimates; measure in CI.)* | |

---

## 7. Build, CI, telemetry, testing

| Topic | Choice | Evidence |
|---|---|---|
| **CI** | GitHub Actions: `ubuntu-latest` for Android, `windows-latest` for Windows, `macos-15` (Apple-silicon) for iOS/macOS. Rates: Linux 2-core $0.006/min, Windows $0.010/min, **macOS $0.062/min**; free for public repos, 2,000 min/month on private Free plan [S80]. Budget: an iOS+macOS matrix at ~25 min each ≈ $3/run on a private repo → keep the repo public (the app is free/OSS anyway). | |
| **Native prebuilts** | Build libmpv/FFmpeg/libvips once per platform in a separate "deps" repo with its own Actions workflow (NDK r28, Xcode 26, MSVC 2022 + Meson/Ninja); publish as GitHub Release assets with SHA-256; app repo downloads by version pin. This isolates the agent from the most fragile part of the toolchain. | |
| **Signing** | Fastlane `match` (git-backed, encrypted) for Apple; Play App Signing + upload key in Actions secrets; Windows: Azure Trusted Signing or a self-signed cert for sideload builds and Store signing for MSIX. | |
| **Crash reporting** | **Sentry** (Flutter SDK; self-hostable under FSL, converts to Apache-2 after 2 years; self-host needs 4 cores / 16 GB RAM + 16 GB swap / 20 GB disk, community support only) [S81]. Crashlytics rejected (Google account linkage, no self-hosting). GlitchTip is the lighter MIT-licensed alternative if Sentry's footprint is too large. **Opt-in only.** | |
| **Analytics** | **Aptabase**: no device IDs/cookies/fingerprints, IP discarded after deriving country + daily rotating hash; SDKs for Flutter, Swift, Kotlin, .NET, React Native, Tauri, Electron; server AGPL-3, SDKs MIT; free tier 20k events/month [S82]. TelemetryDeck (on-device anonymisation, Swift/Kotlin/Flutter/RN SDKs) is the alternative [S83]. Plausible is web-oriented. **Opt-in toggle, default off.** | |
| **Feature flags** | Local JSON in the app bundle + remote override from a static file on the project's GitHub Pages (no third-party SaaS). | |
| **Tests** | Dart unit tests; `flutter_test` widget tests; `integration_test` on emulators (Android), simulators (iOS/macOS) and Windows desktop in Actions; golden tests for UI; a small corpus of sample media (HDR10, DV p5/p8, 10-bit HEVC, ASS, FLAC gapless, JXL, 100 MP TIFF) checked via SHA into a `test-media` LFS folder. | |
| **Agent ergonomics** | One language (Dart) for UI, state and most logic; C via `dart:ffi` only for libmpv render callbacks and libvips; `ffigen` generates bindings from headers so the agent never hand-writes FFI; platform channels only for MediaSession/SMTC/Now Playing/PhotoKit permissions. | |

---

## 8. Open-source precedents

| Project | Stack | What the repo/tracker teaches |
|---|---|---|
| **IINA** (macOS) | Swift + libmpv dylibs copied into the bundle; Swift option/property files generated from mpv docs; 46.8k stars, **1.9k open issues**, nightly per commit [S84] | Generated bindings from mpv docs are the right idea; shipping mpv as dylibs is LGPL-clean; "requires latest public Xcode" shows the cost of tracking Apple. |
| **mpv-android** | Kotlin + libmpv (MIT), 3.6k stars, 152 open issues, releases 2026-04-25; builds libmpv via its own `buildscripts` [S37][S38] | The canonical NDK build script for libmpv + FFmpeg + libass + libplacebo; reuse it (and its 16 KB flags). |
| **Just Player** | Media3 + FFmpeg audio extension, The Unlicense, 2.7k stars; README lists: no AVI/WMV/Theora, 10-bit AVC fails on most devices, **SSA/ASS styling limited**, document providers broken on Android TV, Android 16 orientation quirk [S45] | A precise list of what Media3 cannot do — the reason to use libmpv. |
| **NextPlayer** | Media3 + FFmpeg ext, Compose, Room, GPL-3, 4.6k stars, **455 open issues**; SMB/FTP/SFTP/WebDAV network sources, PiP, Android TV [S46] | Feature checklist for network sources and the same ASS limitation. |
| **Nova** | Media3-based *(not fetched in this pass)* | — |
| **Auxio** | **patched Media3 build** + TagLib via native code, GPL-3, 4.4k stars; full ReplayGain for MP3/FLAC/OGG/OPUS/MP4, gapless [S57] | Even a pure-Android music player had to patch Media3 — a hint that ExoPlayer is not a tagging/gapless-friendly base. |
| **Fossify Gallery** | Kotlin, GPL-3, 3.8k stars, 10k commits; JXL/AVIF/RAW/SVG/GIF [S69] | Format matrix a gallery must meet in 2026. |
| **Aves** | Flutter + Kotlin, BSD-3, 5.4k stars, 4,485 commits; multi-page TIFF, SVG, motion photos, panoramas, GeoTIFF, Android TV [S70] | Proves Flutter can host a serious gallery with native decoding plugins. |
| **Finamp** | Flutter, MPL-2.0, 4.3k stars, Android/iOS/Windows/macOS/Linux, gapless + transcoding; 337 open issues [S75] | Proves Flutter audio on all our targets; its tracker is the best source of just_audio edge cases. |
| **media_kit** | Dart + libmpv, MIT, 340 open issues / 20 PRs, still releasing (16–19 Oct) [S4][S5] | The issue backlog is large relative to maintainer count — the single biggest dependency risk in the primary stack. |
| **Symfonium / Infuse** (closed) | — | Symfonium's support forum documents Android bit-perfect failures per device (44.1 → 48 kHz on Pixel 8 Pro) [S54]; Infuse's format list is the benchmark for Apple-side expectations. |

---

## 9. Recommended architecture

```
┌──────────────────────────────────────────────────────────────────────┐
│  Flutter UI (Dart) — adaptive shells: Material 3 Expressive (Android),│
│  Cupertino/Liquid-Glass-styled (Apple), Fluent-styled (Windows)        │
├──────────────────────────────────────────────────────────────────────┤
│  App core (Dart): library index (SQLite/drift), queue, settings,       │
│  network sources, Jellyfin/Subsonic clients, lyrics, scrobbling        │
├───────────────┬───────────────────────┬──────────────────────────────┤
│ Video/Audio   │ Images                │ Platform services            │
│ libmpv (LGPL) │ libvips + libjxl +    │ MediaSession/Media3Session   │
│ via dart:ffi  │ libavif + LibRaw via  │ (Android), MPNowPlaying +    │
│ render API →  │ dart:ffi; OS decoders │ AVAudioSession + PiP (Apple),│
│ Texture widget│ first (ImageIO, Image-│ SMTC (Windows); PhotoKit /   │
│ hwdec=auto-   │ Decoder, WIC)         │ MediaStore / Windows.Storage │
│ safe, gpu-next│ tiled pyramid viewer  │ via platform channels        │
├───────────────┴───────────────────────┴──────────────────────────────┤
│ Prebuilt native deps (separate repo, NDK r28 / Xcode 26 / MSVC):       │
│ FFmpeg 8.1 LGPL (dav1d, libass, libplacebo, no GPL libs), mpv 0.41,    │
│ libvips 8.18, libjxl 0.12, libavif 1.4, LibRaw 0.22, libsmb2, libnfs    │
└──────────────────────────────────────────────────────────────────────┘
```

**Engine per platform and why**

| Platform | Video | Audio | Images/thumbs | Rationale |
|---|---|---|---|---|
| Android | libmpv (`hwdec=mediacodec`, Vulkan `gpu-next`) | libmpv `ao_aaudio`; Kotlin `setPreferredMixerAttributes` bit-perfect path for USB DACs | MediaStore + `ImageDecoder` first, libvips/libjxl fallback | Media3 cannot do ASS/HDR tone-map/AVI; mpv-android proves libmpv on Android. |
| iOS/iPadOS | libmpv (`hwdec=videotoolbox`, Metal via MoltenVK/`gpu-next`) with AVPlayer fallback for AirPlay/PiP of MP4/HLS | libmpv `ao_avfoundation` under an `AVAudioSession(.playback)` | PhotoKit + ImageIO (JXL/HEIC/AVIF native) | MPVKit/media_kit builds exist; LGPL build shipped as dynamic xcframeworks. |
| macOS | libmpv (VideoToolbox, Metal) | libmpv `coreaudio` + `audio-exclusive` | ImageIO | Same as iOS; IINA precedent. |
| Windows | libmpv (`hwdec=d3d11va`, D3D11/Vulkan `gpu-next`) | libmpv `wasapi` + `audio-exclusive` | WIC + libvips/libjxl/libavif | FFmpegInteropX unnecessary once mpv is present; SMTC from host. |

**Decision rules baked into the design**

1. OS decoder first, software second (patents, battery).
2. One media engine (libmpv) for both video and music; no ExoPlayer/AVPlayer decode paths except the AirPlay/PiP sidecar.
3. No GPL in the binary (Exiv2, SoundTouch-free, rubberband-free, x264/x265-free, smbclient-free).
4. All native code reached through `ffigen`-generated bindings, never hand-written JNI/ObjC except the three platform-service channels.
5. Telemetry off by default.

---

## 10. Licence compliance matrix

| Library | Licence | Linking requirement for a closed/any-licence app | App Store (Apple) | Google Play | Attribution |
|---|---|---|---|---|---|
| mpv (libmpv) | LGPL-2.1+ (`-Dgpl=false`) | Dynamic (`.so`/`.dylib`/`.dll`) or provide relinkable objects | OK as dynamic framework; disable LuaJIT in sandboxed builds [S79] | OK | Licence text + source offer |
| FFmpeg | LGPL-2.1+ (no `--enable-gpl`, no `--enable-nonfree`) | Dynamic | OK | OK | Licence text + exact configure line + source offer |
| libplacebo | LGPL-2.1+ | Dynamic | OK | OK | Licence text |
| libass | ISC | any | OK | OK | Notice |
| dav1d | BSD-2 | any | OK | OK | Notice |
| vvdec | BSD-3-Clause-Clear | any (no patent grant) | OK | OK | Notice; patent risk separate |
| libvips | LGPL-2.1+ | Dynamic | OK | OK | Licence text |
| libjxl | BSD-3 | any | OK | OK | Notice |
| libavif | BSD-2 | any | OK | OK | Notice |
| libheif / libde265 | LGPL-3 | Dynamic; LGPL-3 anti-tivoisation clause | Avoid on Apple (ImageIO covers HEIC) | Avoid (platform decoder) | — |
| LibRaw | LGPL-2.1 **or** CDDL-1.0 | Choose CDDL for static linking (file-level copyleft) | OK | OK | Notice |
| Exiv2 | GPL-2+ | **Incompatible** unless whole app is GPL | ✗ | ✗ | — |
| TagLib | LGPL-2.1 or MPL-1.1 | Choose MPL-1.1 → static OK | OK | OK | Notice |
| lofty-rs | MIT/Apache-2 | any | OK | OK | Notice |
| SoundTouch | LGPL-2.1+ | Dynamic | OK | OK | Not needed (use scaletempo2) |
| libebur128 | MIT | any | OK | OK | Notice |
| Chromaprint | LGPL-2.1+ | Dynamic | OK | OK | Licence text |
| libsmb2 | LGPL-2.1 | **Dynamic on iOS** (AMSMB2 README) [S71] | OK dynamic | OK | Licence text |
| libnfs (library) | LGPL-2.1 (verify per file; utilities GPL-3) | Dynamic | OK | OK | Licence text |
| libssh2 / libcurl | BSD-3 / curl | any | OK | OK | Notice |
| jUPnP | CDDL-1.0 | file-level copyleft | n/a | OK | Notice |
| Open Screen (libcast) | BSD-3 | any | n/a | n/a | Notice |
| media_kit, photo_manager, just_audio | MIT / Apache-2 / MIT+Apache | any | OK | OK | Notice |
| Flutter | BSD-3 | any | OK | OK | Notice |
| Sentry SDK | MIT | any | OK | OK | Notice |
| Aptabase SDK | MIT (server AGPL-3) | SDK any; AGPL only matters if you modify and host the server | OK | OK | Notice |
| Qt (if ever used) | LGPL-3 / commercial | Dynamic; store-policy conflict warned by Qt [S27] | risky | risky | Licence text + relink info |

**LGPL on iOS in practice:** iOS has supported embedded dynamic frameworks since iOS 8, so LGPL compliance is achieved by shipping libmpv/FFmpeg/libvips as `.xcframework` dynamic libraries inside the `.app` bundle (what MPVKit and media_kit already do) and publishing the exact build scripts. On Android, `.so` files are dynamic by construction. On Windows, ship `.dll`s next to the executable.

**Required "About → Licences" content:** full licence texts, FFmpeg configure line, link to the deps repo with sources and build scripts, and the statement that HEVC/AAC/DV decoding uses OS-provided decoders where available.

---

## 11. Risks and mitigations

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| **media_kit maintenance** (340 open issues, small maintainer set) | Medium | High | Depend on media_kit's *prebuilt libmpv packages* only; write our own ~600-line `dart:ffi` wrapper over `mpv_render_context` + Flutter `Texture` (the Dart layer is the easy part); keep a fork ready. |
| **libmpv on iOS is community-maintained** (MPVKit "not maintained very frequently"; Metal unofficial) | Medium | High | Own deps repo builds from mpv 0.41 + FFmpeg 8.1 with MoltenVK `gpu-next`; keep AVPlayer sidecar for MP4/HLS/AirPlay so the app never has zero playback. |
| **16 KB page alignment / NDK r28** | Certain | Medium | Build every `.so` with NDK r28+, run `zipalign -c -P 16` in CI; deadline 1 Feb 2027. |
| **Xcode 26 / iOS 26 SDK requirement** | Certain | Low | `macos-15`/`macos-26` runners with Xcode 26; Flutter 3.47 supports it. |
| **HEVC/AV1 pools targeting software** (Access Advance AV1 pool exploration, HEVC waiver unverified) | Low–Medium | Medium | OS decoders first; software HEVC off by default on Windows if hardware is missing; publish a codec policy. |
| **Dolby Vision p5 via libplacebo is unsigned** | Low | Low | No Dolby marks; feature labelled "DV profile 5 conversion". |
| **Android bit-perfect inconsistency** (44.1 kHz → 48 kHz on some devices) | High | Low | Surface actual device rate in UI; document per-device results; optional user-space USB driver later. |
| **Desktop JVM bloat** (fallback only) | — | — | Use `jpackage` + jlink minimal runtime if KMP is chosen. |
| **GPL contamination** | Low | High | CI licence scan (`cargo-deny`-style allowlist for Dart pub + a script that greps FFmpeg `configure` flags and the `.so` list). |
| **Windows store signing / MSIX friction** | Medium | Low | Ship unpackaged installer + winget manifest first; MSIX second. |
| **Agent toolchain drift** (Flutter quarterly releases, breaking changes) | Medium | Medium | Pin Flutter via FVM/`.fvmrc`; upgrade on a schedule with the breaking-changes page per release. |

---

## 12. Fallback stack in detail (KMP + Compose Multiplatform)

If Android-native behaviour (Media3 `MediaSessionService`, Android Auto, Wear, Material 3 Expressive components, `setPreferredMixerAttributes`) must be written in Kotlin anyway, KMP lets that code live in `androidMain` beside shared Kotlin logic, and CMP 1.12 renders iOS stably. Engine binding: libmpv via JNI (Android, reuse mpv-android's `MPVLib`), via Kotlin/Native cinterop to MPVKit (iOS/macOS), via JNA/Panama on the JVM desktop (IINA-style render-context into a Skia `Surface`). Cost: three binding layers instead of one `dart:ffi`, a JVM on desktop, and no existing library that overlays Compose on a libmpv surface on desktop (vlcj's limitation applies to the same AWT heavy-weight problem). Choose it when native Android quality outranks desktop size.

---

## Sources

- [S1] Flutter release notes index — https://docs.flutter.dev/release/release-notes
- [S2] "Impeller Now Mandatory in Flutter 2026" (vendor blog, unverified figures) — https://ecorpit.com/impeller-mandatory-flutter-android-ios-2026/
- [S3] Flutter Impeller docs/FAQ — https://docs.flutter.dev/perf/impeller ; https://flutter.googlesource.com/mirrors/engine/+show/refs/heads/main/impeller/docs/faq.md
- [S4] media_kit repository — https://github.com/media-kit/media-kit
- [S5] media_kit releases — https://github.com/media-kit/media-kit/releases
- [S6] just_audio on pub.dev — https://pub.dev/packages/just_audio
- [S7] photo_manager on pub.dev — https://pub.dev/packages/photo_manager
- [S8] mpv_audio_kit 0.4.2 changelog — https://pub.dev/packages/mpv_audio_kit/versions/0.4.2/changelog
- [S9] Compose Multiplatform 1.8.0 (iOS stable) — https://blog.jetbrains.com/kotlin/2025/05/compose-multiplatform-1-8-0-released-compose-multiplatform-for-ios-is-stable-and-production-ready/
- [S10] What's new in Compose Multiplatform 1.10 — https://kotlinlang.org/docs/multiplatform/whats-new-compose-110.html
- [S11] Compose Multiplatform releases — https://github.com/JetBrains/compose-multiplatform/releases
- [S12] ComposeMediaPlayer (kdroidFilter) — https://github.com/kdroidFilter/ComposeMediaPlayer ; Chaintech player — https://github.com/Chaintech-Network/ComposeMultiplatformMediaPlayer ; Kotlin Slack thread on vlcj overlay limitation — https://slack-chats.kotlinlang.org/t/16375442/does-compose-multiplatform-has-videoplayer
- [S13] ComposeMediaPlayer Maven listing — https://badges.mvnrepository.com/artifact/io.github.kdroidfilter/composemediaplayer/used-by
- [S14] jellyfin-sdk-kotlin — https://github.com/jellyfin/jellyfin-sdk-kotlin
- [S15] React Native releases overview — https://reactnative.dev/docs/releases
- [S16] React Native Windows blog (0.82, Paper removed) — https://devblogs.microsoft.com/react-native/
- [S17] react-native-windows releases — https://github.com/microsoft/react-native-windows/releases
- [S18] react-native-macos release tracking — https://releasealert.dev/github/microsoft/react-native-macos/links ; npm/Snyk — https://snyk.io/advisor/npm-package/react-native-macos
- [S19] expo-video docs — https://docs.expo.dev/versions/latest/sdk/video/
- [S20] react-native-video — https://github.com/TheWidlarzGroup/react-native-video
- [S21] Avalonia releases — https://github.com/AvaloniaUI/Avalonia/releases
- [S22] LibVLCSharp.Avalonia (NuGet) — https://www.nuget.org/packages/LibVLCSharp.Avalonia/ ; XDev.LibVLCSharp.MAUI — https://www.nuget.org/packages/XDev.LibVLCSharp.MAUI/
- [S23] Avalonia vs MAUI (vendor) — https://avaloniaui.net/maui-compare
- [S24] Uno Platform 6 release (InfoQ) — https://www.infoq.com/news/2025/05/uno-platform-6-release ; Uno 6.6 — https://newreleases.io/project/github/unoplatform/uno/release/6.6.166
- [S25] Uno MediaPlayerElement docs — https://platform.uno/docs/articles/controls/MediaPlayerElement.html
- [S26] Tauri mobile native-view limitation (PR discussion) — https://github.com/tauri-apps/tauri/pull/14484 ; Tauri 2.10 release — https://v2.tauri.app/release/tauri/v2.10.0/
- [S27] Qt open-source LGPL obligations — https://www.qt.io/licensing/open-source-lgpl-obligations
- [S28] Windows App SDK release channels — https://learn.microsoft.com/en-us/windows/apps/windows-app-sdk/release-channels
- [S29] FFmpegInteropX — https://github.com/ffmpeginteropx/FFmpegInteropX
- [S30] UniFFI — https://docs.rs/crate/uniffi/latest ; https://rust-digger.code-maven.com/crates/uniffi
- [S31] crux — https://github.com/redbadger/crux
- [S32] mpv RELEASE_NOTES (0.41.0) — https://github.com/mpv-player/mpv/blob/master/RELEASE_NOTES
- [S33] mpv version history summary — https://www.videohelp.com/software/mpv-media-player/version-history ; Debian 0.41.0 notes — https://sources.debian.org/src/mpv/0.41.0-2/RELEASE_NOTES
- [S34] libplacebo — https://github.com/haasn/libplacebo ; DV profile 5/8 commit history — https://code.videolan.org/videolan/libplacebo/-/merge_requests/207/commits
- [S35] libass releases — https://github.com/libass/libass/releases
- [S36] libass 0.17.x changelog (openSUSE) — https://src.opensuse.org/rpm/libass/src/branch/devel/libass.changes
- [S37] mpv-android — https://github.com/mpv-android/mpv-android
- [S38] mpv-android on F-Droid (2026-04-25 release) — https://cloudflare.f-droid.org/ko/packages/is.xyz.mpv
- [S39] MPVKit — https://github.com/mpvkit/MPVKit
- [S40] media-kit libmpv-darwin-build — https://libraries.io/go/github.com%2Fmedia-kit%2Flibmpv-darwin-build
- [S41] FFmpeg news (8.0, 8.1) — https://ffmpeg.org/
- [S42] FFmpeg licence/GPL component list (Qt republication of FFmpeg LICENSE.md) — https://doc.qt.io/qt-6.10/qtwebengine-3rdparty-ffmpeg.html
- [S43] VLCKit on CocoaPods (4.0.0a18) — https://cocoapods.org/pods/VLCKit ; MobileVLCKit — https://cocoapods.org/pods/MobileVLCKit ; VLCKit NEWS — https://code.videolan.org/videolan/VLCKit/-/raw/master/NEWS
- [S44] Media3 1.8.0 — https://android-developers.googleblog.com/2025/08/media3-180-whats-new.html ; 1.9.0-alpha01 — https://newreleases.io/project/github/androidx/media/release/1.9.0-alpha01
- [S45] Just Player — https://github.com/moneytoo/Player
- [S46] NextPlayer — https://github.com/anilbeesetti/nextplayer
- [S47] Media3 FFmpeg decoder extension README — https://github.com/androidx/media/blob/release/libraries/decoder_ffmpeg/README.md
- [S48] dav1d tags — https://github.com/videolan/dav1d/tags
- [S49] dav1d 1.5.0 notes (VideoLAN tags) — https://code.videolan.org/videolan/dav1d/tags
- [S50] vvdec — https://github.com/fraunhoferhhi/vvdec
- [S51] Access Advance HEVC Advance overview Nov 2025 — https://accessadvance.com/wp-content/uploads/2025/07/HEVC-Advance-Program-Overview-November-2025-v3.pdf ; new licensees July 2026 — https://secure.businesswire.com/news/home/20260707864649/en/ ; AV1/AV2 pool exploration Aug 2026 — https://secure.businesswire.com/news/home/20260825292774/en/ ; older software-royalty waiver report — https://www.streamtvinsider.com/cable/hevc-advance-seeks-to-speed-up-codec-adoption-by-waiving-select-software-royalties
- [S52] miniaudio releases — https://releasealert.dev/github/mackron/miniaudio ; Debian security tracker (CVE-2026-32837) — https://security-tracker.debian.org/tracker/source-package/miniaudio
- [S53] Oboe — https://github.com/google/oboe
- [S54] Android preferred mixer attributes — https://source.android.com/docs/core/audio/preferred-mixer-attr ; Android Authority audiophile guide — https://www.androidauthority.com/android-audiophile-guide-3611225/ ; Symfonium reports — https://support.symfonium.app/t/usb-exclusive-mode-not-working-15-02-beta-pixel-8-pro-qudelix-5k/14023 ; https://support.symfonium.app/t/dac-usb-bit-prefect-improve-audio/12326
- [S55] SoundTouch licence (Debian copyright) — https://metadata.ftp-master.debian.org/changelogs/main/s/soundtouch/stable_copyright
- [S56] TagLib 2.1 release / licence — https://habr.com/en/news/914616 ; PTXdist licence note — https://lore.ptxdist.org/ptxdist/20251026203253.980366-1-m.olbrich@pengutronix.de/ ; Alpine package — https://pkgs.alpinelinux.org/package/edge/community/armv7/libtag
- [S57] Auxio — https://github.com/OxygenCobalt/Auxio
- [S58] lofty-rs — https://github.com/Serial-ATA/lofty-rs
- [S59] Chromaprint — https://acoustid.org/chromaprint
- [S60] LRCLIB API docs (via lrclib client docs) — https://docsearch.algolia.com/mcp/docs/repo/tranxuanthang/lrclib ; https://lrclibapi.readthedocs.io/en/v0.3.1/lrclib.html
- [S61] ListenBrainz API — https://listenbrainz.readthedocs.io/en/latest/users/api/index.html
- [S62] libvips — https://www.libvips.org/
- [S63] libvips vs ImageMagick benchmarks: Southampton 2025 preprint — https://southampton.ac.uk/~km2/papers/2025/vips-ist-preprint.pdf ; Criteo — https://medium.com/criteo-labs/boosting-image-processing-performance-from-imagemagick-to-libvips-268cc3451d55
- [S64] libjxl releases — https://github.com/libjxl/libjxl/releases
- [S65] libavif releases — https://github.com/AOMediaCodec/libavif/releases
- [S66] LibRaw — https://www.libraw.org/
- [S67] Exiv2 — https://exiv2.org/
- [S68] Coil — https://coil-kt.github.io/coil/
- [S69] Fossify Gallery — https://github.com/FossifyOrg/Gallery
- [S70] Aves — https://github.com/deckerst/aves
- [S71] libsmb2 — https://github.com/sahlberg/libsmb2 ; AMSMB2 (dynamic-linking note) — https://github.com/amosavian/AMSMB2
- [S72] libnfs — https://github.com/sahlberg/libnfs
- [S73] jUPnP — https://github.com/jupnp/jupnp
- [S74] Google Cast SDK — https://developers.google.com/cast ; Open Screen libcast — https://chromium.googlesource.com/openscreen/+/HEAD/cast/README.md
- [S75] Finamp — https://github.com/jmshrv/finamp
- [S76] Apple upcoming requirements (Xcode 26 by 28 Apr 2026; iOS 13 min by 9 Sep 2026) — https://developer.apple.com/news/upcoming-requirements/
- [S77] Google Play target API requirements (API 36 by 31 Aug 2026) — https://developer.android.com/google/play/requirements/target-sdk
- [S78] Android 16 KB page sizes — https://developer.android.com/guide/practices/page-sizes
- [S79] Shipping a libmpv player on the Mac App Store (LuaJIT/JIT entitlement crash) — https://dev.to/yamayu-dev/shipping-a-libmpv-based-video-player-on-the-mac-app-store-1f2l
- [S80] GitHub Actions billing — https://docs.github.com/en/billing/managing-billing-for-your-products/managing-billing-for-github-actions/about-billing-for-github-actions
- [S81] Sentry self-hosted — https://develop.sentry.dev/self-hosted/
- [S82] Aptabase — https://aptabase.com/
- [S83] TelemetryDeck — https://telemetrydeck.com/
- [S84] IINA — https://github.com/iina/iina
