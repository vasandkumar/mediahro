import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:mediahro/features/music/abs/abs_account.dart';
import 'package:mediahro/features/music/abs/abs_store.dart';
import 'package:mediahro/features/music/podcasts/podcast_http.dart';
import 'package:mediahro/features/music/podcasts/podcast_service.dart';
import 'package:mediahro_servers/mediahro_servers.dart';
import 'package:meta/meta.dart';

/// An item the listener can pick up where they left off.
@immutable
final class AbsEntry {
  const AbsEntry(this.account, this.item);

  final AbsAccount account;
  final ServerItem item;
}

/// Browsing, offline copies and artwork for Audiobookshelf (POD-003) on the
/// `ServerLibrary` of each connected server. Everything reaches the network
/// through that client (`HttpTransport`) or the gateway; nothing here
/// carries a credential.
final class AbsService {
  AbsService({
    required this.store,
    required this.downloads,
    this.http,
    this.artDir,
  });

  final AbsStore store;
  final EpisodeDownloads downloads;

  /// For artwork (the gateway, one allowed hop at a time).
  final PodcastHttp? http;

  /// Where covers are kept.
  final Directory? artDir;

  /// The libraries of [a] (audiobooks, podcasts).
  Future<List<ServerItem>> libraries(AbsAccount a) async => [
    for (final l in await a.library.libraries())
      if (l.kind == ServerItemKind.library ||
          l.kind == ServerItemKind.folder ||
          l.kind == ServerItemKind.book ||
          l.kind == ServerItemKind.podcast)
        l,
  ];

  Future<ServerPage> browse(
    AbsAccount a,
    String parentId, {
    String? cursor,
    int limit = 60,
  }) => a.library.browse(parentId, cursor: cursor, limit: limit);

  Future<ServerPage> search(AbsAccount a, String query) => a.library.search(
    query,
    kinds: const {
      ServerItemKind.book,
      ServerItemKind.podcast,
      ServerItemKind.podcastEpisode,
    },
  );

  /// "Continue listening" across every connected server, a server whose
  /// answer fails leaving out only its own items.
  Future<List<AbsEntry>> continueListening(List<AbsAccount> accounts) async {
    final out = <AbsEntry>[];
    for (final a in accounts) {
      try {
        for (final i in await a.library.resumeItems(limit: 10)) {
          if (i.playable) out.add(AbsEntry(a, i));
        }
      } on ServerException {
        // That server is unreachable or signed out; the rest still show.
      }
    }
    return out;
  }

  /// Marks the item finished or not started again, on the server.
  Future<void> setPlayed(
    AbsAccount a,
    ServerItem item, {
    required bool played,
  }) => a.library.setPlayed(item.id, played: played);

  // ------------------------------------------------------------ downloads --

  /// Keeps an offline copy of [item]. The address the server gives is kept,
  /// because later requests for it may differ.
  Future<void> download(AbsAccount a, ServerItem item) async {
    final uri = await a.library.downloadUri(item.id);
    final s = await store.item(a.id, item.id);
    await store.save(a.id, item.id, s.copyWith(downloadUri: uri.toString()));
    await downloads.enqueue(uri, title: item.title);
  }

  Future<EpisodeDownload?> downloadStatus(AbsAccount a, ServerItem item) async {
    final uri = (await store.item(a.id, item.id)).downloadUri;
    if (uri == null) return null;
    return await downloads.status(Uri.parse(uri));
  }

  Future<File?> localFile(AbsAccount a, ServerItem item) async {
    final d = await downloadStatus(a, item);
    return d != null && d.done ? d.file : null;
  }

  Future<void> removeDownload(AbsAccount a, ServerItem item) async {
    final s = await store.item(a.id, item.id);
    final uri = s.downloadUri;
    if (uri == null) return;
    await downloads.remove(Uri.parse(uri));
    await store.save(a.id, item.id, s.copyWith(clearDownload: true));
  }

  // -------------------------------------------------------------- artwork --

  /// The cover of [item] on this device (fetched once through the gateway),
  /// or null.
  Future<String?> artPath(ServerItem item) async {
    final dir = artDir;
    final uri = item.artworkUri;
    final h = http;
    if (dir == null || uri == null || h == null) return null;
    final name = sha1.convert(uri.toString().codeUnits).toString();
    for (final ext in const ['jpg', 'png', 'webp']) {
      final f = File('${dir.path}${Platform.pathSeparator}$name.$ext');
      if (f.existsSync()) return f.path;
    }
    try {
      final res = await h.fetch(uri);
      if (res.status != 200 || res.body.isEmpty) return null;
      final type = res.headers['content-type']?.toLowerCase() ?? '';
      final ext = type.contains('png')
          ? 'png'
          : type.contains('webp')
          ? 'webp'
          : 'jpg';
      await dir.create(recursive: true);
      final f = File('${dir.path}${Platform.pathSeparator}$name.$ext');
      final tmp = File('${f.path}.tmp');
      await tmp.writeAsBytes(res.body, flush: true);
      await tmp.rename(f.path);
      return f.path;
    } on Object {
      return null;
    }
  }
}
