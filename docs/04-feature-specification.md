# 04 — Feature Specification

Version 1.0 · 2026-10-19 · Status: the build contract. Every row marked **1.0** ships in Mediahro 1.0 on every platform listed for it. There is no MVP subset.

## 0. Conventions

- **IDs** are stable and referenced by code, tests, issues and release notes (`// KVO: VID-031`).
- **Platforms:** A = Android, I = iOS/iPadOS, M = macOS, W = Windows. "All" = A I M W. Platform-specific exclusions are stated with the reason (OS limitation or store policy), never for scope reduction.
- **Release:** 1.0 unless marked 1.1 / 1.2.
- **AC** = acceptance criteria. Each is testable; doc 11 maps them to test cases.
- Engine terms: *mpv* = libmpv (video + audio engine), *vips* = libvips image pipeline, *index* = the local SQLite library database.

---

## 1. CORE — App shell, settings, onboarding

| ID | Feature | Acceptance criteria | Platforms | Rel. |
|---|---|---|---|---|
| CORE-001 | Three-mode shell (Video, Music, Photos) with a shared Sources and Settings area | Bottom tabs (phone), sidebar (tablet/desktop); mode switch < 100 ms; last mode restored on launch | All | 1.0 |
| CORE-002 | First-run without walls | No account, no sign-in, no mandatory permission on launch; first screen shows "Open a file", "Add a folder", "Add a server"; any permission is requested only when the matching action is taken | All | 1.0 |
| CORE-003 | Open-with / default handler | Registered for every supported video, audio, image, playlist and subtitle extension/UTI/MIME; "Set as default" guidance per OS; files opened from Files/Finder/Explorer/share sheets/other apps play immediately | All | 1.0 |
| CORE-004 | Drag-and-drop | Files/folders/URLs dropped onto the window or player are opened or enqueued | M W, I (iPad) | 1.0 |
| CORE-005 | URL/stream open | Paste or type http(s)/rtsp/rtmp/hls/dash/smb/nfs/ftp/sftp/webdav URL; history of last 50; no bundled lists | All | 1.0 |
| CORE-006 | Settings model | Searchable settings; every option has a one-line description; "Advanced" section exposes engine options with safe defaults; reset per section; import/export settings as JSON | All | 1.0 |
| CORE-007 | Themes | Light/dark/system; AMOLED black; per-mode accent; Material You dynamic colour (A); Liquid-Glass-styled chrome (I M); Fluent/Mica (W); high-contrast variants | All | 1.0 |
| CORE-008 | Localisation | 12 launch languages (en, pt-BR, es, hi, id, de, fr, ja, ru, tr, zh-Hans, it); RTL (ar, he) layout verified; plural rules; Weblate-driven; strings never concatenated | All | 1.0 |
| CORE-009 | Keyboard shortcuts | Full keyboard operation; default map per platform conventions; every shortcut remappable; printable cheat sheet (`?`) | All | 1.0 |
| CORE-010 | Window management | Multi-window (iPad Stage Manager, macOS, Windows); remembers size/position per window; always-on-top mini player (M W) | I M W | 1.0 |
| CORE-011 | Crash resilience | Any engine fault isolates to the player session; app never loses library or queue state; auto-save of playback position every 5 s | All | 1.0 |
| CORE-012 | Updates | Store updates (stores); Sparkle-style signed updater for direct macOS and Windows builds; release notes in-app | All | 1.0 |
| CORE-013 | About and licences | Version, build, engine versions, full OSS licence texts, FFmpeg configure line, source link, privacy policy, trademark policy | All | 1.0 |
| CORE-014 | Backup/restore | Export library metadata (positions, playlists, ratings, tags, settings) to a single encrypted file; restore on any platform | All | 1.0 |
| CORE-015 | Privacy dashboard | One screen listing every network endpoint the app may contact, each with its toggle and last-used time | All | 1.0 |

## 2. LIB — Library, indexing, search

