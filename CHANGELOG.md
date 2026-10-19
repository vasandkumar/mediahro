# Changelog

All notable changes are grouped by feature area and reference feature IDs from `docs/04`.

## [Unreleased]

### Added
- M0 bootstrap: repository layout, flavours, design tokens, localisation pipeline, interface stubs, CI matrix, `STATUS.md`.
- Native dependencies (B4a): `deps.lock` pins mediahro-deps `v2026.10.0-android.1` (Android arm64-v8a, armeabi-v7a, x86_64; FFmpeg 8.1.3, mpv 0.41.0, libplacebo 7.360.1, libvips 8.18.7 and 50 more, all LGPL parts shared). The licence scan now covers Gradle, SwiftPM and CocoaPods dependencies, GPL-only sources compiled into native libraries and GPL/banned markers in the binaries.
