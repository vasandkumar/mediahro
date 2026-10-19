# 03 — Brand and Naming

Version 1.1 · 2026-10-19 · Synthesises `research/06` plus checks run on 2026-10-19 (Apple iTunes Search API, Microsoft Store search endpoint, GitHub, DNS, web search). Version 1.1 records the owner's decision to adopt **Mediahro** over the research shortlist.

> This document is a pre-clearance. It is **not legal advice**. A professional trademark clearance search and an attorney opinion are required before filing and before the first public use of the name (see §6).

## 1. Decision

**The app is named Mediahro.** Pronounced MEE-dee-ah-roh (the "h" is a soft breath; "media-hero" is an acceptable and welcome mis-hearing). Wordmark in sentence case: *Mediahro*. Never "MEDIAHRO" in running text, never "Mediahro Player" as the product name (that is a descriptor allowed in store subtitles).

| Attribute | Value |
|---|---|
| Name | Mediahro |
| Origin | Coined by the owner: "media" plus a distinctive "-hro" ending. The spelling makes it unique while the root keeps it self-explanatory. |
| Length | 8 letters, 3–4 syllables, no diacritics, spelled identically in every Latin-script language; transliterates cleanly (メディアロ, 메디아로, मीडियाह्रो, ميدياهرو) |
| Meaning check | No meaning, negative or otherwise, found in Spanish, Portuguese, Hindi, Arabic, Chinese, Japanese, German, French, Finnish, Swedish; "media" root is understood everywhere |
| Variable use | "Mediahro" (product), "Mediahro for Android/iOS/Mac/Windows" (platform builds), "Mediahro Supporter" (supporter programme), "Mediahro Engine" (the SDK/B2B licence of the playback core), "Mediahro Kiosk" (signage edition), `mediahro` (CLI, package, GitHub org). "Mediahro Pro" is **not** used (there is no paid tier). |
| Tagline | Every file. Every screen. Nothing in the way. |
| Primary domain | `mediahro.com` (DNS does not resolve on 2026-10-19; appears available — verify and register immediately) |
| Secondary domains | `mediahro.app`, `mediahro.io`, `mediahro.dev`, `mediahro.media` (all appear available; register .app and .io at minimum, redirect to .com) |
| GitHub | `github.com/mediahro` is free (404 on 2026-10-19) |
| Application IDs | Android `com.mediahro.app`; iOS/macOS bundle `com.mediahro.app` (extensions `com.mediahro.app.*`); Windows MSIX identity `Mediahro.Mediahro`; F-Droid uses the same Android ID; engine SDK `com.mediahro.engine` |

## 2. Clearance snapshot (2026-10-19)

| Check | Result |
|---|---|
| Apple App Store (iTunes Search API, exact and prefix) | No app named Mediahro; nearest hit "Mediahub" (unrelated) |
| Google Play | No app named Mediahro *(verify manually; the Play web search renders client-side)* |
| Microsoft Store (search endpoint) | No app named Mediahro |
| Web search for the exact string | Zero results; engines fall back to Mediahub, MediaHQ, HIRO Media |
| GitHub organisation | Free |
| Domains | .com/.app/.io/.dev/.media/.so all appear unregistered |
| Trademark registers | Not queryable by automation (USPTO TESS, EUIPO, TMview, WIPO blocked fetches). Nearest known marks in class 9 to assess with counsel: **MEDIAROOM** (Ericsson/MediaKind IPTV platform), **Mediahub** (IPG media agency, class 35), **MediaHQ** (PR software). None is identical; the shared element is the generic word "media", which registers weakly on its own, so the distinctive "-hro" ending is what carries the mark. |

Pre-counsel risk rating: **Low–Medium.** The generic "media" root means the mark will be assessed on its full form; the coined ending has no known neighbours. The descriptive root also helps store search ("media player" intent).

### 2.1 Why Mediahro over the research shortlist

| Criterion | Mediahro | Kuvio | Mediaro | Fovea |
|---|---|---|---|---|
| Exact-name apps on Apple / Play / Microsoft | None / none / none | None / none / none | None / none / none | 5 non-media apps on Apple |
| Known class 9 neighbours | MEDIAROOM (shared generic root only) | Nordic trade names (Kuvio Oy/AB) | MEDIAROOM | **FOVE** (US reg., image-processing software), Fovea AS |
| Says what it does | Yes | No | Yes | No |
| Distinctiveness of the whole mark | Medium–High (coined ending) | High | Medium | High |
| .com available | **Yes** | No | No (premium) | No |
| GitHub org free | Yes | Yes | Yes | No |
| Overall | **Low–Medium, .com in hand** | Low–Medium, no .com | Medium | Medium–High |

Mediahro keeps Mediaro's self-explanatory root and improves on it in three ways: the spelling is unique on the web, the .com is available, and the extra letter moves it further from MEDIAROOM.

**Fallback order:** 1. Mediahro → 2. Kuvio → 3. Mediaro → 4. Fovea.

## 3. Brand identity system

### 3.1 Personality

Calm, precise, generous. Mediahro speaks like a knowledgeable friend who set up your media once and never mentions it again. It never boasts about codecs in the UI; it just plays the file.

