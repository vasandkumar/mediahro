# Android 1.0 feature tiers

Date: 2026-10-22. Source: docs/04 (1.0 rows that apply to Android), STATUS.md and merged code on main. Nothing here is committed.

Status meanings: **Verified** = ticked on Android. **Built** = code is merged, not ticked yet (usually a phone test or hand check is waiting). **Partly built** = some of it is merged. **Blocked** = STATUS marks it blocked. **Not built** = no merged Android code.

## 1. Summary

| Tier | Total | Verified | Built | Partly built | Blocked | Not built |
|---|---:|---:|---:|---:|---:|---:|
| Essential | 53 | 25 | 23 | 1 | 4 | 0 |
| Good to have | 64 | 17 | 30 | 7 | 2 | 8 |
| Advanced | 57 | 10 | 18 | 3 | 11 | 15 |
| Total | 174 | 52 | 71 | 11 | 17 | 23 |

Each feature is counted once; the five status columns add up to Total.

## 2. What is left for Essential

- **CORE-001 Video, Music and Photos tabs** (Blocked): The tabs work. Only the "switch under 100 ms" speed test cannot run on the phone yet (wireless adb cannot reach the profiler).
- **CORE-013 About screen and open-source licences** (Partly built): The open-source licence data is registered, but there is no About screen showing version, licences and links yet.
- **VID-002 Video codecs (H.264, HEVC, AV1 and more)** (Blocked): Video plays; VC-1 has no test file, so the full codec list cannot be ticked. VVC and HAP now pass.
- **VID-003 Audio codecs inside videos** (Blocked): Common audio plays; DTS-HD and DTS:X have no test files, so the list cannot be ticked.
- **AUD-001 Music file types (MP3, FLAC, DSD and more)** (Blocked): Most music types play; TAK, SACD ISO and MIDI still have no test files or synth.

Also: 23 Essential features are built but not ticked. They need a phone test or an owner hand check, not new code.

## 3. Essential (53)