| ID | Feature | Acceptance criteria | Platforms | Rel. |
|---|---|---|---|---|
| LIB-001 | Unified index | SQLite index of files across all sources with type, size, mtime, duration, codecs, resolution, HDR type, audio layout, subtitle tracks, tags, art, position, play count, rating, labels | All | 1.0 |
| LIB-002 | Local sources | Android: MediaStore + SAF trees (internal, SD, USB-OTG); iOS: app container, Files bookmarks, external drives via Files; macOS/Windows: any folder via picker with security-scoped bookmarks (M) | All | 1.0 |
| LIB-003 | Scan performance | 10 k files ≤ 30 s initial on a mid-range phone; incremental rescan ≤ 2 s; scanning never blocks UI; pausable; per-source schedule (manual / on open / watch) | All | 1.0 |
| LIB-004 | Folder mode and library mode | Every mode offers both a raw folder tree view and a curated library view; toggle persists per mode | All | 1.0 |
| LIB-005 | Search | Instant (≤ 50 ms) prefix search across titles, filenames, tags, artists, albums, people, places; filters by type, source, resolution, codec, HDR, duration, date, rating, unplayed | All | 1.0 |
| LIB-006 | Continue watching / recently added / recently played | Cross-mode home rows with resume thumbnails | All | 1.0 |
| LIB-007 | Playlists | Manual and smart playlists (rule builder: any indexed field, AND/OR, limits, sort); import/export M3U/M3U8/PLS/XSPF; cross-source | All | 1.0 |
| LIB-008 | Multiple queues | Named queues (Musicolet pattern) for audio; one active queue for video; queue persists | All | 1.0 |
| LIB-009 | Tags and labels | User tags on any item; colour labels; bulk apply | All | 1.0 |
| LIB-010 | Watched/unwatched state and progress sync | Per item; synced to Jellyfin/Emby/Plex when connected (opt-in) (Trakt removed by ADR-048) | All | 1.0 |
| LIB-011 | Metadata scraping (video) | Local-only metadata: filename parser (title, year, SxxEyy, release group ignored); NFO files and local artwork sidecars (poster, fanart, folder) supply posters, backdrops, cast, ratings, episode names; metadata served by the user's own Jellyfin/Emby/Plex; manual edit/match/unmatch; works fully offline (TMDB/TVDB online scraping removed by ADR-048) | All | 1.0 |
| LIB-012 | Collections | Series/season grouping (TMDB collections removed by ADR-048), music albums/artists/genres/years/composers, photo albums/people/places | All | 1.0 |
| LIB-013 | Parental PIN and hidden items | PIN/biometric gate for chosen folders/sources; hidden items excluded from search and rows | All | 1.0 |
| LIB-014 | Duplicate finder | Exact (hash) and perceptual (pHash for images, chromaprint for audio, duration+size for video); user reviews and chooses; never auto-deletes | All | 1.0 |
| LIB-015 | Statistics | Play counts, time listened/watched, top items, storage by type/source | All | 1.0 |

## 3. FILE — File browser and management

| ID | Feature | Acceptance criteria | Platforms | Rel. |
|---|---|---|---|---|
| FILE-001 | Browser | Breadcrumb tree, list/grid, sort (name, date, size, duration, type), thumbnails with resume bar, folder art | All | 1.0 |
| FILE-002 | Operations | Rename, move, copy, delete (to OS trash/recycle bin where available, with undo), new folder, share, "open in", properties with full media info (mediainfo-style) | All | 1.0 |
| FILE-003 | Batch operations | Multi-select across folders; batch rename with patterns and metadata tokens; batch convert images (format/size/quality); batch tag edit | All | 1.0 |
| FILE-004 | Archives | Browse ZIP/CBZ/RAR/7z/CBR and play/view contents without extraction (libarchive) | All | 1.0 |
| FILE-005 | Transfer | Wi-Fi transfer web page (upload/download from a browser on the LAN) with QR code; iOS Files integration; USB-C drives | All | 1.0 |
| FILE-006 | Subtitle/audio sidecars | Auto-detect sidecar files by name and language suffix; move/rename keeps sidecars together | All | 1.0 |

## 4. VID — Video playback

### 4.1 Formats and decoding

| ID | Feature | Acceptance criteria | Platforms | Rel. |
|---|---|---|---|---|
| VID-001 | Containers | MKV, MP4/M4V/MOV, WebM, AVI, WMV/ASF, FLV, TS/M2TS/MTS, MPG/VOB, OGM/OGV, 3GP, RM/RMVB, ISO/BDMV folder (unencrypted), MXF, playlists (M3U/PLS/XSPF/CUE) | All | 1.0 |
| VID-002 | Video codecs | H.264, HEVC (8/10-bit, 4:2:0/4:2:2), AV1, VP8/9, VVC/H.266 (software, vvdec), MPEG-1/2/4, VC-1, ProRes, DNxHD, Theora, MJPEG, FFV1, HAP; hardware decode first (MediaCodec, VideoToolbox, D3D11VA/D3D12VA, Vulkan video), software fallback automatic per file | All | 1.0 |
| VID-003 | Audio codecs in video | AAC, AC-3, E-AC-3, TrueHD, DTS, DTS-HD MA/HRA, DTS:X core, FLAC, Opus, Vorbis, MP3, PCM, ALAC, WMA; multichannel decode to PCM | All | 1.0 |
| VID-004 | Audio passthrough | Bitstream AC-3/E-AC-3/DTS/DTS-HD/TrueHD over HDMI/SPDIF/USB where the OS allows (A: AudioTrack encoded/HDMI; W: WASAPI exclusive; M: CoreAudio encoded formats); per-device setting; automatic fallback to decode | A M W | 1.0 |
| VID-005 | Playback edge cases | Files > 4 GB and > 20 GB; variable frame rate; broken/truncated files play to the last good frame; missing index (AVI) rebuilt; hev1/hvc1 both handled; 10-bit AVC software path | All | 1.0 |
| VID-006 | Network playback | Streams from every NET source with read-ahead cache sized to bitrate; seek on SMB/NFS/WebDAV/HTTP range; resume after Wi-Fi drop within 30 s | All | 1.0 |
| VID-007 | DVD/Blu-ray folder playback | Unencrypted VIDEO_TS and BDMV with menu-less title selection, chapters, subtitles (no libdvdcss/AACS) | M W, A I (folders) | 1.0 |

### 4.2 Rendering, HDR, quality

