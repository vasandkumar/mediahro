# 07 — Platform and Store Compliance

Version 1.0 · 2026-10-19 · Synthesises `research/03`. Policy text was checked against the official pages on 2026-10-19 (Apple guidelines dated 16 Oct 2026; Microsoft Store Policies v7.20 effective 22 Oct 2026; Google Play pages updated Oct 2026). Items marked *(verify)* must be re-checked at submission time.

## 1. Hard constraints (the twelve rules)

| # | Rule | Where | Mediahro's implementation |
|---|---|---|---|
| 1 | In-app tips must use the platform's purchase system | Apple 3.1.1 (allows IAP "tips"), Google Payments policy (only tax-exempt donations exempt), Microsoft 10.8.2 (donations via Microsoft payment-request API or declared third-party processor; Microsoft IAP only if digital goods are returned) | SUP-002: StoreKit 2 consumables + optional subscription; Play Billing consumables; Windows uses a declared third-party web checkout; perks are cosmetic only |
| 2 | External purchase links are restricted | Apple: allowed in the US storefront; EU under Attachment 14 terms (15 %/10 % commissions, 12-month lock-in, monthly reporting); forbidden elsewhere. Google: US since 29 Oct 2025 with programme enrolment; EEA programmes | SUP-003: web link shown only when `Storefront.countryCode == "USA"` (and EU after accepting terms); never in other storefronts; never with perks |
| 3 | Android media permissions are gated | `READ_MEDIA_IMAGES`/`READ_MEDIA_VIDEO` only for apps whose core function needs broad library access, with a Play Console declaration and a Photo Picker/SAF fallback; `READ_MEDIA_AUDIO` unrestricted; `MANAGE_EXTERNAL_STORAGE` disallowed for media | SYS-007: declaration filed with gallery/library justification video; `READ_MEDIA_VISUAL_USER_SELECTED` handled; Photo Picker and SAF fallbacks; no all-files access |
| 4 | Android platform deadlines | Target API 36 (since 31 Aug 2026); 16 KB page alignment (hard block 1 Feb 2027); 64-bit; AAB + Play App Signing | All native libs built with NDK r28+; `zipalign -c -P 16` in CI |
| 5 | New personal Play accounts need a closed test | 12 testers opted in for 14 continuous days before production | Scheduled in doc 10 (milestone M7) |
| 6 | Apple privacy artefacts | Privacy policy URL in App Store Connect **and** in-app; nutrition labels; `PrivacyInfo.xcprivacy` with required-reason codes for app and every SDK | CORE-013, PRIV-*; manifest lists UserDefaults (CA92.1), file timestamps (C617.1/DDA9.1), disk space (E174.1/85F4.1), boot time (35F9.1) |
| 7 | Consent for any usage data, even anonymous | Apple 5.1.1(ii) | PRIV-001…003: all telemetry off by default with explicit toggles |
| 8 | Mac App Store sandbox; direct macOS notarisation | Entitlements: `app-sandbox`, `files.user-selected.read-write`, `files.bookmarks.app-scope`, `network.client`, `network.server` (DLNA renderer/web remote/transfer), optional `assets.movies/music/pictures.read-only`; Developer ID (G2 Sub-CA before 1 Feb 2027) + hardened runtime + notarytool + staple | Two macOS targets: `store` (sandboxed) and `direct` |
| 9 | Microsoft Store packaging | MSIX preferred; unpackaged Win32 allowed with silent install, all PEs signed by a trusted-root cert, versioned immutable URL; privacy policy always required for Win32; IARC rating mandatory | MSIX for Store; signed installer + winget for direct |
| 10 | No GPL on Apple stores (and practically on all stores) | FSF/GNU Go and VLC precedents | ADR-002: FFmpeg/libmpv LGPL build, dynamic linking, notices, no Exiv2/x264/x265/libdvdcss |
| 11 | Android developer verification | Enforced from 30 Sep 2026 in BR/ID/SG/TH, global 2027; register package and all signing keys incl. F-Droid's | Doc 03 §4 step 9 |
| 12 | Export compliance | `ITSAppUsesNonExemptEncryption=NO` only if OS crypto alone is used | FFmpeg/libcurl built with OS TLS backends; SFTP/FTPS and the open Cast sender use OS SSH/TLS (ADR-017); vault uses OS crypto APIs (CryptoKit/Keystore/CNG) through `VaultCryptoFacade` (ADR-039). The encryption inventory must also list BoringSSL inside the Flutter engine (`dart:io` HTTPS); counsel confirms the resulting `ITSAppUsesNonExemptEncryption` answer and any self-classification before submission (owner task, STATUS.md §4) |

