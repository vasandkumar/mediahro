# 05 — Technical Architecture

Version 1.0 · 2026-10-19 · Synthesises `research/04` and `research/03`. This document is normative for the build; deviations require an ADR entry (§12).

## 1. Architecture at a glance

```
┌───────────────────────────────────────────────────────────────────────────────┐
│  UI — Flutter 3.47+ (Dart), Impeller, 120 Hz                                   │
│  Adaptive shells: Material 3 Expressive (Android) · Cupertino/Liquid Glass     │
│  styling (iOS, macOS) · Fluent (Windows) · Leanback/10-foot (TV, 1.1)          │
├───────────────────────────────────────────────────────────────────────────────┤
│  Application layer (Dart) — feature modules                                     │
│  video · music · photos · library · sources · servers · cast · supporter ·      │
│  settings · b2b (managed config, kiosk, control API)                            │
├───────────────────────────────────────────────────────────────────────────────┤
│  Domain/core (Dart) — pure, platform-free                                      │
│  index (drift/SQLite) · scanner · metadata parsers · playlist · queue · DSP     │
│  config · smart rules · sync engines (Jellyfin/Emby/Plex/Subsonic/Immich)      │
├─────────────────┬────────────────────────┬────────────────────────────────────┤
│ Playback engine │ Image engine           │ Platform services (native)          │
│ libmpv (LGPL)   │ libvips + libjxl +     │ Kotlin: Media3 session, SAF,        │
│ via dart:ffi,   │ libavif + LibRaw +     │   MediaStore, Cast SDK, bit-perfect │
│ mpv_render_ctx  │ libheif(platform-first)│ Swift: AVAudioSession, NowPlaying,  │
│ → Flutter       │ via dart:ffi; OS       │   PiP, PhotoKit, AirPlay, CarPlay   │
│ Texture         │ decoders first         │ C++/WinRT: SMTC, WASAPI, WIC, MSIX  │
├─────────────────┴────────────────────────┴────────────────────────────────────┤
│ Native deps (prebuilt in `mediahro-deps` repo, pinned by hash):                   │
│ FFmpeg 8.1 (LGPL config) · mpv 0.41+ · libplacebo · libass · dav1d · vvdec ·    │
│ libvips 8.18 · libjxl 0.12 · libavif 1.4 · LibRaw 0.22 · libsmb2 · libnfs ·    │
│ libcurl/libssh2 · libarchive · libebur128 · chromaprint · libopenmpt ·          │
│ whisper.cpp · uchardet · SQLite                                                 │
└───────────────────────────────────────────────────────────────────────────────┘
```

## 2. Stack decision (ADR-001)

**Decision:** Flutter (Dart) single codebase for UI and application logic on Android, iOS/iPadOS, macOS and Windows; **libmpv** as the sole video *and* audio playback engine on all four; **libvips** plus format libraries for images with OS decoders first; **thin native modules** (Kotlin, Swift, C++/WinRT) for OS integration only.

**Why:**

1. Performance in a media app is engine-dominated. libmpv 0.41 with libplacebo `gpu-next` is the only engine delivering HDR/Dolby Vision tone mapping, libass typesetting, user shaders, gapless audio and exclusive-mode output identically on all four targets. Media3/ExoPlayer (limited ASS, no AVI/WMV, SoC-dependent HDR), AVPlayer (no MKV), MediaPlayerElement and web views all fall short.
2. libmpv is already packaged for every target (media_kit prebuilts, MPVKit xcframeworks, mpv-android build scripts). Flutter's `Texture` widget composites the GPU frame without copies.
3. One language (Dart), one build tool, one CI matrix, `ffigen`-generated bindings. For a build executed by an AI agent this is the lowest-risk path to **feature parity on four platforms**.
4. Flutter with Impeller adds a few MB per ABI and renders at display refresh. Binary budget: ≤ 75 MB installed per ABI on Android (ADR-019), ≤ 40 MB thinned on iOS, ≤ 70 MB desktop (docs/11 §5).
5. Licence posture is clean: Flutter BSD, mpv/FFmpeg LGPL dynamic, no GPL in the binary.

