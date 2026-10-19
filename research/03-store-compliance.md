# 03 — Store Compliance Report: Free Media Player (video + audio + images, local + network sources, supporter payments only, no ads)

**Research date:** 2026-10-19. **Scope:** what the app must do to be *approved* and to *succeed* on Apple App Store (iOS/iPadOS), Mac App Store, notarized direct macOS distribution, Google Play, Microsoft Store (MSIX and unpackaged Win32), plus F-Droid, Samsung Galaxy Store, Amazon Appstore, Huawei AppGallery, winget and Homebrew.

**Evidence quality.** Policy text below was pulled from the official pages on 2026-10-19 (Apple App Review Guidelines "Last Updated: October 16, 2026"; Microsoft Store Policies v7.20 "Effective date: October 22, 2026"; Google Play pages updated through 2026-10-16). Items marked **(verify)** rest on secondary sources or on well-established but un-fetched documentation and should be re-checked against the linked primary page before shipping. Search budget was exhausted mid-research, so a few optional-store details (Huawei, Samsung fees) are thinner than the rest.

---

## 0. Hard constraints at a glance

| # | Constraint | Platforms | Source |
|---|---|---|---|
| 1 | Tips/donations that happen *inside the app* must go through the platform's IAP system (Apple 3.1.1 explicitly allows IAP "tips"; Google Payments policy exempts only *tax-exempt* donations; Microsoft requires its IAP only if the donor gets digital goods in return). | Apple, Google, Microsoft | [G1] [G8] [G20] |
| 2 | Outside the US storefront (and, under new terms, the EU), Apple apps and metadata may not contain buttons/links/CTAs to other purchase mechanisms (Patreon/Ko-fi/GitHub Sponsors are risky in-app). | Apple | [G1] |
| 3 | Google Play: `READ_MEDIA_IMAGES`/`READ_MEDIA_VIDEO` only for apps whose *core functionality* needs broad library access; a Play Console declaration is required; `MANAGE_EXTERNAL_STORAGE` is **disallowed** for "media files access". | Google | [G3] [G4] |
| 4 | Google Play: new apps/updates must target API 36 (Android 16) since Aug 31 2026 (extension to Nov 1 2026); 16 KB page-size support required for apps targeting Android 15+ (Nov 1 2025), hard block on non-compliant updates from Feb 1 2027. | Google | [G5] [G6] [G7] |
| 5 | Google Play: personal developer accounts created after Nov 13 2023 must run a closed test with ≥12 testers opted-in for 14 continuous days before production access. | Google | [G9] |
| 6 | Apple: privacy policy URL in App Store Connect **and** inside the app; privacy nutrition labels; `PrivacyInfo.xcprivacy` with approved reasons for required-reason APIs (incl. in every third-party SDK). | Apple | [G1] [A4] [A5] |
| 7 | Apple: consent required for *any* usage/crash data collection "even if … anonymous" (5.1.1(ii)); ATT only if you track. | Apple | [G1] |
| 8 | Mac App Store: App Sandbox mandatory; file access only via user-selected entitlements + security-scoped bookmarks; outbound network needs `network.client`. Direct macOS: Developer ID + Hardened Runtime + notarization + stapling; Sequoia removed the Control-click Gatekeeper bypass. | Apple | [A6] [A7] [A8] |
| 9 | Microsoft Store unpackaged Win32 (policy 10.2.9): `.exe`/`.msi` only, **silent install mandatory**, every PE file signed by a Microsoft Trusted Root CA cert, versioned immutable download URL, PC only. Privacy policy always required for Win32 (10.5.1). IARC age rating mandatory (11.11). | Microsoft | [M1] |
| 10 | GPL code cannot ship on the Apple App Store (FSF/GNU Go precedent; VLC's 2011 removal and 2013 LGPL relicense). Build FFmpeg/libmpv **without** `--enable-gpl`/`--enable-nonfree` and link dynamically. | Apple (and practically all stores) | [X1] [X2] |
| 11 | Android developer verification: identity-verified developers required for installs on certified devices in BR/ID/SG/TH from Sep 30 2026 (participating stores), global in 2027; $25 full-distribution registration; affects F-Droid/sideloaded builds. | Android | [G10] [G11] |
| 12 | Export compliance: set `ITSAppUsesNonExemptEncryption=NO` only if you rely solely on OS crypto; bundling OpenSSL/mbedTLS inside FFmpeg/libmpv for HTTPS moves you to the "French declaration" tier. | Apple | [A9] |

---

## 1. Apple — App Store (iOS/iPadOS), Mac App Store, direct macOS

### 1.1 App Review Guidelines mapping (text as of Oct 16 2026)

**2.1 App Completeness.** Submit final builds; no placeholders; "include demo account info" if login exists (not applicable unless you gate SMB/cloud accounts — provide a test server or built-in demo mode "with prior approval"). Binaries that crash or "exhibit obvious technical problems" are rejected. Test on device with real large files, HDR content, and network shares before submitting. [G1]

**2.3 Accurate Metadata.** Screenshots/previews must "accurately reflect the app's core experience". 2.3.1(a): every new feature must be described "with specificity in the Notes for Review" (generic notes are rejected). New in Oct 2026: **2.3.14** (creative assets — the new product-page headers/search assets) and **2.5.19** (hidden/dormant/undocumented features; bait-and-switch after approval leads to removal and Program termination). Don't use other apps' names (VLC, Infuse, Plex) or trademarks (Chromecast, Dolby) in title/keywords/subtitle unless you hold rights. [G1] [A1]

**2.5.4 Background services** — "Multitasking apps may only use background services for their intended purposes: VoIP, audio playback…". Declare `UIBackgroundModes = audio` only for actual playback; keep the `AVAudioSession` category `.playback` and `MPNowPlayingInfoCenter`/`MPRemoteCommandCenter` wired, so lock-screen/Control Center controls work (reviewers check this). Picture-in-Picture must be real video via `AVPictureInPictureController` (requires the audio background mode). Do not use background audio to keep a silent track alive for downloads. **(verify API specifics)** [G1]

**3.1.1 In-App Purchase (payments — the key clause).** Verbatim: "Apps may use in-app purchase currencies to enable customers to 'tip' the developer or digital content providers in the app." So a **tip jar built on consumable IAPs is explicitly permitted**. Constraints: credits "may not expire"; if a tip unlocks anything (icons, themes, "supporter badge", feature flags), it is a digital unlock and must be IAP — "Apps may not use their own mechanisms to unlock content or functionality, such as license keys…". Apple's cut: 30 % standard, 15 % via the App Store Small Business Program (<$1 M/yr) **(verify current program terms)**. [G1]

**3.1.1(a) / 3.1.3 — external links.** "In all other storefronts, except for the United States storefront, where this prohibition does not apply, apps and their metadata may not include buttons, external links, or other calls to action that direct customers to purchasing mechanisms other than in-app purchase." Since the May 2025 Epic v. Apple contempt order, US-storefront apps may show external purchase links with no entitlement; the link must open in the default browser, and Apple's commission on those purchases is contested in ongoing litigation **(verify status)**. In the **EU**, from Oct 1 2026 (Attachment 14) you may offer IAP, an in-app alternative PSP (20 % / 10 % reduced commission) and/or link-out (15 % / 10 %), with a 12-month lock-in of the chosen option, monthly transaction reporting within 15 days, tax responsibility, and parental-gate rules for under-18 users; the 5 % Core Technology Commission applies to alternative distribution and link-out sales within 7 days of a tap. [G1] [A2] [A3]

**3.2.1(vi)/(vii) — donations.** (vi) only **approved nonprofits** may fundraise in-app (and must support Apple Pay). (vii) individuals may gift money to *another individual* without IAP if "100 % of the funds go to the receiver" and the gift is not "connected to or associated at any point in time with receiving digital content or services" — this is the creator-tipping carve-out, not a developer-donation carve-out; reviewers have applied it inconsistently and have rejected non-nonprofit donation collection under 3.2.2. [G1] [A10]

> **Practical rule for this app:** Ship a consumable-IAP tip jar everywhere. Expose Patreon/Ko-fi/GitHub Sponsors links **only** when `Storefront.current.countryCode == "USA"` (and, after accepting Attachment 14, in EU storefronts), otherwise keep those links on your website and in the App Store "Support URL", never in the binary or metadata for other storefronts. Never attach perks to external donations.

**3.1.3(a) Reader apps** — covers access to "previously purchased content or content subscriptions (magazines, newspapers, books, audio, music, and video)". A local/network file player is **not** a reader app; do not claim the External Link Account entitlement. If you add Plex/Jellyfin/Emby sign-in, you still aren't selling anything, so the clause is moot; just don't advertise their paid tiers. [G1]

**4.x Design.** 4.2 minimum functionality is easily met; 4.2.3(i) the app "should work on its own without requiring installation of another app" (SMB/Plex servers are optional sources, fine). Adopt iOS 26 "Liquid Glass" design kits for featuring chances. [G1] [A1]

**5.1.1 Privacy.** (i) privacy policy link in App Store Connect **and** "within the app in an easily accessible manner"; must identify data collected, third parties/SDKs, retention/deletion, how to revoke consent. (ii) "Apps that collect user or usage data must secure user consent for the collection, even if such data is considered to be anonymous" and must offer a way to withdraw consent — so **opt-in crash/analytics toggles**, default off or an explicit first-run choice. (iii) data minimization: "use the out-of-process picker or a share sheet rather than requesting full access to protected resources like Photos". [G1]

**Photos & Files.** Prefer `PHPickerViewController` (no permission prompt, out-of-process) for picking; request `PHPhotoLibrary` access only for a "library browse" mode, handle `.limited` status, and set `PHPhotoLibraryPreventAutomaticLimitedAccessAlert=YES` while offering `presentLimitedLibraryPicker`. Info.plist: `NSPhotoLibraryUsageDescription` (read), `NSPhotoLibraryAddUsageDescription` (save-only). For general files use `UIDocumentPickerViewController`, set `UIFileSharingEnabled` + `LSSupportsOpeningDocumentsInPlace` so the app appears in Files and can open-in-place; declare `CFBundleDocumentTypes`/`UTExportedTypeDeclarations` for MKV/FLAC etc. so "Open in" works. Security-scoped URL access (`startAccessingSecurityScopedResource`) and bookmarks are required to re-open files/folders later. **(verify API specifics)** [A11]

**Local network (SMB, DLNA/UPnP, Chromecast, AirPlay discovery).** iOS 14+ (and macOS 15 Sequoia) prompt for local-network access on Bonjour browsing, multicast, or unicast to local addresses. Required keys: `NSLocalNetworkUsageDescription` and `NSBonjourServices` listing every browsed type (e.g., `_smb._tcp`, `_googlecast._tcp`, `_airplay._tcp`, `_raop._tcp`, `_http._tcp`). SSDP/UPnP (DLNA) discovery uses multicast 239.255.255.250 and needs the **`com.apple.developer.networking.multicast` entitlement, granted on request** — apply early. Apple DTS confirmed that browsing silently fails without `NSBonjourServices`. Handle "denied" gracefully (manual IP entry). [A12] [A13]

**Bluetooth.** Audio output to BT headphones needs nothing. Only add `NSBluetoothAlwaysUsageDescription` if you use CoreBluetooth (e.g., custom remote). Unused purpose strings are a 5.1.1 rejection trigger. **(verify)**

**5.1.2 / ATT.** Tracking (linking your data with third-party data for ads, or sharing with data brokers) requires the AppTrackingTransparency prompt. A no-ads, donation-only player with first-party crash reporting does **not** track — don't show the ATT prompt (showing it unnecessarily is also a rejection reason). Note Sept 2026: an alternative ATT prompt exists in the EU from iOS 27.2 and is the only option in DE/FR/IT/PL/RO. [G1] [A1] [A14]

**5.2 Intellectual Property.** 5.2.1: no third-party trademarks/copyrighted works/"patented ideas" without permission; 5.2.2: if you access third-party services (YouTube, Plex, cloud drives), you must be "specifically permitted … under the service's terms of use" and show authorization on request. Codec and font implications are in §5.4–5.5. [G1]

### 1.2 Privacy nutrition labels, privacy manifest, required-reason APIs

- **Nutrition labels** (App Store Connect, required for every submission): declare Diagnostics → Crash Data / Performance Data if you send crash logs off-device; "collection" = transmitted off-device and retained beyond the real-time request. Third-party SDK data counts as yours. On-device-only data (playback history, library index) is **not** collected. [A4]
- **Privacy manifest** (`PrivacyInfo.xcprivacy`) is enforced since May 1 2024 for apps and SDKs. Declare `NSPrivacyAccessedAPITypes` with approved reasons — a media player typically hits: **UserDefaults** (`CA92.1`), **File timestamp** (`C617.1` for own container, `DDA9.1` to show timestamps to the user), **Disk space** (`E174.1` write/delete, `85F4.1` display to user), **System boot time** (`35F9.1` elapsed-time measurement). Every SDK on Apple's "privacy manifest required" list (crash reporters, Firebase, etc.) must ship its own manifest and signature. Missing reasons = upload rejected. [A5] [A1]
- **Tracking domains**: none, if you don't track.

### 1.3 Export compliance (encryption)

`ITSAppUsesNonExemptEncryption = NO` is correct only when the app "uses no encryption or uses only exempt forms" (Apple OS crypto: URLSession/TLS, CryptoKit). If your FFmpeg/libmpv/libsmb2 build links **OpenSSL, mbedTLS or GnuTLS** for `https://`/SMB signing, you are in the "industry-standard algorithm not supplied by Apple's OS" tier: upload a **French encryption declaration** (ANSSI) in App Store Connect once per app, and keep year-end US self-classification reporting in mind **(verify)**. Easiest path: build FFmpeg with `--disable-openssl --disable-gnutls --disable-mbedtls` and route network I/O through platform TLS (e.g., custom AVIO via `URLSession`), or accept the declaration step. [A9]

### 1.4 Age rating, accessibility, platform requirements

- **Age ratings**: the new rating questionnaire became mandatory Jan 31 2026 (ratings display on OS 26); new social-media questions mandatory from Sept 2026 for new submissions and updates. A player that opens arbitrary URLs/streams may be pushed to a higher rating by the "unrestricted web access" question — scope URL opening to media only. [A15] [A1]
- **Accessibility Nutrition Labels** (iOS 26): declare VoiceOver, Voice Control, Larger Text, Dark Interface, Differentiate Without Color Alone, Sufficient Contrast, Reduced Motion, **Captions**, **Audio Descriptions**. Voluntary now; Apple states it will become required for new apps/updates. A media player should truthfully support Captions (render embedded/external subtitles honoring the system `MACaptionAppearance` style) and expose audio-description tracks. [A16]
- **SDK/Xcode minimums**: uploads must use Xcode 26 / OS 26 SDKs since Apr 28 2026; iOS 27 SDK minimum arrives April 2027; iOS/iPadOS apps must target iOS 13+ (Sept 9 2026). **iPhone Duo** (foldable, Oct 23 2026): screenshots required from April 2027; recompile with Xcode 27.1. macOS 27 is Apple-silicon-only (Rosetta ends) — ship arm64. [A15] [A1]
- **iPad multitasking**: iPadOS 26 windowing means apps should be resizable and not rely on `UIRequiresFullScreen` (Apple has signalled it will be ignored in a future release) **(verify current enforcement)**; test Stage Manager/Split View. **visionOS**: iPad apps are offered in compatibility mode by default — either test the player in visionOS compatibility (PiP, AVPlayerViewController behave differently) or uncheck "Apple Vision" availability in App Store Connect. **(verify)**
- **EU DSA trader status**: required since Feb 17 2025 for EU availability (name, address, email/phone shown on the listing). [A15]
- **Apple-provided decoders**: VideoToolbox/AVFoundation decode H.264, **HEVC** (incl. 10-bit, HDR10/HLG), **Dolby Vision** (profiles 5/8.x on supported devices), **ProRes** (Apple silicon/A-series Pro chips), AAC, AC-3/E-AC-3 (passthrough/decode via AVFoundation) — using them keeps patent risk on Apple (§5.4). Software fallbacks (FFmpeg) are needed for MKV demux, ASS subtitles, VP9/AV1 on older chips (AV1 hardware decode from A17 Pro/M3), DTS and legacy codecs. **(verify per-device capability)**

### 1.5 Mac App Store specifics

- **App Sandbox is mandatory** for Mac App Store apps. Entitlements a media player needs: `com.apple.security.app-sandbox`, `com.apple.security.files.user-selected.read-write` (or `.read-only` if you never write), `com.apple.security.files.bookmarks.app-scope` (persist access to library folders via security-scoped bookmarks — without it access ends when the app quits), `com.apple.security.network.client` (streams, SMB, Chromecast), `com.apple.security.network.server` only if you accept incoming connections (DLNA renderer, remote control), optional `assets.movies.read-only` / `assets.music.read-only` / `assets.pictures.read-only` for ~/Movies, ~/Music, ~/Pictures, and `files.downloads.read-write` for ~/Downloads. "Temporary exception" entitlements are routinely rejected. Full Disk Access is not available to sandboxed MAS apps, and Apple announced (Oct 2 2026) tighter controls on FDA generally. [A6] [A1]
- All code in the bundle must be signed with your Mac App Store certificate; libmpv/FFmpeg dylibs re-signed by you. 3.1.1 allows MAS apps to "host plug-ins or extensions that are enabled with mechanisms other than the App Store". [G1]
- Mac screenshots: 16:10 at 1280×800, 1440×900, 2560×1600 or 2880×1800; previews 1920×1080 landscape only. [A17] [A18]

### 1.6 Direct macOS distribution (Developer ID + notarization)

Checklist (from Apple's notarization/hardened-runtime docs and the 2025–2026 news items):

- [ ] Sign with **Developer ID Application** certificate; replace certificates issued under the expiring Developer ID Sub-CA before **Feb 1 2027** (G2 Sub-CA); `.pkg` files signed without a secure timestamp by affected certs stop installing that day. [A1]
- [ ] Enable **Hardened Runtime** (`--options runtime`) and `--timestamp`; sign every nested dylib/framework/helper (inside-out), then the app. [A7] [A8]
- [ ] Hardened-runtime exceptions only when needed: `com.apple.security.cs.disable-library-validation` if you load plugins signed by another team (not needed if you re-sign libmpv/FFmpeg yourself); `allow-jit` only for an embedded JS/Lua JIT; avoid `allow-unsigned-executable-memory` and `allow-dyld-environment-variables`. [A8]
- [ ] Submit with `notarytool` (altool/Xcode ≤13 rejected since Nov 2023), wait, read the log, then `stapler staple` the `.app`/`.dmg`/`.pkg`. [A7] [A15]
- [ ] Strip `com.apple.quarantine` xattrs from the bundle before upload (requirement since Feb 18 2025). [A15]
- [ ] macOS Sequoia removed the Control-click "Open anyway" bypass; un-notarized apps require a trip to System Settings → Privacy & Security — in practice, **notarization is mandatory** for a consumer app. [A19]
- [ ] Ship arm64 (universal only while you still support Intel; Rosetta ends after macOS 27). [A1]
- [ ] Sparkle (or similar) updates must be signed (EdDSA) and the updater's XPC services signed/notarized too. **(verify)**
- [ ] GPL/LGPL compliance (§5.3) is easier here (no App Store usage rules), but the notices still ship in About.

**Homebrew cask**: download URL must be the developer's own (or endorsed) release location, not forums/mirrors; app must pass Gatekeeper (i.e., be notarized) and must not require SIP/Gatekeeper to be disabled; must run on the latest macOS; notability is judged via the Package Acceptance Policy metrics (GitHub stars/forks are the usual proxy) **(verify current thresholds)**; a free app with optional paid features is eligible. [H1]

---

## 2. Google Play

### 2.1 Account, process and platform deadlines

| Item | Requirement | Source |
|---|---|---|
| Account | $25 one-time; identity verification; organizations need a D-U-N-S number (can take up to 28 days). | [G11] |
| New personal accounts (created after Nov 13 2023) | Closed test with **≥12 testers opted in for 14 continuous days**, then a production-access application (questions on tester feedback, audience, readiness). Testers who drop out reset their 14-day clock. | [G9] |
| Target API | From **Aug 31 2026**: new apps/updates must target **API 36 (Android 16)**; Wear/Automotive API 35; TV/XR API 34. Existing apps need API 35 to remain visible to new users. Extension to **Nov 1 2026** via Play Console form. | [G5] |
| 16 KB page size | Since **Nov 1 2025**, new apps and updates targeting Android 15+ must support 16 KB pages; from **Feb 1 2027** non-compliant updates cannot be released. Rebuild all native `.so` (FFmpeg, libmpv, libass, dav1d, libsmb2) with NDK r28+ (or `-Wl,-z,max-page-size=16384`), AGP ≥ 8.5.1, verify with `zipalign -c -P 16 4` and `bundletool dump config`. Android TV adds the same requirement from Aug 1 2026 (TV-G6). | [G6] [G7] [G14] |
| Packaging/signing | AAB + Play App Signing (mandatory for new apps); 64-bit native libs required. | [G6] **(verify)** |
| Pre-launch report | Automatic Firebase Test Lab crawl on every track; fix crashes it finds before promoting. **(verify)** | — |
| Content rating | IARC questionnaire in Play Console (an "unrestricted internet access" answer raises the rating). | [G12] **(verify)** |
| Data safety form | Required for **every** app, even if nothing is collected; crash logs, performance data and pseudonymous device IDs count as collected Diagnostics; SDK data is your responsibility; a **privacy policy URL is required** to complete the form; misrepresentation leads to blocked updates/removal. | [G13] |
| Android 14–16 behaviour | FGS types mandatory (API 34); edge-to-edge enforced and orientation locks ignored on large screens when targeting 36; predictive back default. **(verify)** | [G15] |

### 2.2 Storage and media permissions — the policy heart of a media player

**Photo and Video Permissions policy (apps targeting API 33+, enforced since May 28 2025).** `READ_MEDIA_IMAGES` and `READ_MEDIA_VIDEO` are reserved for apps "whose core functionality revolves around broad access to Photos and Videos" — the example is "gallery-style apps that manage all of a user's photos and videos". If a system picker could serve the core use, the permissions must be removed from the manifest. Apps with custom pickers "do not qualify automatically" and must file a **declaration in Play Console** explaining why the Android Photo Picker is insufficient. Apps must also "make a reasonable effort to serve users who deny broad access" (picker or degraded mode). Private/enterprise device-management apps are the only listed exemption; the page does not name media players either way. [G3] [G4]

> **How to position a media player:** `READ_MEDIA_AUDIO` is **not** covered by this policy — request it freely for the music library. For video, request `READ_MEDIA_VIDEO` *only if* the app genuinely offers a library/gallery experience (folder browsing, continuous scanning, resume positions, thumbnails, playlists across the whole library) and submit the declaration with that justification plus a video; declare and handle `READ_MEDIA_VISUAL_USER_SELECTED` (Android 14 "select photos" partial grant) and fall back to the Photo Picker/`ACTION_OPEN_DOCUMENT` when denied. Only request `READ_MEDIA_IMAGES` if an image-gallery mode is a real feature; otherwise use the Photo Picker for images. Declarations that read like "convenience" are rejected.

**All files access (`MANAGE_EXTERNAL_STORAGE`).** Permitted uses are file managers, backup/restore, antivirus, document managers, on-device search, disk encryption, device migration. Google's disallowed list explicitly includes **"media files access"** ("use MediaStore") and "any file selection activity". A media player will be rejected for requesting it. Use `MediaStore` for indexed media and the **Storage Access Framework** (`ACTION_OPEN_DOCUMENT_TREE` with persisted URI permissions) for arbitrary folders, SD cards and USB drives; network sources (SMB/WebDAV/DLNA/Plex) need no storage permission at all. [G4]

**Foreground service (mediaPlayback).** On API 34+, declare `android:foregroundServiceType="mediaPlayback"` and `FOREGROUND_SERVICE_MEDIA_PLAYBACK`; use Media3 `MediaSessionService`. Play Console requires a **FGS declaration per type** (App content page): description, user impact if interrupted, a **video showing the user starting playback** (auto-playing soundtracks don't qualify) and, if claimed, PiP being triggered. `mediaProcessing` (Android 15, 6-hour limit) is the type for transcoding/downloads, not playback. [G15] [G16]

### 2.3 Payments: tips and donations

Google's Payments policy requires Google Play's billing system for in-app purchases of digital content/features. The exemption list covers physical goods/services, bill remittances, "peer-to-peer payments, online auctions, and **tax-exempt donations**", gambling and disallowed categories. A developer tip jar is not a tax-exempt donation, so **tips must use Play Billing** (consumable products; 15 % service fee for the first $1 M/yr via the reduced-fee tier **(verify)**). Section 4 bars leading users to other payment methods (in listings, in-app, webviews, buttons) except where Sections 3/8/9 apply. [G8]

Regional carve-outs:
- **United States** (mobile/tablet, since **Oct 29 2025**, court-ordered through at least Nov 2027): developers may use non-Play billing in-app, promote it, and link out; enrollment in the Alternative Billing and External Content Links programs is required, with transaction/download reporting and service fees starting **Oct 1 2026** (links: **Dec 1 2026**). A March 4 2026 Epic settlement with a modified injunction is pending court approval. [G17]
- **EEA**: Alternative billing / user-choice billing for business-registered developers (PCI-DSS, support/dispute process, 24-hour reporting); fees from June 30 2026 are 10 % on the first $1 M then 20–25 %; the standard fee is reduced by 3 % when alternative billing is used. External-offers programme also exists. [G18]
- Korea, India and Japan have separate alternative-billing pages **(verify)**.

> **Recommendation:** Play Billing consumable "Buy me a coffee" SKUs globally; optionally enroll US/EEA programmes later; **F-Droid flavour** strips Play Billing and shows Liberapay/GitHub Sponsors links instead (allowed there). Never gate features behind tips in any flavour, which also keeps the Microsoft rule (§3.2) simple.

### 2.4 Developer verification (2026–2027) — affects F-Droid and sideloading

Google's verification links every app installed on certified Android 7+ devices to a verified developer. Timeline: Android Developer Console + "limited distribution" accounts (≤20 devices, no ID, no fee) and the power-user "advanced flow" (developer mode → reboot → 24-hour wait → biometric) launched Aug 2026; enforcement from **Sep 30 2026** for apps from participating stores in Brazil, Indonesia, Singapore, Thailand; **global in 2027**. Full-distribution registration costs **$25**; organizations need a D-U-N-S. ADB installs are exempt. For F-Droid-style distribution where the store re-signs with its own key, the upstream developer registers the package name and adds the store key's SHA-256 fingerprint (an `adi-registration.properties` asset is used for existing apps with ≥50 installs). Unregistered apps become installable only via the advanced flow. [G10] [G11] [G19]

### 2.5 Store listing assets, ratings prompts, form factors

- **Assets**: icon 512×512 PNG (≤1 MB), feature graphic 1024×500, phone screenshots 2–8 (320–3840 px, ≤2:1), tablet 7"/10" screenshots (≥1080 px, 16:9/9:16, 4+ recommended), TV screenshot + 1280×720 banner, Chromebook; YouTube preview (public/unlisted, ads off, embeddable). **Featuring eligibility** needs ≥4 screenshots at 1920×1080/1080×1920, no ranking/price/"best" claims, alt text. [G12]
- **In-App Review API**: don't ask before the user has experienced the app; never pre-ask "do you like it?"; don't alter/overlay the card; quota is undocumented (calls within ~a month may show nothing); never bind a "Rate us" button to the API — deep-link to the Play listing instead. [G21]
- **Android TV** (if targeting): leanback launcher intent, 320×180 banner, D-pad-only navigation, `touchscreen` not required, landscape fill, Now Playing card for background audio, `minSdk ≤ 31`, AAB, 16 KB + 32/64-bit from Aug 1 2026. [G14]
- **Android Auto** (audio only): no autoplay on start, MediaBrowserService/Media3, no video/animation, voice-command support, additional manual review that can block releases for other form factors — use a separate track. [G22]

---

## 3. Microsoft Store (policies v7.20, effective Oct 22 2026) and Windows direct distribution

### 3.1 Packaging choices

| Route | Rules | Notes |
|---|---|---|
| **MSIX (packaged)** | Store hosts, signs and auto-updates the package; Store commerce or third-party commerce; appears automatically in `winget` via the `msstore` source. | Preferred for a free app: zero SmartScreen friction, no certificate cost. |
| **Unpackaged Win32 (10.2.9)** | `.exe`/`.msi` only; "the binary and all of its Portable Executable (PE) files must be digitally signed" by a Microsoft Trusted Root CA cert; versioned, immutable HTTPS download URL you host; **silent install required** (UAC allowed); no stub/web installers; PC only; you handle updates; 10.4 adds "must not have an unreasonably low installation success rate". | Needs a code-signing cert (§3.4). |

### 3.2 Policy mapping

- **10.1 / 10.1.1** metadata must be accurate; title must be unique and contain no marketing/keyword stuffing; "value proposition … must be clear during the first run experience"; no pricing terms in search terms (10.1.3). [M1]
- **10.2** no dynamic code that changes described functionality (10.2.2 — careful with scripting/plugin systems), no bundled third-party software (10.2.3), clean uninstall (10.2.7), use supported methods for defaults/file associations (10.2.8). Browser-engine rule (10.2.1) is irrelevant unless you embed a browser. [M1]
- **10.5.1 Privacy**: "Product types that inherently have access to Personal Information must always have privacy policies. These include … Desktop Bridge and Win32 products" — provide the URL in Partner Center. Opt-in consent for publishing personal data (10.5.2), secure transmission (10.5.4). [M1]
- **10.8 Financial transactions**: 10.8.1 only games and Xbox products must use Microsoft IAP; "Non-game products made available on PC devices may either use a secure third-party purchase API or the Microsoft Store in-product purchase API". **10.8.2**: "You must use the Microsoft payment request API or a secure third-party purchase API to receive voluntary donations from users. However, if the user receives digital goods or services in return … you must use the Microsoft Store in-product purchase API instead." Third-party API conditions: identify the provider, authenticate, confirm each transaction, PCI-DSS, and "note the use of a secure third-party purchase API in Partner Center". Microsoft announced in 2021/22 that non-game apps using their own commerce keep 100 % (0 % Store fee) **(verify current terms)**; Store IAP takes 12 % for non-games **(verify)**. 10.8.3: products that *require* financial information must come from a company account; 10.8.7: open-source software must not be "priced irrationally high" (free is fine). [M1] [M2]
- **10.14 Account type**: individual account OK for a solo developer; a company account is needed if the publisher name reads as a business. Fees ≈ $19 individual / $99 company one-time **(verify)**. [M1]
- **11.2** all content/metadata originally created or licensed; **11.11** IARC questionnaire mandatory at submission and must be kept current (an existing IARC ID from another store can be reused); **11.13/11.15/11.16** (third-party storefront content, child safety, live generative-AI transparency) only if applicable. [M1] [M3]
- **Certification notes**: declare any third-party commerce, test files/URLs for reviewers, and codec dependencies; policy 10.2.4 requires disclosing dependencies on non-integrated software at the start of the description (e.g., "requires the HEVC Video Extensions from the Store for hardware HEVC"). [M1]

### 3.3 Listing assets

One screenshot minimum; up to 10 desktop screenshots (≥1366×768, 4K supported, PNG ≤50 MB, keep text in the top two-thirds); 1:1 app tile icon 300×300 strongly recommended; 16:9 "super hero art" 1920×1080/3840×2160 (no text) required for trailers to show and for featuring consideration; trailers MP4 (H.264 High, 1920×1080, AAC-LC 48 kHz) or MOV ProRes, ≤2 GB, ≤60 s recommended, up to 15, with a 1920×1080 PNG thumbnail; captions (.vtt) and audio descriptions (.mp3) supported. [M4]

### 3.4 Code signing, SmartScreen, winget

- Store-distributed MSIX is signed by Microsoft — no certificate needed and no SmartScreen prompt. [M5]
- Direct download: sign with an OV/EV certificate or **Azure Artifact Signing** (formerly Trusted Signing; individuals currently limited to US/Canada; ~$10/month basic tier **(verify)**). Since Microsoft's 2024 Trusted Root Program change, **EV certificates no longer grant instant SmartScreen reputation**; reputation accrues per file hash, so every release starts cold until enough installs occur. Plan for the "Windows protected your PC" dialog in your download instructions, or push users to the Store/winget. [M5] [M6]
- **winget** (community repo policies v1.0): `InstallerUrl` "must be the ISV's release location"; silent-install switches required; ≤16 tags; `PrivacyUrl` if personal info is accessed; no malware/dynamic code; submission is a PR validated automatically and sometimes reviewed manually; new versions need new PRs (automate with `wingetcreate`/GitHub Action). An MSIX in the Store appears in the `msstore` source without a PR. [W1] [W2]

---

## 4. Optional stores

| Store | Must-haves for this app | Payments | Source |
|---|---|---|---|
| **F-Droid** | FLOSS licence for all code; built from source by F-Droid with a fully FLOSS toolchain; **no Google Play Services, Firebase, Crashlytics or proprietary SDKs** (ship a `foss` flavour without Play Billing/Cast SDK — Google Cast SDK is proprietary → NonFreeDep anti-feature or exclude); prebuilt binaries only from trusted sources (Maven Central etc.) or built from source — FFmpeg/libmpv must be compiled in the F-Droid build; anti-features must be disclosed (NonFreeNet if you default to proprietary services); app ID must not squat someone else's domain; reproducible builds let you keep your own signing key. Donation links in metadata must be verifiable via `funding.json`/`FUNDING.yml`/README. From 2027, register the package and F-Droid's signing key with Google developer verification. | External donation links allowed. | [F1] [G19] |
| **Samsung Galaxy Store** | Seller Portal registration; publication review; privacy policy URL if data is collected; age rating + categories; English metadata if >1 country; accurate screenshots; test credentials for login; no beta binaries, no in-app downloading of other apps, no auto-update mechanisms. Samsung IAP is "recommended" (not strictly mandated in the fetched guide). | Samsung IAP recommended. | [S1] |
| **Amazon Appstore** | Free developer account; APK/AAB for Fire OS (plus VPKG for the new Vega OS); test on a physical Fire device; Fire TV apps must register the `main` category; IAP items entered on the In-App Items tab; version code must increase on updates. Amazon requires its own IAP SDK for in-app digital goods **(verify)**. | Amazon IAP. | [AM1] |
| **Huawei AppGallery** | Developer identity verification; "User Privacy" section (privacy policy, permission minimum-necessity); "App Payment" section (HMS In-App Purchases for digital goods **(verify)**); China distribution needs ICP filing/business licences — likely distribute "overseas" only. | HMS IAP. | [HW1] |
| **Homebrew / winget** | See §1.6 and §3.4. | n/a | [H1] [W1] |

---

## 5. Cross-cutting obligations

### 5.1 Privacy policy and data protection (GDPR / CCPA / COPPA)

Every store needs a privacy policy URL (Apple: in App Store Connect *and* in-app; Google: required to complete Data safety for all apps; Microsoft: always for Win32; Samsung: if data collected). It must list data types (crash logs, device model, OS version, IP addresses if logged), purposes, third parties/SDKs (e.g., Sentry, Firebase Crashlytics — note Crashlytics is barred on F-Droid), retention and deletion, how to withdraw consent, and a contact. [G1] [G13] [M1]

- **Telemetry/crash reporting**: treat as personal data under GDPR (device identifiers, IPs). Apple independently requires **opt-in consent even for anonymous usage data** (5.1.1(ii)), so a first-run "Send crash reports? (off by default)" toggle satisfies Apple, GDPR consent (Art. 6(1)(a)) and the ePrivacy "storing/accessing information on terminal equipment" rules; keep a settings switch to revoke. Minimise: no user IDs, no precise location, scrub file paths/filenames from crash payloads (they may reveal personal media). Sign a DPA with the crash-reporting vendor and mention EU→US transfers. **CCPA/CPRA** thresholds ($25 M revenue / 100 k consumers / 50 % revenue from selling data) are unlikely to be met by a donation-funded app, but the policy should still state "we do not sell or share personal information". **(verify thresholds)**
- **COPPA / Families**: do not select Google's "Designed for Families", Apple's Kids category, or a sub-13 target audience; declare the target audience as 13+/general. US state age-assurance laws (Texas SB 2420 effective June 4 2026, Utah, Louisiana) are handled by Apple's Declared Age Range API only where content is age-restricted — a local player isn't, but a stream/URL feature could be. [A1]
- **EU DSA trader status** (Apple since Feb 2025; Google Play also collects trader status for EU listings **(verify)**): publish name, address, email/phone.

### 5.2 Accessibility (EAA, WCAG, ADA)

The **European Accessibility Act** (Directive 2019/882) applies from **June 28 2025**; it covers listed services (e-commerce, banking, e-books, "services providing access to audiovisual media services", transport, e-communications) and consumer hardware/OS; mobile apps delivering those services are in scope, and conformity with **EN 301 549** (which incorporates WCAG 2.1 AA plus native-app clauses) gives a presumption of conformity. A standalone local-file player is arguably not an "access service" to an AVMS, and **microenterprises (<10 staff and ≤€2 M turnover/balance sheet) providing services are exempt (Art. 4(5))** — but platform policies (Apple accessibility labels, Google's accessibility checks in pre-launch reports) and US ADA litigation risk make WCAG-level support the practical bar anyway. [X3] [A16]

Media-player specifics: every control labelled for VoiceOver/TalkBack/Narrator; full keyboard and D-pad operability (also an Android TV hard requirement); captions/subtitles rendered with system caption preferences and user-adjustable size/contrast; audio-description track selection; "Reduce Motion" respected in transitions; Dynamic Type/200 % text; focus order in the player chrome; don't convey state by colour alone (e.g., selected audio track).

### 5.3 Open-source licence obligations (FFmpeg, libmpv, etc.)

- **GPL is incompatible with the App Store.** The FSF's 2010 GNU Go complaint held that the App Store Terms of Service impose restrictions GPLv2 §6 forbids; Apple removed the app rather than change its terms. VLC for iOS was pulled in January 2011 for the same reason and returned in 2013 only after VideoLAN relicensed libVLC and the iOS app to **LGPL/MPL**. The same logic applies to Mac App Store, and the GPL's "no further restrictions" clause makes Google Play and Microsoft Store usage terms contentious too — treat **GPL as a no-go for store builds** (direct macOS/Windows downloads and F-Droid are fine). [X1] [X2]
- **LGPL (FFmpeg default, libmpv with `--enable-lgpl`, libbluray)** is workable if you (a) link dynamically (`.framework`/`.dylib` inside the bundle on macOS/iOS — permitted since iOS 8; `.so` on Android; `.dll` on Windows) or provide object files for relinking, (b) ship the licence texts and a written offer/URL for the corresponding source of the **exact** library build with your patches, (c) don't apply DRM to the library that prevents relinking, and (d) include notices in the app's About → Licences screen (also satisfies Apple 5.2, Microsoft 11.2, F-Droid). **(verify libmpv's LGPL build coverage for the features you need)**
- **Configure flags**: build FFmpeg with `--disable-gpl --disable-nonfree` (drops x264/x265/libpostproc-GPL parts and fdk-aac); use `dav1d` (BSD-2) for AV1, `libvpx` (BSD), `opus`/`FLAC`/`libogg` (BSD), `libass` (ISC), `libsmb2` (LGPL-2.1), `libbluray` (LGPL) **without** `libaacs`/`libbdplus` keys, and **never** `libdvdcss` (GPL + DRM-circumvention exposure). Patent-related: see §5.4.
- **Attribution screen** listing every component, licence and source link is expected by all stores and by the licences themselves (BSD/MIT/ISC/Apache notices too).

### 5.4 Codec patent realities (what free players actually do)

| Codec | Patent status (Oct 2026) | Safe path for a free app |
|---|---|---|
| **H.264/AVC** | Pools still active (Via LA/Access Advance "VCL Advance"); many core patents expiring. | Platform decoders (VideoToolbox, MediaCodec, Media Foundation) — Apple/Google/Microsoft hold the licences. |
| **HEVC/H.265** | Heavily licensed: Access Advance lists >29 000 patents, absorbed the Via LA HEVC/VVC pool in Dec 2025, and runs software-codec programmes; per-unit fees apply to "end-user codecs" including software. VLC/mpv ship FFmpeg HEVC unlicensed, relying on enforcement focus on device makers and on EU/non-US jurisdiction — a real but rarely exercised risk for a zero-revenue app. | Prefer hardware/platform decode; keep the FFmpeg software HEVC path as fallback and disclose nothing that invites licensor attention (no "HEVC inside" marketing claims). On Windows, hardware HEVC via Media Foundation requires the "HEVC Video Extensions" Store add-on ($0.99 or OEM-preinstalled) — disclose per policy 10.2.4. [X4] |
| **AV1** | Royalty-free under AOMedia's patent licence with a defensive-termination clause; Sisvel asserts an AV1/VP9 pool and Access Advance is "exploring" an AV1/AV2 pool — residual risk is widely accepted. | dav1d (BSD) everywhere; hardware AV1 where available. [X4] |
| **VP8/VP9** | Google's royalty-free grant; Sisvel claims exist. | libvpx / platform. |
| **MP3** | **Patent-free**: EU by 2012, US since Apr 16 2017. | FFmpeg/minimp3 freely. [X5] |
| **AAC-LC/HE-AAC** | Via LA AAC pool still active; last baseline patents expire **2028**, extensions 2031; per-unit software royalties apply in theory; FFmpeg's decoder is now shipped by Fedora (2023) and all platforms expose licensed decoders. | Use platform AAC decoders (AVFoundation, MediaCodec, MF); FFmpeg AAC as fallback. [X6] |
| **AC-3 (Dolby Digital)** | **All patents expired Mar 20 2017** — free to decode. | FFmpeg `ac3` decoder is fine; avoid the Dolby logo/trademark. [X7] |
| **E-AC-3, Dolby TrueHD, Dolby Vision, Dolby Atmos** | Still under Dolby licensing/trademark programmes **(verify)**; Dolby Vision is a licensed trademark + metadata spec. | Decode via platform (Apple decodes E-AC-3 and Dolby Vision natively); do not advertise "Dolby" support or show logos without a Dolby licence; FFmpeg `eac3` works but the trademark is the practical constraint. |
| **DTS / DTS-HD** | Core DTS patents from the 1990s have largely lapsed; DTS-HD/DTS:X extensions remain licensed by Xperi **(verify)**. | FFmpeg `dca` decoder (what VLC/mpv/Kodi do); no DTS logos. |
| **ProRes** | Apple-controlled; Apple provides decoders on its platforms; FFmpeg has reverse-engineered decoders. | Platform decoder on Apple; FFmpeg elsewhere, no "ProRes" logo. |
| **Opus, FLAC, Vorbis** | Royalty-free. | Anything. |

Apple's guideline 5.2.1 ("patented ideas … without permission") has never, in practice, been used against FFmpeg-based players (VLC, Infuse, nPlayer, PlayerXtreme are all on the App Store), so the real exposure is from licensors, not reviewers. Keep hardware decode as the default path on every platform and let software decode be the compatibility fallback.

### 5.5 Fonts and trademarks

- Bundle only OFL/Apache fonts for subtitle rendering (Noto Sans/Noto Sans CJK, Open Sans, Roboto); OFL permits embedding and redistribution but forbids selling the font alone. **Do not redistribute** Apple's SF fonts, Microsoft's Segoe UI or other OS fonts — their licences restrict use to the vendor's platforms. **(verify current OFL/Apple font terms)**
- Trademarks in metadata/UI: "Chromecast"/"Google Cast" only per Google's brand guidelines and with the official Cast SDK; "AirPlay" sender support via AVKit route pickers is fine, but an **AirPlay receiver** requires an MFi licence — don't build one; "Dolby", "DTS", "Plex" marks only with permission; Apple rejects competitor names in keywords (2.3.7) **(verify)**.

### 5.6 Export compliance

See §1.3 for Apple. Google Play and Microsoft Store have no equivalent questionnaire, but US EAR still applies to the binary; HTTPS/TLS-only software via OS libraries is mass-market exempt. Keep a one-page "encryption inventory" (TLS via OS, SMB signing/encryption via libsmb2 + bundled crypto?) for App Store Connect answers.

---

## 6. Store-listing success factors

### 6.1 Asset matrix

| Store | Screenshots | Video | Other | Source |
|---|---|---|---|---|
| **Apple** | 1–10 per device size; **required**: iPhone 6.1" (1179×2556/1206×2622); 6.5" (1284×2778) unless 6.9" (1290×2796 / 1320×2868) provided; iPad 13" (2064×2752/2048×2732); Mac 16:10; Apple TV 1920×1080; Vision Pro 3840×2160; no alpha; **iPhone Duo screenshots from April 2027**. | App previews 15–30 s, up to 3 per size/language, H.264 ≤30 fps or ProRes 422 HQ, 886×1920 for modern iPhones, 1600×1200 iPad, 1920×1080 Mac/TV. | New (Oct 2026) product-page headers/search assets via Asset Library; 50 localisable metadata languages; name 30 chars, subtitle 30, keywords 100 **(verify limits)**. | [A17] [A18] [A1] |
| **Google Play** | 2–8 phone (320–3840 px); ≥4 tablet at 1080+ px for featuring; TV screenshot + 1280×720 banner. | YouTube URL, public/unlisted, ads off, first 10 s must show real use, first 30 s autoplay. | Icon 512², feature graphic 1024×500, title 30, short description 80, full 4000 **(verify)**; alt text on assets. | [G12] |
| **Microsoft Store** | 1–10 desktop (≥1366×768, PNG ≤50 MB). | Up to 15 trailers, 1920×1080 MP4/MOV ≤2 GB, 1920×1080 PNG thumbnail. | 300×300 tile icon, 1920×1080 super-hero art (no text) for featuring. | [M4] |
| **F-Droid** | `fastlane/metadata/android/<locale>/images/phoneScreenshots/` | — | `short_description.txt` (≤80), `full_description.txt`, changelogs per versionCode. **(verify)** | [F1] |

### 6.2 ASO and conversion for a media player

- **Keyword set** (research-driven, not stuffed): "video player", "media player", "MKV player", "music player", "HEVC", "subtitles", "SMB", "NAS", "DLNA", "cast", "play any format", "FLAC". Apple weighs the **title + subtitle + keyword field** (no repeats); Google indexes title, short and full description (natural repetition 3–5× per key phrase). Avoid competitor names (Apple 2.3.7) and price/ranking words (Google featuring rules, Microsoft 10.1.3). [G12] [M1]
- **First screenshot** = the playing experience with subtitles and a recognisable format badge list; second = sources (Files/SMB/NAS/cloud); third = audio with lock-screen controls; fourth = "free, no ads, supported by tips" (honest framing increases conversion for utility apps).
- **Ratings prompts**: Apple's system prompt is capped at **3 per 365 days per device**; call `AppStore.requestReview` only after a success moment (e.g., third completed playback), never on launch or during playback, never behind a custom "Do you like it?" gate (1.1.7/4.0 rejections) **(verify guideline cite)**; provide a settings "Rate on the App Store" deep link (`?action=write-review`) that doesn't count against the cap. Google: same ethic, undocumented quota, no CTA button bound to the API. [A20] [G21]
- **Release notes**: Apple requires specific "What's New" text (generic notes are rejected under 2.3.12 **(verify)**); Google and Microsoft show them prominently; keep a changelog per version for F-Droid.
- **Localisation**: Apple now offers 50 metadata locales; prioritise EN, DE, FR, ES, PT-BR, IT, JA, KO, ZH-Hans/Hant, RU, TR, ID — subtitle-heavy audiences (JP/KR/BR/TR) convert well for players. Microsoft policy 10.7 expects descriptions localised for every supported language. [A1] [M1]
- **What gets featured**: Apple editorial favours apps adopting the current OS design (Liquid Glass, iOS 26/27 features), accessibility labels, privacy, iPad windowing and visionOS compatibility; Google favours large-screen quality (tablet/ChromeOS layouts), Android vitals under the bad-behaviour thresholds (user-perceived crash rate <1.09 %, ANR <0.47 % **(verify)**), 16 KB/API-36 compliance and the featuring asset rules; Microsoft needs the super-hero art and trailers. Submitting a **"featuring nomination"** (Apple: App Store Connect → Featuring; Google: through the Play Console "Promote" channels) 6–8 weeks before a big release is routine. **(verify nomination channels)**

---

## 7. Pre-submission checklists

### Apple (iOS/iPadOS + Mac App Store)
- [ ] Xcode 26+/OS 26 SDK (27 from Apr 2027); iPad windowing tested; visionOS compatibility tested or opted out.
- [ ] `UIBackgroundModes=audio`; Now Playing + remote commands; PiP works; audio session interruptions handled.
- [ ] Info.plist purpose strings only for APIs actually used (Photos, Local Network + `NSBonjourServices`, Bluetooth if any); multicast entitlement requested if SSDP/DLNA.
- [ ] Document types/UTIs declared; Files app open-in-place; PHPicker preferred; limited-library handling.
- [ ] `PrivacyInfo.xcprivacy` (required-reason APIs) for app and every SDK; nutrition labels; privacy policy URL in ASC + About screen; opt-in diagnostics toggle.
- [ ] Tip jar as consumable IAPs, restore not needed for consumables but "credits may not expire"; external donation links gated to US storefront (and EU under Attachment 14) or removed.
- [ ] No GPL code; LGPL dynamic frameworks + licence screen; FFmpeg built without gpl/nonfree.
- [ ] Export compliance answer consistent with bundled crypto; French declaration if OpenSSL/mbedTLS.
- [ ] Age-rating questionnaire (incl. social-media and web-access questions) completed; DSA trader info for EU.
- [ ] Notes for Review: test SMB/WebDAV share credentials, sample media URLs, where the tip jar lives.
- [ ] Mac: App Sandbox entitlements (user-selected files, bookmarks app-scope, network client), all dylibs re-signed; screenshots 16:10.

### Direct macOS
- [ ] Developer ID (G2 Sub-CA) + Hardened Runtime + timestamp on every binary; notarytool + staple; quarantine xattr stripped; arm64 build; Sparkle feed signed; Homebrew cask PR with the GitHub release URL.

### Google Play
- [ ] targetSdk 36; AAB; 64-bit + 16 KB-aligned `.so`; Play App Signing.
- [ ] Permissions: `READ_MEDIA_AUDIO`; `READ_MEDIA_VIDEO` only with a filed Photo/Video declaration + Photo Picker/SAF fallback; `READ_MEDIA_VISUAL_USER_SELECTED` handled; **no** `MANAGE_EXTERNAL_STORAGE`; SAF for folders; network sources permission-free.
- [ ] `mediaPlayback` FGS type + permission + Play Console FGS declaration video; Media3 MediaSession; notification controls.
- [ ] Data safety form (Diagnostics if crash logs), privacy policy URL, IARC rating, target audience 13+.
- [ ] Tips via Play Billing consumables (optionally US/EEA alternative billing enrolment); no external payment links in store builds; `foss` flavour for F-Droid.
- [ ] New personal account: 12 testers × 14 days closed test completed; pre-launch report clean.
- [ ] Android TV/Auto only if their quality bars are met (separate track for Auto).
- [ ] Register package + signing keys (incl. F-Droid's) for developer verification before 2027.

### Microsoft Store / Windows
- [ ] MSIX (recommended) or unpackaged `.exe`/`.msi` meeting 10.2.9 (silent install, trusted-root-signed PEs, versioned URL).
- [ ] Privacy policy URL (mandatory for Win32); IARC questionnaire; accurate category/title; first-run value proposition visible.
- [ ] Tips: third-party processor or Microsoft payment request API with provider identification and confirmation, declared in Partner Center; use Microsoft IAP only if tips return digital goods.
- [ ] Dependencies (HEVC Video Extensions) disclosed at the top of the description; clean uninstall; no bundled third-party software.
- [ ] Direct download: Azure Artifact Signing/OV cert; expect cold SmartScreen reputation per release; winget manifest PR with silent switches and ISV-hosted InstallerUrl.

---

## Sources

**Apple**
- [G1] App Store Review Guidelines (Last Updated Oct 16 2026) — https://developer.apple.com/app-store/review/guidelines/
- [A1] Apple Developer News (2026 items: Oct 16 guideline update; Oct 5 iPhone Duo & creative assets; Oct 2 Full Disk Access; Oct 1 Developer ID Sub-CA; Sep 16 ATT in EU; Sep 9 OS 27 submissions; Sep 1 Rosetta; Aug 18 EU terms; Jul 9 age-rating questions; Feb 3 SDK minimums) — https://developer.apple.com/news/
- [A2] DMA and apps in the EU (Attachment 14, commissions, CTC, reporting) — https://developer.apple.com/support/dma-and-apps-in-the-eu/
- [A3] Apple EU terms coverage (Aug 18 2026) — https://mjtsai.com/blog/?p=52942 ; https://aiweekly.co/alerts/apple-replaces-eu-core-technology-fee-with-5-commission
- [A4] App privacy details (nutrition labels) — https://developer.apple.com/app-store/app-privacy-details/
- [A5] Privacy manifest files / required-reason APIs — https://developer.apple.com/documentation/bundleresources/privacy-manifest-files ; https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api
- [A6] App Sandbox entitlements & security-scoped bookmarks — https://developer.apple.com/documentation/security/accessing-files-from-the-macos-app-sandbox ; https://developer.apple.com/library/archive/documentation/Miscellaneous/Reference/EntitlementKeyReference/Chapters/EnablingAppSandbox.html
- [A7] Notarizing macOS software before distribution — https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution
- [A8] Hardened Runtime — https://developer.apple.com/documentation/security/hardened-runtime
- [A9] Export compliance documentation for encryption; Complying with encryption export regulations — https://developer.apple.com/help/app-store-connect/reference/export-compliance-documentation-for-encryption ; https://developer.apple.com/documentation/security/complying-with-encryption-export-regulations
- [A10] Developer forum reports on 3.2.1(vii)/3.2.2 donation rejections — https://developer.apple.com/forums/tags/app-review?page=30 ; https://forums.expo.dev/t/app-rejected-ios-app-store-business-guideline-3-1-1-business-payments-in-app-purchase/39908
- [A11] PhotoKit: Delivering an enhanced privacy experience — https://developer.apple.com/documentation/photokit/delivering-an-enhanced-privacy-experience-in-your-photos-app
- [A12] TN3179 Understanding local network privacy — https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy
- [A13] Apple DTS on NSBonjourServices (forum) — https://developer.apple.com/forums/thread/653316
- [A14] App Tracking Transparency / user privacy — https://developer.apple.com/app-store/user-privacy-and-data-use/
- [A15] Upcoming requirements (dated list) — https://developer.apple.com/news/upcoming-requirements/
- [A16] Accessibility Nutrition Labels overview — https://developer.apple.com/help/app-store-connect/manage-app-accessibility/overview-of-accessibility-nutrition-labels
- [A17] Screenshot specifications — https://developer.apple.com/help/app-store-connect/reference/screenshot-specifications
- [A18] App preview specifications — https://developer.apple.com/help/app-store-connect/reference/app-preview-specifications
- [A19] Gatekeeper and notarization in Sequoia — https://eclecticlight.co/2024/08/10/gatekeeper-and-notarization-in-sequoia/
- [A20] Requesting App Store reviews — https://developer.apple.com/documentation/storekit/requesting-app-store-reviews
- US external links after Epic (May 2025) — https://mjtsai.com/blog/2025/05/02/app-review-guidelines-updated-for-epic-anti-steering ; https://www.pocketgamer.biz/apple-updates-app-store-rules-to-allow-external-payment-after-court-ruling

**Google / Android**
- [G3] Photo and Video Permissions policy details — https://support.google.com/googleplay/android-developer/answer/16935362 ; https://support.google.com/googleplay/android-developer/answer/14115180
- [G4] All files access (MANAGE_EXTERNAL_STORAGE) policy — https://support.google.com/googleplay/android-developer/answer/10467955 ; https://developer.android.com/training/data-storage/manage-all-files
- [G5] Target API level requirements — https://developer.android.com/google/play/requirements/target-sdk ; https://support.google.com/googleplay/android-developer/answer/11926878
- [G6] 16 KB page sizes guide — https://developer.android.com/guide/practices/page-sizes
- [G7] Android Developers Blog, 16 KB requirement from Nov 1 2025 — https://android-developers.googleblog.com/2025/05/prepare-play-apps-for-devices-with-16kb-page-size.html
- [G8] Payments policy — https://support.google.com/googleplay/android-developer/answer/9858738
- [G9] App testing requirements for new personal accounts — https://support.google.com/googleplay/android-developer/answer/14151465
- [G10] Android developer verification overview — https://developer.android.com/developer-verification
- [G11] Developer verification FAQ (fees, limited distribution, ADB, timeline) — https://developer.android.com/developer-verification/guides/faq
- [G12] Store listing asset requirements & featuring eligibility — https://support.google.com/googleplay/android-developer/answer/9866151
- [G13] Data safety form — https://support.google.com/googleplay/android-developer/answer/10787469
- [G14] Android TV app quality — https://developer.android.com/docs/quality-guidelines/tv-app-quality
- [G15] Foreground service types (Android 14) — https://developer.android.com/about/versions/14/changes/fgs-types-required ; https://developer.android.com/guide/components/fg-service-types
- [G16] Play Console FGS / full-screen-intent declarations — https://support.google.com/googleplay/android-developer/answer/13392821
- [G17] US billing/linking policy changes (Oct 29 2025) — https://support.google.com/googleplay/android-developer/answer/15582165 ; https://www.neonpay.com/blog/google-plays-new-u.s.-billing-linking-policies-what-game-developers-need-to-know
- [G18] EEA alternative billing — https://support.google.com/googleplay/android-developer/answer/12348241
- [G19] Open-source app registration for developer verification — https://developer.android.com/developer-verification/guides/open-source-app-registration
- [G20] (see [M1] for Microsoft donation rule)
- [G21] In-app review guidelines — https://developer.android.com/guide/playcore/in-app-review
- [G22] Android for Cars app quality — https://developer.android.com/docs/quality-guidelines/car-app-quality
- Developer verification press coverage — https://9to5google.com/2025/08/25/android-apps-developer-verification/

**Microsoft / Windows**
- [M1] Microsoft Store Policies v7.20 (effective Oct 22 2026) — https://learn.microsoft.com/en-us/windows/apps/publish/store-policies
- [M2] Store policies change history (v7.19 Sep 10 2025) — https://learn.microsoft.com/en-us/windows/apps/publish/store-policies-change-history ; third-party billing coverage — https://www.neowin.net/news/microsoft-explains-how-third-party-billing-works-in-the-microsoft-store/
- [M3] Age ratings (IARC) for MSIX apps — https://learn.microsoft.com/en-us/windows/apps/publish/publish-your-app/msix/age-ratings
- [M4] Screenshots, images and trailers — https://learn.microsoft.com/en-us/windows/apps/publish/publish-your-app/msix/screenshots-and-images
- [M5] Code signing options / SmartScreen reputation — https://learn.microsoft.com/en-us/windows/apps/package-and-deploy/code-signing-options ; https://learn.microsoft.com/en-us/windows/apps/package-and-deploy/smartscreen-reputation
- [M6] Distribute Win32 apps through the Store — https://learn.microsoft.com/en-us/windows/apps/distribute-through-store/how-to-distribute-your-win32-app-through-microsoft-store
- [W1] Windows Package Manager repository policies — https://learn.microsoft.com/en-us/windows/package-manager/package/windows-package-manager-policies
- [W2] Submit your manifest to the repository — https://learn.microsoft.com/en-us/windows/package-manager/package/repository

**Optional stores**
- [F1] F-Droid Inclusion Policy — https://f-droid.org/docs/Inclusion_Policy/
- [H1] Homebrew Acceptable Casks — https://docs.brew.sh/Acceptable-Casks
- [S1] Samsung Galaxy Store distribution guide — https://developer.samsung.com/galaxy-store/distribution-guide.html
- [AM1] Amazon Appstore: Submitting apps — https://developer.amazon.com/docs/app-submission/submitting-apps-to-amazon-appstore.html
- [HW1] Huawei AppGallery Review Guidelines index — https://developer.huawei.com/consumer/en/doc/app/50104

**Cross-cutting**
- [X1] FSF on App Store GPL non-compliance (GNU Go, 2010) — https://www.fsf.org/news/2010-05-app-store-compliance
- [X2] VLC iOS removal and LGPL return — https://cdm.link/as-apple-pulls-gpl-licensed-vlc-the-developers-version-of-events-what-it-means-for-free-video-2/ ; https://news.slashdot.org/story/13/07/18/1943202/vlc-for-ios-returns-on-july-19-rewritten-and-fully-open-sourced ; FFmpeg ticket #1229 — https://trac.ffmpeg.org/ticket/1229
- [X3] European Accessibility Act explainers — https://e-include.eu/web-accessibility/european-accessibility-act/ ; https://www.qualibooth.com/resources/european-accessibility-act-faq/ ; https://sota.io/blog/eaa-compliance-finale-2026-developer-toolkit-enforcement-national-authorities
- [X4] HEVC/AV1 pool landscape — https://www.businesswire.com/news/home/20260126799824/en/Access-Advance-Extends-HEVC-Advance-Rate-Increase-Deadline ; https://www.law360.com/mlex/articles/2422258/combined-access-advance-via-la-codec-pools-could-fend-off-av1-threat ; https://secure.businesswire.com/news/home/20260707864649/en/Access-Advance-Welcomes-Wave-of-New-Licensees-to-the-HEVC-Advance-Patent-Pool
- [X5] MP3 patent expiry — https://en.wikipedia.org/wiki/MP3
- [X6] AAC licensing/patent expiry — https://en.wikipedia.org/wiki/Advanced_Audio_Coding
- [X7] AC-3 patents expired Mar 20 2017 — https://en.wikipedia.org/wiki/Dolby_Digital
- Azure Artifact Signing / SmartScreen anecdotes — https://moonbase.sh/articles/code-signing-audio-plugins-in-2025-a-round-up/