## 2. Apple (iOS/iPadOS, Mac App Store, direct macOS)

### 2.1 Guideline mapping

| Guideline | Requirement | Mediahro |
|---|---|---|
| 2.1 Completeness | No placeholders; demo access for login features | Notes for Review include a public test Jellyfin/WebDAV/SMB server and sample media URLs; no login required for core |
| 2.3 Metadata | Accurate screenshots; specific review notes; 2.3.7 unique name, no competitor names/trademarks in title, subtitle, keywords; 2.5.19 no hidden features | Doc 12 listing rules; all features documented |
| 2.5.4 Background | `UIBackgroundModes=audio` only for playback | Media session wired; PiP via `AVPictureInPictureController`; no silent-audio tricks |
| 3.1.1 IAP | Tips allowed via IAP; credits never expire; any unlock must be IAP | Consumable tips; subscription "Supporter"; perks via StoreKit entitlements only |
| 3.1.1(a)/3.1.3 external links | US-only (and EU under terms) | Storefront-gated link |
| 3.2.1(vi)/(vii) | Nonprofit fundraising / individual gifting carve-outs don't apply | Not used |
| 4.2 Minimum functionality | Works on its own | Yes |
| 5.1.1 Privacy | Policy in ASC and in-app; consent; data minimisation — prefer PHPicker | PHPicker for picking; `PHPhotoLibrary` only for "Photos library" mode; limited access handled; `PHPhotoLibraryPreventAutomaticLimitedAccessAlert=YES` |
| 5.1.2 / ATT | Only if tracking | No ATT prompt (no tracking) |
| 5.2 IP | No third-party marks without permission; third-party services per their terms | "Works with Plex/Jellyfin…" factual only; no Dolby/DTS marks; LRCLIB and MusicBrainz per their API terms |
| Age rating | New questionnaire mandatory; "unrestricted web access" answer raises rating | URL opening scoped to media; no browser |
| Accessibility labels | Voluntary now, expected to become required | Declared per doc 06 §7 |
| Platform | Xcode 26 / iOS 26 SDK now; iOS 27 SDK from April 2027; iOS 13+ target (we target iOS 16+); iPhone Duo screenshots from April 2027; macOS 27 Apple-silicon-only | CI on macOS 26 runners; arm64 + x86_64 universal for macOS until 27 |
| iPad | Resizable; Stage Manager; no `UIRequiresFullScreen` | CORE-010 |
| visionOS | Compatibility mode tested or opted out | Tested in compatibility; PiP behaviour verified |
| EU DSA trader status | Required for EU availability | Trader details in ASC |

### 2.2 Info.plist and entitlements (iOS)

- `NSPhotoLibraryUsageDescription`, `NSPhotoLibraryAddUsageDescription`
- `NSLocalNetworkUsageDescription`; `NSBonjourServices`: `_smb._tcp`, `_afpovertcp._tcp`, `_nfs._tcp`, `_webdav._tcp`, `_webdavs._tcp`, `_http._tcp`, `_https._tcp`, `_googlecast._tcp`, `_airplay._tcp`, `_raop._tcp`, `_jellyfin._tcp`, `_mediahro._tcp`
- `com.apple.developer.networking.multicast` entitlement (SSDP/DLNA) — request early
- `UIBackgroundModes`: `audio`; `UIFileSharingEnabled`, `LSSupportsOpeningDocumentsInPlace`; `CFBundleDocumentTypes` + `UTExportedTypeDeclarations`/`UTImportedTypeDeclarations` for MKV, FLAC, DSF, JXL, ASS, etc.
- `CADisableMinimumFrameDurationOnPhone=true` (ProMotion)
- CarPlay audio entitlement (apply early); App Groups for widgets/Live Activities
- No Bluetooth purpose string (not used)

### 2.3 Mac App Store vs direct

| Topic | Store (`store` flavour) | Direct (`direct` flavour) |
|---|---|---|
| Sandbox | Required; bookmarks for folders | Not sandboxed; still hardened runtime |
| Folder access | User-selected + bookmarks; optional Movies/Music/Pictures entitlements | Any path after user selection |
| Updates | Store | Sparkle (EdDSA-signed appcast) |
| Payments | IAP | Web link |
| Signing | Mac App Distribution cert; all dylibs re-signed | Developer ID; notarised; stapled; quarantine xattr stripped |
| Homebrew cask | — | After notarisation; our own release URL |

## 3. Google Play

### 3.1 Permissions and manifest