**Rejected:** Kotlin Multiplatform + Compose (fallback; JVM on desktop, no maintained libmpv overlay binding), React Native (no desktop video engine), Avalonia/.NET MAUI (LibVLCSharp not on Avalonia mobile; libVLC lacks libplacebo-grade HDR), Uno (OS players), Tauri/Electron (webview media; Electron bloat), Qt (store/licence friction), fully native ×4 (four UIs; schedule risk), Rust core + native shells (UniFFI pre-1.0, same four-UI cost).

**Fallback trigger:** if libmpv on iOS proves unshippable (App Store rejection or Metal path instability unresolved within the milestone), the Apple platforms switch to a Swift player module (AVPlayer for native formats + libmpv via MPVKit for the rest) behind the same Dart `PlaybackEngine` interface. The interface is designed for this (§4.2).

## 3. Repository layout

```
mediahro/                              (this repo, AGPL-3.0)
├── CLAUDE.md                       agent build brief
├── docs/                           these documents
├── research/
├── app/                            Flutter application
│   ├── lib/
│   │   ├── main.dart
│   │   ├── app/                    shell, routing, theming, l10n
│   │   ├── features/               one folder per feature module (video, music, photos, library, sources, servers, cast, supporter, settings, b2b, onboarding)
│   │   ├── core/                   domain: index, scanner, models, rules, queue, dsp, sync
│   │   ├── engine/                 PlaybackEngine interface + mpv implementation (ffi)
│   │   ├── images/                 ImagePipeline interface + vips implementation (ffi)
│   │   ├── platform/               platform channel facades (media session, storage, pip, cast, keychain)
│   │   └── ui/                     design system widgets, adaptive layouts
│   ├── android/                    Kotlin modules
│   ├── ios/ · macos/               Swift modules
│   ├── windows/                    C++/WinRT modules
│   ├── test/ · integration_test/
│   └── pubspec.yaml
├── packages/
│   ├── mediahro_engine/               reusable playback core (B2B SDK), Dart API + C API
│   ├── mediahro_ffi/                  ffigen bindings (mpv, vips, jxl, avif, raw, smb2, nfs, archive, ebur128, chromaprint, openmpt, whisper, uchardet)
│   ├── mediahro_servers/              Jellyfin/Emby/Plex/Subsonic/Immich/Nextcloud/Audiobookshelf clients (OpenAPI-generated + hand-written)
│   ├── mediahro_subtitles/            parsers, auto-sync, OCR glue
│   └── mediahro_design/               tokens, themes, icons
├── deps/                           submodule → mediahro-deps (build scripts; outputs fetched as release assets)
├── tools/                          scripts: licence scan, size report, perf harness, test-media fetch
├── test-media/                     LFS pointers to the test corpus (doc 11)
├── fastlane/ · .github/workflows/
├── LICENSE (AGPL-3.0) · LICENSE-COMMERCIAL.md · TRADEMARK.md · SECURITY.md · PRIVACY.md
└── CHANGELOG.md
```

`mediahro-deps` (separate repo, scripts only, MIT) builds every native library per platform with the exact configure flags in §10 and publishes versioned, SHA-256-pinned archives; the app's build fetches them. This isolates the fragile part of the toolchain from feature work.

## 4. Playback engine

### 4.1 libmpv configuration