Voice rules: plain words, no exclamation marks, no "awesome", no marketing adjectives in-app; error messages say what happened and what to do next; supporter copy is honest ("Mediahro is free for everyone. If it's useful to you, you can help pay for it.").

### 3.2 Logo direction

- **Mark:** a rounded square containing three overlapping, slightly rotated rounded rectangles (a frame, a waveform bar, a photo) that resolve into a single "M" negative space at icon size — the three media types in one shape. No play-triangle (over-used), no film reel, no musical note.
- **Icon:** platform-specific masks (iOS squircle, Android adaptive icon with monochrome layer for themed icons, macOS Tahoe icon with Liquid Glass layering, Windows 1:1 tile with transparent padding).
- **Alternate icons** (supporter perk, cosmetic only): six colourways plus a monochrome set.
- **Wordmark:** geometric sans; the "h" and "r" ligate so the distinctive "-hro" ending reads as one gesture; lowercase "mediahro" acceptable in the wordmark, sentence case in text.

### 3.3 Colour

| Token | Light | Dark | Use |
|---|---|---|---|
| `brand.primary` | #3A5BFF (ultramarine) | #7B93FF | Accent, progress, active states |
| `brand.secondary` | #FF7A59 (coral) | #FF9A80 | Audio mode accent |
| `brand.tertiary` | #22C3A6 (teal) | #5EDDC6 | Image mode accent |
| `surface.player` | #000000 | #000000 | Video surface always true black |
| `text.onPlayer` | #FFFFFF 92 % | same | Player chrome text |

Each mode (Video, Music, Photos) carries its own accent so the user always knows where they are; Android Material You dynamic colour can override `brand.primary` when the user opts in.

### 3.4 Typography

System fonts only in UI (SF Pro, Roboto/Google Sans Flex, Segoe UI Variable) for native feel and zero licence risk. Subtitles render with bundled OFL fonts (Noto Sans, Noto Sans CJK, Noto Sans Arabic/Devanagari/Thai/Hebrew) plus the system font directory via libass font providers.

### 3.5 Motion and sound

Motion follows each platform's reduced-motion setting; 200–300 ms spring curves; no bounce on the player surface. No UI sounds.

### 3.6 Store presentation

- App name: **Mediahro** (30-char limit respected everywhere).
- Apple subtitle: "Video, music & photo player". Google short description: "Free player for every video, song and photo. No ads, no account, no limits."
- Never put competitor names in title/subtitle/keywords (Apple 2.3.7). "Works with Plex, Jellyfin, Emby, Navidrome, Immich" belongs in the description as a factual compatibility statement.
- Never use "Dolby", "DTS", "Chromecast" marks outside the permitted factual/SDK contexts (doc 09).

## 4. Name reservation plan (do in this order, same week)

1. Register `mediahro.com`, `mediahro.app`, `mediahro.io`, `mediahro.dev`. Enable DNSSEC. Point `mediahro.com` at the static site; the others redirect.
2. Create GitHub organisation `mediahro`; reserve `mediahro` on npm, pub.dev, crates.io (name-squatting defence; placeholder packages only where allowed).
3. Social handles: `@mediahro` (fall back to `@mediahroapp`) on X/Bluesky/Mastodon/YouTube/Reddit, Matrix `#mediahro:matrix.org`.
4. **USPTO ITU application** (Section 1(b)) for MEDIAHRO, class 9 (downloadable software for playing video, audio and images) and class 42 (providing online non-downloadable software; SDK/engine licensing). Use ID Manual wording. Budget USD 350/class + counsel.
5. **App Store Connect**: create the app record "Mediahro" (reserves the name; upload a TestFlight build within 180 days).
6. **Google Play Console**: create the app, push an internal-test build to lock `com.mediahro.app`.
7. **Microsoft Partner Center**: reserve "Mediahro" (reservation window ~3 months; submit within it).
8. Within the 6-month Paris Convention window: EUIPO (EUR 850 first class) and UK IPO filings; Madrid designations for JP, IN, BR, KR later if revenue justifies.
9. Register the package name and signing keys (including F-Droid's) with Google's developer verification before 2027.
10. Publish `TRADEMARK.md` (doc 09 §5) with the first public release.

## 5. Trademark policy summary

The code is AGPL-3.0; the **name and logo are not**. Forks must rebrand or label themselves "unofficial build, not endorsed by the Mediahro project". Package repositories (F-Droid, Homebrew, winget, AUR) may use the name for unmodified or lightly patched builds. Nobody may publish a modified build under the Mediahro name on any app store, register domains or handles starting with "mediahro", or combine the mark into new product names. Full text in doc 09.

## 6. Open items before first public use

- [ ] Professional clearance search (USPTO TESS/TSDR, EUIPO eSearch, TMview, WIPO Global Brand Database, common law, domains, social) for MEDIAHRO; specifically assess MEDIAROOM (Ericsson/MediaKind), Mediahub (IPG) and MediaHQ for likelihood of confusion.
- [ ] Manual Google Play search for "Mediahro" (automation could not render the page).
- [ ] Attorney opinion letter; then file USPTO ITU.
- [ ] Confirm Kuvio and Mediaro remain clear as fallbacks.
- [ ] Logo designed and trademarked as a design mark after the word mark is on file.
- [x] Project folder renamed to `K:\Projects\Mediahro` (2026-10-19).
