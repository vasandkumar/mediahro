# Changelog

All notable changes are grouped by feature area and reference feature IDs from `docs/04`.

## [Unreleased]

### Added
- M0 bootstrap: repository layout, flavours, design tokens, localisation pipeline, interface stubs, CI matrix, `STATUS.md`.
- Library index (LIB-001): SQLite schema per docs/05 §6 with FTS5, one database per profile, scanner isolate pool with move detection, viewport-priority probe queue.
- Local scanning (LIB-002, LIB-003): manual, on-open and watch schedules; pause, resume and cancel; fast Windows directory enumeration.
- Search (LIB-005) with type, source, resolution, codec, HDR, duration, date, rating and unplayed filters.
- Folder and library views (LIB-004), home rows (LIB-006), collections (LIB-012) and statistics (LIB-015).
- Playlists (LIB-007): manual and smart (rule builder), import and export of M3U, M3U8, PLS, XSPF and CUE.
- Named audio queues and a video queue (LIB-008); tags and colour labels (LIB-009); progress with a sync seam (LIB-010).
- Video metadata from TMDB and TVDB by filename, NFO files and an offline artwork cache (LIB-011).
- Parental PIN, biometrics, locked sources and folders, hidden items (LIB-013); duplicate finder that never deletes (LIB-014).
- File browser, operations with trash and undo, batch rename and convert, sidecars kept together (FILE-001, FILE-002, FILE-003, FILE-006).
- Archive browsing through libarchive (FILE-004); Wi-Fi transfer page with a QR code (FILE-005).
- Network sources: SMB, NFS, WebDAV, FTP, FTPS, SFTP and DLNA, with LAN discovery and an opt-in renderer (NET-001 to NET-005).
- Open URL with headers, user agent and history (CORE-005, NET-006); cloud drives over OAuth PKCE and REST (NET-007).
- FTP and FTPS on iOS and macOS through a built-in client, and a prompt to trust a server's self-signed certificate or SSH host key after comparing its fingerprint (NET-003, NET-004).
- Offline downloads (NET-018), connection health (NET-019) and an encrypted backup and restore (CORE-014).