| ID | Feature | Acceptance criteria | Platforms | Rel. |
|---|---|---|---|---|
| VID-030 | GPU renderer | libplacebo `gpu-next` (Vulkan/Metal via MoltenVK/D3D11); zero-copy from hardware decoder where supported; 4K60 10-bit without drops on 2022 flagship phones | All | 1.0 |
| VID-031 | HDR10 / HLG | Displayed natively on HDR displays (A I M W); tone-mapped to SDR otherwise with libplacebo dynamic tone mapping (bt.2390 default; options: spline, reinhard, hable, mobius, clip); peak detection; no washed-out output | All | 1.0 |
| VID-032 | HDR10+ | Dynamic metadata honoured where the platform exposes it; otherwise falls back to HDR10 path | All | 1.0 |
| VID-033 | Dolby Vision profile 8.1/8.4 | Plays as HDR10/HLG base layer with correct colours; profile reported in info panel; no Dolby branding | All | 1.0 |
| VID-034 | Dolby Vision profile 5 | libplacebo RPU reshaping to PQ/SDR; on Apple hardware with native DV decode, VideoToolbox path used | All | 1.0 |
| VID-035 | Dolby Vision profile 7 (MEL/FEL) | Base layer (HDR10) played; enhancement layer ignored with a one-time info note; never a black screen | All | 1.0 |
| VID-036 | Auto frame-rate and resolution matching | On Android TV/boxes and desktop (where OS API exists) switch display mode to content frame rate; user toggle; 24/25/30/50/60 and fractional | A W M | 1.0 (TV UI 1.1) |
| VID-037 | Scaling and filters | Scalers (bilinear, spline36, ewa_lanczos), debanding, deinterlace (yadif/bwdif, auto on interlaced), sharpen, colour (brightness/contrast/saturation/gamma/hue), rotate/flip, aspect override, crop/zoom/pan, stretch modes | All | 1.0 |
| VID-038 | User shaders | Built-in presets with one toggle: Anime4K (multiple strengths), FSR, NNEDI3-lite, SSimSuperRes, film-grain; custom GLSL from a user folder; performance guard disables on thermal throttle | All | 1.0 |
| VID-039 | Frame interpolation | mpv `interpolation` with `display-resample` on desktop; opt-in on mobile with battery warning | All | 1.0 |
| VID-040 | ICC / display calibration | Use system display profile (M W); 3D LUT loading | M W | 1.0 |
| VID-041 | 3D and 360° | SBS/TAB 3D to 2D/anaglyph; 360°/180° equirectangular with gyro (mobile) and drag (desktop); VR180 | All | 1.0 |
| VID-042 | Screenshot, GIF and clip export | Screenshot with/without subtitles (PNG/JPEG XL/WebP, HDR-aware); GIF/WebP animation export of a range; lossless clip trim (stream copy) | All | 1.0 |

### 4.3 Controls and ergonomics

| ID | Feature | Acceptance criteria | Platforms | Rel. |
|---|---|---|---|---|
| VID-060 | Gesture set | Horizontal swipe seek with preview thumbnails; left/right vertical swipe brightness/volume; double-tap sides to skip (configurable 5–60 s); long-press for 2× speed; pinch zoom/fit; two-finger swipe for subtitle delay; all sensitivities adjustable; all gestures disableable; touch lock | A I | 1.0 |
| VID-061 | Seek bar | Scrubbing preview thumbnails (generated on demand, cached), chapter marks, A-B loop markers, precise seek (frame-accurate) when paused | All | 1.0 |
| VID-062 | Speed | 0.25–4.0× in 0.05 steps with pitch correction (scaletempo2); per-item and global memory; quick presets | All | 1.0 |
| VID-063 | Frame step, A-B loop, chapters, bookmarks | Frame forward/back; A-B loop with count; chapter list from container/Matroska/MP4/CUE; user bookmarks with notes | All | 1.0 |
| VID-064 | Resume and post-playback | Resume position per file (and per server); "play next in folder/series"; post-playback actions (stop, next, repeat, close, delete-with-confirm) | All | 1.0 |
| VID-065 | Audio/subtitle track switching | In-player chooser with language names, codec, channels; defaults by preferred language list; per-series memory | All | 1.0 |
| VID-066 | Audio delay and volume | ±5 s audio delay in 10 ms steps; volume boost to 300 % with limiter; mute; per-device volume memory | All | 1.0 |
| VID-067 | Picture-in-Picture | System PiP (A: Android PiP; I: AVPictureInPictureController via sample-buffer layer; M: native PiP; W: compact overlay) with play/pause/seek controls; auto-PiP on leave (opt-in) | All | 1.0 |
| VID-068 | Background and audio-only playback | Continue audio when screen off/app backgrounded (opt-in per session or always); video-off power-saving mode | All | 1.0 |
| VID-069 | Sleep timer and auto-off | Time, end-of-item, end-of-queue; fade-out | All | 1.0 |
| VID-070 | Orientation and display | Auto/lock rotation; follows video aspect; notch/cutout-safe; edge-to-edge; keeps screen awake while playing | A I | 1.0 |
| VID-071 | Second screen / external display | Full-screen video on external display with controls on device; HDR passthrough on external; AirPlay/Cast when available | All | 1.0 |
| VID-072 | Info overlay | Toggle stats: codec, hwdec path, resolution, fps, dropped frames, bitrate, HDR type, audio format/output, subtitle renderer | All | 1.0 |
| VID-073 | Skip intro/credits | IntroDB community markers (opt-in; keyless anonymous reads, looked up by IMDb ID from NFO or server metadata) and Jellyfin/Plex-provided markers; manual "skip 85 s" chapter heuristic | All | 1.0 |
| VID-074 | Remote control | Web remote (LAN web page) and companion control from another Mediahro instance; keyboard/media keys; MPRIS-like OS integrations | All | 1.0 |

