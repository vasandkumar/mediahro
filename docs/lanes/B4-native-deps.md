# Lane B4 — Native dependencies (`mediahro-deps`)

Three sub-lanes, each its own session and worktree of `vasandkumar/mediahro-deps` (sibling folder `K:\Projects\mediahro-deps`):

| Sub-lane | Owns (in mediahro-deps) | Also owns (in mediahro) |
|---|---|---|
| **B4a Android + shared** | `android/`, `versions.json`, `flags/*.common.flags`, `flags/mpv.flags`, `flags/libplacebo.flags`, `flags/vips.flags`, `flags/ffmpeg.android.flags`, `scripts/`, `.github/workflows/` | `deps.lock`, `tools/deps/`, `tools/licence_scan/` |
| **B4b Apple** | `apple/`, `flags/ffmpeg.apple.flags` | — |
| **B4c Windows** | `windows/`, `flags/ffmpeg.windows.flags` | — |

B4b and B4c request changes to shared files through B4a (STATUS.md §6 row or a PR comment); B4a applies them.

**Read:** Mediahro docs/05 §4.1, §10, §12 (ADR-002, 003, 004); docs/09 §2, §4; docs/07 §1 rules 4, 10, 12; docs/13 §6.2 (supply chain); `mediahro-deps/README.md`.

## Deliverables

1. **Pin** every library in `versions.json` to an exact upstream release with the source SHA-256 taken from the upstream release (verify signatures where upstream publishes them). Builds verify the hash before extracting.
2. **`<platform>/build.sh <out-dir>`** building every applicable library with the flags in `flags/`, hardened (`_FORTIFY_SOURCE=2`, stack protector, PIE, CFI or `/guard:cf`), staging `lib/`, `include/`, `licenses/`, then `scripts/package.py`. Targets: Android arm64-v8a / armeabi-v7a / x86_64 with NDK r28+ and 16 KB page size; Apple dynamic xcframeworks for iOS device + simulator and macOS arm64 + x86_64 (MoltenVK); Windows x64 + arm64 DLLs.
3. **TLS from the OS** (no OpenSSL anywhere): Schannel on Windows, SecureTransport / Network.framework on Apple; on Android, network I/O reaches FFmpeg/curl through the app's stream callbacks (coordinate with B1/B2 via STATUS.md §6 if a library needs a TLS backend on Android).
4. **CI:** `build.yml` builds per platform on `workflow_dispatch` and tags, publishes a GitHub Release with archives and `.sha256` files. Each sub-lane proves its platform through that workflow (this machine cannot build Apple targets locally).
5. **Licence scan** (B4a, in mediahro): extend `tools/licence_scan/licence_scan.py` with Gradle and SwiftPM/CocoaPods dependency sources, keep the configure-flag and static-LGPL checks, and make `licence-sbom` run with `--require-native` once `deps.lock` is pinned. Scan the built objects for GPL-only sources (e.g. glslang/shaderc components) and fail on any.
6. **Pin in the app:** B4a writes the release tag, URLs and SHA-256 per target into `deps.lock` (PR to mediahro); `tools/deps/fetch.py` verifies them.

## Exit

Archives for every target published with SHA-256 and pinned in `deps.lock`; `scripts/verify_flags.py` and the app's licence scan pass with `--require-native`; B1 has replaced the media_kit bootstrap prebuilts.
