import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:mediahro/core/db/library_database.dart' show DownloadState;
import 'package:mediahro/core/net/network_policy.dart' show NetworkBlocked;
import 'package:mediahro/features/music/podcasts/feed_parser.dart';
import 'package:mediahro/features/music/podcasts/opml.dart';
import 'package:mediahro/features/music/podcasts/podcast_http.dart';
import 'package:mediahro/features/music/podcasts/podcast_store.dart';
import 'package:meta/meta.dart';

enum PodcastFailure {
  invalidUrl,
  unreachable,
  notAFeed,
  tooLarge,
  blocked,
  alreadySubscribed,
}

final class PodcastException implements Exception {
  const PodcastException(this.reason, {this.showId});

  final PodcastFailure reason;

  /// For [PodcastFailure.alreadySubscribed]: the existing show.
  final String? showId;

  @override
  String toString() => 'PodcastException($reason)';
}

/// What a refresh of one show found.
@immutable
final class RefreshResult {
  const RefreshResult(this.showId, {this.added = 0, this.failure});

  final String showId;

  /// Episodes that were not in the list before.
  final int added;
  final PodcastFailure? failure;

  bool get ok => failure == null;
}

@immutable
final class OpmlImportResult {
  const OpmlImportResult({
    required this.added,
    required this.alreadySubscribed,
    required this.failed,
  });

  final int added;
  final int alreadySubscribed;

  /// Addresses that could not be subscribed to.
  final List<String> failed;
}

/// Where an episode's offline copy stands.
@immutable
final class EpisodeDownload {
  const EpisodeDownload(this.state, {this.received = 0, this.total, this.file});

  final DownloadState state;
  final int received;
  final int? total;

  /// The finished file.
  final File? file;

  bool get done => state == DownloadState.done && file != null;
  double? get fraction =>
      total == null || total == 0 ? null : received / total!;
}

/// Offline copies of episodes: the app's download manager (NET-018) behind
/// a seam, so the service does not depend on the database or the network.
abstract interface class EpisodeDownloads {
  Future<void> enqueue(Uri url, {required String title, int? size});
  Future<EpisodeDownload?> status(Uri url);
  Future<void> remove(Uri url);
}

/// One row of a show's episode list.
@immutable
final class EpisodeEntry {
  const EpisodeEntry(this.episode, this.progress, this.download);

  final ParsedEpisode episode;
  final EpisodeProgress progress;
  final EpisodeDownload? download;

  bool get played => progress.played;
}

