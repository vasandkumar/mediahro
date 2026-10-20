# Handoff: Lane C4a (Sonnet 5.5), 2026-10-20

The Opus session for this lane is retired. You continue its work from the same folder.

## Read first (every lane)
1. `CLAUDE.md`, then `docs/lanes/README.md` rules 1–12 (on main). Most important:
   - **Android first:** every Android feature ships before the first Play upload.
   - **No GitHub CI.** Never start a workflow.
   - **Never touch the phone or an emulator.** The orchestrator runs integration tests on the owner's Samsung, in batches of 25 features.
   - **16 GB PC:** at most 2 lanes at once and one heavy build (Gradle/APK, native compile, integration_test) at a time. Lanes prove their work at Dart level: `tools/check` plus unit and widget tests.
   - **Nothing large on C:.** Keep your build folder while you're active.
   - **No phone-home SDKs** (ADR-034 no ML Kit, ADR-035 no Google Cast SDK). Check any SDK's terms and data collection first.
   - **Frozen interfaces** (`app/lib/platform/*.dart`, the engine API, VFS) change only through an ADR request to the orchestrator.
   - The orchestrator owns `STATUS.md`, `CHANGELOG.md`, `app/pubspec.yaml`, `app/lib/main.dart` and workflows. Ask under "Orchestrator changes needed".
2. Your brief: `docs/lanes/C4-servers-cast-platform.md (section C4a)`. ADRs: `docs/05-technical-architecture.md` §12 (ADR-011…037).
3. **Models:** Sonnet 5.5. Use Haiku subagents (`model: "haiku"`) for simple, mechanical chores (cleanup, file moves, routine commands); use an Opus subagent (`model: "opus"`) only for genuinely hard problems. See rule 12.
4. **PRs:** small to medium (3–6 IDs), each listing the integration_test files for the orchestrator's phone batch. Merge proof is local, re-run by the orchestrator on the merge result and merged pinned to your head. Message the orchestrator (the session that started you) when a PR is ready, when you're blocked, or when you need an ADR.

## Where this lane stands
- **Folder:** `K:\Projects\Mediahro\.claude\worktrees\lane-c4a-android-4bcd9a` (you start here; this lane's work is already in it).
- **Branch:** `lane/c4a-car-cold` at **38a7843**, local only, **not compiled or pushed**: "cold car connect starts the app's engine headless" (ADR-036, accepted). It's 5 commits behind main, so rebase first.
- **Merged Android facades:**
  - #23 storage and photo library; #24 media session and audio output; #25 signing (key.properties) and kotlin.incremental=false
  - #27 display and PiP; #29 predictive back; #30 setAspectRatio; #33 secure storage and biometrics; #36 picker fix
  - #39 network status, multicast, auth browser; #41 TLS client and mutual TLS; #45 SFTP (sshj on JCA)
  - #46 caption style; #56 Android Auto and alarms; #59 power status; #62 home widgets
  - #65 open-with, share, shortcuts, App Actions; #67 TTS only plus openTextServiceOverrides
- **Next, in order:**
  1. Compile and finish the cold-connect PR (ADR-036 text in the PR).
  2. Play Billing (PurchasesFacade, store flavour only; storefrontCountry for link gating).
  3. ManagedConfig plus Kiosk (B2B-001/002).
  4. ImagingFacade on Android (ADR-037: ImageDecoder, loadThumbnail, HeifWriter, HDR still view, WallpaperManager, PrintHelper, clipboard, android.media.FaceDetector, noBackupFilesDir).
  5. Add `mediahroNativeLibs=libvips.so,libjxl.so,libjxl_threads.so,libavif.so,libraw.so` to app/android/gradle.properties (ADR-037).
  6. HDR SurfaceView video view (ADR-022).
  7. SYS-008 accessibility, SYS-009 input, SYS-011 foldables.
- **No Cast work** (ADR-035: C4d writes the open sender in Dart).
- **Gotchas:**
  - Android builds need `GRADLE_OPTS=-Dorg.gradle.project.kotlin.incremental=false` (also in gradle.properties).
  - Delete `packages/mediahro_engine/android/.cxx` if CMake complains after a crash.
  - Check that no other heavy build is running before each APK build.