## 5. SUB — Subtitles

| ID | Feature | Acceptance criteria | Platforms | Rel. |
|---|---|---|---|---|
| SUB-010 | Text formats | SRT, WebVTT, ASS/SSA (full libass typesetting incl. karaoke, embedded fonts, animations), SMI/SAMI, MicroDVD, TTML/DFXP, LRC (for music videos), TXT heuristics | All | 1.0 |
| SUB-011 | Image formats | PGS/SUP, VobSub (IDX/SUB), DVB, HDR PGS tone-mapped | All | 1.0 |
| SUB-012 | Embedded and external | All embedded tracks; external by same name, language suffix, `Subs/` folder, user-chosen folder; drag-drop or pick any file | All | 1.0 |
| SUB-013 | Encoding detection | Auto-detect charset (uchardet) with manual override; UTF-8 BOM handling | All | 1.0 |
| SUB-014 | Styling | Font, size, colour, outline, shadow, background box, position (vertical/horizontal), alignment; override ASS styles optionally; honours system caption preferences (MACaptionAppearance / Android CaptioningManager / Windows caption styles) | All | 1.0 |
| SUB-015 | Timing | Delay ±60 s in 50 ms steps; speed/stretch (fps conversion 23.976↔25); keyboard and gesture shortcuts; per-file memory | All | 1.0 |
| SUB-016 | Dual subtitles | Primary + secondary track with independent position/size/delay | All | 1.0 |
| SUB-020 | Online download | Podnapisi (OpenSubtitles.com and Subdl removed by ADR-048); hash + name search; one-tap best match; auto-download for preferred languages (opt-in); rate-limit aware | All | 1.0 |
| SUB-030 | Subtitle editor | Shift, resync by two points, fix encoding, save as SRT/ASS | All | 1.0 |
| SUB-040 | Text-to-speech | Read subtitles aloud via system TTS (accessibility) | All | 1.0 |
| SUB-050 | Auto-sync (audio-based) | On-device alignment of a subtitle file to the audio track (VAD + cross-correlation, alass/ffsubsync approach); runs in background ≤ 2× real-time on phone; result previewed before save | All | 1.0 |
| SUB-051 | OCR of image subtitles | Convert PGS/VobSub to editable SRT with on-device OCR (platform OCR: Vision/ML Kit/Windows OCR; Tesseract fallback); language auto-detect | All | 1.0 |
| SUB-052 | Auto-captions (speech-to-text) | Generate captions on device with Whisper-class model (whisper.cpp, small model downloaded on demand, opt-in) for videos without subtitles | All | 1.0 |
| SUB-053 | Translation | On-device translation of subtitle text where the OS offers it (Apple Translation, ML Kit, Windows); online translation never without consent | All | 1.0 |

## 6. AUD — Audio engine and player

### 6.1 Formats and output

| ID | Feature | Acceptance criteria | Platforms | Rel. |
|---|---|---|---|---|
| AUD-001 | Formats | MP3, AAC/M4A, FLAC, ALAC, WAV/AIFF (up to 32-bit/768 kHz), Opus, Vorbis, WavPack, APE, TTA, TAK, MPC, DSF/DFF (DSD64–DSD512), SACD ISO, WMA, AC-3/DTS audio files, tracker modules (MOD/XM/IT/S3M via libopenmpt), MIDI (soundfont), CUE sheets with per-track splitting | All | 1.0 |
| AUD-002 | Gapless | Sample-accurate gapless for all formats incl. encoder delay/padding (LAME tags, iTunSMPB) | All | 1.0 |
| AUD-003 | Crossfade | 0–12 s, per-transition type (manual skip vs natural end), disabled automatically for gapless albums (opt-in) | All | 1.0 |
| AUD-004 | Loudness | ReplayGain track/album (reads tags; scans missing with libebur128 in background); EBU R128 normalisation target selectable; pre-amp; clipping prevention | All | 1.0 |
| AUD-005 | DSP chain | 10-band graphic EQ + up to 32-band parametric EQ (biquads), presets, AutoEq import (APO/Wavelet); limiter; balance; mono; channel mixer; tempo/pitch independent (scaletempo2/rubberband-free); crossfeed; bass/treble quick controls | All | 1.0 |
| AUD-006 | Output quality indicator | Shows actual device sample rate/bit depth and whether the path is bit-perfect, resampled or mixed | All | 1.0 |
| AUD-040 | Bit-perfect Android | Android 14+ `setPreferredMixerAttributes` bit-perfect path for USB DACs; AAudio exclusive/low-latency; automatic sample-rate switching; documented per-device results | A | 1.0 |
| AUD-041 | Bit-perfect Apple | CoreAudio hog/exclusive mode with automatic device sample-rate switching (M); best-available on iOS (AVAudioSession preferred sample rate) | I M | 1.0 |
| AUD-042 | Bit-perfect Windows | WASAPI exclusive and shared; ASIO (if driver present); automatic rate switching | W | 1.0 |
| AUD-043 | DSD | Native DSD/DoP on supporting outputs; otherwise PCM conversion with selectable filter | All | 1.0 |
| AUD-044 | Bluetooth | AVRCP 1.6 metadata and absolute volume; codec shown; no first-seconds cut-off (pre-roll silence priming); A/V sync offset for video over BT | All | 1.0 |
| AUD-045 | Audio focus and interruptions | Ducking/pausing on calls, notifications, other apps; resume rules configurable; headphone unplug pauses | All | 1.0 |
| AUD-046 | Visualiser | Spectrum/waveform/VU, album-art-reactive; GPU; low-power mode | All | 1.0 |

