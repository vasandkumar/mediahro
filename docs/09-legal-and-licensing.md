# 09 — Legal and Licensing

Version 1.0 · 2026-10-19 · Synthesises `research/03`, `research/04`, `research/06`. Not legal advice; counsel reviews §4, §5 and §7 before launch.

## 1. Mediahro's own licence

- **App and engine:** AGPL-3.0-or-later. Rationale: maximal trust with the FOSS/self-hosted audience, F-Droid eligibility, and a dual-licensing lever (proprietary integrators must buy a commercial licence).
- **Commercial licence:** `LICENSE-COMMERCIAL.md` for OEM/white-label/SDK use without AGPL obligations; priced in doc 08.
- **Contributions:** DCO sign-off on every commit; core maintainers assign copyright to the Mediahro entity so dual licensing remains possible; outside contributions remain AGPL-licensed to the project under the inbound=outbound rule plus a lightweight CLA for substantial contributions (> 300 lines) granting relicensing rights.
- **Docs and design:** CC BY 4.0. **Test media:** each file's own licence recorded in `test-media/LICENSES.md` (only CC0/CC BY/own recordings).
- **Trademarks** are excluded from every licence (§5).

## 2. Third-party licence policy

| Class | Policy |
|---|---|
| GPL (any version) | **Never linked into any store or binary distribution.** Excluded: Exiv2, x264, x265, libpostproc GPL parts, rubberband, libdvdcss, libcdio, frei0r, mutagen. GPL tools may be used at build time only if they produce no derived binary (none currently). |
| LGPL-2.1/3 | Allowed, **dynamically linked** (`.so`, `.dylib`/`.xcframework`, `.dll`), with licence text, exact configure line, patches and a source offer (URL to `mediahro-deps` release matching the build). LGPL-3 (libheif/libde265) additionally avoided where platform decoders exist and never shipped on Windows. |
| MIT/BSD/ISC/Apache/MPL/CDDL/curl/zlib/public domain | Allowed statically or dynamically with notices. LibRaw taken under CDDL; TagLib (if used) under MPL. |
| Proprietary SDKs (Google Cast, platform ML) | Only in `store` flavours; excluded from `foss`. |
| Fonts | OFL/Apache only (Noto, Roboto, Open Sans). Never redistribute SF, Segoe, or other OS fonts. |
| Services/APIs | Each third-party service used under its published terms with an app key where required (OpenSubtitles.com API key, TMDB API terms incl. attribution "This product uses the TMDB API but is not endorsed or certified by TMDB", LRCLIB User-Agent rule, MusicBrainz/AcoustID rate limits and app key, ListenBrainz/Last.fm API keys, OSM tile usage policy → use a tile provider that permits app use or self-host tiles, IntroDB terms). All opt-in. |

**CI enforcement:** `tools/licence_scan` builds an SBOM (CycloneDX) from pub, Gradle, SPM and the `mediahro-deps` manifest, fails on any GPL/AGPL-incompatible or unknown licence, verifies FFmpeg/mpv were configured without `--enable-gpl`/`--enable-nonfree`/`-Dgpl=true`, and checks that LGPL libraries are not statically linked into the main executable.

**About → Licences** screen: every component with licence text; FFmpeg configure line; link to `mediahro-deps` sources; statement that HEVC/AAC/DV decoding uses OS decoders where available.

## 3. Open-source precedents applied

- VLC (removed from App Store 2011 over GPL; returned 2013 under LGPL/MPL) → AGPL app is fine on stores **because we are the copyright holder** and grant ourselves the store-compatible terms; third-party GPL code is not fine. The AGPL app itself is distributed by us under our own terms on stores (we are the licensor; the "no further restrictions" clause binds downstream, not us). Counsel to confirm the exact store-licence addendum wording (commonly a dual-licence note "App Store builds are provided under the AGPL plus the App Store terms as an additional permission from the copyright holder").
- mpv's LGPL relicensing → our `-Dgpl=false` build is required; Lua/JS disabled.
- IINA/MPVKit → LGPL dylibs inside the bundle, signed by us, is accepted App Store practice.

## 4. Codec and patent policy

