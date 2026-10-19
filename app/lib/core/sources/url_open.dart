import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:mediahro/core/db/library_database.dart';
import 'package:meta/meta.dart';

/// Kinds of URL the open dialog accepts (CORE-005, NET-006).
enum UrlKind {
  /// Played by the engine directly (http(s), HLS, DASH, RTSP, RTMP).
  stream,

  /// Opened through a VirtualFileSystem (smb, nfs, ftp, sftp, WebDAV).
  share,
}

/// A validated URL ready to open.
@immutable
final class OpenableUrl {
  const OpenableUrl(
    this.uri,
    this.kind, {
    this.headers = const {},
    this.userAgent,
    this.isLive = false,
  });

  final Uri uri;
  final UrlKind kind;

  /// Custom request headers (NET-006).
  final Map<String, String> headers;
  final String? userAgent;

  /// RTSP/RTMP and HLS without an end are treated as live streams.
  final bool isLive;
}

final class UrlRejected implements Exception {
  const UrlRejected(this.reason);

  final UrlRejectReason reason;

  @override
  String toString() => 'UrlRejected($reason)';
}

enum UrlRejectReason {
  empty,
  malformed,
  unsupportedScheme,
  missingHost,
  badHeader,
}

const _streamSchemes = {
  'http', 'https', 'rtsp', 'rtsps', 'rtmp', 'rtmps', 'rtmpt', 'rtmpe', //
  'mms', 'mmsh', 'srt', 'udp', 'rtp',
};
const _shareSchemes = {
  'smb',
  'nfs',
  'ftp',
  'ftps',
  'ftpes',
  'sftp',
  'dav',
  'davs',
  'webdav',
  'webdavs',
};

/// Parses what the user typed or pasted: trims, accepts bare hosts
/// (`example.org/live.m3u8` → https), `\\server\share\path` UNC paths
/// (→ smb), and validates custom headers. No bundled lists (NET-006).
OpenableUrl parseUserUrl(
  String input, {
  Map<String, String> headers = const {},
  String? userAgent,
}) {
  var s = input.trim();
  if (s.isEmpty) throw const UrlRejected(UrlRejectReason.empty);
  if (s.startsWith(r'\\')) {
    s = 'smb:${s.replaceAll(r'\', '/')}';
  } else if (!RegExp('^[a-zA-Z][a-zA-Z0-9+.-]*://').hasMatch(s)) {
    s = 'https://$s';
  }
  final uri = Uri.tryParse(s);
  if (uri == null) throw const UrlRejected(UrlRejectReason.malformed);
  final scheme = uri.scheme.toLowerCase();
  if (!_streamSchemes.contains(scheme) && !_shareSchemes.contains(scheme)) {
    throw const UrlRejected(UrlRejectReason.unsupportedScheme);
  }
  if (uri.host.isEmpty && scheme != 'udp' && scheme != 'rtp') {
    throw const UrlRejected(UrlRejectReason.missingHost);
  }
  for (final e in headers.entries) {
    // RFC 7230 token names; no CR/LF injection in values.
    if (!RegExp(r"^[!#$%&'*+.^_`|~0-9A-Za-z-]+$").hasMatch(e.key) ||
        e.value.contains('\r') ||
        e.value.contains('\n')) {
      throw const UrlRejected(UrlRejectReason.badHeader);
    }
  }
  final path = uri.path.toLowerCase();
  return OpenableUrl(
    uri.replace(scheme: scheme),
    _shareSchemes.contains(scheme) ? UrlKind.share : UrlKind.stream,
    headers: Map.unmodifiable(headers),
    userAgent: userAgent?.trim().isEmpty ?? true ? null : userAgent!.trim(),
    isLive:
        scheme.startsWith('rtsp') ||
        scheme.startsWith('rtmp') ||
        scheme == 'udp' ||
        scheme == 'rtp' ||
        scheme == 'srt' ||
        path.endsWith('/live') ||
        path.contains('/live/'),
  );
}

/// Recently opened URLs, newest first, capped at [maxEntries] (CORE-005).
/// Credentials in URLs (`user:pass@`) are stripped before storing.
final class UrlHistoryRepository {
  UrlHistoryRepository(
    this.db, {
    DateTime Function()? clock,
    this.maxEntries = 50,
  }) : _clock = clock ?? DateTime.now;

  final LibraryDatabase db;
  final DateTime Function() _clock;
  final int maxEntries;

  Future<void> record(OpenableUrl url) => db.transaction(() async {
    final clean = url.uri.replace(userInfo: '').toString();
    await db
        .into(db.urlHistory)
        .insert(
          UrlHistoryCompanion.insert(
            url: clean,
            headers: Value(jsonEncode(url.headers)),
            userAgent: Value(url.userAgent),
            openedAt: _clock(),
          ),
          onConflict: DoUpdate(
            (_) => UrlHistoryCompanion(
              headers: Value(jsonEncode(url.headers)),
              userAgent: Value(url.userAgent),
              openedAt: Value(_clock()),
            ),
            target: [db.urlHistory.url],
          ),
        );
    await db.customStatement(
      'DELETE FROM url_history WHERE id NOT IN '
      '(SELECT id FROM url_history ORDER BY opened_at DESC, id DESC LIMIT ?)',
      [maxEntries],
    );
  });

  Future<List<UrlHistoryRow>> recent() =>
      (db.select(db.urlHistory)..orderBy([
            (u) => OrderingTerm.desc(u.openedAt),
            (u) => OrderingTerm.desc(u.id),
          ]))
          .get();

  Stream<List<UrlHistoryRow>> watch() => (db.select(
    db.urlHistory,
  )..orderBy([(u) => OrderingTerm.desc(u.openedAt)])).watch();

  Future<void> remove(int id) =>
      (db.delete(db.urlHistory)..where((u) => u.id.equals(id))).go();

  Future<void> clear() => db.delete(db.urlHistory).go();

  /// Re-opens a history entry with its headers.
  static OpenableUrl toOpenable(UrlHistoryRow row) {
    final h = jsonDecode(row.headers);
    return parseUserUrl(
      row.url,
      headers: h is Map<String, Object?>
          ? {for (final e in h.entries) e.key: '${e.value}'}
          : const {},
      userAgent: row.userAgent,
    );
  }
}
