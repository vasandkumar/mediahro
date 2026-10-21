import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:mediahro/core/net/local_hosts.dart' show normalizeHost;
import 'package:mediahro/features/music/player/music_prefs.dart';
import 'package:mediahro/features/music/podcasts/feed_parser.dart';
import 'package:meta/meta.dart';

/// Episodes kept per show besides the ones with a place, a played mark or a
/// download.
const keptEpisodes = 400;

/// A show the listener subscribed to (POD-002).
@immutable
final class PodcastShow {
  const PodcastShow({
    required this.id,
    required this.url,
    required this.title,
    required this.subscribedAt,
    this.author,
    this.description,
    this.link,
    this.imageUrl,
    this.artPath,
    this.lastFetched,
    this.etag,
    this.lastModified,
    this.oldestFirst = false,
    this.autoDownload = 0,
    this.deleteWhenPlayed = false,
    this.speed,
    this.skipSilence = false,
    this.episodes = const [],
  });

  factory PodcastShow.fromJson(Map<String, Object?> j) => PodcastShow(
    id: '${j['id']}',
    url: '${j['url']}',
    title: '${j['title'] ?? ''}',
    subscribedAt: DateTime.fromMillisecondsSinceEpoch(
      (j['sub'] as num?)?.toInt() ?? 0,
      isUtc: true,
    ),
    author: j['author'] as String?,
    description: j['desc'] as String?,
    link: j['link'] as String?,
    imageUrl: j['img'] as String?,
    artPath: j['art'] as String?,
    lastFetched: j['fetched'] is int
        ? DateTime.fromMillisecondsSinceEpoch(j['fetched']! as int, isUtc: true)
        : null,
    etag: j['etag'] as String?,
    lastModified: j['lm'] as String?,
    oldestFirst: j['oldest'] == true,
    autoDownload: ((j['auto'] as num?)?.toInt() ?? 0).clamp(0, 20),
    deleteWhenPlayed: j['delPlayed'] == true,
    speed: j['speed'] is num ? (j['speed']! as num).toDouble() : null,
    skipSilence: j['skip'] == true,
    episodes: [
      if (j['eps'] case final List<Object?> l)
        for (final e in l)
          if (e is Map<String, Object?>) ?ParsedEpisode.fromJson(e),
    ],
  );

  final String id;
  final String url;
  final String title;
  final DateTime subscribedAt;
  final String? author;
  final String? description;
  final String? link;
  final String? imageUrl;

  /// The show's artwork cached on this device.
  final String? artPath;
  final DateTime? lastFetched;
  final String? etag;
  final String? lastModified;

  /// Serials: continue with the next older episode after one ends.
  final bool oldestFirst;

  /// Keeps this many of the newest unplayed episodes downloaded (0 = off).
  final int autoDownload;
  final bool deleteWhenPlayed;

  /// Speed this show plays at; null until the listener chooses one.
  final double? speed;
  final bool skipSilence;

  /// Newest first.
  final List<ParsedEpisode> episodes;

  PodcastShow copyWith({
    String? title,
    String? author,
    String? description,
    String? link,
    String? imageUrl,
    String? artPath,
    DateTime? lastFetched,
    String? etag,
    String? lastModified,
    bool? oldestFirst,
    int? autoDownload,
    bool? deleteWhenPlayed,
    double? speed,
    bool? skipSilence,
    List<ParsedEpisode>? episodes,
  }) => PodcastShow(
    id: id,
    url: url,
    subscribedAt: subscribedAt,
    title: title ?? this.title,
    author: author ?? this.author,
    description: description ?? this.description,
    link: link ?? this.link,
    imageUrl: imageUrl ?? this.imageUrl,
    artPath: artPath ?? this.artPath,
    lastFetched: lastFetched ?? this.lastFetched,
    etag: etag ?? this.etag,
    lastModified: lastModified ?? this.lastModified,
    oldestFirst: oldestFirst ?? this.oldestFirst,
    autoDownload: autoDownload ?? this.autoDownload,
    deleteWhenPlayed: deleteWhenPlayed ?? this.deleteWhenPlayed,
    speed: speed ?? this.speed,
    skipSilence: skipSilence ?? this.skipSilence,
    episodes: episodes ?? this.episodes,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'url': url,
    'title': title,
    'sub': subscribedAt.toUtc().millisecondsSinceEpoch,
    'author': author,
    'desc': description,
    'link': link,
    'img': imageUrl,
    'art': artPath,
    'fetched': lastFetched?.toUtc().millisecondsSinceEpoch,
    'etag': etag,
    'lm': lastModified,
    'oldest': oldestFirst,
    'auto': autoDownload,
    'delPlayed': deleteWhenPlayed,
    'speed': speed,
    'skip': skipSilence,
    'eps': [for (final e in episodes) e.toJson()],
  };
}

