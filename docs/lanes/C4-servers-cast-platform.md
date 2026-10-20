# Lane C4 — Servers, casting and platform modules (milestone M6)

C4 has four sub-lanes (ADR-025 §4). Each is its own session and worktree, owning only its folders. The facade **interfaces** in `app/lib/platform/*.dart` are frozen and belong to the orchestrator, as does `app/lib/platform/platform_bindings.dart`. Each platform sub-lane implements the facades in its own `app/lib/platform/<platform>/` and registers them in its own `bindings.dart`.

**Read (all sub-lanes):** CLAUDE.md, docs/lanes/README.md, docs/04 §8 NET-010…017, §9 CAST, §10 SYS, CORE-003/004/010, docs/05 §8 (platform modules), §9 (networking), §12 (ADR-014, 015, 017, 021…025), docs/06 §5 (platform adaptation), docs/07 (all of it: permissions, entitlements, privacy manifest, store rules), docs/13 §6.

## C4a — Android platform

**Owns:** `app/android/`, `app/pigeons/android/`, `app/lib/platform/android/`.

- **Facades, on Kotlin with coroutines (no Java):**
  - storage: SAF trees, MediaStore with trash/undo, Photo Picker fallback
  - photo library, media session (Media3 `MediaLibraryService` + foreground service, SYS-001/002/006)
  - audio output (AAudio, USB exclusive and DoP per ADR-023, ducking, Bluetooth codec), display, PiP, secure storage (Keystore), biometrics
  - managed config (`RestrictionsManager`), kiosk (lock task), system integration (open-with, share targets, SYS-003 App Actions), home widgets
  - TLS client and server (`SSLSocket`/`SSLServerSocket`), SFTP (sshj over JCA, ADR-017), auth browser (Custom Tabs), network status and multicast lock
  - Cast (official Cast SDK in `store`/`direct`; the `foss` flavour uses C4d's open sender), purchases (Play Billing, `store` flavour only), TTS, OCR/translation (ML Kit in `store`/`direct` only, ADR-025 §5)
  - media browse (Android Auto, MUS-013), alarms (`setAlarmClock`)
- **HDR:** the native HDR `SurfaceView` platform view (ADR-022).
- **App setup:** predictive back (`enableOnBackInvokedCallback`), 16 KB page alignment, `READ_MEDIA_*` with declarations and picker fallbacks, no `MANAGE_EXTERNAL_STORAGE` (docs/07 §3), foldables and large screens (SYS-011), accessibility services (SYS-008), input (SYS-009).

## C4b — Apple platforms (iOS/iPadOS, macOS)

**Owns:** `app/ios/`, `app/macos/`, `app/pigeons/apple/`, `app/lib/platform/apple/`.

- **Facades, on Swift with async/await:**
  - PhotoKit, security-scoped bookmarks, the Files/File Provider extension (SYS-005, I)
  - media session: `MPNowPlayingInfoCenter` and remote commands
  - AVAudioSession / CoreAudio hog mode with DoP, `AVPictureInPictureController` with the sample-buffer layer
  - Keychain, LocalAuthentication, managed app config, Guided Access / Single App Mode
  - App Intents, WidgetKit and Live Activities, menu-bar extra (M)
  - Network.framework TLS client and `NWListener` mutual TLS, SwiftNIO SSH for SFTP (ADR-017), `ASWebAuthenticationSession`, multicast entitlement handling
  - Cast SDK (I) and AirPlay (`AVRoutePickerView`, CAST-002), StoreKit 2, AVSpeechSynthesizer, Vision OCR, the Translation framework, CarPlay templates, alarms
- **HDR:** the native HDR video and image view (ADR-022, `AVSampleBufferDisplayLayer` / EDR).
- **Builds:** Xcode configurations for the four flavours (ADR-015), `PrivacyInfo.xcprivacy`, sandbox entitlements for the Mac App Store (`network.client`/`network.server`, user-selected files, bookmarks), drag-and-drop (CORE-004), window management (CORE-010).

## C4c — Windows platform

**Owns:** `app/windows/`, `app/pigeons/windows/`, `app/lib/platform/windows/`.

- **Facades, on C++/WinRT and the Windows App SDK 2.5+:**
  - storage (`StorageFolder` access, Recycle Bin), SMTC media session, WASAPI exclusive with DoP, display (`DisplayInformation`, mode switching for VID-036), compact overlay for PiP
  - Credential Locker / DPAPI, Windows Hello, MDM policy CSP for managed config, Assigned Access for kiosk
  - jump lists, taskbar thumbnail toolbar, open-with and Share target, drag-and-drop, window management
  - SChannel TLS client and server, libssh2 + WinCNG for SFTP (ADR-017), WebAuthenticationBroker / system browser
  - Microsoft Store purchases, `Windows.Media.SpeechSynthesis`, `Windows.Media.Ocr`, on-device translation where present, wake timers or notifications for alarms
- **Look and HDR:** Mica/Acrylic materials, the native HDR swap-chain view (ADR-022).
- **Packaging:** MSIX for `store`; the `direct` build's installer and signed updater hooks for CORE-012 (with C5).

## C4d — Servers and casting (Dart)

**Owns:** `packages/mediahro_servers/`, `app/lib/features/servers/`, `app/lib/features/cast/`.

- **Server clients (`ServerLibrary` implementations, through `HttpTransport` only):** Jellyfin, Emby, Plex, Subsonic/OpenSubsonic/Navidrome/Airsonic, Immich, Nextcloud (NET-015, over B2's WebDAV) and Audiobookshelf.
  - Coverage: browse, search, stream, transcode negotiation, progress and played-state sync, offline downloads with B2's NET-018 model.
  - Each client gets a recorded-fixture test suite plus a docker-compose server in network-env where an image exists.
- **Mediahro-to-Mediahro (NET-017):** an opt-in LAN share, QR pairing, mutual TLS over `TlsServerFacade`.
- **Casting:**
  - CAST-001: the open CASTv2 sender over `TlsSocketFacade` (M W, `foss` everywhere), with B1's cast server for remux/transcode, WebVTT subtitles, queue and volume.
  - CAST-003: DLNA renderer push.
  - CAST-004: external display through `DisplayFacade`.
  - The device picker and cast UI cover every `CastFacade` route, including AirPlay and the Cast SDK on A/I.

## Cross-lane dependencies

- **Platform sub-lanes:** they implement the native halves of C1/C2/C3/C5 features. Those lanes build against fakes; your implementation plus CI on your platform lets them tick.
- **Pigeon definitions:** if two platforms need the same message shape, copy it into your own pigeon file rather than sharing one.
- **New facade or member:** file an ADR request with the orchestrator.
- **Human-owned:** Cast receiver ID, multicast entitlement, CarPlay entitlement, store products and signing. List them in STATUS §4; never attempt them.

## Exit (M6)

Every C4 ID ☑ on each listed platform. Every facade is implemented on every platform doc 04 lists for the features that use it, with integration tests on that platform's CI job. The compliance guard (`tools/compliance/check_manifests.py`) passes for every flavour.