| ID | Feature | Android status | Note |
|---|---|---|---|
| CORE-001 | Video, Music and Photos tabs | Blocked | Speed test cannot reach phone over wireless adb |
| CORE-002 | First run with no sign-in or permissions | Verified | Ticked on Android |
| CORE-003 | Open files from other apps | Built | Needs owner hand check |
| CORE-006 | Settings screen | Verified | Ticked on Android |
| CORE-007 | Light, dark, AMOLED and Material You themes | Verified | Ticked on Android |
| CORE-011 | Crash resilience and auto-saved position | Verified | Ticked on Android |
| CORE-013 | About screen and open-source licences | Partly built | Licence data registered; About screen not built |
| CORE-015 | Privacy dashboard | Verified | Ticked on Android |
| LIB-001 | Library database of all media | Built | Code merged; speed proven by LIB-003 |
| LIB-002 | Local storage, SD card and USB sources | Built | Storage tests passed on phone |
| LIB-003 | Fast library scan | Verified | Ticked on Android |
| LIB-004 | Folder view and library view toggle | Built | Code merged; needs phone test |
| LIB-005 | Instant search with filters | Verified | Ticked on Android |
| LIB-007 | Playlists and M3U/PLS import and export | Built | Code merged; needs phone test |
| FILE-001 | File browser | Built | Code merged; needs phone test |
| FILE-002 | Rename, move, copy, delete, share | Built | Code merged; needs phone test |
| VID-001 | Video file types (MKV, MP4, AVI and more) | Verified | Ticked on Android |
| VID-002 | Video codecs (H.264, HEVC, AV1 and more) | Blocked | No VC-1 test sample exists |
| VID-003 | Audio codecs inside videos | Blocked | No DTS-HD test samples |
| VID-005 | Huge, broken and odd video files | Verified | Ticked on Android |
| VID-060 | Swipe gestures (volume, brightness, seek) | Verified | Ticked on Android |
| VID-061 | Seek bar with previews | Verified | Ticked on Android |
| VID-062 | Playback speed | Verified | Ticked on Android |
| VID-064 | Resume and what plays next | Verified | Ticked on Android |
| VID-065 | Switch audio and subtitle tracks | Verified | Ticked on Android |
| VID-067 | Picture-in-picture | Built | Needs owner hand check |
| VID-068 | Background and audio-only playback | Built | Needs owner hand check |
| VID-070 | Rotation, notch and keep-awake | Built | Needs owner hand check |
| SUB-010 | Subtitle text formats (SRT, ASS, VTT) | Built | Engine passes; player menus built |
| SUB-012 | Embedded and external subtitle files | Built | Needs owner hand check |
| SUB-013 | Subtitle character-set detection | Built | Engine tests pass on phone |
| SUB-014 | Subtitle styling and system caption style | Built | Needs owner hand check |
| AUD-001 | Music file types (MP3, FLAC, DSD and more) | Blocked | No TAK, SACD ISO or MIDI samples |
| AUD-045 | Pause for calls and other apps | Built | Code merged; needs phone test |
| MUS-001 | Music library views | Verified | Ticked on Android |
| MUS-002 | Read song tags | Verified | Ticked on Android |
| MUS-004 | Album art | Verified | Ticked on Android |
| MUS-006 | Now Playing screen | Verified | Ticked on Android |
| MUS-007 | Play queue | Verified | Ticked on Android |
| IMG-001 | Photo file types (JPEG, HEIC, RAW, SVG) | Built | Hand checks for odd formats pending |
| IMG-003 | Fast gallery | Verified | Ticked on Android |
| IMG-004 | Photo viewer with zoom | Verified | Ticked on Android |
| IMG-014 | Recently deleted bin | Built | Phone tests passed; hand check pending |
| IMG-015 | Share, wallpaper, print, copy | Built | Needs owner hand check |
| SYS-001 | Media session and headset buttons | Verified | Ticked on Android |
| SYS-002 | Notification and lock-screen controls | Verified | Ticked on Android |
| SYS-006 | Background service and battery care | Verified | Ticked on Android |
| SYS-007 | Storage access done right | Verified | Ticked on Android |
| SYS-008 | TalkBack and large-text support | Built | Code merged; hand check pending |
| PRIV-001 | No telemetry by default | Built | First-run explainer built; hand check pending |
| PRIV-004 | Network allow-list in dashboard | Built | Dashboard ticked; per-feature toggles built |
| PRIV-005 | Safe parsing of untrusted files | Built | Isolates and size limits built |
| PRIV-006 | Passwords kept in Android keystore | Built | Facade built; needs phone test |

## 4. Good to have (64)

