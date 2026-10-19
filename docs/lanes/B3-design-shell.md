# Lane B3 — Design system, shell, settings, onboarding, privacy dashboard

**Owns:** `packages/mediahro_design/`, `app/lib/app/` (shell, routing, theming, l10n fragments `app/lib/app/l10n/app_*.arb`, capabilities, flags), `app/lib/ui/`, `app/lib/features/settings/`, `app/lib/features/onboarding/`, `tools/l10n/`.

**Read:** docs/06 (all), docs/03 §3, docs/01 §4 and §7.2, docs/04 §1 (CORE), SYS-008, SYS-011, PRIV-001, PRIV-004; docs/05 §6 (Settings), §11; docs/11 §1 (goldens, accessibility, localisation rows).

## Feature IDs (STATUS.md rows marked B3)

CORE-001, CORE-002, CORE-006, CORE-007, CORE-008, CORE-009, CORE-015. You also own the shared accessibility foundation for SYS-008 and the adaptive layouts for SYS-011 (those rows are C4's; deliver the components and tests they build on).

## Deliverables

1. **Component library** in `packages/mediahro_design` (docs/06 §10): `KButton`, `KSeekBar`, `KSheet`, `KGrid`, `KRow`, `KChip`, `KSidebar`, `KPlayerChrome`, `KMiniPlayer`, `KCompareView`, `KTimelineScrubber`, plus `KSettingsRow`, skeleton rows, empty/error states (docs/06 §8–9). Every component: semantics labels and dynamic state labels, 44 pt targets, focus traversal, contrast ≥ 4.5:1, reduced-motion and reduced-transparency variants, Dynamic Type to 200 % without truncating primary labels, RTL.
2. **Goldens** per platform family (material, apple, fluent) × light/dark × 3 text scales × LTR/RTL × reduced motion, for every component and screen you own. Golden files committed per platform family; update only with intent.
3. **Shell** (CORE-001): bottom bar / rail / sidebar per docs/06 §2 and window-size classes, platform materials (Material 3 Expressive + dynamic colour opt-in on Android, Liquid-Glass-styled bars on Apple — never over video, Mica/Fluent on Windows), predictive back, mode switch < 100 ms in profile builds, **last mode restored on launch**, mini-player slot above the bar for C2.
4. **First run** (CORE-002) — keep it one screen, no walls, permissions only on action; wire the three actions to routes the owning lanes fill (sources, open file) behind facades.
5. **Settings** (CORE-006): typed `Settings` model (freezed, JSON in the app support dir), searchable settings UI, one-line description per row, Advanced sections collapsed, reset per section, import/export JSON, managed-config overlay hook (read-only rows show "Managed by your organisation" with a lock; C5 supplies the overlay values). Provide a settings registry so other lanes can contribute sections from their own folders without editing yours.
6. **Themes** (CORE-007): light/dark/system, AMOLED, per-mode accent, high-contrast variants.
7. **Localisation** (CORE-008): keep `tools/l10n/merge_arb.dart`; add a pseudo-locale (expanded strings + RTL) used by tests, the missing-string report in CI, Weblate configuration (one component per fragment glob, ADR-013), plural/locale formatting helpers (durations `1:23:45`, binary sizes with one decimal).
8. **Keyboard shortcuts** (CORE-009): action registry, default maps per platform (docs/06 §6.2), remapping UI, conflict detection, printable cheat sheet on `?`; other lanes register their actions.
9. **Privacy dashboard** (CORE-015): lists every `Endpoints.all` entry and user-configured hosts with toggle and last-used time, reading B2's `NetworkPolicy`; first-run explanation of the three telemetry toggles (off) for PRIV-001 (C5 owns the telemetry implementation).

## Exit

B3 goldens green in CI on every platform family; CORE-001/002/006/007/008/009/015 ticked on A/I/M/W; components available for Phase C lanes.
