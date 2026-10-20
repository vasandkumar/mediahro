# Lane C5 — Supporter, privacy, B2B, engine packaging and store metadata (milestone M7)

**Owns:**
- `app/lib/features/supporter/`, `app/lib/features/b2b/`, `app/lib/features/privacy/`. The CORE-015 dashboard screen stays B3's; you own the telemetry opt-in, crash-report and app-lock code.
- `packages/mediahro_engine/sdk/` and `packages/mediahro_engine/capi/`. The engine itself is B1's (ADR-025 §2).
- `fastlane/`, `docs/help/` pages for your IDs, and store listing sources.

**Read:** CLAUDE.md, docs/lanes/README.md, docs/04 §11 (SUP), §12 (PRIV), §13 (B2B), CORE-012/013, docs/05 §9, §11, §12 (ADR-005, 014, 015, 025), docs/07 (store payment and link rules, privacy labels), docs/08 §2–3 (supporter copy and B2B), docs/09 (licences, notices), docs/12 §2 (store listings generated from sources), docs/13 §3, §6.

## Feature IDs (STATUS.md rows marked C5)

CORE-012, CORE-013, SUP-001…006, PRIV-001…006, PRIV-008, B2B-001…006. PRIV-007 is C3's.

## Deliverables

1. **Supporter programme:**
   - Support page (SUP-001).
   - **Store rails (SUP-002):** `PurchasesFacade`, implemented natively by C4a/b/c. External links are gated by `storefrontCountry()` per docs/07. The `foss` flavour shows only Liberapay/GitHub Sponsors links.
   - Web rail (SUP-003) for `direct`.
   - Perks, cosmetic only (SUP-004): themes, icons, badge.
   - Ask policy (SUP-005): rate-limited, never during playback, one dismissal silences it.
   - Transparency page (SUP-006).
2. **Privacy:**
   - **Zero telemetry by default (PRIV-001).**
   - **Opt-in crash reports (PRIV-002):** self-hosted Sentry with PII scrubbing (no paths, filenames or IPs) and a view-before-send. The host is an owner task (STATUS §4).
   - **Opt-in usage analytics (PRIV-003):** Aptabase.
   - **Network allow-list (PRIV-004):** audit every endpoint any lane added to `Endpoints.all`, and add a CI test asserting that only allow-listed hosts are reachable.
   - **Parsing safety (PRIV-005):** a review across lanes, with fuzz targets wired into `nightly.yml`. Ask the orchestrator to apply the workflow edit.
   - **Credentials (PRIV-006):** only in `SecureStorageFacade`, with an audit test.
   - **App lock (PRIV-008).**
3. **Updates and about:**
   - **CORE-012:** the store builds defer to the stores. Direct macOS uses a Sparkle-style signed appcast; direct Windows uses its signed updater (C4b/C4c provide the native hooks). The appcast host is on the allow-list and off unless the user enables it.
   - **CORE-013:** about and licences, generated from the CycloneDX SBOM and the mediahro-deps manifests, offline.
4. **B2B:**
   - Managed configuration keys and schema (B2B-001, over `ManagedConfigFacade`).
   - Kiosk/signage mode (B2B-002).
   - **Headless control API (B2B-003):** loopback by default, LAN opt-in with a token, with the OpenAPI spec published.
   - **Mediahro Engine SDK (B2B-004):** package the engine in `sdk/` (Kotlin AAR, Swift package, C API in `capi/` over B1's engine) under AGPL + commercial. Docs and samples are 1.1.
   - Audit and compliance export (B2B-005).
   - White-label hooks (B2B-006).
5. **Store metadata:** fastlane metadata for every store, generated from one source (docs/12 §2). No competitor or codec trademarks, and no Dolby/DTS/Chromecast marks outside permitted use (docs/07). Also prepare the privacy labels and data-safety forms. Submission stays with the owner.

## Cross-lane dependencies

- **C4a/b/c:** purchases, updater hooks, managed config and kiosk natively.
- **B1:** the engine API for the SDK.
- **B3:** settings registry and dashboard.
- **Orchestrator:** workflow edits.

## Exit (M7)

Every C5 ID ☑ on each listed platform. The allow-list test passes. The SBOM-driven licences screen matches the shipped binaries. Store metadata is generated for every store with nothing left but credentials.
