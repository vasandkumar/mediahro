# Lane C2 — Music, podcasts and audiobooks (milestone M4)

**Owns:** `app/lib/features/music/` (music, radio, podcasts, audiobooks; subfolders as you like), your pages in `docs/help/`.

**Read:** CLAUDE.md, docs/lanes/README.md, docs/04 §6.2, §6.3 and AUD-046, docs/05 §4 (audio path), §6 (data model), §12 (ADR-021, 023, 025), docs/06 §3 (Now Playing, library screens), docs/07 (car, widgets, alarm policy), docs/11 §5.

## Feature IDs (STATUS.md rows marked C2)

AUD-046, MUS-001…014, POD-001…003. MUS-015 is 1.1: leave it ☐ and don't build it.

## Deliverables

1. **Music library views** (MUS-001) over B2's index: artists, albums, genres, composers, folders and years, with sorting and grouping.
   - **Tag reading (MUS-002):** a Dart tag reader in an isolate covering ID3v2.2–2.4, Vorbis comments, MP4 atoms, APE and ASF, with limits and fuzz targets. Use the engine's metadata where it already has it.
   - **Tag editing (MUS-003):** write-back with a backup copy, never in place without a verified temp file.
2. **Art (MUS-004):** embedded art, folder art and opt-in online lookup through `NetworkGateway`.
3. **Lyrics (MUS-005):** LRC with sync, embedded and sidecar files, opt-in online lookup.
4. **Now Playing (MUS-006)** on B3's components, with the AUD-046 visualiser fed from engine PCM taps. If you need a tap, file an ADR request to B1.
5. **Queues (MUS-007)** and smart playlists (MUS-008), on B2's queue model and rule engine.
6. **Scrobbling (MUS-009):** ListenBrainz and Last.fm, opt-in with an offline queue. API keys are an owner task, so record them in STATUS §4.
7. **Fingerprinting (MUS-010):** chromaprint (B2's binding) plus AcoustID lookup, opt-in.
8. **Sleep timer and alarms (MUS-011)** over `AlarmFacade`.
9. **Widgets and quick controls (MUS-012)** over `HomeWidgetsFacade`.
10. **Car (MUS-013):** implement `MediaBrowseProvider` (queues, playlists, albums, artists, folders, podcasts, voice search) over `MediaBrowseFacade`.
11. **Internet radio (MUS-014):** user-added stations only, with M3U/PLS import and no directory, per doc 04. Station metadata comes from ADR-027.
12. **Podcasts and audiobooks:**
    - Audiobook and podcast mode (POD-001): chapters, per-book speed, skip silence through the engine, bookmarks.
    - Podcast feeds (POD-002): RSS/Atom parsed in an isolate, OPML import/export, background refresh within OS limits.
    - Audiobookshelf client (POD-003): its UI sits here, on C4d's `ServerLibrary` client.

## Cross-lane dependencies

- **B1:** engine behaviour (gapless, ReplayGain, EQ, DoP and output are already merged).
- **B2:** index, queue and rules.
- **C4a/b:** car, widgets, alarms and media session natively.
- **C4d:** the Audiobookshelf `ServerLibrary`.

Build against fakes and tick a cell when its platform's implementation lands and CI passes there.

## Exit (M4)

Every C2 ID ☑ on each listed platform. Gapless and crossfade are verified end to end on each platform. Library views meet the LIB-005 search budget with 50 k tracks (perf harness).