/// Where the listener is in an episode.
@immutable
final class EpisodeProgress {
  const EpisodeProgress({
    this.position = Duration.zero,
    this.played = false,
    this.updatedAt,
  });

  factory EpisodeProgress.fromJson(Map<String, Object?> j) => EpisodeProgress(
    position: Duration(milliseconds: (j['p'] as num?)?.toInt() ?? 0),
    played: j['d'] == true,
    updatedAt: j['at'] is int
        ? DateTime.fromMillisecondsSinceEpoch(j['at']! as int, isUtc: true)
        : null,
  );

  final Duration position;
  final bool played;
  final DateTime? updatedAt;

  bool get started => position > Duration.zero;

  Map<String, Object?> toJson() => {
    'p': position.inMilliseconds,
    'd': played,
    'at': updatedAt?.toUtc().millisecondsSinceEpoch,
  };
}

/// Subscriptions, episodes and the listener's place in each, in the
/// library's settings table (so they travel with backups, CORE-013).
final class PodcastStore {
  PodcastStore(this.prefs);

  final MusicPrefs prefs;

  static const _index = 'pod.feeds';

  /// Stable id of a feed address: the first 16 hex digits of its SHA-1.
  static String idOf(String url) =>
      sha1.convert(utf8.encode(url.trim())).toString().substring(0, 16);

  /// The speed a show with none of its own starts at: the last one chosen.
  Future<double> lastSpeed() async =>
      (jsonDouble(await prefs.read('pod.lastSpeed')) ?? 1).clamp(0.5, 3.0);

  Future<void> setLastSpeed(double speed) =>
      prefs.write('pod.lastSpeed', speed);

  Future<List<String>> ids() async => [
    for (final v in await prefs.readList(_index) ?? const [])
      if (v is String) v,
  ];

  /// The host of the feed that lists [episodeUrl] (normalised), or none:
  /// the one private-network host that episode's file may reach.
  Future<Set<String>> feedHostFor(Uri episodeUrl) async {
    final wanted = episodeUrl.toString();
    for (final s in await shows()) {
      if (s.episodes.any((e) => e.url == wanted)) {
        final host = Uri.tryParse(s.url)?.host;
        return host == null || host.isEmpty ? const {} : {normalizeHost(host)};
      }
    }
    return const {};
  }

  Future<List<PodcastShow>> shows() async {
    final out = <PodcastShow>[];
    for (final id in await ids()) {
      final s = await show(id);
      if (s != null) out.add(s);
    }
    return out;
  }

  Future<PodcastShow?> show(String id) async {
    final j = await prefs.readMap('pod.f.$id');
    return j == null ? null : PodcastShow.fromJson(j);
  }

  /// Adds the show to the list (at the end) when it is new, and saves it.
  Future<void> save(PodcastShow show) async {
    final ids = await this.ids();
    await prefs.write('pod.f.${show.id}', show.toJson());
    if (!ids.contains(show.id)) await prefs.write(_index, [...ids, show.id]);
  }

  Future<void> remove(String id) async {
    await prefs.write(_index, [
      for (final i in await ids())
        if (i != id) i,
    ]);
    await prefs.write('pod.f.$id', null);
    await prefs.write('pod.s.$id', null);
  }

  Future<Map<String, EpisodeProgress>> progress(String id) async => {
    for (final e in (await prefs.readMap('pod.s.$id') ?? const {}).entries)
      if (e.value case final Map<String, Object?> j)
        e.key: EpisodeProgress.fromJson(j),
  };

  Future<void> saveProgress(String id, String guid, EpisodeProgress p) async {
    final all = await progress(id);
    all[guid] = p;
    await prefs.write('pod.s.$id', {
      for (final e in all.entries) e.key: e.value.toJson(),
    });
  }

  /// Marks every one of [guids] played (or not) in one write.
  Future<void> setPlayed(
    String id,
    Iterable<String> guids, {
    required bool played,
    DateTime? at,
  }) async {
    final all = await progress(id);
    for (final g in guids) {
      final before = all[g];
      all[g] = EpisodeProgress(
        position: played ? Duration.zero : (before?.position ?? Duration.zero),
        played: played,
        updatedAt: at,
      );
    }
    await prefs.write('pod.s.$id', {
      for (final e in all.entries) e.key: e.value.toJson(),
    });
  }
}