| Option | Value | Reason |
|---|---|---|
| `vo` | `gpu-next` | libplacebo renderer, HDR, shaders |
| `gpu-api` | Vulkan (A, W), Metal via MoltenVK (I, M; direct Metal when the upstream patch is stable), D3D11 fallback (W) | Zero-copy hwdec interop |
| `hwdec` | `auto-safe` (mediacodec, videotoolbox, d3d11va/vulkan) | OS decoders first (patents, battery) |
| `vd-lavc-dr` | yes | Direct rendering |
| `target-colorspace-hint` | yes | HDR passthrough on HDR displays |
| `tone-mapping` | `bt.2390` default, user-selectable | VID-031 |
| `hdr-compute-peak` | yes | Dynamic tone mapping |
| `ao` | aaudio (A), avfoundation/audiounit (I), coreaudio (M), wasapi (W) | AUD-040…042 |
| `audio-exclusive` | user toggle | Bit-perfect |
| `gapless-audio` | yes | AUD-002 |
| `af` | `scaletempo2` for speed; `lavfi` graph for EQ/limiter/crossfeed/R128 | AUD-005 |
| `sub-ass` | yes; `sub-font-provider` fontconfig (A, W), CoreText (I, M) | SUB-010 |
| `cache` | yes, `demuxer-max-bytes` sized by bitrate and network type | VID-006 |
| `video-sync` | `display-resample` desktop; `audio` mobile | VID-039 |
| scripting | Lua/JS **disabled** in LGPL build | Sandbox + licence |

Build: `-Dgpl=false`, FFmpeg configured without `--enable-gpl`/`--enable-nonfree`, no x264/x265/rubberband/postproc/smbclient/libdvdcss; with `libdav1d`, `libvpx`, `libopus`, `libass`, `libplacebo`, `vvdec` (optional, BSD-3-Clear), `libopenmpt`; TLS via OS (custom AVIO over platform HTTP stacks) so no OpenSSL/mbedTLS ships in our native libraries (export-compliance simplification, doc 07). Exception, stated explicitly: the Flutter engine (`libflutter.so`, `Flutter.framework`, `flutter_windows.dll`) statically contains BoringSSL for `dart:io` TLS (used by `NetworkGateway`); it is listed in the encryption inventory (ADR-017).

### 4.2 `PlaybackEngine` interface (Dart)

```dart
abstract class PlaybackEngine {
  Future<void> open(MediaSource src, {OpenOptions? opts});
  Stream<PlaybackState> get state;        // position, duration, buffering, tracks, chapters, hdr, hwdec, drops
  Future<void> play(); pause(); stop(); seek(Duration, {SeekMode mode});
  Future<void> setRate(double); setVolume(double); setAudioDelay(Duration); setSubDelay(Duration);
  Future<void> selectTrack(TrackType, int id); addExternalTrack(TrackType, Uri);
  Future<void> setVideoFilters(VideoFilterChain); setShaderPreset(ShaderPreset);
  Future<void> setAudioDsp(AudioDspChain);
  Future<Uint8List> screenshot({bool subtitles});
  int get textureId;                       // Flutter Texture
  Future<void> dispose();
}
```

Implementations: `MpvEngine` (all platforms, default). `NativeAppleEngine` is specified as the fallback (§2) and is only built if the trigger fires. The interface is also the public surface of **Mediahro Engine** (B2B-004).

### 4.3 Rendering path

- Android: `mpv_render_context` with Vulkan → `SurfaceTexture`/`HardwareBuffer` imported into Flutter's `Texture`; hwdec `mediacodec` outputs to the same surface; HDR via `SurfaceControl` HDR hints.
- iOS/macOS: Metal layer via MoltenVK (`gpu-next`) rendering into an `IOSurface`-backed `CVPixelBuffer` registered as a Flutter external texture; `AVSampleBufferDisplayLayer` mirror only for PiP (VID-067).
- Windows: D3D11 shared texture (`ID3D11Texture2D` with keyed mutex) registered with Flutter's `FlutterDesktopGpuSurfaceDescriptor`; swap chain `R10G10B10A2`/`R16G16B16A16_FLOAT` when the display is in HDR mode.

### 4.4 Audio-only mode

Music playback uses the same `MpvEngine` instance pool (one for video, one for music, so a film can pause while a track plays) with `vid=no`. Media session plumbing (SYS-001) is driven by `PlaybackState`.

### 4.5 Casting pipeline

