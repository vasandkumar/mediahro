import 'package:meta/meta.dart';

/// Server families supported at 1.0 (NET-010…017, POD-003).
enum ServerKind {
  jellyfin,
  emby,
  plex,
  subsonic,
  immich,
  nextcloud,
  photoprism,
  audiobookshelf,
  mediahro,
}

enum ServerItemKind {
  library,
  folder,
  movie,
  series,
  season,
  episode,
  video,
  album,
  artist,
  track,
  playlist,
  photo,
  photoAlbum,
  person,
  place,
  book,
  podcast,
  podcastEpisode,
}

/// Opaque per-server identifiers; credentials are referenced by
/// [secretRef] (a key into OS secure storage, PRIV-006), never stored here.
@immutable
final class ServerAccount {
  const ServerAccount({
    required this.id,
    required this.kind,
    required this.baseUri,
    required this.displayName,
    this.userId,
    this.secretRef,
    this.trustedCertSha256,
  });

  final String id;
  final ServerKind kind;
  final Uri baseUri;
  final String displayName;
  final String? userId;
  final String? secretRef;

  /// Pinned fingerprint for a self-signed certificate after explicit user
  /// confirmation (docs/05 §9).
  final String? trustedCertSha256;
}

@immutable
final class ServerItem {
  const ServerItem({
    required this.id,
    required this.kind,
    required this.title,
    this.parentId,
    this.sortTitle,
    this.overview,
    this.year,
    this.duration,
    this.artworkUri,
    this.indexNumber,
    this.parentIndexNumber,
    this.playedPosition,
    this.played = false,
    this.childCount,
    this.extra = const {},
  });

  final String id;
  final ServerItemKind kind;
  final String title;
  final String? parentId;
  final String? sortTitle;
  final String? overview;
  final int? year;
  final Duration? duration;
  final Uri? artworkUri;

  /// Episode / track number.
  final int? indexNumber;

  /// Season / disc number.
  final int? parentIndexNumber;
  final Duration? playedPosition;
  final bool played;
  final int? childCount;

  /// Server-specific fields mapped by the client (string values only; no `dynamic`).
  final Map<String, String> extra;
}

@immutable
final class ServerPage {
  const ServerPage({required this.items, required this.total, this.nextCursor});

  final List<ServerItem> items;
  final int total;
  final String? nextCursor;
}

/// How to play an item: direct play preferred, transcode as fallback (NET-010).
@immutable
final class StreamInfo {
  const StreamInfo({
    required this.uri,
    this.headers = const {},
    this.isTranscode = false,
    this.externalSubtitles = const [],
    this.introStart,
    this.introEnd,
    this.creditsStart,
  });

  final Uri uri;
  final Map<String, String> headers;
  final bool isTranscode;
  final List<Uri> externalSubtitles;

  /// Server-provided skip markers (VID-073).
  final Duration? introStart;
  final Duration? introEnd;
  final Duration? creditsStart;
}

enum ServerErrorCode {
  unreachable,
  unauthorized,
  notFound,
  rateLimited,
  certificateUntrusted,
  protocol,
  unsupported,
}

final class ServerException implements Exception {
  const ServerException(this.code, [this.detail]);

  final ServerErrorCode code;
  final String? detail;

  @override
  String toString() =>
      'ServerException(${code.name}${detail == null ? '' : ': $detail'})';
}

/// One item's per-user play state on a server (LIB-010).
@immutable
final class ServerUserData {
  const ServerUserData({
    required this.itemId,
    required this.played,
    this.position,
    this.playCount = 0,
    this.lastPlayed,
  });

  final String itemId;
  final bool played;

  /// Resume position; null when not started or finished.
  final Duration? position;
  final int playCount;
  final DateTime? lastPlayed;
}

/// Common contract over every media server client (docs/05 §9).
abstract interface class ServerLibrary {
  ServerAccount get account;

  /// Checks reachability and credentials; returns server name/version.
  Future<String> ping();

  /// Top-level libraries/views.
  Future<List<ServerItem>> libraries();

  Future<ServerPage> browse(String parentId, {String? cursor, int limit = 100});

  Future<ServerPage> search(
    String query, {
    Set<ServerItemKind>? kinds,
    int limit = 50,
  });

  /// Continue-watching / next-up style rows where the server provides them.
  Future<List<ServerItem>> resumeItems({int limit = 20});

  Future<StreamInfo> streamInfo(String itemId, {bool allowTranscode = true});

  /// Progress and watched sync (LIB-010); no-op if the server lacks support.
  Future<void> reportProgress(
    String itemId,
    Duration position, {
    bool finished = false,
  });

  Future<void> setPlayed(String itemId, {required bool played});

  /// Watched state and positions the server changed since [changedSince]
  /// (all when null), for the pull side of LIB-010 progress sync. Jellyfin /
  /// Emby: `Items` with `UserData` and `MinDateLastSaved`; Plex:
  /// `viewOffset` / `viewCount` / `lastViewedAt` from the library sections.
  /// Lane C4 implements it per server; an empty list where unsupported.
  Future<List<ServerUserData>> userData({
    DateTime? changedSince,
    int limit = 500,
  });

  /// Direct download URI for offline copies (NET-018).
  Future<Uri> downloadUri(String itemId);

  Future<void> close();
}

/// HTTP transport injected by the app so every request passes the network
/// allow-list and privacy toggles (PRIV-004). Clients never create their
/// own `HttpClient`.
abstract interface class HttpTransport {
  Future<HttpResponseData> send(HttpRequestData request);
}

@immutable
final class HttpRequestData {
  const HttpRequestData({
    required this.method,
    required this.uri,
    this.headers = const {},
    this.body,
  });

  final String method;
  final Uri uri;
  final Map<String, String> headers;
  final List<int>? body;
}

@immutable
final class HttpResponseData {
  const HttpResponseData({
    required this.statusCode,
    this.headers = const {},
    this.body = const [],
  });

  final int statusCode;
  final Map<String, String> headers;
  final List<int> body;
}
