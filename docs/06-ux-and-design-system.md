# 06 — UX and Design System

Version 1.0 · 2026-10-19 · Normative for all screens. Visual direction: calm, dense-but-breathable, content-first; chrome recedes, media is the hero.

## 1. Design principles

1. **Content first.** Video and photos render edge-to-edge on true black; chrome is translucent and auto-hides. Nothing is drawn over the picture unless the user asked for it.
2. **One tap to play.** From any screen the most likely action is reachable in one tap: a file row plays, an album row plays, a photo opens.
3. **Native idioms, shared structure.** Navigation, pickers, share sheets, typography and motion follow each platform; information architecture, terminology and feature placement are identical everywhere so documentation and support are one.
4. **Discoverable power.** Advanced features sit one level below the obvious control (long-press, overflow, "More") with consistent labelling; nothing requires a config file.
5. **Never nag.** No modals on launch, no ratings pop-ups, no supporter prompts outside SUP-005 rules.
6. **Accessible by construction.** Every component ships with labels, focus order, 44×44 pt targets, contrast ≥ 4.5:1, reduced-motion variants.

## 2. Information architecture

```
Mediahro
├── Video            (tab / sidebar)
│   ├── Home: Continue watching · Recently added · Unwatched · Collections
│   ├── Library: Movies · Series · Other videos · Folders · Playlists
│   ├── Sources (filter chip): All · Local · NAS… · Jellyfin…
│   └── Player (full-screen route)
├── Music
│   ├── Home: Recently played · Recently added · Mixes (smart) · Queues
│   ├── Library: Songs · Albums · Artists · Genres · Years · Composers · Folders · Playlists · Podcasts & Audiobooks
│   ├── Now Playing (bottom mini-bar → sheet)
│   └── Queue (sheet)
├── Photos
│   ├── Timeline (years → months → days)
│   ├── Library: Albums · Folders · People · Places · Favourites · Vault · Trash · Duplicates
│   ├── Viewer (full-screen route) · Compare · Editor
│   └── Map
├── Sources           (shared: add/manage local folders, shares, servers, cloud; health)
├── Search            (global, scoped by current mode by default)
└── Settings          (searchable; Playback · Video · Audio · Subtitles · Photos · Library · Sources · Appearance · Shortcuts · Privacy · Support Mediahro · About)
```

Navigation surfaces:

| Form factor | Primary nav | Secondary |
|---|---|---|
| Phone (A, I) | Bottom bar: Video · Music · Photos · Search · Settings (A: Material 3 navigation bar; I: tab bar with Liquid Glass) | Top app bar with source chip and sort/filter |
| Tablet / foldable (A, I) | Navigation rail (A) / sidebar (I) with list-detail | Same |
| macOS | Sidebar (source list style) with sections; toolbar; menu bar with full menus | Inspector pane for info |
| Windows | NavigationView (left, collapsible) with Mica; command bar | Info pane |
| TV (1.1) | Leanback rows with left rail | — |

## 3. Key screens

### 3.1 Video player

- **Surface:** video on black; letterbox area is black; HDR surfaces when the display supports it.
- **Chrome (auto-hide after 3 s; tap to toggle; never during gestures):** top: back, title (episode name + series), source badge, cast button, PiP, overflow. Bottom: seek bar with chapter ticks and thumbnail preview, elapsed/remaining (tap to toggle), play/pause, ±10 s, speed chip, subtitle chip, audio chip, lock, rotate (mobile), fullscreen (desktop).
- **Gesture layer (mobile):** per VID-060; visual feedback is a thin ring or bar near the gesture, not a centred popup; haptics on boundaries.
- **Side sheets:** Subtitles (tracks, download, style, delay, sync, OCR, dual), Audio (tracks, delay, boost, passthrough, EQ), Video (aspect, zoom, filters, shaders, HDR mode, deinterlace), Info (stats overlay toggle), Chapters/Bookmarks, Queue/Next up.
- **Desktop:** keyboard-first; scroll wheel seek; right-click context menu; always-on-top mini window; drag-drop subtitles onto the window.
- **End of item:** quiet "Next: …" card with countdown (cancellable) or returns to list per setting.

### 3.2 Music Now Playing

- Art dominant with blurred backdrop (optional), title/artist/album tappable, progress with time, transport, shuffle/repeat, output picker (route icon), lyrics toggle, queue toggle, EQ shortcut, favourite, rating, sleep timer, "add to", info.
- Lyrics view: synced lines, tap to seek, font size control, LRC editor entry.
- Mini-bar persistent across the app (not over the video player).
- Landscape phone: art left, controls right. Tablet/desktop: three-pane (library, queue, now playing) or compact window.