| Permission | Used? | Justification |
|---|---|---|
| `READ_MEDIA_AUDIO` | Yes | Music library (unrestricted) |
| `READ_MEDIA_VIDEO` | Yes, with declaration | Video library: folder browsing, continuous indexing, resume positions, thumbnails, playlists across the whole library; Photo Picker cannot deliver this |
| `READ_MEDIA_IMAGES` | Yes, with declaration | Photos mode is a full gallery (timeline, albums, vault, duplicates, batch); the same declaration |
| `READ_MEDIA_VISUAL_USER_SELECTED` | Yes | Partial grant on Android 14+ handled with "manage selection" UI |
| `MANAGE_EXTERNAL_STORAGE` | **No** | Disallowed for media; SAF trees cover arbitrary folders/SD/USB |
| `FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_MEDIA_PLAYBACK` | Yes | `mediaPlayback` FGS type; Play Console FGS declaration with video of user-initiated playback |
| `INTERNET`, `ACCESS_NETWORK_STATE`, `CHANGE_WIFI_MULTICAST_STATE` | Yes | Network sources, SSDP; privacy dashboard explains |
| `POST_NOTIFICATIONS` | Yes | Playback notification |
| `USE_BIOMETRIC` | Yes | Vault/app lock |
| `RECEIVE_BOOT_COMPLETED` | Enterprise flavour only | Kiosk auto-start |
| `WAKE_LOCK` | Yes | Playback |
| Location | **No** | Map uses photo EXIF only |

### 3.2 Console requirements

- Target API 36; AAB; Play App Signing; 16 KB-aligned libs; 64-bit.
- Data safety: Diagnostics (crash logs, performance) declared as *optional, user-controlled*; no device IDs; privacy policy URL.
- IARC questionnaire (no unrestricted web).
- Photo/Video permissions declaration with justification and demo video.
- FGS `mediaPlayback` declaration with video.
- Closed test (12 testers × 14 days) for a new personal account; organisation accounts need D-U-N-S.
- Android Auto: separate review; no autoplay on start; MediaLibraryService; voice support. Android TV (1.1): leanback intent, banner, D-pad-only, Now Playing card, 16 KB rule from 1 Aug 2026 for TV.
- In-App Review API only after a success moment; never tied to a "Rate us" button (deep-link instead).
- Developer verification: register `com.mediahro.app` and all signing fingerprints (Play upload, F-Droid).

### 3.3 Payments

Play Billing consumables ("Buy the team a coffee" tiers) and a subscription; fee 15 % first USD 1 M outside the EEA/UK/US/AU/JP; new regional structures from 30 Jun / 30 Sep 2026 (10 %+5 % subscriptions, 20–25 %+5 % one-off) *(verify at launch)*. Optional enrolment in US External Content Links / EEA programmes later. The `foss` flavour removes Play Billing and shows Liberapay/GitHub Sponsors links (allowed on F-Droid).

## 4. Microsoft Store and Windows direct

- **MSIX** (Store-signed, auto-updated, appears in winget `msstore`). Identity `Mediahro.Mediahro`; file associations and protocol handlers declared in the manifest; Mica/Fluent.
- **Policies:** 10.1 accurate metadata and clear first-run value; 10.2.4 disclose dependency on "HEVC Video Extensions" for hardware HEVC via Media Foundation (Mediahro decodes HEVC in software via FFmpeg when the extension is absent, so the note reads "optional, for hardware decoding"); 10.2.7 clean uninstall; 10.5.1 privacy policy; 10.8.2 donations via declared third-party checkout; 11.11 IARC.
- **Direct installer:** signed with Azure Artifact Signing (formerly Trusted Signing) or an OV certificate; silent switches (`/S`, `/VERYSILENT`); versioned URL on `mediahro.com/download`; winget manifest PR automated with `wingetcreate` on each release; SmartScreen reputation accrues per file hash — documentation prepares users for the first-run warning on brand-new releases.
- **Intune/MDM:** MSIX in Store + winget manifest cover managed deployment.

## 5. Alternative stores and channels

| Channel | Requirements | Mediahro flavour |
|---|---|---|
| F-Droid | Built from source by F-Droid; no proprietary SDKs; reproducible build recommended (keeps our signing key); anti-features declared (NonFreeNet for the optional online services: LRCLIB, MusicBrainz, ListenBrainz, IntroDB); `funding.json`/`FUNDING.yml`; fastlane metadata | `foss` |
| IzzyOnDroid | Our APK from GitHub releases | `foss` |
| Samsung Galaxy Store | Seller Portal; privacy URL; age rating; no beta binaries | `store` APK |
| Amazon Appstore | Fire OS APK; Fire TV category (1.1) | `store` |
| Huawei AppGallery | Identity verification; HMS IAP if digital goods (we sell none; tips via web) *(verify)* | `foss` + web link |
| Homebrew cask | Notarised DMG at our release URL; passes Gatekeeper | `direct` |
| winget | ISV-hosted installer URL; silent install | `direct` |
| GitHub Releases | Signed artefacts + SBOM + checksums | all |

