# 11 — QA and Testing Strategy

Version 1.0 · 2026-10-19 · Every acceptance criterion in doc 04 maps to at least one automated test; manual device passes cover what automation cannot (HDR on real panels, Bluetooth, casting to real receivers, car head units).

## 1. Test pyramid

| Layer | Tooling | Scope | Gate |
|---|---|---|---|
| Unit | `dart test` | Parsers (tags, subtitles, playlists, XMP), smart-rule engine, filename parser, queue logic, DSP math (EQ coefficients, R128), settings, managed-config overlay, server client mappers | Every PR, 100 % of core packages; coverage ≥ 85 % on `core/`, `mediahro_subtitles`, `mediahro_servers` |
| FFI contract | `dart test` with native libs | mpv property/command round-trips, vips decode of each format, smb2/nfs/curl virtual-file read/seek, archive listing | Every PR (desktop runners) |
| Widget / golden | `flutter_test` | Every screen per platform family theme, light/dark, 3 text scales, RTL, reduced motion | Every PR; goldens per platform family |
| Integration | `integration_test` on emulator/simulator/desktop | End-to-end flows: open file → play → seek → subtitle → PiP; add SMB source → scan → play; music queue/gapless; gallery scroll; vault; IAP sandbox; managed config | Every PR (smoke) + nightly (full) |
| Media corpus | custom harness driving `MpvEngine` headless | Every corpus file: opens, first frame ≤ 500 ms, no decode errors, correct track counts, HDR type detected, seeks to 10 points, plays 10 s without drops > 1 % | Nightly + release |
| Performance | perf harness (Android Perfetto/Macrobenchmark, Xcode XCTest metrics/Instruments, Windows ETW/PerfView, Flutter DevTools timeline) | Budgets in §5 | Every PR (desktop), nightly (devices), release |
| Fuzzing | libFuzzer on native parsers (via `mediahro-deps`), Dart fuzz harness for subtitle/playlist/XMP/M3U | Crash-free on 1 M iterations per target | Nightly |
| Accessibility | Flutter semantics tests; Android Accessibility Scanner; Xcode Accessibility Inspector audit; Windows Accessibility Insights | 100 % labelled controls, focus order, contrast | Every PR (semantics), release (manual) |
| Security | dependency audit, SBOM diff, secrets scan, sandbox escape checks for parsers | No criticals | Every PR |
| Localisation | pseudo-locale run (expanded strings, RTL), missing-string check | No truncation of primary labels at 200 % | Every PR |
| Manual device matrix | checklists per platform (§4) | HDR panels, BT, casting, car, external displays, foldables, store IAP sandbox | Beta + release |

## 2. Test media corpus (`test-media/`, Git LFS, licences recorded)