| ID | Feature | Android status | Note |
|---|---|---|---|
| CORE-005 | Open a web or network stream by link | Built | Code merged; last 50 links kept |
| CORE-008 | Languages and right-to-left layout | Partly built | Pipeline done; the 12 translations still to come |
| CORE-012 | Update notes inside the app | Not built | Play handles updates; release notes screen missing |
| CORE-014 | Backup and restore to one encrypted file | Built | Code merged; needs phone test |
| LIB-006 | Continue watching and recently added rows | Built | Code merged; needs phone test |
| LIB-008 | Multiple named queues | Verified | Ticked on Android |
| LIB-009 | Tags and colour labels | Verified | Ticked on Android |
| LIB-010 | Watched marks and server sync | Partly built | Local marks done; server sync waits on servers |
| LIB-011 | Local movie and show info and posters | Built | Code merged; online lookups were removed |
| LIB-012 | Grouping into series, albums, artists | Built | Code merged; needs phone test |
| LIB-014 | Duplicate finder | Built | Code merged; needs phone test |
| LIB-015 | Play statistics | Verified | Ticked on Android |
| FILE-003 | Batch rename, convert and tag | Built | Code merged; needs phone test |
| FILE-006 | Subtitle files kept with their video | Built | Code merged; needs phone test |
| VID-006 | Play from network shares | Verified | Ticked on Android |
| VID-037 | Crop, deinterlace, sharpen, colour | Built | Needs owner hand check |
| VID-042 | Screenshot, GIF and clip export | Partly built | Engine export done; no player screen yet |
| VID-063 | Frame step, A-B loop, chapters, bookmarks | Verified | Ticked on Android |
| VID-066 | Audio delay and volume boost | Built | Needs owner hand check |
| VID-069 | Video sleep timer | Built | Needs owner hand check |
| VID-072 | Playback info overlay | Verified | Ticked on Android |
| SUB-011 | Image subtitles (PGS, VobSub) | Built | Engine passes; player menus built |
| SUB-015 | Subtitle delay and speed | Built | Needs owner hand check |
| AUD-002 | Gapless playback | Verified | Ticked on Android |
| AUD-003 | Crossfade | Verified | Ticked on Android |
| AUD-004 | Loudness levelling | Verified | Ticked on Android |
| AUD-005 | Equalizer and sound effects | Verified | Ticked on Android |
| AUD-044 | Bluetooth headphones polish | Partly built | Delay and pre-roll hooks only; no phone test |
| MUS-003 | Tag editing | Built | Phone test failing; fix merged, re-run pending |
| MUS-005 | Lyrics | Verified | Ticked on Android |
| MUS-008 | Smart playlists | Verified | Ticked on Android |
| MUS-011 | Sleep timer and alarms | Verified | Ticked on Android |
| MUS-012 | Home-screen widgets | Verified | Ticked on Android |
| MUS-013 | Android Auto | Built | Needs owner hand check |
| MUS-014 | Internet radio | Built | Pause on live station failed; fix merged |
| POD-001 | Audiobook mode | Built | Phone test and hand checks pending |
| POD-002 | Podcasts | Partly built | Background refresh merged; feeds and player not merged |
| IMG-005 | Albums, favourites, ratings, People | Partly built | Face grouping not merged; rest built |
| IMG-006 | Photo details (EXIF) | Verified | Ticked on Android |
| IMG-007 | Places tab and location editing | Built | Map view removed by owner; hand check pending |
| IMG-009 | Photo editor | Built | Needs owner hand check |
| IMG-010 | Batch photo tools | Built | Needs owner hand check |
| IMG-012 | Slideshow | Built | Needs owner hand check |
| IMG-013 | Photo duplicate finder | Built | Phone tests passed; hand check pending |
| IMG-016 | Photo sources | Partly built | Immich, Nextcloud, PhotoPrism missing |
| NET-001 | SMB network shares | Blocked | Live server test run still pending |
| NET-002 | NFS network shares | Blocked | Live server test run still pending |
| NET-003 | WebDAV | Built | Tested against local server only |
| NET-004 | FTP, FTPS and SFTP | Verified | Ticked on Android |
| NET-005 | DLNA/UPnP browsing and renderer | Built | Tested on test network only |
| NET-006 | Web, HLS, DASH, RTSP, RTMP streams | Built | Code merged; needs phone test |
| NET-018 | Offline downloads | Built | Code merged; needs phone test |
| CAST-001 | Google Cast | Not built | Not started |
| CAST-003 | Push to DLNA TVs and speakers | Not built | Not started |
| CAST-005 | Local transcoding for casting | Verified | Ticked on Android |
| SYS-003 | Assistant and app shortcuts | Built | Needs owner hand check |
| SYS-004 | Receive shared files and links | Built | Needs owner hand check |
| SYS-011 | Tablets and foldables layout | Built | Needs a foldable or tablet test |
| SUP-001 | Support Mediahro page | Not built | Not started |
| SUP-002 | Tips through Google Play | Built | Real payment hand check pending |
| SUP-003 | Web donation link | Not built | Not started |
| SUP-005 | Gentle ask rules | Not built | Not started |
| SUP-006 | Where the money goes page | Not built | Not started |
| PRIV-008 | App lock | Not built | Only fingerprint helper exists; no lock screen |

## 5. Advanced (57)