### 6.2 Music library and player UI

| ID | Feature | Acceptance criteria | Platforms | Rel. |
|---|---|---|---|---|
| MUS-001 | Library views | Songs, albums, artists, album artists, genres, years, composers, folders, playlists, queues; grid/list; alphabet scroller; sort options everywhere | All | 1.0 |
| MUS-002 | Tag reading | ID3v1/2.2/2.3/2.4, Vorbis comments, APE, MP4 atoms, ASF, WAV/AIFF chunks, multi-value artists, disc/track numbers, embedded art, embedded lyrics, ReplayGain, MusicBrainz IDs | All | 1.0 |
| MUS-003 | Tag editing | Single and batch edit of all common fields, art replace, rename-from-tags and tags-from-filename with patterns; writes safely (temp + rename); undo last batch | All | 1.0 |
| MUS-004 | Art | Embedded first; folder art (cover/folder/front.*); online fetch from Cover Art Archive/MusicBrainz (opt-in); cache; artist images (opt-in) | All | 1.0 |
| MUS-005 | Lyrics | Embedded (USLT/SYLT/LYRICS), sidecar LRC (incl. enhanced word-level), online synced lyrics from LRCLIB (opt-in, no account); karaoke scroll; LRC editor/creator with tap-to-time | All | 1.0 |
| MUS-006 | Now Playing | Art, progress, queue, lyrics, EQ quick access, output picker, sleep timer, rating, favourite, "go to album/artist"; swipe gestures; landscape and tablet layouts | All | 1.0 |
| MUS-007 | Queues | Multiple named queues; play next/add to queue/add to another queue; reorder; save as playlist; history | All | 1.0 |
| MUS-008 | Smart playlists | Rule builder over tags, play count, last played, rating, date added, length, path | All | 1.0 |
| MUS-009 | Scrobbling | Native ListenBrainz (incl. offline queue; the user supplies their own token); per-source toggle (Last.fm and Libre.fm removed by ADR-048) | All | 1.0 |
| MUS-010 | Fingerprinting | Removed from 1.0 by owner decision 2026-10-22 (ADR-047): online identification needs an external API key | All | — |
| MUS-011 | Sleep timer and alarms | Sleep by time/tracks with fade; wake alarm with playlist (A W M) | All | 1.0 |
| MUS-012 | Widgets and quick controls | Home-screen widgets (A), Lock Screen/Home widgets (I), menu-bar extra (M), taskbar thumbnail toolbar and SMTC (W) | All | 1.0 |
| MUS-013 | Car | Android Auto (MediaBrowser tree: queues, playlists, albums, artists, folders, podcasts) and CarPlay (templates) with voice | A I | 1.0 |
| MUS-014 | Internet radio | Play HTTP/ICY/HLS radio URLs with metadata; user-added stations only (no directory) | All | 1.0 |
| MUS-015 | Watch companion | Wear OS and watchOS remote with queue, volume, like; offline playlists on watch | A I | 1.1 |

### 6.3 Podcasts and audiobooks

| ID | Feature | Acceptance criteria | Platforms | Rel. |
|---|---|---|---|---|
| POD-001 | Audiobook/podcast mode | Folder or M4B/MP3 series treated as a book: chapters (MP4 chapters, ID3 CHAP, CUE, Overdrive markers), per-book resume, speed memory, skip silence, bookmarks with notes, sleep timer with shake-to-extend | All | 1.0 |
| POD-002 | Podcast feeds | Subscribe to RSS URLs the user provides (OPML import/export), download/stream episodes, mark played; no directory, no recommendations | All | 1.0 |
| POD-003 | Audiobookshelf client | Connect, browse, stream/download, progress sync | All | 1.0 |

## 7. IMG — Images and gallery

