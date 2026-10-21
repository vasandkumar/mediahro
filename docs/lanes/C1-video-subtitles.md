# Lane C1 — Video and subtitles (milestone M3)

**Owns:** `app/lib/features/video/`, `packages/mediahro_subtitles/`, the `tesseract` part of `packages/mediahro_ffi` (`lib/src/tesseract/`, `ffigen/tesseract.yaml`), your pages in `docs/help/`.

**Read:** CLAUDE.md, docs/lanes/README.md, docs/04 §4 (VID) and §5 (SUB), docs/05 §4, §7, §12 (ADR-021, 022, 025), docs/06 §3 (player screens), §6 (gestures and shortcuts), §7 (captions honour system styles), docs/11 §1, §2, §5 (seek, first-frame and subtitle budgets).

## Feature IDs (STATUS.md rows marked C1 and B1 → C1)

VID-036…042, VID-060…074, SUB-010…016 (UI and editor side; the engine side is B1's and already merged), SUB-020, SUB-030, SUB-040, SUB-050…053. VID-031's Dart half: the HDR platform-view switch from ADR-022.

## Deliverables

1. **Player screen** on B3's `KPlayerChrome` and `KSeekBar`, adapted to each platform family:
   - the full gesture set (VID-060) and the shortcut map from docs/06 §6
   - a seek bar with thumbnails and chapters
   - speed presets that persist per item
   - frame step, A-B loop, bookmarks, resume and post-playback (VID-061…064)
   - track switching, audio delay and volume boost (VID-065, 066)
   - sleep timer, info overlay, skip intro/credits, remote control (VID-069, 072…074)
2. **Platform behaviour through facades only:**
   - PiP: `PipFacade` (VID-067)
   - background and audio-only: `MediaSessionFacade` (VID-068)
   - orientation and brightness: `DisplayFacade` (VID-070)
   - second screen (VID-071)
   - auto frame-rate matching: `DisplayFacade.matchFrameRate` (VID-036)
   - HDR: switch to the native view when `VideoStats.hdrOutput` and the display report HDR (ADR-022). C4a/b/c implement the native view.
3. **Rendering features** over the frozen engine API: scaling and filter presets, user shaders, interpolation, ICC, 3D/360° (VID-037…041), and screenshot/GIF/WebP/clip export through `PlaybackEngine.export` (VID-042). If a property you need isn't on the API, file an ADR request; B1 implements it.
4. **`mediahro_subtitles`:**
   - parsing and the model for the editor (SUB-030: timing shift and stretch, split/merge, spell check through the OS, save as SRT/ASS/VTT)
   - online download (SUB-020): Podnapisi only through `NetworkGateway`, opt-in (ADR-048 removed OpenSubtitles and Subdl, which need a publisher API key; raise any provider that needs a key with the owner first).
   - TTS over `SpeechSynthesisFacade` (SUB-040)
   - audio-based auto-sync (SUB-050): VAD + cross-correlation in an isolate, ≤ 2× real time on phone, preview before save
   - OCR of PGS/VobSub (SUB-051): `TextRecognitionFacade`, or Tesseract via FFI when it reports unsupported (ADR-025 §5)
   - auto-captions (SUB-052): whisper.cpp from mediahro-deps. The model downloads on demand after consent and uses ggml's runtime CPU dispatch.
   - translation (SUB-053): `TranslationFacade`, never online without consent
5. Every parser runs in an isolate with limits (PRIV-005), with Dart fuzz targets under `tools/fuzz/targets/`.

## Cross-lane dependencies

- **B1:** engine behaviour (ADR requests to the orchestrator).
- **C4a/b/c:** platform halves of PiP, HDR view, display, media session, TTS, OCR and translation. Build against fakes and tick a cell when the platform's implementation lands and CI passes there.
- **B4a:** Tesseract and Leptonica in mediahro-deps. Until then, skip the Tesseract tests with the blocker named.

## Exit (M3)

Every C1 ID ☑ on each platform listed in doc 04. Seek and first-frame budgets hold (docs/11 §5). Subtitle corpus green. Accessibility (captions follow system styles, 200 % text, focus order) verified in widget tests and goldens.