### 3.3 Photos timeline and viewer

- Timeline: square or aspect grid (toggle), pinch to change density (1–6 columns phone, up to 12 desktop), year/month scrubber on the edge, selection mode with drag-select, badges for RAW/Live/Motion/HDR/video duration.
- Viewer: edge-to-edge; chrome shows title/date/location; actions: share, favourite, info (sheet with EXIF/map/histogram), edit, compare (add to compare tray), delete, more (rotate, set as, print, copy, vault, slideshow from here).
- Compare: 2-up/4-up with synced pan/zoom, swipe/overlay/diff; keep/reject toolbar.
- Editor: non-destructive sliders with before/after press-and-hold; crop with ratio presets; draw tools; save copy default.

### 3.4 Sources

- List of sources with health dot, last scan, item counts; add flow: Local folder · Network share (SMB/NFS/WebDAV/FTP/SFTP) with discovery list · Media server (Jellyfin/Emby/Plex/Subsonic/Immich/Nextcloud/Audiobookshelf) · Cloud drive · DLNA · Another Mediahro.
- Credentials screens explain where secrets are stored; test connection before save; per-source toggles (scan schedule, metadata, include in modes).

### 3.5 Settings

- Searchable; grouped; every row has a one-line description; Advanced sections collapsed; "Reset section"; per-platform rows hidden when not applicable; managed-config-locked rows show a lock icon with "Managed by your organisation".

### 3.6 Supporter page

- Headline: "Mediahro is free for everyone." Paragraph on funding; three tip buttons and a monthly option; link to transparency; badge preview; "Not now" is a plain text button, same weight as the rest. No countdown, no comparison tables, no "most popular" tags.

### 3.7 First run

- One screen: logo, one sentence, three buttons (Open a file · Add a folder · Add a server), a small "Privacy: nothing leaves this device unless you turn it on" line linking to the privacy dashboard. No carousel.

## 4. Design tokens

