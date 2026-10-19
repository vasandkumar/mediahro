# Lane B1 — Engine (milestone M1)

**Owns:** `app/lib/engine/`, `packages/mediahro_engine/` (whole package in Phase B, including its `android/`, `ios/`, `macos/`, `windows/` plugin folders), `packages/mediahro_ffi/lib/src/mpv/` and `ffigen/mpv.yaml`, `tools/corpus/`, `test-media/`.

**Read:** docs/05 §1–4, §7, §10, §12 (ADR-001…004, 011, 012, 016); docs/04 §4 (VID), §5 (SUB-010…016), §6.1 (AUD), §9 (CAST-005); docs/09 §2, §4; docs/11 §1, §2, §5.

## Feature IDs (STATUS.md rows marked B1)

VID-001…007, VID-030…035, SUB-010…016 (engine rendering side; C1 later owns the UI), AUD-001…006, AUD-040…045 (engine side), CAST-005, CORE-011.

## Deliverables

1. `MpvEngine implements PlaybackEngine` in `packages/mediahro_engine/lib/src/mpv/`, over the libmpv client API through ffigen bindings (`mpv/client.h`, `render.h`, `render_gl.h`, `stream_cb.h`). Option defaults exactly as docs/05 §4.1. Property observation off the UI isolate; `PlaybackState` stream; errors surface as `PlaybackState.error` (CORE-011), never crashes.
2. **Render bridge** per platform (docs/05 §4.3) in the plugin's native folders, reached only via `RenderBridge` (ADR-011): Android SurfaceTexture/HardwareBuffer → Flutter `Texture`; Apple IOSurface-backed `CVPixelBuffer` external texture (MoltenVK / Metal); Windows D3D11 shared texture via `FlutterDesktopGpuSurfaceDescriptor`, HDR swap-chain formats. If the libmpv render API cannot drive the prescribed GPU path on a platform (it officially exposes OpenGL and software render APIs), implement the closest path that keeps every AC (HDR passthrough, tone mapping, zero-copy where possible) and record an ADR request in STATUS.md §6 — never drop HDR or a platform.
3. **VirtualFile → mpv**: register a stream protocol with `mpv_stream_cb_add_ro` so any `VirtualFileSource` is seekable (VID-006).
4. **Audio**: `ao` per platform, `audio-exclusive`, gapless, `scaletempo2`, `lavfi` DSP graph for `AudioDspChain` (10-band + 32-band parametric EQ, limiter, crossfeed, R128/ReplayGain with libebur128 scan in background), crossfade (AUD-003), truthful output indicator (AUD-006). Android bit-perfect (`setPreferredMixerAttributes`, AAudio) may live in the engine plugin's Kotlin until C4's AudioModule exists; expose it through `AudioOutputConfig` / `PlaybackState.audio`.
5. **Two-engine pool** (video + music) in `app/lib/engine/engine_pool.dart`; override `playbackEngineFactoryProvider` with `MpvEngine`. Ask the orchestrator (PR note) for any `main.dart` wiring.
6. **Casting pipeline** (docs/05 §4.5, CAST-005): local HTTP server (`shelf`) + passthrough/remux/transcode decision + WebVTT conversion in `packages/mediahro_engine/lib/src/cast/`. Senders are C4's.
7. **Native libraries:** until B4 publishes `mediahro-deps` archives you may bootstrap with media_kit's prebuilt libmpv packages (ADR-004); replace them with the `deps.lock` archives before M1 exits. Bundle the archives into the plugin builds (Gradle `jniLibs`, podspec `vendored_frameworks`, Windows CMake install of DLLs). LGPL libraries stay dynamic.
8. **DVD/Blu-ray folders (VID-007)** without GPL: libdvdnav/libdvdread are GPL and banned. Use an own MIT IFO parser (titles, chapters, audio/subtitle streams) and feed VOBs to mpv (EDL/concat); BDMV via libbluray (LGPL, dynamic) for unencrypted discs only.
9. **Corpus + harness:** `test-media/` (Git LFS, CC0/CC BY/own-generated files, licences in `test-media/LICENSES.md`; generating test files with any encoder at build time is fine — nothing generated ships) and `tools/corpus/run.dart` driving `MpvEngine` headless per docs/11 §1 (opens, first frame ≤ 500 ms, track counts, HDR detection, 10 seeks, 10 s without > 1 % drops). The nightly workflow already calls it.
10. FFI contract tests (docs/11 §1) on desktop runners; first-frame and seek budgets (docs/11 §5) in the perf harness.

## Exit (M1, docs/10 §3)

Corpus plays on A/I/M/W with AC for VID-001…007, VID-030…035, SUB-010…016, AUD-001…006, AUD-040…045 met; first frame ≤ 500 ms; prebuilts replaced by `mediahro-deps`; every B1 row ticked per platform or ⛔ with a STATUS.md blocker.