| ID | Feature | Android status | Note |
|---|---|---|---|
| CORE-009 | Keyboard shortcuts | Verified | Mostly useful for tablets with keyboards |
| LIB-013 | Parental PIN and hidden items | Built | Code merged; needs phone test |
| FILE-004 | Browse ZIP, RAR and 7z archives | Blocked | STATUS says libarchive proof pending |
| FILE-005 | Wi-Fi transfer page with QR code | Built | Code merged; needs phone test |
| VID-004 | Sound passthrough to receivers | Blocked | Needs HDMI/SPDIF test equipment |
| VID-007 | DVD and Blu-ray folders | Verified | Ticked on Android |
| VID-030 | Fast GPU video drawing (4K60) | Blocked | Needs device lab zero-copy and 4K60 check |
| VID-031 | HDR10 and HLG display | Blocked | Flutter textures are 8-bit |
| VID-032 | HDR10+ | Verified | Ticked on Android |
| VID-033 | Dolby Vision 8.1/8.4 | Blocked | No 8.4 sample or info check |
| VID-034 | Dolby Vision profile 5 | Blocked | No samples, libdovi missing |
| VID-035 | Dolby Vision profile 7 | Blocked | No test samples |
| VID-036 | Match screen refresh rate to video | Verified | Ticked on Android |
| VID-038 | Upscaling shaders (Anime4K, FSR, grain) | Built | Needs owner hand check |
| VID-039 | Smooth-motion frame interpolation | Verified | Ticked on Android |
| VID-041 | 3D and 360 degree video | Built | Needs owner hand check |
| VID-071 | Video on an external screen | Partly built | Slideshow external display done; video not confirmed |
| VID-073 | Skip intro and credits | Not built | Only a server-marker interface exists |
| VID-074 | Remote control | Partly built | Media keys done; LAN web remote missing |
| SUB-016 | Two subtitles at once | Built | Needs owner hand check |
| SUB-030 | Subtitle editor | Built | Needs owner hand check |
| SUB-040 | Read subtitles aloud | Verified | Ticked on Android |
| SUB-050 | Auto-sync subtitles to audio | Verified | Ticked on Android |
| SUB-051 | Turn image subtitles into text (OCR) | Built | Needs owner hand check |
| SUB-052 | Auto-generated captions | Not built | Video side not built |
| SUB-053 | Subtitle translation on the phone | Built | Needs owner hand check |
| AUD-006 | Output quality indicator | Verified | Ticked on Android |
| AUD-040 | Bit-perfect USB DAC output | Blocked | Needs USB DAC test equipment |
| AUD-043 | DSD music playback | Blocked | Needs owner hand check on real DAC |
| AUD-046 | Music visualiser | Verified | Ticked on Android |
| MUS-009 | Scrobbling to ListenBrainz | Built | Phone re-run pending |
| POD-003 | Audiobookshelf client | Not built | Code in open PR, not merged |
| IMG-002 | HDR photos | Built | Needs owner hand check |
| IMG-008 | Compare photos side by side | Built | Phone tests passed; hand check pending |
| IMG-011 | Photo vault | Built | Phone tests pass; fingerprint hand check pending |
| IMG-017 | Comic reader for CBZ and CBR | Built | Needs hand check with real comics |
| NET-010 | Jellyfin | Not built | Only a shared interface exists |
| NET-011 | Emby | Not built | Not started |
| NET-012 | Plex | Not built | Not started |
| NET-013 | Subsonic and Navidrome | Not built | Not started |
| NET-014 | Immich | Not built | Not started |
| NET-015 | Nextcloud | Not built | Not started |
| NET-016 | Audiobookshelf source | Not built | Not started |
| NET-017 | Mediahro to Mediahro sharing | Verified | Ticked on Android |
| NET-019 | Connection health test | Built | Code merged; needs phone test |
| CAST-004 | External display | Partly built | Slideshow done; video not confirmed |
| SYS-009 | Game controllers and D-pad | Built | Test fix merged; real controller check pending |
| SUP-004 | Cosmetic supporter perks | Not built | Not started |
| PRIV-002 | Opt-in crash reports | Blocked | On hold by owner decision |
| PRIV-003 | Opt-in usage statistics | Blocked | On hold by owner decision |
| PRIV-007 | Hidden videos and music in vault | Built | Phone tests passed; hand check pending |
| B2B-001 | Managed configuration for companies | Built | Phone tests passed; MDM tenant check pending |
| B2B-002 | Kiosk and signage mode | Built | Phone tests passed; hand check pending |
| B2B-003 | Remote control API | Not built | Not started |
| B2B-004 | Engine SDK for developers | Not built | Not started |
| B2B-005 | Compliance reports | Not built | Not started |
| B2B-006 | White-label builds | Not built | Not started |