| Group | Tokens |
|---|---|
| Spacing | 4, 8, 12, 16, 20, 24, 32, 40, 48 (dp/pt) |
| Radius | xs 4, sm 8, md 12, lg 16, xl 24, pill |
| Elevation | 0, 1 (cards), 2 (sheets), 3 (dialogs); platform shadow/blur mapping |
| Type scale | display, headline, title, body, label; maps to SF/Roboto/Segoe variable; Dynamic Type/font scale respected up to 200 % with layout reflow |
| Colour roles | background, surface, surface-variant, on-surface, primary (mode accent), on-primary, outline, error, success, player-surface (#000), player-chrome (white 92 %/ black 60 % scrim), subtitle-default (#FFFFFF with #000000 outline) |
| Motion | duration-fast 120 ms, base 200 ms, slow 300 ms; spring (stiffness 400, damping 30); reduced-motion = crossfade only |
| Icons | Material Symbols (A, W), SF Symbols (I, M) via a semantic icon map (`KIcon.play`), own glyphs for mode badges |
| Shape | Material 3 Expressive shapes on Android (rounded/squircle), Apple continuous corners, Fluent 8 px |

Implemented in `packages/mediahro_design` as `ThemeExtension`s; one `MediahroTheme` builder per platform family.

## 5. Platform adaptation rules

| Concern | Android | iOS/iPadOS | macOS | Windows |
|---|---|---|---|---|
| Visual language | Material 3 Expressive, dynamic colour opt-in, edge-to-edge, predictive back | Liquid Glass translucency for bars/sheets only (never over video), system materials, large titles | Sidebar + toolbar, Tahoe icon style, menu bar with full command set, Settings window | Fluent 2, Mica backdrop, NavigationView, context menus, title-bar integration |
| Navigation | Navigation bar / rail; back gesture | Tab bar / sidebar; swipe-back | Sidebar | NavigationView |
| Pickers | SAF / Photo Picker | Document picker / PHPicker | NSOpenPanel | File pickers |
| Share | Share sheet | Share sheet | Share menu | Share UI |
| Typography | Roboto/Google Sans Flex | SF Pro / New York (none) | SF Pro | Segoe UI Variable |
| Haptics | Yes (gesture boundaries) | Yes | No | No |
| Keyboard | Media keys, shortcuts | iPad hardware keyboard | Full menu shortcuts | Full shortcuts, Alt accelerators |
| Window chrome | — | Stage Manager resizable | Native; full-screen mode | Custom title bar with Mica; snap layouts |

## 6. Gesture and shortcut reference

### 6.1 Touch (player)

| Gesture | Action | Configurable |
|---|---|---|
| Tap | Toggle chrome | — |
| Double-tap left/right | Seek −/+ (10 s default) | 5–60 s |
| Double-tap centre | Play/pause | on/off |
| Horizontal drag | Seek with preview | sensitivity |
| Vertical drag left | Brightness | on/off |
| Vertical drag right | Volume | on/off |
| Long-press | 2× speed while held | speed |
| Pinch | Zoom/fit cycle | on/off |
| Two-finger horizontal drag | Subtitle delay | on/off |
| Two-finger tap | Screenshot | on/off |
| Swipe down from top (mobile) | Exit to PiP / mini | on/off |

### 6.2 Keyboard (desktop; all remappable)

| Key | Action |
|---|---|
| Space / K | Play/pause |
| ← → | Seek 5 s; Shift 1 s; Ctrl/Cmd 60 s |
| J / L | Seek −10 / +10 |
| ↑ ↓ | Volume |
| M | Mute |
| F / Esc | Fullscreen / exit |
| [ ] | Speed −/+ 0.1; Backspace resets |
| , . | Frame step back/forward |
| S | Subtitle track cycle; Shift+S toggle |
| A | Audio track cycle |
| Z X | Subtitle delay −/+ 50 ms |
| C V | Audio delay −/+ 10 ms |
| I | Info overlay |
| P | PiP |
| T | Always on top |
| Ctrl/Cmd+S | Screenshot |
| B / N | A-B loop set / clear |
| 1–9 | Jump to 10 %–90 % |
| Ctrl/Cmd+O / U | Open file / URL |
| Ctrl/Cmd+, | Settings |
| ? | Shortcut sheet |

## 7. Accessibility specification

- Labels and roles on every control; dynamic labels announce state ("Play", "Pause", "Subtitles: English, on").
- Focus order follows visual order; focus visible on all platforms; D-pad/TV focus engine.
- Captions follow system caption style by default (MACaptionAppearance / CaptioningManager / Windows closed-caption settings) with Mediahro overrides available.
- Audio description tracks are selectable and announced; "prefer audio description" preference.
- Reduce motion: no parallax, no autoplaying previews, crossfades only.
- Reduce transparency: opaque chrome.
- Dynamic Type up to 200 %: layouts reflow, no truncation of primary labels.
- Colour is never the only state carrier (icons + text).
- Screen-reader-specific affordances: "Describe image" via platform Vision/ML Kit (opt-in), rotor/actions for seek, VoiceOver-friendly seek bar with 1 %/10 % increments.
- Accessibility Nutrition Labels (Apple) declared truthfully: VoiceOver, Voice Control, Larger Text, Dark Interface, Differentiate Without Color Alone, Sufficient Contrast, Reduced Motion, Captions, Audio Descriptions.
- Conformance target EN 301 549 / WCAG 2.2 AA; report shipped with B2B-005.

## 8. Content and copy guidelines

- Sentence case everywhere; no exclamation marks; no jargon in primary labels ("Subtitles", not "ASS/SSA renderer"); technical detail in secondary text.
- Errors: "Couldn't open this file. It may be corrupt or on a disconnected drive." plus one action ("Try again", "Choose another").
- Permission rationale screens explain *what for* and *what happens if denied* before the OS prompt.
- Numbers formatted per locale; durations as `1:23:45`; sizes in binary units with one decimal.

## 9. Empty, loading, error states

- Empty library: illustration-free, one sentence, the three add buttons.
- Loading: skeleton rows (no spinners) under 300 ms; progress bar for scans with pause.
- Offline source: dimmed with "Unavailable — last seen 2 h ago"; cached items still play.
- Unsupported format: info sheet with codec string, copy-to-clipboard and "Report a playback problem" (opens issue template, no telemetry).

## 10. Deliverables for the build

- Figma-equivalent is not required: the build implements these specs directly with golden tests per screen and per platform family (doc 11).
- `packages/mediahro_design` exports tokens, theme builders, icon map, component library (`KButton`, `KSeekBar`, `KSheet`, `KGrid`, `KRow`, `KChip`, `KSidebar`, `KPlayerChrome`, `KMiniPlayer`, `KCompareView`, `KTimelineScrubber`).
- Screenshot sets for all stores are generated from the running app via the integration-test harness (doc 12).