| ID | Feature | Acceptance criteria | Platforms | Rel. |
|---|---|---|---|---|
| IMG-001 | Formats | JPEG (incl. progressive, CMYK, 12-bit), PNG/APNG, GIF, WebP (animated), AVIF (animated), HEIC/HEIF (platform decoders; sequences), JPEG XL (incl. animated, HDR), SVG, TIFF (multi-page, 16-bit), BMP, ICO, PSD/PSB flattened, EXR/HDR (tone-mapped), DDS, TGA, PNM, QOI, RAW via LibRaw (CR2/CR3/NEF/ARW/DNG/RAF/ORF/RW2/PEF/SRW and others), Live Photos (HEIC+MOV), Motion Photos (MP4-in-JPEG/HEIC), panoramas (XMP GPano) | All | 1.0 |
| IMG-002 | HDR images | Gain-map JPEG/HEIC/AVIF (ISO 21496) and HDR JXL/AVIF displayed on HDR displays; tone-mapped otherwise | All | 1.0 |
| IMG-003 | Gallery performance | OS thumbnail first, then libvips shrink-on-load into a disk LRU (256/512 px WebP); 60/120 fps scroll with 50 k items; prefetch ±2 screens; memory cap | All | 1.0 |
| IMG-004 | Viewer | Tiled pyramid rendering for 100 MP+ (512 px tiles); pinch/scroll zoom to 1:1 and beyond; pan inertia; swipe between items; double-tap zoom cycle; rotate; fit/fill; zoom level readout | All | 1.0 |
| IMG-005 | Organisation | Folders, albums (user), smart albums (rules), favourites, ratings (1–5), colour labels, tags (XMP dc:subject), people (on-device face grouping opt-in, A I M W via platform/ML), places (map), dates (timeline with year/month scrub) | All | 1.0 |
| IMG-006 | Metadata | Full EXIF/IPTC/XMP/ICC view; edit date, GPS, title, description, keywords, rating; writes to XMP sidecar for RAW and to the file for JPEG/HEIC/PNG/WebP/TIFF (platform/own writer, no Exiv2); strip metadata on share (opt-in default) | All | 1.0 |
| IMG-007 | Map | Places: reverse geocoding offline from a bundled gazetteer; Places tab; set/clear location (search or coordinates). Map view with online tiles removed by owner decision 2026-10-21 (ADR-041) | All | 1.0 |
| IMG-008 | Compare | 2-up and 4-up with synced pan/zoom, swipe/overlay/difference modes; keep/reject workflow | All | 1.0 |
| IMG-009 | Editing | Non-destructive: crop (ratios), rotate (free), flip, straighten, exposure/contrast/highlights/shadows/whites/blacks, saturation/vibrance, temperature/tint, sharpen, vignette, curves; draw/annotate/blur region; save copy or overwrite with confirm; batch apply | All | 1.0 |
| IMG-010 | Batch | Rename with tokens, convert (JPEG/PNG/WebP/AVIF/JXL/HEIC where OS can encode), resize, rotate by EXIF, strip metadata | All | 1.0 |
| IMG-011 | Vault | Biometric/PIN-locked encrypted container for chosen items (AES-256-GCM, key in Keychain/Keystore/DPAPI); items hidden from OS gallery (Android: moved to app-private with .nomedia; iOS: app container); decoy option off by default | All | 1.0 |
| IMG-012 | Slideshow | Transitions, interval, random, Ken Burns, music from the Music library, external display, loop; speed adjustable (the feature Apple removed) | All | 1.0 |
| IMG-013 | Duplicates | Perceptual duplicate finder with side-by-side review; never deletes automatically | All | 1.0 |
| IMG-014 | Trash | App recycle bin (30 days, size-capped) in addition to OS trash where available | All | 1.0 |
| IMG-015 | Sharing and output | Share sheet with size/metadata options; set wallpaper/lock screen (A), set desktop (M W); print with layout; copy image; AirDrop/Nearby Share/Quick Share pass-through | All | 1.0 |
| IMG-016 | Sources | Local folders, OS photo library (PhotoKit limited/full, MediaStore), SMB/NFS/WebDAV/FTP/SFTP, Immich, Nextcloud/ownCloud, PhotoPrism (read) (cloud drives removed by ADR-048) | All | 1.0 |
| IMG-017 | Archives | Browse images inside ZIP/CBZ/RAR/CBR/7z with comic reading mode (RTL, two-page, fit modes) | All | 1.0 |
| IMG-018 | Screensaver / ambient | Desktop screensaver module (M W) and ambient mode (A TV) from chosen albums | M W (A TV 1.1) | 1.0 |

## 8. NET — Sources, protocols, servers

| ID | Feature | Acceptance criteria | Platforms | Rel. |
|---|---|---|---|---|
| NET-001 | SMB2/3 | libsmb2; discovery (mDNS/WS-Discovery/NetBIOS), credentials in OS keychain, guest, DFS, large files, seek, encryption/signing | All | 1.0 |
| NET-002 | NFS v3/v4 | libnfs; manual and discovered mounts | All | 1.0 |
| NET-003 | WebDAV | HTTPS, basic/digest, Nextcloud/ownCloud/Synology/Seafile tested; range requests | All | 1.0 |
| NET-004 | FTP/FTPS/SFTP | libcurl/libssh2; key auth for SFTP; resume | All | 1.0 |
| NET-005 | DLNA/UPnP | Browse media servers (SSDP + ContentDirectory); play; our own renderer exposure (opt-in) so TVs/phones can push to Mediahro | All | 1.0 |
| NET-006 | HTTP(S)/HLS/DASH/RTSP/RTMP | Direct URL playback incl. live streams; custom headers/user-agent; no bundled lists, no EPG | All | 1.0 |
| NET-007 | Cloud drives | Removed from 1.0 by owner decision 2026-10-22 (ADR-048): needs a publisher API key | All | — |
| NET-010 | Jellyfin | Full client: auth (incl. Quick Connect), libraries, continue watching, next up, metadata, trickplay, subtitles, direct play preferred, transcode fallback, progress and watched sync, offline downloads, multiple servers/users | All | 1.0 |
| NET-011 | Emby | Same as Jellyfin via Emby API | All | 1.0 |
| NET-012 | Plex | Sign-in (PIN), direct play of local/remote libraries the user owns, progress sync; no Plex-hosted content surfaces | All | 1.0 |
| NET-013 | Subsonic/OpenSubsonic/Navidrome/Airsonic/Gonic | Music client with offline cache, playlists sync, scrobble pass-through, transcoding option | All | 1.0 |
| NET-014 | Immich | Photo/video client: timeline, albums, people, map, search, local-only browsing, backup of chosen folders (opt-in) | All | 1.0 |
| NET-015 | Nextcloud | Files/Photos/Music via WebDAV + Nextcloud APIs; share links | All | 1.0 |
| NET-016 | Audiobookshelf | See POD-003 | All | 1.0 |
| NET-017 | Mediahro-to-Mediahro | Browse and play another Mediahro instance's shared library on the LAN (opt-in, paired by QR, mutual TLS) | All | 1.0 |
| NET-018 | Offline downloads | Any server item downloadable for offline use with size/expiry management | All | 1.0 |
| NET-019 | Connection health | Latency/throughput test per source; cache sizing suggestion; metered-network warnings | All | 1.0 |

