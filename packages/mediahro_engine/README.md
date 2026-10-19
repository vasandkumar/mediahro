# mediahro_engine

The Mediahro playback core and the public surface of the **Mediahro Engine SDK** (B2B-004): the `PlaybackEngine` contract (docs/05 §4.2), its libmpv implementation, the per-platform render bridge (docs/05 §4.3), disc reading, the casting pipeline and audio tooling.

Licence: AGPL-3.0-or-later, or the commercial licence (`LICENSE-COMMERCIAL.md`). libmpv, FFmpeg and other LGPL libraries are only ever loaded dynamically (docs/09 §2).

## Layout

| Path | What |
|---|---|
| `lib/src/api/` | The contract: `PlaybackEngine`, `MediaSource`, value types (`freezed`). Frozen at the end of Phase B; changes need an ADR (docs/05 §12). |
| `lib/src/mpv/` | `MpvEngine`, `MpvClient` (own `dart:ffi` wrapper, ADR-004), option defaults, state mapping, DSP/loudness, subtitle conversion, `CrossfadingEngine`, `SoftwareRenderer`, `LoudnessScanner`, the `mhvf://` stream protocol. |
| `lib/src/bridge/` | `RenderBridge` (video surfaces) and `AudioBridge` (OS bit-perfect requests) — the only channel users (ADR-011). |
| `lib/src/disc/` | `DiscReader` (VIDEO_TS, BDMV, `.iso`), `UdfImage`. |
| `lib/src/cast/` | `decideCastPlan`, `CastTranscoder`, `CastServer`, WebVTT. |
| `lib/src/session/` | `PlaybackCheckpointer` (resume points every 5 s). |
| `src/shim/` + `hook/build.dart` | C shim for the stream protocol, compiled per platform by the Dart build hook. |
| `android/`, `ios/`, `macos/`, `windows/` | Render bridges and audio bridges; bundling of libmpv from `.deps-cache`. |
| `example/` | Test bed: runs the conformance suites and the render-bridge tests on Android, iOS, macOS, Windows. |
| `test/unit/` | Pure tests (no native libraries). |
| `test/conformance/` | Engine conformance suites against real libmpv, shared by desktop FFI runs and device runs. |
| `tool/` | `fetch_libmpv.py` (ADR-004 bootstrap), `stage_native.py`, `stage_corpus.py`. |

## Using the engine

```dart
final engine = MpvEngine(
  EngineRole.video,
  config: MpvEngineConfig(renderBridge: RenderBridge(), audioBridge: AudioBridge()),
);
await engine.open(UriSource(Uri.file('/media/film.mkv')));
engine.state.listen((s) => print('${s.status} ${s.position}'));
// Texture(textureId: engine.textureId!) shows the video.
```

- Any `VirtualFile` (SMB, NFS, WebDAV, archives, server downloads) plays and seeks: `engine.open(VirtualFileSource(file))`.
- Disc folders and `.iso` images open their main title; `DiscReader.read(dir)` / `DiscReader.readImage(file)` list titles, chapters and languages for title selection.
- Music: `CrossfadingEngine(() => MpvEngine(EngineRole.music))`, `setNext(...)` for gapless, `setTransition(...)` for crossfades.
- Faults never throw from playback calls: they surface as `PlaybackState.error` with an `EngineErrorCode` for user copy (docs/06 §8). Without libmpv the engine reports `libraryMissing`.

## Native libraries

Builds take libmpv from the pinned mediahro-deps archive in `.deps-cache/<target>` (deps.lock, `tools/deps/fetch.py`). Until lane B4 pins it, fetch the ADR-004 bootstrap:

```bash
python packages/mediahro_engine/tool/fetch_libmpv.py windows-x64
```

Apple builds also need `python packages/mediahro_engine/tool/stage_native.py ios|macos` to copy the xcframeworks into the plugin.

## Tests

```bash
cd packages/mediahro_engine && flutter test
```

FFI conformance tests need libmpv and the generated corpus (`dart run tools/corpus/generate.dart --ffmpeg <ffmpeg>`); they skip without them. The nightly harness is `dart run tools/corpus/run.dart --report build/corpus-report.json`.