Local HTTP server (Dart, `shelf`) exposes the current item; `CastTranscoder` chooses passthrough (MP4/H.264/AAC), remux (MKV→fMP4 via FFmpeg libavformat) or transcode (FFmpeg + hardware encoder via MediaCodec/VideoToolbox/D3D12 where available) based on receiver capabilities. Subtitles converted to WebVTT. Cast senders: Cast SDK (A I, Play/App Store flavours), Open Screen `libcast` (M W, FOSS flavour), AirPlay (I M) via `AVPlayer` on an HLS URL from the same server, DLNA via AVTransport.

## 5. Image pipeline

- `ImagePipeline` interface: `thumbnail(src, size)`, `decode(src, region, scale)`, `metadata(src)`, `encode(...)`, `edit(ops)`.
- Order of decoders: **OS first** (ImageIO on Apple incl. HEIC/JXL/AVIF; `ImageDecoder` on Android incl. HEIF/AVIF; WIC on Windows incl. installed extensions) → libvips (JPEG/PNG/WebP/TIFF/SVG/GIF/EXR with shrink-on-load) → libjxl, libavif, LibRaw, QOI/TGA/PNM via small decoders. libheif/libde265 are **not shipped** on Windows (patent); if WIC lacks HEVC, a one-time prompt links the free/paid Microsoft extension.
- Thumbnails: OS thumbnail cache first; then libvips into a disk LRU keyed by (path, mtime, size, orientation) as 256/512 px WebP; generation on an isolate pool; memory cap 64 MB mobile / 256 MB desktop.
- Large images: pyramid built on demand (1/8, 1/4, 1/2 via shrink-on-load) and 512 px tiles for the full level; viewer requests tiles for the visible rect (CATiledLayer-style) — 100 MP TIFF pans at 60 fps on a 2022 phone.
- Metadata: platform readers (ImageIO, `ExifInterface`, WIC) + own MIT XMP/IPTC reader-writer in Dart; **Exiv2 excluded (GPL)**. Writes are atomic (temp file + rename) and preserve unknown blocks.
- Editing: non-destructive op stack applied on export via libvips; previews on GPU (Flutter shaders) for sliders.
- Faces (IMG-005): platform APIs only (Vision on Apple, ML Kit face detection on Android Play flavour, Windows.Media.FaceAnalysis); FOSS flavour uses no on-device ML except an optional downloadable model; grouping stays on device.

## 6. Data model and storage

- **Database:** SQLite via `drift` with FTS5 for search; WAL; schema migrations versioned; one DB per profile.
- **SQLite floor (ADR-020):** the index needs SQLite **≥ 3.30.0** with FTS5 (bm25, prefix indexes, `unicode61 remove_diacritics 2`) and the JSON functions (`json_each`). That covers UPSERT 3.24, window functions 3.25, `remove_diacritics 2` 3.27 and `NULLS LAST` 3.30; trigram is not used.
  - iOS and macOS use the system SQLite. iOS 16 ships 3.39 and macOS 12 at least 3.36.
  - Android and Windows bundle `package:sqlite3`'s build, with FTS5 on and JSON never omitted.
  - `checkSqliteSupport` probes the features at every open and fails with `SqliteUnsupported` and actionable copy (`app/lib/core/db/sqlite_support.dart`).
- Core tables: `source`, `item` (polymorphic with `kind`), `video_meta`, `audio_meta`, `image_meta`, `track`, `chapter`, `artwork`, `tag`, `item_tag`, `playlist`, `playlist_item`, `queue`, `queue_item`, `progress`, `rating`, `label`, `person`, `place`, `album`, `artist`, `series`, `season`, `collection`, `server_account`, `server_item_map`, `download`, `scan_job`, `thumb_cache`, `setting`, `shader_preset`, `eq_preset`, `subtitle_cache`, `scrobble_queue`.
- Items keyed by stable `source_id + relative_path + size + mtime` with content hash (xxh3 of first/last 1 MB + size) for move detection.
- Secrets: OS keychain/keystore/DPAPI; DB fields that reference them hold only identifiers.
- Vault: separate encrypted SQLCipher-free design — files are AES-256-GCM encrypted chunks in an app-private directory; index entries flagged `vault=1` with encrypted names; key wrapped by OS secure enclave/Keystore/DPAPI and unlocked by biometric.
- Settings: typed `Settings` object serialised to JSON in app support dir; managed-config overlay (B2B-001) is read-only and wins.