## 9. CAST — Casting and external playback

| ID | Feature | Acceptance criteria | Platforms | Rel. |
|---|---|---|---|---|
| CAST-001 | Google Cast | Official Cast SDK (A I); Open Screen/CASTv2 implementation (M W); local files served to the receiver via embedded HTTP server with on-the-fly remux (and transcode fallback for unsupported codecs); subtitles sent as WebVTT; queue; volume; FOSS flavour omits the proprietary SDK and uses the open implementation | All | 1.0 |
| CAST-002 | AirPlay | Sender via AVRoutePicker for compatible formats (MP4/HLS); for others, local remux/transcode to HLS served to the AirPlay target; AirPlay audio for music | I M | 1.0 |
| CAST-003 | DLNA renderer push | Push to any DLNA/UPnP renderer (TVs, speakers) with control | All | 1.0 |
| CAST-004 | External display | See VID-071 | All | 1.0 |
| CAST-005 | Local transcoding | FFmpeg (LGPL) software H.264/AAC transcoder with hardware encode where available (MediaCodec/VideoToolbox/D3D12) for casting fallback; never for library storage | All | 1.0 |

## 10. SYS — Platform integration

| ID | Feature | Acceptance criteria | Platforms | Rel. |
|---|---|---|---|---|
| SYS-001 | Media session | Media3 MediaSessionService (A), MPNowPlayingInfoCenter + MPRemoteCommandCenter (I M), SMTC (W); artwork, seek, skip, speed; works for video audio-only and music | All | 1.0 |
| SYS-002 | Notifications/lock screen | Rich playback notification (A), Lock Screen/Dynamic Island Live Activity (I), Now Playing (M), flyout (W) | All | 1.0 |
| SYS-003 | Shortcuts/intents | Siri Shortcuts/App Intents (I M), Android App Actions/Assistant, Windows jump lists; "play playlist X", "resume last" | All | 1.0 |
| SYS-004 | Share targets | Receive files/URLs via share sheet (A I), Services (M), Explorer "Send to" (W) | All | 1.0 |
| SYS-005 | File provider / Files integration | Appear in Files (I) with open-in-place; Finder Quick Look generator for unsupported formats (M, 1.1); Explorer thumbnail/property handlers (W, 1.1) | I (M W 1.1) | 1.0 |
| SYS-006 | Foreground service & battery | mediaPlayback FGS type (A); no wake-locks after stop; thermal-aware quality scaling | A | 1.0 |
| SYS-007 | Storage access | SAF trees with persisted permissions, Photo Picker fallback, READ_MEDIA_* with declaration, no MANAGE_EXTERNAL_STORAGE (A); PHPicker + limited library + bookmarks (I); sandbox entitlements + bookmarks (M MAS) | All | 1.0 |
| SYS-008 | Accessibility services | VoiceOver/TalkBack/Narrator labels and traits on 100 % of controls; focus order; Dynamic Type/font scale to 200 %; reduce motion/transparency; switch control; captions prefs; audio description track selection | All | 1.0 |
| SYS-009 | Input | Game controllers (TV/desktop), D-pad, Apple Remote, keyboard media keys, mouse wheel seek/volume, trackpad gestures | All | 1.0 |
| SYS-010 | TV mode | Leanback/10-foot UI with focus engine, banner, voice search; Apple TV native UI | A TV, tvOS | 1.1 |
| SYS-011 | Foldables/large screens | Adaptive layouts (list-detail), tabletop posture (player on top half, controls on bottom), window-size classes; no orientation locks on large screens (API 36 rule) | A I | 1.0 |

## 11. SUP — Supporter programme (free app; nothing gated)

