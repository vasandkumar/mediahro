# Lane B2 — Library and sources (milestone M2)

**Owns:** `app/lib/core/` (index, scanner, models, rules, queue, sync engines' shared parts, `net/`), `app/lib/features/library/`, `app/lib/features/sources/`, `packages/mediahro_ffi/lib/src/vfs/` and the smb2 / nfs / curl / archive / ebur128 / chromaprint / uchardet parts of `packages/mediahro_ffi` (`lib/src/<lib>/`, `ffigen/<lib>.yaml`).

**Read:** docs/05 §5–7, §9, §12 (ADR-006, 012, 014); docs/04 §2 (LIB), §3 (FILE), §8 NET-001…007, 018, 019; CORE-005, CORE-014; docs/06 §2, §3.4, §8, §9; docs/07 §3.1 (storage policy); docs/11 §1, §2 (network docker compose), §5.

## Feature IDs (STATUS.md rows marked B2)

LIB-001…015, FILE-001…006, NET-001…007, NET-018, NET-019, CORE-005, CORE-014.

## Deliverables

1. **Index** (drift + SQLite FTS5, WAL, versioned migrations, one DB per profile) with every table in docs/05 §6; stable item keys (`source_id + relative_path + size + mtime`, xxh3 first/last 1 MB for move detection).
2. **Scanner**: isolate pool (cores/2), viewport-priority queues, pausable, per-source schedule (manual / on open / watch), 10 k files ≤ 30 s phone / ≤ 10 s desktop, incremental ≤ 2 s (perf harness test).
3. **Search** ≤ 50 ms / 30 ms with filters (LIB-005); smart-rule engine shared by smart playlists (LIB-007, MUS-008) and smart albums; queue model (LIB-008); tags/labels; duplicate finder (hash, pHash, chromaprint, duration+size) that never deletes; statistics; parental PIN gate (through `BiometricsFacade`); TMDB/TVDB scraping with the filename parser (LIB-011) through `NetworkGateway`.
4. **Sources**: `VirtualFileSystem` implementations — SMB2/3 (libsmb2, discovery, keychain credentials via `SecureStorageFacade`), NFS v3/v4, WebDAV, FTP/FTPS/SFTP (libcurl/libssh2), DLNA browse (SSDP + ContentDirectory), HTTP(S)/HLS/DASH/RTSP/RTMP URL sources with headers; cloud drives (Google Drive, OneDrive, Dropbox, Box, pCloud, MEGA, Yandex, Proton Drive where an API exists) via OAuth + REST through `NetworkGateway` (client IDs are an owner task — record in STATUS.md §4); offline downloads (NET-018); connection health (NET-019). Use ffigen against headers from the upstream source tarballs pinned in `mediahro-deps/versions.json` until B4's archives exist.
5. **Archives** (FILE-004) via libarchive VFS; **file browser and operations** (FILE-001…003, 006) incl. trash with undo through `StorageFacade`; **Wi-Fi transfer** page (FILE-005, `shelf`, random per-session token, off by default); **URL open** with history of 50 (CORE-005); **backup/restore** to one encrypted file (CORE-014).
6. **`NetworkPolicy` implementation** for `NetworkGateway` lives here (`app/lib/core/net`); B3's privacy dashboard reads it. Parsers (playlists M3U/PLS/XSPF/CUE, NFO, metadata) run in isolates with limits (PRIV-005) and get Dart fuzz targets under `tools/fuzz/targets/`.
7. UI for sources, library views, search and file browser in your feature folders, using B3's design components as they land (start with Material widgets + tokens; swap when components merge).

## Cross-lane dependencies

Native storage (SAF trees, MediaStore, PhotoKit, bookmarks, Recycle Bin) is C4's `StorageFacade` implementation in Phase C. Build and test everything against the facade with fakes now; on desktop, `dart:io` paths already work. A B2 cell is ticked only when the platform passes end-to-end, so mobile storage-dependent cells stay ☐ until C4 lands (not ⛔ — this is sequencing).

## Exit (M2, docs/10 §3)

LIB-*, FILE-*, NET-001…007, NET-018/019 AC met (per-platform ticks as above); 10 k-file scan ≤ 30 s; docker-compose network test environment (docs/11 §2) running in CI for SMB/NFS/WebDAV/FTP/SFTP/DLNA.