## 7. Concurrency and performance model

- UI isolate never decodes, scans, hashes, or parses. Work goes to: engine threads (mpv), a scanner isolate pool (N = cores/2), an image isolate pool, a network isolate per source.
- Backpressure: scan and thumbnail queues are priority queues keyed to the visible viewport.
- Budgets enforced in CI (doc 11): cold start, first frame, scroll jank, memory, binary size, battery (Android Batterystats / Xcode Energy / Windows ETW).
- Thermal: on `thermalStatus >= moderate` (A) / `ProcessInfo.thermalState` (I M) / power throttling (W), shaders and interpolation downgrade automatically with a toast.

## 8. Platform modules (native code allowed only here)

| Platform | Module | Responsibilities |
|---|---|---|
| Android (Kotlin) | `MediaSessionModule` | Media3 `MediaSessionService`, notification, Android Auto `MediaLibraryService`, Assistant |
| | `StorageModule` | SAF trees, MediaStore queries/observers, Photo Picker, `READ_MEDIA_VISUAL_USER_SELECTED`, trash via `MediaStore.createTrashRequest` |
| | `AudioModule` | `setPreferredMixerAttributes` bit-perfect, AAudio device enumeration, AVRCP, audio focus |
| | `CastModule` | Cast SDK (Play flavour only) |
| | `PipModule`, `DisplayModule` (frame-rate switching `Surface.setFrameRate`/`preferredDisplayModeId`), `KioskModule` (lock task), `ManagedConfigModule` |
| iOS/macOS (Swift) | `AudioSessionModule` | `AVAudioSession`, Now Playing, remote commands, AirPlay route picker, CarPlay templates |
| | `PipModule` | `AVPictureInPictureController` with `AVSampleBufferDisplayLayer` fed by engine frames |
| | `PhotosModule` | PhotoKit (limited/full), PHPicker, Live Photo pairing |
| | `FilesModule` | Document picker, security-scoped bookmarks, open-in-place, external drives |
| | `AppIntentsModule`, `WidgetModule` (WidgetKit/Live Activities), `SandboxModule` (M) |
| Windows (C++/WinRT) | `SmtcModule` | SystemMediaTransportControls, taskbar thumbnail buttons, jump lists |
| | `AudioModule` | WASAPI exclusive/shared device enumeration, ASIO (optional driver) |
| | `StorageModule` | Known folders, pickers, Recycle Bin via `IFileOperation`, thumbnails via `IShellItemImageFactory` |
| | `DisplayModule` | HDR mode detection, refresh-rate switching, DXGI output info |
| | `PackagingModule` | MSIX identity, file associations, protocol handlers, installer (unpackaged build) |

All modules are reached through a single typed Pigeon/platform-channel facade per capability; no feature code calls `MethodChannel` directly.

## 9. Networking

- Protocol clients: libsmb2, libnfs, libcurl (HTTP/FTP/WebDAV/SFTP with libssh2), all via FFI with a `VirtualFile` abstraction exposing `read(offset, len)`; mpv consumes them through a custom stream protocol (`mpv_stream_cb_add_ro`) so every source is seekable in the engine.
- Server clients generated from OpenAPI (Jellyfin, Immich, Audiobookshelf) or hand-written (Plex, Subsonic, Emby, Nextcloud) in `mediahro_servers`, with a common `ServerLibrary` interface (browse, search, stream URL, progress, download).
- Discovery: mDNS/DNS-SD (`_smb._tcp`, `_webdav._tcp`, `_googlecast._tcp`, `_airplay._tcp`, `_http._tcp`, `_jellyfin._tcp`), SSDP (needs multicast entitlement on Apple), WS-Discovery/NetBIOS for Windows shares.
- TLS: platform stacks; certificate pinning not used (self-hosted servers); self-signed certificates accepted per-server after explicit fingerprint confirmation.
- Allow-list: the only Mediahro-controlled endpoints are `api.mediahro.com` (feature flags/static JSON on GitHub Pages) and the opt-in Sentry/Aptabase hosts; third-party endpoints (OpenSubtitles, TMDB, LRCLIB, MusicBrainz, ListenBrainz/Last.fm, OSM tiles, IntroDB, AcoustID) each sit behind a user toggle (PRIV-004).

