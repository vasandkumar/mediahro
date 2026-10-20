# features/photos

Owner lane: C3 Photos (IMG-*, PRIV-007). Strings: `l10n/photos_<locale>.arb` (keys prefixed `photos`).

| Folder | What |
|---|---|
| `timeline/` | The photo timeline (IMG-003): geometry (`timeline_model.dart`), thumbnail scheduling (`thumbnail_controller.dart`), widgets |
| `viewer/` | Full-screen viewer (IMG-004): zoom maths, tile pyramid planning, the zoomable surface, pages, filmstrip |
| `info/` | Details sheet and metadata editing (IMG-006) |
| `image_prober.dart` | Reads image facts for the index (plug into the probe queue for `ItemKind.image`) |
| `photo_open.dart` | `openImageItem` for the orchestrator's `openItemActionProvider` dispatcher |
| `photos_providers.dart` | Riverpod wiring: worker pool, thumbnail cache, pipeline, entries |

The engine itself is in `app/lib/images/` (pipeline, metadata codecs, worker pool, thumbnail cache) and
`packages/mediahro_ffi/lib/src/vips/` (libvips wrapper).

Index conventions (no schema change): a Motion Photo is a still with `video_codec = 'mp4'`; a gain-map still has
`hdr_type = 'gainmap'`; a Live Photo has `image_meta.paired_video_path`.