/// Podcast subscriptions (POD-002): subscribe by feed address, refresh with
/// conditional requests, OPML in and out, mark played, offline copies. No
/// directory and no recommendations; the only addresses used are the ones
/// the listener gave and what those feeds list.
final class PodcastService {
  PodcastService({
    required this.store,
    required this.http,
    required this.downloads,
    this.artDir,
    this.parse = parseFeedIsolated,
    this.canDownloadNow,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final PodcastStore store;
  final PodcastHttp http;
  final EpisodeDownloads downloads;

  /// Where show artwork is kept; null keeps none.
  final Directory? artDir;
  final Future<ParsedFeed> Function(Uint8List bytes, {Uri? base}) parse;

  /// False on a metered connection (automatic downloads wait for Wi-Fi).
  final Future<bool> Function()? canDownloadNow;
  final DateTime Function() _clock;

  final _changes = StreamController<void>.broadcast();

  /// Fires when subscriptions, episodes or played marks change.
  Stream<void> get changes => _changes.stream;

  /// The feed address for what the listener typed: `https://` is assumed,
  /// and the podcast-app schemes (`feed:`, `itpc:`, `pcast:`) mean http(s).
  static Uri? normalize(String input) {
    var t = input.trim();
    if (t.isEmpty || t.contains(RegExp(r'\s'))) return null;
    final lower = t.toLowerCase();
    for (final s in const ['feed:', 'itpc:', 'pcast:', 'podcast:']) {
      if (lower.startsWith(s)) {
        t = t.substring(s.length);
        if (t.startsWith('//')) {
          t = t.startsWith('//http') ? t.substring(2) : 'https:$t';
        }
        break;
      }
    }
    if (!t.contains('://')) t = 'https://$t';
    final u = Uri.tryParse(t);
    if (u == null ||
        (u.scheme != 'http' && u.scheme != 'https') ||
        u.host.isEmpty ||
        !u.host.contains('.') &&
            u.host != 'localhost' &&
            !u.host.contains(':')) {
      return null;
    }
    return u;
  }

  Future<List<PodcastShow>> shows() => store.shows();

  /// Subscribes to the feed at [input]. Throws [PodcastException].
  Future<PodcastShow> subscribe(String input) async {
    final uri = normalize(input);
    if (uri == null) throw const PodcastException(PodcastFailure.invalidUrl);
    final id = PodcastStore.idOf(uri.toString());
    if (await store.show(id) != null) {
      throw PodcastException(PodcastFailure.alreadySubscribed, showId: id);
    }
    final res = await _get(uri);
    if (res.status != 200) {
      throw const PodcastException(PodcastFailure.unreachable);
    }
    final feed = await _parse(res.body, res.uri);
    final show = PodcastShow(
      id: id,
      url: uri.toString(),
      title: feed.title.isEmpty ? uri.host : feed.title,
      subscribedAt: _clock().toUtc(),
      author: feed.author,
      description: feed.description,
      link: feed.link,
      imageUrl: feed.imageUrl,
      lastFetched: _clock().toUtc(),
      etag: res.headers['etag'],
      lastModified: res.headers['last-modified'],
      episodes: _kept(feed.episodes, const {}),
    );
    final withArt = show.copyWith(artPath: await _cacheArt(show));
    await store.save(withArt);
    _changes.add(null);
    return withArt;
  }

  /// Checks the feed again. A feed that has not changed since the last
  /// check costs one small request (ETag / If-Modified-Since).
  Future<RefreshResult> refresh(String showId) async {
    final show = await store.show(showId);
    if (show == null) return RefreshResult(showId);
    try {
      final res = await _get(
        Uri.parse(show.url),
        headers: {
          if (show.etag != null) 'if-none-match': show.etag!,
          if (show.lastModified != null)
            'if-modified-since': show.lastModified!,
        },
      );
      if (res.status == 304) {
        // The listener may have unsubscribed while the request was out.
        final now = await store.show(showId);
        if (now == null) return RefreshResult(showId);
        await store.save(now.copyWith(lastFetched: _clock().toUtc()));
        return RefreshResult(showId);
      }
      if (res.status != 200) {
        return RefreshResult(showId, failure: PodcastFailure.unreachable);
      }
      final feed = await _parse(res.body, res.uri);
      final image = feed.imageUrl ?? show.imageUrl;
      final art = image != show.imageUrl || show.artPath == null
          ? await _cacheArt(show, image)
          : null;
      // Everything above took time, and the listener may have unsubscribed
      // or changed the show's settings meanwhile: merge into the show as it
      // is now, and drop the result when it is gone.
      final current = await store.show(showId);
      if (current == null) {
        await _dropArt(art);
        return RefreshResult(showId);
      }
      final before = {for (final e in current.episodes) e.guid};
      final progress = await store.progress(showId);
      final updated = current.copyWith(
        title: feed.title.isEmpty ? current.title : feed.title,
        author: feed.author ?? current.author,
        description: feed.description ?? current.description,
        link: feed.link ?? current.link,
        imageUrl: feed.imageUrl ?? current.imageUrl,
        artPath: art ?? current.artPath,
        lastFetched: _clock().toUtc(),
        etag: res.headers['etag'],
        lastModified: res.headers['last-modified'],
        episodes: _kept(feed.episodes, {
          ...progress.keys,
          ...await _downloadedGuids(current.episodes),
        }, previous: current.episodes),
      );
      await store.save(updated);
      final added = [
        for (final e in feed.episodes)
          if (!before.contains(e.guid)) e,
      ];
      await _autoDownload(updated, progress, newest: added);
      _changes.add(null);
      return RefreshResult(showId, added: added.length);
    } on PodcastException catch (e) {
      return RefreshResult(showId, failure: e.reason);
    }
  }

  /// Refreshes every show checked longer than [minAge] ago, a few at a time.
  Future<List<RefreshResult>> refreshAll({
    Duration minAge = Duration.zero,
    int concurrency = 3,
  }) async {
    final now = _clock();
    final due = [
      for (final s in await store.shows())
        if (s.lastFetched == null || now.difference(s.lastFetched!) >= minAge)
          s.id,
    ];
    final out = <RefreshResult>[];
    for (var i = 0; i < due.length; i += concurrency) {
      out.addAll(
        await Future.wait([
          for (final id in due.skip(i).take(concurrency)) refresh(id),
        ]),
      );
    }
    return out;
  }

  Future<void> unsubscribe(String showId) async {
    final show = await store.show(showId);
    if (show == null) return;
    for (final e in show.episodes) {
      await downloads.remove(Uri.parse(e.url));
    }
    final art = show.artPath;
    if (art != null) {
      final f = File(art);
      if (f.existsSync()) await f.delete();
    }
    await store.remove(showId);
    _changes.add(null);
  }

  /// Per-show choices: order, automatic downloads, deleting what is played.
  Future<void> configure(
    String showId, {
    bool? oldestFirst,
    int? autoDownload,
    bool? deleteWhenPlayed,
    double? speed,
    bool? skipSilence,
  }) async {
    final show = await store.show(showId);
    if (show == null) return;
    await store.save(
      show.copyWith(
        oldestFirst: oldestFirst,
        autoDownload: autoDownload,
        deleteWhenPlayed: deleteWhenPlayed,
        speed: speed,
        skipSilence: skipSilence,
      ),
    );
    _changes.add(null);
  }

  /// The episodes of a show in its order, with where the listener is and
  /// what is downloaded.
  Future<List<EpisodeEntry>> episodes(String showId) async {
    final show = await store.show(showId);
    if (show == null) return const [];
    final progress = await store.progress(showId);
    final list = show.oldestFirst ? show.episodes.reversed : show.episodes;
    return [
      for (final e in list)
        EpisodeEntry(
          e,
          progress[e.guid] ?? const EpisodeProgress(),
          await downloads.status(Uri.parse(e.url)),
        ),
    ];
  }

  /// Number of episodes not played yet, by show.
  Future<Map<String, int>> unplayedCounts() async {
    final out = <String, int>{};
    for (final s in await store.shows()) {
      final progress = await store.progress(s.id);
      out[s.id] = s.episodes
          .where((e) => !(progress[e.guid]?.played ?? false))
          .length;
    }
    return out;
  }

  Future<void> markPlayed(
    String showId,
    Iterable<String> guids, {
    required bool played,
  }) async {
    final show = await store.show(showId);
    if (show == null) return;
    await store.setPlayed(showId, guids, played: played, at: _clock().toUtc());
    if (played && show.deleteWhenPlayed) {
      for (final e in show.episodes.where((e) => guids.contains(e.guid))) {
        await downloads.remove(Uri.parse(e.url));
      }
    }
    _changes.add(null);
  }

  Future<void> markAllPlayed(String showId, {required bool played}) async {
    final show = await store.show(showId);
    if (show == null) return;
    await markPlayed(showId, [
      for (final e in show.episodes) e.guid,
    ], played: played);
  }

  /// The offline copy of [episode], when it is on the device.
  Future<File?> localFile(ParsedEpisode episode) async {
    final d = await downloads.status(Uri.parse(episode.url));
    return d != null && d.done ? d.file : null;
  }

  /// Keeps an offline copy of [episode]. The download follows the redirect
  /// chain itself, one request at a time (see `HttpUrlFileSystem`).
  Future<void> download(PodcastShow show, ParsedEpisode episode) async {
    final url = Uri.parse(episode.url);
    await downloads.enqueue(url, title: episode.title, size: episode.size);
    _changes.add(null);
  }

  Future<void> removeDownload(ParsedEpisode episode) async {
    await downloads.remove(Uri.parse(episode.url));
    _changes.add(null);
  }

  /// The subscriptions as OPML.
  Future<String> exportOpml() async => buildOpml([
    for (final s in await store.shows())
      OpmlFeed(s.url, title: s.title, link: s.link),
  ]);

  /// Subscribes to every feed in [opml] not already subscribed to.
  /// [onProgress] reports how many of the total have been handled.
  Future<OpmlImportResult> importOpml(
    String opml, {
    void Function(int done, int total)? onProgress,
  }) async {
    final feeds = parseOpml(opml);
    var added = 0;
    var already = 0;
    final failed = <String>[];
    for (final (i, f) in feeds.indexed) {
      try {
        await subscribe(f.url);
        added++;
      } on PodcastException catch (e) {
        if (e.reason == PodcastFailure.alreadySubscribed) {
          already++;
        } else {
          failed.add(f.url);
        }
      }
      onProgress?.call(i + 1, feeds.length);
    }
    return OpmlImportResult(
      added: added,
      alreadySubscribed: already,
      failed: failed,
    );
  }

  Future<void> dispose() => _changes.close();

  // ------------------------------------------------------------ internals --

  Future<FetchResult> _get(
    Uri uri, {
    Map<String, String> headers = const {},
    int maxBytes = maxFeedBytes,
  }) async {
    try {
      return await http.fetch(
        uri,
        headers: headers,
        maxBytes: maxBytes,
        // The listener gave this address, so it may be on their own network.
        trusted: {uri.host.toLowerCase()},
      );
    } on PodcastHttpException catch (e) {
      throw PodcastException(
        e.reason == 'private address'
            ? PodcastFailure.blocked
            : PodcastFailure.tooLarge,
      );
    } on NetworkBlocked {
      throw const PodcastException(PodcastFailure.blocked);
    } on Exception {
      throw const PodcastException(PodcastFailure.unreachable);
    }
  }

  Future<ParsedFeed> _parse(Uint8List body, Uri base) async {
    try {
      return await parse(body, base: base);
    } on FeedFormatException {
      throw const PodcastException(PodcastFailure.notAFeed);
    }
  }

  /// The newest [keptEpisodes] of [fresh], plus every episode in [keep]
  /// (a place, a played mark or a download), from [fresh] or, when the feed
  /// dropped it, from [previous].
  List<ParsedEpisode> _kept(
    List<ParsedEpisode> fresh,
    Set<String> keep, {
    List<ParsedEpisode> previous = const [],
  }) {
    final out = <ParsedEpisode>[];
    final seen = <String>{};
    for (final e in fresh) {
      if (out.length < keptEpisodes || keep.contains(e.guid)) {
        out.add(_trimmed(e));
        seen.add(e.guid);
      }
    }
    for (final e in previous) {
      if (keep.contains(e.guid) && seen.add(e.guid)) out.add(e);
    }
    return out;
  }

  ParsedEpisode _trimmed(ParsedEpisode e) {
    final d = e.description;
    if (d == null || d.length <= 1000) return e;
    return ParsedEpisode(
      guid: e.guid,
      title: e.title,
      url: e.url,
      published: e.published,
      duration: e.duration,
      mimeType: e.mimeType,
      size: e.size,
      description: d.substring(0, 1000),
      imageUrl: e.imageUrl,
      episode: e.episode,
      season: e.season,
      explicit: e.explicit,
    );
  }

  Future<Set<String>> _downloadedGuids(List<ParsedEpisode> episodes) async => {
    for (final e in episodes)
      if (await downloads.status(Uri.parse(e.url)) != null) e.guid,
  };

  Future<String?> _cacheArt(PodcastShow show, [String? imageUrl]) async {
    final dir = artDir;
    final url = imageUrl ?? show.imageUrl;
    if (dir == null || url == null) return show.artPath;
    try {
      final res = await http.fetch(
        Uri.parse(url),
        // Artwork may sit on the feed's own host, even on the listener's
        // network; any other private address is refused.
        trusted: {Uri.parse(show.url).host.toLowerCase()},
      );
      if (res.status != 200 || res.body.isEmpty) return show.artPath;
      final type = res.headers['content-type']?.toLowerCase() ?? '';
      final ext = type.contains('png')
          ? 'png'
          : type.contains('webp')
          ? 'webp'
          : 'jpg';
      await dir.create(recursive: true);
      final f = File('${dir.path}${Platform.pathSeparator}${show.id}.$ext');
      final tmp = File('${f.path}.tmp');
      await tmp.writeAsBytes(res.body, flush: true);
      await tmp.rename(f.path);
      return f.path;
    } on Object {
      return show.artPath;
    }
  }

  /// Keeps the newest [PodcastShow.autoDownload] unplayed episodes of
  /// [show] on the device, when this is a good moment (not metered).
  Future<void> _autoDownload(
    PodcastShow show,
    Map<String, EpisodeProgress> progress, {
    required List<ParsedEpisode> newest,
  }) async {
    final n = show.autoDownload;
    if (n <= 0 || newest.isEmpty) return;
    if (!(await (canDownloadNow?.call() ?? Future.value(true)))) return;
    final wanted = show.episodes
        .where((e) => !(progress[e.guid]?.played ?? false))
        .take(n);
    for (final e in wanted) {
      // Unsubscribing stops what is still to come.
      if (await store.show(show.id) == null) return;
      if (await downloads.status(Uri.parse(e.url)) == null) {
        await download(show, e);
      }
    }
  }

  /// Deletes artwork fetched for a show that is gone.
  Future<void> _dropArt(String? path) async {
    if (path == null) return;
    final f = File(path);
    if (f.existsSync()) await f.delete();
  }
}