## 10. Native dependency matrix (versions pinned in `mediahro-deps`)

| Library | Version (min) | Licence | Linking | Notes |
|---|---|---|---|---|
| FFmpeg | 8.1 | LGPL-2.1+ | dynamic | configure line published in About |
| mpv (libmpv) | 0.41 | LGPL-2.1+ (`-Dgpl=false`) | dynamic | Lua/JS off |
| libplacebo | 7.x | LGPL-2.1+ | dynamic | |
| libass | 0.17.5 | ISC | any | fontconfig/CoreText/DirectWrite providers |
| dav1d | 1.5.4 | BSD-2 | any | AV1 |
| vvdec | latest | BSD-3-Clear | any | VVC; optional flag |
| libvpx, libopus, libogg, FLAC | current | BSD | any | |
| libopenmpt | 0.8 | BSD-3 | any | trackers |
| libvips | 8.18 | LGPL-2.1+ | dynamic | |
| libjxl | 0.12 | BSD-3 | any | |
| libavif | 1.4 | BSD-2 | any | with dav1d |
| LibRaw | 0.22 | CDDL-1.0 (chosen) | static OK | |
| libheif/libde265 | — | LGPL-3 | **not shipped on Windows**; OS decoders on Apple/Android | patent posture |
| libsmb2 | current | LGPL-2.1 | dynamic (required on iOS) | |
| libnfs | current | LGPL-2.1 (lib) | dynamic | |
| libcurl + libssh2 | current | curl / BSD-3 | any | TLS via OS backends (Schannel/SecureTransport/Android) |
| libarchive | 3.x | BSD-2 | any | ZIP/RAR/7z/CBZ (RAR5 via unrar-free codepath only) |
| libebur128 | 1.2 | MIT | any | |
| chromaprint | 1.6 | LGPL-2.1+ | dynamic | AcoustID |
| whisper.cpp | current | MIT | any | model downloaded on demand |
| uchardet | 0.0.8 | MPL-1.1 | any | |
| SQLite | 3.4x bundled (A, W); system on I, M (≥ 3.30, §6) | public domain | any | FTS5 and JSON required, never stripped |
| Open Screen libcast | current | BSD-3 | any | desktop/FOSS Cast sender |
| Google Cast SDK | current | proprietary | Play/App Store flavours only | excluded from FOSS |
| Sentry Flutter, Aptabase Flutter | current | MIT | any | opt-in, FOSS flavour excludes Sentry if non-FOSS deps |

All `.so` built with NDK r28+ (16 KB page alignment), all Apple binaries as dynamic `.xcframework`s signed by us, Windows as `.dll`s next to the executable. A CI licence scan fails the build if any artefact's configure flags or linked symbols indicate GPL code.

## 11. Build flavours

| Flavour | Stores | Differences |
|---|---|---|
| `store` | App Store, Mac App Store, Google Play, Microsoft Store | IAP rails; Cast SDK (A I); platform ML; sandbox (MAS) |
| `direct` | Direct macOS DMG (notarised), Windows installer + winget | Web supporter links; Sparkle/own updater; no sandbox (M) |
| `foss` | F-Droid, GitHub releases | No proprietary SDKs (no Cast SDK → Open Screen; no ML Kit; no Sentry if required); donation links; reproducible |
| `enterprise` | MDM/custom app distribution | Managed config defaults; branding hooks; commercial licence |

