import 'package:flutter/foundation.dart';
import 'package:mediahro_engine/mediahro_engine.dart';

/// What the video player opens (docs/06 §3.1).
///
/// [memoryKey] identifies the item for resume, speed, bookmarks and track
/// memory (VID-062…065). Library items use `item:<id>`; server items
/// `server:<serverId>:<remoteId>`, so a file played from two servers keeps
/// two resume points (VID-064); anything else uses its URI.
@immutable
final class PlayRequest {
  const PlayRequest({
    required this.title,
    required this.memoryKey,
    this.source,
    this.resolve,
    this.subtitle,
    this.sourceBadge,
    this.itemId,
    this.seriesKey,
    this.next = const [],
    this.chapters = const [],
    this.onDelete,
  });

  /// A request for a URI, keyed by the URI.
  factory PlayRequest.uri(
    Uri uri, {
    String? title,
    Map<String, String> headers = const {},
    String? userAgent,
    List<PlayRequest> next = const [],
  }) => PlayRequest(
    source: UriSource(
      uri,
      headers: headers,
      userAgent: userAgent,
      title: title,
    ),
    title:
        title ??
        (uri.pathSegments.isEmpty
            ? uri.toString()
            : Uri.decodeComponent(uri.pathSegments.last)),
    memoryKey: uri.toString(),
    next: next,
  );

  /// The source, when known up front.
  final MediaSource? source;

  /// Opens the source on demand (network shares, SAF files); used when
  /// [source] is null.
  final Future<MediaSource> Function()? resolve;
  final String title;

  /// Episode or series line under the title.
  final String? subtitle;

  /// Short source label ("SMB", "Jellyfin").
  final String? sourceBadge;
  final String memoryKey;

  /// Library item id, when indexed (library progress and watched state).
  final int? itemId;

  /// Series for per-series track memory (VID-065).
  final String? seriesKey;

  /// "Play next in folder/series" (VID-064), in order.
  final List<PlayRequest> next;

  /// Chapters known from outside the stream (disc, CUE).
  final List<Chapter> chapters;

  /// Deletes the item for the "delete with confirmation" post-playback
  /// action; null where the source is read-only.
  final Future<void> Function()? onDelete;

  Future<MediaSource> mediaSource() async => source ?? await resolve!.call();

  /// This request followed by the remaining items.
  PlayRequest advance() {
    if (next.isEmpty) return this;
    final head = next.first;
    return PlayRequest(
      source: head.source,
      resolve: head.resolve,
      title: head.title,
      memoryKey: head.memoryKey,
      subtitle: head.subtitle,
      sourceBadge: head.sourceBadge,
      itemId: head.itemId,
      seriesKey: head.seriesKey,
      chapters: head.chapters,
      onDelete: head.onDelete,
      next: next.sublist(1),
    );
  }
}
