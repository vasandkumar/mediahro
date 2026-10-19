# mediahro_engine

The Mediahro playback core and the public surface of the **Mediahro Engine SDK** (B2B-004): the `PlaybackEngine` contract (docs/05 §4.2), its libmpv implementation over `mpv_render_context`, and the per-platform render bridge that turns engine frames into a Flutter texture (docs/05 §4.3).

- `lib/src/api/` — the frozen contract (changes via ADR, docs/05 §12).
- `lib/src/mpv/` — `MpvEngine` (lane B1).
- `lib/src/bridge/` + `android/`, `ios/`, `macos/`, `windows/` — render bridge (platform module, ADR-011).
- `lib/testing.dart` — `FakePlaybackEngine` for feature-lane tests.

Licence: AGPL-3.0-or-later, or the commercial licence (`LICENSE-COMMERCIAL.md`).
