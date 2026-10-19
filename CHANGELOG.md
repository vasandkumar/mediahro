# Changelog

All notable changes are grouped by feature area and reference feature IDs from `docs/04`.

## [Unreleased]

### Added
- Design system (lane B3, SYS-008, SYS-011): component library (`KButton`, `KSeekBar`, `KSheet`, `KGrid`, `KRow`, `KChip`, `KSidebar`, `KPlayerChrome`, `KMiniPlayer`, `KCompareView`, `KTimelineScrubber`, settings rows, skeletons, empty and error states) with semantics, platform target sizes, focus rings, reduced motion and transparency, 200 % text and RTL; window size classes, list-detail and tabletop layouts; golden matrix per platform family.
- Shell (CORE-001): sidebar per window class, last mode restored on launch, glass/Mica/solid bar materials, mini-player slot.
- First run (CORE-002): actions routed to the owning lanes; note that crash reports, usage statistics and update checks are off (PRIV-001).
- Settings (CORE-006): typed settings store with import/export, reset per section, managed-config overlay, search, and a registry other lanes contribute to.
- Themes (CORE-007): AMOLED, per-mode and custom accents with contrast-safe primaries, high contrast, follow-system theme.
- Localisation (CORE-008): pseudo-locales, ICU and placeholder checks, missing-string report, Weblate component config, size and duration formatting.
- Keyboard shortcuts (CORE-009): remappable actions with platform defaults, conflict detection and a cheat sheet on `?`.
- Privacy dashboard (CORE-015): every allow-listed endpoint with its switch and last-used time, and the hosts you added.
- M0 bootstrap: repository layout, flavours, design tokens, localisation pipeline, interface stubs, CI matrix, `STATUS.md`.
- Native dependencies (B4a): `deps.lock` pins mediahro-deps `v2026.10.0-android.1` (Android arm64-v8a, armeabi-v7a, x86_64; FFmpeg 8.1.3, mpv 0.41.0, libplacebo 7.360.1, libvips 8.18.7 and 50 more, all LGPL parts shared). The licence scan now covers Gradle, SwiftPM and CocoaPods dependencies, GPL-only sources compiled into native libraries and GPL/banned markers in the binaries.
