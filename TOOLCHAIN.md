# Toolchain

Pinned versions (docs/10 §1). CI uses exactly these; bump them only in a PR that updates this file, `.fvmrc` and the workflows together.

| Tool | Version | Pinned in |
|---|---|---|
| Flutter | 3.47.7 (stable, 2026-10-08) | `.fvmrc` (FVM 4.3.2) |
| Dart | 3.13.5 (bundled with Flutter) | — |
| Android Gradle / Kotlin | from Flutter 3.47.7 templates | `app/android/settings.gradle.kts` |
| Android NDK | r28c (28.2.13676358) — 16 KB page alignment | `app/android/app/build.gradle.kts` |
| Android SDK | compile/target 36, min 29 | `app/android/app/build.gradle.kts` |
| JDK | 21 (CI: Temurin 21; local: Android Studio JBR 21) | workflows |
| Xcode | 26.x on `macos-26` runners; iOS 16+ / macOS 12+ deployment | workflows, Xcode projects |
| Visual Studio | 2022 17.14 Build Tools, Windows SDK 10.0.22621+ | workflows |
| Windows App SDK | 2.5.x (added with the first WinRT module, lane C4) | `app/windows` |
| Python | 3.10+ (tools only) | workflows |
| very_good_analysis | ^11.0.0 | `pubspec.yaml` |
| Native libraries | `mediahro-deps` release pinned by SHA-256 | `deps.lock` |

Local setup:

```bash
dart pub global activate fvm
fvm install
fvm flutter pub get
tools/bootstrap
```
