# Lane C3 — Photos and gallery (milestone M5)

**Owns:**
- `app/lib/features/photos/` and `app/lib/images/`. The `ImagePipeline` interface in `image_pipeline.dart` is frozen; you implement it.
- The image parts of `packages/mediahro_ffi`: `lib/src/{vips,raw,jxl,avif,heif}/` and their `ffigen/*.yaml`.
- Your pages in `docs/help/`.

**Read:** CLAUDE.md, docs/lanes/README.md, docs/04 §7 (IMG) and PRIV-007, docs/05 §5 (image pipeline), §6, §7, §12 (ADR-008 vault, 022, 025), docs/06 §3 (gallery, viewer, editor), docs/09 (no Exiv2), docs/11 §2 (image corpus), §5 (gallery scroll and decode budgets).

## Feature IDs (STATUS.md rows marked C3)

IMG-001…017, PRIV-007, and IMG-018 on M and W. IMG-018 on Android is 1.1, so leave it ☐ there.

## Deliverables

1. **`ImagePipeline` implementation:**
   - **Decoders:** libvips (JPEG via libjpeg-turbo, PNG via spng, WebP, TIFF, GIF, AVIF via libavif + dav1d, EXR, PSD flattened) and libjxl through its own binding (libvips in mediahro-deps has no JXL loader).
   - **RAW:** LibRaw through `NativeLibrary.raw` (`libraw.so`/`.dylib`/`.dll`), loaded directly because libvips has no RAW loader.
   - **Platform decoders** for HEIC/HEIF through `PhotoLibraryFacade`/OS codecs.
   - **The rest of IMG-001:** Live Photos and Motion Photos.
   - **Thumbnails:** viewport-priority queues in isolates, an on-disk cache with LRU, and budgets from docs/11 §5.
2. **HDR images (IMG-002):** gain-map JPEG/HEIC/AVIF (ISO 21496) and HDR JXL/AVIF. Tone-map otherwise; on HDR displays use the native view per ADR-022, implemented by the C4 platform sub-lanes.
3. **Gallery and viewer (IMG-003, 004):** 60/120 fps scroll, zoom and pan, and a filmstrip.
   - Organisation (IMG-005).
   - **Metadata (IMG-006):** an own EXIF/IPTC/XMP reader and writer in Dart. No Exiv2; XMP sidecars for RAW; strip on share.
   - **Map (IMG-007):** OSM tiles opt-in through `NetworkGateway`, and an offline gazetteer bundled as an asset with its licence recorded.
   - Compare (IMG-008).
4. **Editing (IMG-009):** non-destructive with a history.
   - Batch (IMG-010), slideshow (IMG-012), duplicates (IMG-013, pHash, shared with B2's duplicate finder), trash (IMG-014), sharing and output (IMG-015), sources (IMG-016, B2's VFS), archives (IMG-017, B2's libarchive VFS), screensaver/ambient (IMG-018, M W).
5. **Vault (IMG-011, PRIV-007):** ADR-008, i.e. AES-256-GCM chunks with the key wrapped by `SecureStorageFacade.wrapKey`. Biometric unlock, no plaintext on disk, and an excluded-from-backup location.

## Cross-lane dependencies

- **B4a:** the image libraries are in mediahro-deps. If a codec is missing on a platform, request it from B4a and skip its tests with the blocker named.
- **C4a/b/c:** the photo library, OS codecs and HDR views natively.
- **B2:** sources and archives.

## Exit (M5)

Every C3 ID ☑ on each listed platform. Gallery budgets hold with 100 k images (perf harness). The image corpus decodes to reference hashes on every platform.