| Codec | Status (Oct 2026) | Mediahro policy |
|---|---|---|
| H.264 | Pools active, many core patents expiring | Platform decoders first; FFmpeg fallback |
| HEVC | Heavily licensed; Access Advance absorbed Via LA's HEVC/VVC pool (Dec 2025); software-decoder waivers unverified | Platform hardware/OS decoders first; FFmpeg software HEVC as fallback; **off by default on Windows when no hardware/OS decoder is present** with a one-time prompt; no "HEVC inside" marketing; no logos |
| VVC/H.266 | Same pool; vvdec is BSD-3-Clear (no patent grant) | Build flag `MEDIAHRO_VVC` on by default in `direct`/`foss`, off in `store` until counsel clears; info panel shows "VVC (software)" |
| AV1 | AOMedia royalty-free licence; Sisvel claims; Access Advance exploring a pool (Aug 2026) | dav1d everywhere; hardware where available; monitor |
| VP8/VP9 | Google royalty-free | libvpx/platform |
| MP3, AC-3 | Patent-free (2017) | FFmpeg; no Dolby mark |
| AAC | Via LA pool to 2028/2031 | Platform decoders first; FFmpeg fallback |
| E-AC-3, TrueHD, Dolby Vision, Atmos | Dolby licensing and trademarks | Platform decode where available; FFmpeg `eac3`/`truehd` decode; DV handled as described in VID-033…035 using libplacebo on unsigned metadata; **no Dolby names/logos in UI or metadata** — the UI says "HDR (dynamic metadata, profile 8)" and the info panel may show the technical profile string |
| DTS/DTS-HD | Core patents lapsed; HD extensions licensed by Xperi | FFmpeg `dca`; no DTS logos; UI says "DTS" only as a codec string in the info panel |
| ProRes | Apple-controlled | Platform decoder on Apple; FFmpeg elsewhere; no logo |
| Opus/FLAC/Vorbis/JPEG XL/WebP/AVIF | Royalty-free | Free use |
| HEIC/HEIF | HEVC inside | Platform decoders only; no libde265 on Windows |

Marketing never claims licensed-codec support; store listings describe "plays MKV, HEVC, AV1, FLAC, DSD…" as factual format support, which is standard practice (VLC, Infuse, nPlayer are all on the stores).

## 5. Trademark policy (`TRADEMARK.md`, summary)

1. **Marks:** the word mark "Mediahro", the Mediahro logo, and their combination, owned by the Mediahro entity. The AGPL licence grants **no** trademark rights.
2. **Allowed without permission:** referring to the app by name; "works with Mediahro", "plugin for Mediahro", "client for Mediahro"; linking to official downloads; redistributing **unmodified** official builds with attribution; package repositories (F-Droid, IzzyOnDroid, Homebrew, winget, AUR, Flathub, Debian) using the name for unmodified or lightly patched builds; tutorials, reviews, meetups, academic use.
3. **Allowed with conditions:** forks and modified builds must remove the name and logo **or** display "Unofficial build — not endorsed by the Mediahro project" prominently in the app name, store listing and About screen.
4. **Not allowed:** publishing modified builds under the Mediahro name on any app store; domains, handles or product names beginning with or containing "mediahro" (e.g. "MediahroTube", "Mediahro Pro"); merchandise; implying endorsement; altering the logo; using the marks for IPTV/piracy-adjacent products.
5. **Enforcement:** contact `legal@mediahro.com`; good-faith resolution first; store takedown for impersonating listings.
6. Based on the Model Trademark Guidelines and Mozilla's policy; published next to `LICENSE` and linked from the README, site and store legal sections.

Registration path (doc 03 §4): USPTO ITU classes 9 and 42 → EUIPO and UK within the 6-month priority window → Madrid designations as revenue justifies. Use ™ now, ® after registration.

## 6. Privacy policy and terms

- `PRIVACY.md` / mediahro.com/privacy content per doc 07 §6.1; in-app link in About and in the privacy dashboard; plain language; effective date; change log.
- `TERMS.md` (short): the app is provided under AGPL; no warranty; supporter payments are voluntary and non-refundable except as required by law or store policy; no accounts; third-party services under their own terms; abuse/DMCA contact.
- **DMCA/abuse policy** (`mediahro.com/abuse`): Mediahro hosts no content; it plays files and URLs the user supplies. Requests to remove content should go to the hosting party. A counter-notice template is prepared for bogus store complaints (Perfect Player precedent).

## 7. Compliance register

| Area | Obligation | Owner | Status |
|---|---|---|---|
| Trademark clearance and ITU filing | Before public beta | Founder + counsel | Open |
| Entity formation and store accounts in entity name | Before store submissions | Founder | Open |
| Privacy policy, terms, abuse policy published | Before public beta | Founder | Drafted in docs |
| SBOM and licence scan in CI | Milestone M2 | Build | Specified |
| Export-compliance inventory | Before App Store submission | Build | Specified (OS crypto only) |
| Accessibility conformance report (EN 301 549) | 1.0 | QA | Specified |
| EU DSA trader information | Before EU availability | Founder | Open |
| Developer verification (Android) incl. F-Droid key | Before 2027 | Founder | Open |
| Third-party API keys and terms acceptance (OpenSubtitles, TMDB, AcoustID, Last.fm, ListenBrainz) | Before beta | Founder | Open |
| Multicast entitlement (Apple), CarPlay entitlement | Milestone M1 | Founder | Open |