| ID | Feature | Acceptance criteria | Platforms | Rel. |
|---|---|---|---|---|
| SUP-001 | Support page | In Settings → "Support Mediahro": honest copy, transparency link, one-time tip amounts (consumable IAP: 3 tiers + custom where allowed) and optional monthly (subscription IAP, cancellable, no perks lost on cancel beyond badge) | All | 1.0 |
| SUP-002 | Store rails | StoreKit 2 (I M), Play Billing (A Play flavour), Microsoft Store/third-party web checkout per policy 10.8.2 (W); FOSS flavour shows Liberapay/GitHub Sponsors links only | All | 1.0 |
| SUP-003 | Web rail | Link to `mediahro.com/support` (merchant of record) shown only where store rules allow (US storefront on Apple; EU under accepted terms; Windows; F-Droid; direct builds); never with perks attached | All | 1.0 |
| SUP-004 | Perks (cosmetic only) | Supporter badge in About, alternate icons, accent pack, name in credits (opt-in), beta channel access; **no feature, codec or limit is ever tied to payment** | All | 1.0 |
| SUP-005 | Ask policy | At most one contextual prompt per quarter after demonstrated value (≥ 20 sessions or ≥ 10 h); dismiss forever; no countdowns, no guilt copy; year-end campaign banner opt-in | All | 1.0 |
| SUP-006 | Transparency | "Where the money goes" page linking the annual report | All | 1.0 |

## 12. PRIV — Privacy and security

| ID | Feature | Acceptance criteria | Platforms | Rel. |
|---|---|---|---|---|
| PRIV-001 | Zero telemetry by default | No analytics, no crash upload, no update check beyond the store, unless each is enabled; first-run explains the three toggles (off) | All | 1.0 |
| PRIV-002 | Opt-in crash reports | Sentry (self-hosted) with PII scrubbing (no paths/filenames/IPs); viewable before send | All | 1.0 |
| PRIV-003 | Opt-in usage analytics | Aptabase events without identifiers; event list published | All | 1.0 |
| PRIV-004 | Network allow-list | Every outbound domain listed in the privacy dashboard; subtitle/metadata/lyrics/scrobble/map each toggleable; FOSS flavour defaults all off | All | 1.0 |
| PRIV-005 | Parsing safety | Subtitle, playlist, metadata and image parsing run in sandboxed isolates/processes with size limits; fuzzed in CI | All | 1.0 |
| PRIV-006 | Credentials | OS keychain/keystore/DPAPI; never in plain files; export encrypted | All | 1.0 |
| PRIV-007 | Vault | See IMG-011; applies to videos and audio too | All | 1.0 |
| PRIV-008 | App lock | Biometric/PIN lock for the whole app (opt-in) | All | 1.0 |

## 13. B2B — Managed deployment, kiosk, engine

| ID | Feature | Acceptance criteria | Platforms | Rel. |
|---|---|---|---|---|
| B2B-001 | Managed configuration | Android Enterprise managed config (restrictions XML), Apple MDM managed app configuration, Windows registry/MSIX policy; keys: allowed sources, locked settings, kiosk flag, branding off, telemetry off, playlist URL, update channel | All | 1.0 |
| B2B-002 | Kiosk/signage mode | Lock-task (A), Guided Access/Single App Mode compatible (I), full-screen kiosk (M W); auto-start playlist on boot, loop, schedule by time/day, multi-screen sync over LAN (NTP-aligned), watchdog restart, remote status page | All | 1.0 |
| B2B-003 | Headless control API | Local HTTP/WebSocket JSON API (loopback by default; LAN opt-in with token) for play/queue/status; OpenAPI spec published | All | 1.0 |
| B2B-004 | Mediahro Engine SDK | The playback core (mpv wrapper, subtitle, HDR, audio DSP) packaged as a library with Dart, Kotlin, Swift and C APIs under AGPL + commercial licence | All | 1.0 (docs/samples 1.1) |
| B2B-005 | Audit and compliance | Accessibility conformance report (EN 301 549 / WCAG 2.2 AA mapping), SBOM (CycloneDX) per release, signed builds, reproducible F-Droid build | All | 1.0 |
| B2B-006 | White-label hooks | Build-time branding variables (name, icon, colours) and feature flags for OEM builds under commercial licence; trademark policy enforced | All | 1.0 |

## 14. Platform parity summary

| Area | Android | iOS/iPadOS | macOS | Windows | Notes |
|---|---|---|---|---|---|
| Video engine, HDR, shaders, subtitles | Full | Full | Full | Full | libmpv everywhere |
| Audio passthrough | Full | Limited (OS) | Full | Full | iOS has no bitstream API; decode to PCM/spatial |
| Bit-perfect | USB DAC (API 34+) | Best effort | Hog mode | WASAPI/ASIO | Indicator shows truth |
| Casting | Cast SDK + DLNA | Cast SDK + AirPlay + DLNA | Open Cast + AirPlay + DLNA | Open Cast + DLNA | AirPlay sender is Apple-only |
| Photo library access | MediaStore/SAF/Picker | PhotoKit/PHPicker/Files | Folders + Photos (read) | Folders + Pictures | Store policies in doc 07 |
| Vault | Full | Full | Full | Full | |
| Car | Android Auto | CarPlay | — | — | |
| Watch | 1.1 | 1.1 | — | — | |
| TV | Compatibility 1.0, Leanback 1.1 | tvOS 1.1 | — | — | |
| Managed config / kiosk | Full | Full | Full | Full | |

## 15. Explicitly excluded (policy)

IPTV channel lists or directories, EPG, add-on/plugin marketplaces that fetch content, torrent/magnet, DRM circumvention (no libdvdcss/AACS), AirPlay receiver (MFi), ads, accounts, cloud storage of user media operated by Mediahro.