| Category | Files (minimum) |
|---|---|
| Containers | MKV (multi-track, chapters, attachments/fonts, ordered chapters), MP4 (hvc1/hev1, fragmented, edit lists), MOV (ProRes), WebM (VP9/AV1/Opus), AVI (no index, OpenDML > 4 GB), WMV/ASF, FLV, TS/M2TS (interlaced, multiple programs), MPG/VOB + VIDEO_TS folder, BDMV folder, OGV, 3GP, RMVB, MXF, CUE+FLAC, M3U/PLS/XSPF |
| Video codecs | H.264 (8-bit, 10-bit, 4:2:2, VFR), HEVC (8/10-bit, 4:2:0/4:2:2, HDR10, HLG, HDR10+, DV P5, DV P8.1, DV P8.4, DV P7 MEL/FEL), AV1 (8/10-bit, film grain, HDR), VP8/9, VVC, MPEG-2 interlaced, VC-1, ProRes 422/4444, DNxHD, Theora, MJPEG, FFV1, HAP; resolutions 240p→8K; frame rates 23.976/24/25/29.97/30/48/50/59.94/60/120 |
| Audio codecs | AAC-LC/HE/HEv2, AC-3 5.1, E-AC-3 7.1 (JOC), TrueHD 7.1, DTS 5.1, DTS-HD MA, DTS:X, FLAC 16/24/32-bit up to 768 kHz, ALAC, WAV/AIFF 32-bit float, Opus, Vorbis, MP3 (with LAME gapless tags), WavPack, APE, TTA, TAK, MPC, DSF/DFF DSD64–512, SACD ISO, WMA, MOD/XM/IT/S3M, MIDI; gapless album (10 tracks); crossfade cases; ReplayGain-tagged set; CUE-split album |
| Subtitles | SRT (UTF-8/BOM/Windows-1251/GBK/Shift-JIS), VTT, ASS (karaoke, animations, embedded fonts, positioning), SSA, SMI, MicroDVD, TTML, PGS (SDR + HDR), VobSub, DVB; out-of-sync pairs for auto-sync; image subs for OCR in 6 scripts |
| Images | JPEG (baseline, progressive, CMYK, 12-bit, EXIF orientations 1–8, gain map), PNG/APNG, GIF animated, WebP (animated, lossless), AVIF (animated, HDR), HEIC (sequence, Live Photo pair), JXL (lossless, animated, HDR), SVG, TIFF (multi-page, 16-bit, 100 MP, 500 MP), BMP, ICO, PSD/PSB, EXR, DDS, TGA, PNM, QOI, RAW from 12 cameras (CR2/CR3/NEF/ARW/DNG/RAF/ORF/RW2/PEF/SRW), Motion Photo (JPEG+MP4, HEIC+MP4), panorama with GPano XMP; XMP sidecars; IPTC; GPS; duplicate sets (exact, resized, re-encoded) |
| Network | Docker compose: Samba (SMB2/3, DFS), NFSv3/v4, WebDAV (Nextcloud), vsftpd/FTPS, OpenSSH SFTP, MiniDLNA, Jellyfin, Emby (trial), Navidrome, Immich, Audiobookshelf, HLS/DASH origin, RTSP server; throttled/lossy network profiles |
| Malformed | Truncated files, wrong extensions, zero-byte, 10 GB sparse, zip bombs (archives), oversized subtitle files, malformed EXIF |

## 3. Device and OS matrix

| Platform | Automated | Manual (beta/release) |
|---|---|---|
| Android | Emulator API 36 (16 KB page image), API 34, API 29 (min); x86_64 + arm64 | Pixel 9 (HDR OLED, Android 16), Galaxy S24 (One UI, HDR10+), a 2022 mid-range (Snapdragon 6-series, 120 Hz LCD), a 2019 low-end (API 29, 3 GB), Pixel Fold/Galaxy Z Fold (postures), Galaxy Tab S9, Android TV box (Google TV, Chromecast with Google TV, Shield), Fire TV Stick 4K, Android Auto head unit/emulator, Wear OS (1.1) |
| iOS/iPadOS | Simulators iOS 26/18/16 | iPhone 17 Pro (ProMotion, HDR), iPhone 13 (min realistic), iPhone SE (small), iPad Pro M4 (Stage Manager, external display), iPad 9th gen, Apple TV 4K (1.1), Vision Pro compatibility (sim), CarPlay (sim + car) |
| macOS | macOS 26 runner (Apple silicon) | MacBook Pro M3 (XDR HDR), Intel Mac (until macOS 27), Studio Display, external HDR monitor, AirPlay to Apple TV |
| Windows | Windows 11 25H2 runner | Windows 11 desktop with NVIDIA/AMD/Intel GPUs, HDR monitor, Surface (ARM64, pen/touch), USB DAC, ASIO device, Windows 10 22H2 (if supported) |
| Receivers | — | Chromecast (Google TV), Chromecast Audio, DLNA TV (Samsung/LG), Sonos (DLNA), AirPlay 2 speaker, Bluetooth headphones (SBC/AAC/LDAC/aptX), USB DACs (3) |

## 4. Manual checklists (per release)