## 6. Cross-cutting obligations

### 6.1 Privacy policy (PRIVACY.md and mediahro.com/privacy)

Lists: data processed on device (library index, positions, settings); optional transmissions (on hold, PRIV-002/PRIV-003, owner 2026-10-22: crash reports via self-hosted Sentry — device model, OS version, app version, stack; usage analytics via Aptabase — anonymous events, country derived from IP then discarded); third-party services the user may enable (LRCLIB, MusicBrainz and Cover Art Archive, ListenBrainz, IntroDB; ADR-048 removed every service that needs a publisher API key) with links to their policies; retention (90 days crash, 12 months aggregates); deletion/withdrawal (toggle off; email); no sale/sharing; no children's targeting; EU representative/DSA trader info; contact.

### 6.2 GDPR/CCPA posture

Lawful basis: consent (toggles). DPA with hosting provider of the Sentry/Aptabase instances. No profiling, no cross-app tracking. CCPA thresholds not met; policy still states "we do not sell or share". Age: 13+/general audience; not in Kids/Families programmes.

### 6.3 Accessibility law

EAA (EN 301 549) presumption of conformity targeted even though a microenterprise is exempt; conformance report shipped (B2B-005). ADA risk mitigated by WCAG 2.2 AA mapping.

### 6.4 Open-source and codec obligations

See doc 09. Summary: LGPL dynamic linking, notices, configure line, source offer; hardware-first codec policy; no Dolby/DTS/Chromecast marks outside permitted uses; AirPlay sender only.

## 7. Pre-submission checklists

### Apple (iOS/iPadOS + Mac App Store)
- [ ] Xcode 26+/OS 26 SDK; iPad windowing tested; visionOS compatibility tested
- [ ] Background audio, Now Playing, remote commands, PiP verified on device
- [ ] Purpose strings only for used APIs; `NSBonjourServices` complete; multicast entitlement granted
- [ ] Document types/UTIs; Files open-in-place; PHPicker default; limited library UI
- [ ] `PrivacyInfo.xcprivacy` for app and SDKs; nutrition labels; privacy policy URL in ASC and About; telemetry toggles default off
- [ ] Tip jar consumables + subscription configured; storefront-gated external link verified for non-US
- [ ] No GPL; LGPL dylibs dynamic; licence screen complete; FFmpeg configure line shown
- [ ] Export compliance answer consistent (OS crypto only)
- [ ] Age rating questionnaire; DSA trader info
- [ ] Notes for Review: test server credentials, sample URLs, where the supporter page lives, how to trigger PiP/casting
- [ ] Mac: sandbox entitlements; all dylibs re-signed; 16:10 screenshots

### Direct macOS
- [ ] Developer ID (G2) + hardened runtime + timestamp on every binary; notarytool; stapled; quarantine xattr stripped; universal/arm64; Sparkle appcast signed; Homebrew cask PR

### Google Play
- [ ] targetSdk 36; AAB; 64-bit; 16 KB; Play App Signing
- [ ] Permissions exactly as §3.1; declarations and videos uploaded; no `MANAGE_EXTERNAL_STORAGE`
- [ ] `mediaPlayback` FGS + declaration; Media3 session; notification controls
- [ ] Data safety; privacy policy URL; IARC; target audience 13+
- [ ] Play Billing consumables + subscription; no external payment links in `store` flavour
- [ ] Closed test complete (new account); pre-launch report clean; Android vitals green
- [ ] Android Auto track reviewed separately
- [ ] Developer verification registration incl. F-Droid key

### Microsoft Store / Windows
- [ ] MSIX passes WACK; identity reserved; file associations; Mica
- [ ] Privacy policy URL; IARC; accurate title/category; first-run value visible
- [ ] Third-party checkout declared in Partner Center; no digital goods sold
- [ ] HEVC extension dependency disclosed as optional
- [ ] Direct: signed installer, silent switches, versioned URL, winget manifest

### F-Droid
- [ ] `foss` flavour builds with F-Droid's toolchain from source; no proprietary deps; reproducible; metadata and changelogs; funding files