Flavour differences are compile-time (`--dart-define=MEDIAHRO_FLAVOR=`) and Gradle/Xcode configurations; feature code checks `Flavor` only through a `Capabilities` service.

## 12. Decision log (ADRs)

| ADR | Decision | Status |
|---|---|---|
| 001 | Flutter + libmpv single codebase; KMP fallback; Apple native-engine fallback trigger | Accepted |
| 002 | No GPL in binaries; LGPL dynamic; Exiv2/x264/x265/rubberband/libdvdcss excluded | Accepted |
| 003 | OS decoders first for HEVC/HEIC/DV/AAC; software fallback | Accepted |
| 004 | Own thin `dart:ffi` wrapper over `mpv_render_context` instead of depending on media_kit's Dart layer (use its prebuilts only during bootstrap, replaced by `mediahro-deps`) | Accepted |
| 005 | Telemetry opt-in only; Sentry self-hosted + Aptabase | Accepted |
| 006 | SQLite/drift with FTS5; no cloud backend | Accepted |
| 007 | No torrent, no IPTV lists, no add-on marketplace | Accepted |
| 008 | Vault encryption design (AES-256-GCM chunks, OS-wrapped key) | Accepted |
| 009 | Cast fallback via local server + remux/transcode | Accepted |
| 010 | Linux desktop deferred to 1.2 | Accepted |
| 011 | `PlaybackEngine` API, `MpvEngine` and the per-platform render bridge live in `packages/mediahro_engine` (a Flutter plugin with `android/`, `ios/`, `macos/`, `windows/`), so the B2B Engine SDK (B2B-004) is self-contained. `app/lib/engine` holds only the app-side engine pool and providers. The render bridge's native code is an engine-owned platform module in addition to §8 and is reached only through `RenderBridge` | Accepted (Phase A) |
| 012 | The `VirtualFile` / `VirtualFileSystem` abstraction lives in `packages/mediahro_ffi/lib/src/vfs/` so the engine, scanner, archive browser and image pipeline share it without depending on the app | Accepted (Phase A) |
| 013 | Localisation by per-module ARB fragments (`<owned folder>/l10n/<module>_<locale>.arb`, keys prefixed by module) merged by `tools/l10n/merge_arb.dart` into the `gen-l10n` input; merged and generated files are git-ignored; Weblate uses one component per fragment glob. Lanes never edit each other's string files | Accepted (Phase A) |
| 014 | All outbound HTTP passes `NetworkGateway` (`app/lib/core/net`), which enforces the PRIV-004 allow-list and records last use for CORE-015; server clients receive it as `HttpTransport`; `tools/lints/check_rules.dart` (`no_direct_http`) forbids `HttpClient`/`package:http` elsewhere | Accepted (Phase A) |
| 015 | Build flavours: Android uses Gradle product flavours `store/direct/foss/enterprise` (`--flavor` + `--dart-define=MEDIAHRO_FLAVOR`); Apple and Windows select the flavour by `--dart-define` in Phase A. Xcode build configurations/schemes per flavour with per-flavour entitlements (MAS sandbox vs direct hardened runtime) and the privacy manifest are authored by lane C4 and proven on macOS CI; until then Apple builds use the sandboxed (stricter) entitlements. With no define, the flavour is `foss` (most conservative) | Accepted (Phase A) |
| 016 | Engine API value types use `freezed`; analyzer lints for the Dart 3.13 constructor syntax (`unnecessary_type_name_in_constructor`) are disabled so hand-written and generated code read the same; `dart format` defaults (80 columns) everywhere | Accepted (Phase A) |
| 017 | **Crypto stays with the OS (keeps docs/07 rule 12).** SFTP (NET-004) uses the platform's SSH stack behind `SftpFacade`: sshj over JCA (A), SwiftNIO SSH over CryptoKit (I M), libssh2 with the WinCNG backend (W). FTPS (NET-004) and the Open Screen/CASTv2 sender (CAST-001, desktop and FOSS) run their protocols in Dart over OS TLS sockets from `TlsSocketFacade`: SSLSocket (A), Network.framework (I M), SChannel (W). No mbedTLS, OpenSSL or BoringSSL is added; libssh2 and openscreen-libcast are not built for Android/Apple; openscreen-libcast is replaced by the Dart CASTv2 sender. Implementations: C4 (platform modules, cast), B2 (VirtualFileSystem over `SftpFacade`/`TlsSocketFacade`, Windows libssh2 FFI), B4c (libssh2 + WinCNG, curl Schannel). Note: the Flutter engine embeds BoringSSL for `dart:io` TLS; counsel confirms the export-compliance answer (owner task) | Accepted (owner, 2026-10-20) |
| 018 | VVC/H.266 (VID-002) is decoded in software by FFmpeg's native `vvc` decoder (LGPL, part of libavcodec) instead of a separate vvdec library; the `MEDIAHRO_VVC` / `Capabilities.vvcSoftwareDecoder` gate (docs/09 §4: off in `store`) still applies by enabling or disabling that decoder. Saves a library per platform toward the install-size budget | Accepted (2026-10-20) |
| 019 | Android install-size budget raised from 40 to **75 MB per ABI** (docs/01 §7.2, docs/11 §5). After trimming (FFmpeg `--disable-everything` + the doc 04 component list, glslang instead of shaderc, section GC, unused libraries removed) the native set is 44.3 MB per ABI and Flutter + app ≈ 27 MB; the playback core alone is 23.6 MB, so 40 MB would require cutting doc 04 features. The > 5 % regression rule still applies, and Play download size per ABI (AAB splits via bundletool) is reported every build. iOS stays at 40 MB thinned until measured | Accepted (owner, 2026-10-20) |
| 020 | **Features are never cut for size (owner, 2026-10-20).** Install-size ceilings follow the measured full-feature build: Android ≤ 75 MB per ABI (ADR-019); iOS and desktop ceilings are re-set from B4b/B4c measurements of the full native set plus headroom instead of dropping features. Size stays controlled by (1) the > 5 % regression gate against `tools/perf/baseline.json`, which is enforced on `main` and reported as a warning on PRs: the PR justifies the growth with feature IDs and the orchestrator raises the baseline in the merge commit, and (2) mandatory state-of-the-art optimisation: native libraries with LTO/ThinLTO, section GC, identical-code folding (`--icf=all`, `/OPT:REF /OPT:ICF`), stripped symbols, only referenced codec/filter components, `-O2/-O3` on hot paths and `-Os` elsewhere; Dart `--split-debug-info` + `--obfuscate`, icon tree-shaking; Android R8 full mode, resource shrinking, ABI splits, page-aligned uncompressed `.so`; Apple dead-stripping and app thinning; no duplicated libraries. **Speed budgets (cold start, first frame, seek, scroll jank, RAM, battery) are not relaxed** and size optimisations must not regress them | Accepted (owner, 2026-10-20) |

## 13. Risks and mitigations

| Risk | Mitigation |
|---|---|
| libmpv Metal path on iOS/macOS is community-maintained | Own builds in `mediahro-deps`; MoltenVK path primary; AVPlayer sidecar for PiP/AirPlay; fallback trigger in §2 |
| media_kit backlog | Depend only on prebuilts during bootstrap; own FFI wrapper (ADR-004) |
| 16 KB pages / NDK r28, API 36, Xcode 26 requirements | Pinned toolchains in CI; `zipalign -c -P 16` check; deadlines tracked in doc 10 |
| Android bit-perfect inconsistencies | Truthful indicator (AUD-006); per-device documentation |
| Patent pools targeting software decoders | Hardware-first; software HEVC off by default on Windows without hardware; counsel before OEM |
| Flutter release churn | FVM-pinned Flutter; quarterly upgrade task |
| Parser attack surface (subtitles, playlists, archives, images) | Isolate sandboxing, size limits, fuzzing in CI (PRIV-005) |