- **HDR:** HDR10/HLG/HDR10+/DV P5/P8/P7 files on each HDR panel: no washed-out colours, correct peak, no banding; SDR panels: tone mapping presets look correct; info overlay reports the path.
- **Audio:** passthrough on HDMI/USB (A M W); bit-perfect indicator truthful on 44.1/48/96/192 kHz and DSD; BT first-second not cut; A/V sync within 40 ms on BT with offset; audio focus/interruptions.
- **Casting:** every corpus container to Chromecast (passthrough/remux/transcode paths), AirPlay, DLNA; subtitles present; seek; queue; volume.
- **Storage/permissions:** fresh install flows on each OS incl. denied/limited permissions; SD card and USB-OTG; Files app open-in-place; sandbox bookmarks persist across relaunch.
- **Car/TV:** Android Auto browse tree and voice; CarPlay templates; TV remote navigation (compat mode).
- **Battery:** 1 h 4K HEVC playback drain vs stock player on the same device (A, I); thermal behaviour with shaders.
- **Accessibility:** VoiceOver/TalkBack/Narrator full-flow walkthrough; switch control; 200 % text; captions styles.
- **Store flows:** IAP sandbox tips and subscription; restore; storefront-gated links; managed-config profile applied via MDM test tenant; kiosk lock-task.
- **Localisation:** 12 languages visual review; RTL.

## 5. Performance budgets (CI-enforced; fail on > 5 % regression)

Size ceilings follow the measured full-feature build and never justify cutting a doc 04 feature (ADR-020); growth above 5 % must raise `tools/perf/baseline.json` in the same PR with feature-ID justification. Speed and memory budgets are never relaxed.

| Metric | Mobile (2022 mid-range) | Desktop |
|---|---|---|
| Cold start to interactive | ≤ 1.5 s | ≤ 1.0 s |
| Open → first frame (local 4K HEVC) | ≤ 500 ms | ≤ 300 ms |
| Seek latency (local) | ≤ 150 ms | ≤ 100 ms |
| Gallery scroll (50 k items) | 0 jank frames > 16 ms over 10 s at 60 Hz; ≤ 1 % at 120 Hz | same |
| 100 MP image open → interactive | ≤ 800 ms | ≤ 400 ms |
| Library scan 10 k files | ≤ 30 s | ≤ 10 s |
| Search latency | ≤ 50 ms | ≤ 30 ms |
| Idle RAM | ≤ 120 MB | ≤ 150 MB |
| 4K playback RAM | ≤ 350 MB | ≤ 500 MB |
| Install size | Android ≤ 75 MB per ABI (ADR-019); iOS ≤ 80 MB thinned (ADR-024) | macOS ≤ 175 MB universal (ADR-024); Windows ≤ 70 MB |
| Play download size (reported, not gated) | per ABI from the AAB, every build | — |
| Dropped frames (4K60 hwdec) | ≤ 0.5 % | ≤ 0.1 % |

## 6. Bug severity and SLAs

| Severity | Definition | Policy |
|---|---|---|
| P0 | Crash on launch, data loss, security, store-policy violation | Hotfix within 48 h; blocks release |
| P1 | Core AC fails on any platform (file doesn't play, library broken, casting fails) | Fixed before release; blocks gate |
| P2 | Degraded experience with workaround | Next train |
| P3 | Cosmetic | Backlog |

## 7. Release gates (all must pass)

1. All doc 04 `1.0` AC tests green on all listed platforms.
2. Media corpus 100 % pass (nightly report attached to the release).
3. Performance budgets met on the reference devices.
4. Zero P0/P1 open.
5. Crash-free sessions ≥ 99.5 % over the beta period (≥ 500 beta users across platforms).
6. Accessibility audit complete; conformance report updated.
7. Licence scan and SBOM clean; configure flags verified.
8. Store checklists (doc 07 §7) complete; metadata and screenshots reviewed.
9. Localisation complete for the 12 launch languages (100 % strings, visual review).
10. Security review of new network/parsing code; fuzz targets stable.
11. Release notes written; rollback plan noted.
12. Human owner sign-off.
