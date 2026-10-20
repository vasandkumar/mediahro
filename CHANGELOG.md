# Changelog

All notable changes are grouped by feature area and reference feature IDs from `docs/04`.

## [Unreleased]

### Fixed
- Guest access to SMB shares works, including NAS defaults that prefer encryption (NET-001).
- Opening a missing or moved file on an NFSv3 share now says it couldn't be found, instead of a generic read error (NET-002).
- Comic and archive files on network shares open without crashing (FILE-004).
- A wrong password or a disabled account on an SMB share now says so instead of reporting the server as unreachable (NET-001).

### Added
- Android music: library by artist, album, song and folder from your phone's music, tags and album art, gapless queue, mini player and Now Playing (MUS-001, MUS-002, MUS-004, MUS-007).
- Android: background playback with lock-screen, notification, headset and car controls; pauses or ducks for calls and other apps, and pauses when headphones are unplugged (SYS-001, SYS-002, SYS-006, AUD-045).
- Android: browse folders you grant, the phone's videos, music and photos (with Motion Photos), delete to the system trash with undo, and save files anywhere (SYS-007).
- Engine API: native-HDR video targets, ducking, audio device list, Bluetooth pre-roll and codec, DoP/native-DSD output paths, GIF/WebP/lossless clip export (VID-031, VID-042, AUD-040…045).
- Engine (lane B1, M1): `MpvEngine` over libmpv with own ffigen bindings and an event isolate; render bridges for Windows (D3D11 shared textures), Android (SurfaceProducer) and iOS/macOS (IOSurface pixel buffers) (VID-001…007, VID-030/031, CORE-011).
- Seekable playback from any `VirtualFile` source through the `mhvf://` stream protocol, including files over 20 GB (VID-005, VID-006).
- Gapless AAC trims its padding once when a file has both an iTunSMPB tag and a container duration that already excludes the padding (AUD-002).
- Network read-ahead cache sized to each file's bitrate within the memory budgets; index-less AVI files play and seek (VID-005, VID-006).
- DVD `VIDEO_TS` and Blu-ray `BDMV` folder playback with title selection and chapters, without GPL code (VID-007).
- Subtitles: every text format incl. TTML/DFXP, LRC, TXT and MicroDVD, image subtitles, external lookup, charset detection with override, styling, timing, dual subtitles (SUB-010…016, engine side).
- Audio: sample-accurate gapless, crossfade, ReplayGain and EBU R128 scan, 10-band and 32-band parametric EQ with AutoEq import, DSP chain, truthful output indicator, DSD→PCM, bit-perfect requests on Android and iOS (AUD-001…006, AUD-040…045 engine side).
- Casting pipeline: local cast server with byte ranges, passthrough/remux/transcode decision, OS-encoder transcoding to HLS, WebVTT subtitles (CAST-005).
- Apple render bridge falls back to GL readback on the iOS Simulator only; devices and macOS stay zero-copy (VID-030).
- `VideoStats.renderBackend` reports the render path for the info overlay (VID-030, VID-072).
- Android packages native libraries only for the ABIs a build targets (VID-030).
- Shift-JIS subtitles detected or forced (SUB-013).
- The library checks at start-up that the device's database engine supports full-text search, and explains what to do if it doesn't (LIB-001).
- iOS and macOS use the system's SQLite, which keeps the app smaller (LIB-001, LIB-005).
- Design system (lane B3, SYS-008, SYS-011): component library (`KButton`, `KSeekBar`, `KSheet`, `KGrid`, `KRow`, `KChip`, `KSidebar`, `KPlayerChrome`, `KMiniPlayer`, `KCompareView`, `KTimelineScrubber`, settings rows, skeletons, empty and error states) with semantics, platform target sizes, focus rings, reduced motion and transparency, 200 % text and RTL; window size classes, list-detail and tabletop layouts; golden matrix per platform family.
- Shell (CORE-001): sidebar per window class, last mode restored on launch, glass/Mica/solid bar materials, mini-player slot.
- First run (CORE-002): actions routed to the owning lanes; note that crash reports, usage statistics and update checks are off (PRIV-001).
- Settings (CORE-006): typed settings store with import/export, reset per section, managed-config overlay, search, and a registry other lanes contribute to.
- Themes (CORE-007): AMOLED, per-mode and custom accents with contrast-safe primaries, high contrast, follow-system theme.
- Localisation (CORE-008): pseudo-locales, ICU and placeholder checks, missing-string report, Weblate component config, size and duration formatting.
- Keyboard shortcuts (CORE-009): remappable actions with platform defaults, conflict detection and a cheat sheet on `?`.
- Privacy dashboard (CORE-015): every allow-listed endpoint with its switch and last-used time, and the hosts you added.
- M0 bootstrap: repository layout, flavours, design tokens, localisation pipeline, interface stubs, CI matrix, `STATUS.md`.
- Library index (LIB-001): SQLite schema per docs/05 §6 with FTS5, one database per profile, scanner isolate pool with move detection, viewport-priority probe queue.
- Local scanning (LIB-002, LIB-003): manual, on-open and watch schedules; pause, resume and cancel; fast Windows directory enumeration.
- Search (LIB-005) with type, source, resolution, codec, HDR, duration, date, rating and unplayed filters.
- Folder and library views (LIB-004), home rows (LIB-006), collections (LIB-012) and statistics (LIB-015).
- Playlists (LIB-007): manual and smart (rule builder), import and export of M3U, M3U8, PLS, XSPF and CUE.
- Named audio queues and a video queue (LIB-008); tags and colour labels (LIB-009); progress with a sync seam (LIB-010).
- Video metadata from TMDB and TVDB by filename, NFO files and an offline artwork cache (LIB-011).
- Parental PIN, biometrics, locked sources and folders, hidden items (LIB-013); duplicate finder that never deletes (LIB-014).
- File browser, operations with trash and undo, batch rename and convert, sidecars kept together (FILE-001, FILE-002, FILE-003, FILE-006).
- Archive browsing through libarchive (FILE-004); Wi-Fi transfer page with a QR code (FILE-005).
- Device media on Android: videos and music on the phone show up without picking folders (LIB-002).
- Export and import playlists as M3U8, PLS or XSPF (LIB-007); backups are saved wherever you choose (CORE-014).
- Share files or open them in another app from the browser (FILE-002).
- Network sources: SMB, NFS, WebDAV, FTP, FTPS, SFTP and DLNA, with LAN discovery and an opt-in renderer (NET-001 to NET-005).
- Open URL with headers, user agent and history (CORE-005, NET-006); cloud drives over OAuth PKCE and REST (NET-007).
- FTP and FTPS through a built-in client that takes TLS from the operating system, SFTP through the platform's SSH stack, and a prompt to trust a server's self-signed certificate or SSH host key after comparing its fingerprint (NET-003, NET-004).
- Offline downloads (NET-018), connection health (NET-019) and an encrypted backup and restore (CORE-014).
- Native dependencies (B4a): `deps.lock` pins mediahro-deps `v2026.10.0-android.1` (Android arm64-v8a, armeabi-v7a, x86_64; FFmpeg 8.1.3, mpv 0.41.0, libplacebo 7.360.1, libvips 8.18.7 and 50 more, all LGPL parts shared). The licence scan now covers Gradle, SwiftPM and CocoaPods dependencies, GPL-only sources compiled into native libraries and GPL/banned markers in the binaries.
