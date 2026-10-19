import 'dart:convert';
import 'dart:isolate';

import 'package:mediahro_servers/mediahro_servers.dart';
import 'package:meta/meta.dart';

/// A metadata match candidate (LIB-011).
@immutable
final class MetadataMatch {
  const MetadataMatch({
    required this.provider,
    required this.id,
    required this.title,
    required this.isSeries,
    this.year,
    this.overview,
    this.posterUrl,
    this.backdropUrl,
    this.rating,
    this.collectionId,
    this.collectionName,
    this.imdbId,
    this.cast = const [],
    this.directors = const [],
  });

  /// `tmdb` or `tvdb`.
  final String provider;
  final String id;
  final String title;
  final bool isSeries;
  final int? year;
  final String? overview;
  final String? posterUrl;
  final String? backdropUrl;
  final double? rating;
  final String? collectionId;
  final String? collectionName;
  final String? imdbId;
  final List<(String name, String? character)> cast;
  final List<String> directors;
}

@immutable
final class EpisodeMetadata {
  const EpisodeMetadata({
    required this.season,
    required this.episode,
    this.title,
    this.overview,
    this.stillUrl,
    this.rating,
  });

  final int season;
  final int episode;
  final String? title;
  final String? overview;
  final String? stillUrl;
  final double? rating;
}

final class MetadataUnavailable implements Exception {
  const MetadataUnavailable(this.reason);

  final String reason;

  @override
  String toString() => 'MetadataUnavailable($reason)';
}

/// A provider client. Implementations go through [HttpTransport]
/// (NetworkGateway, ADR-014), whose allow-list toggles `tmdb` / `tvdb`.
abstract interface class MetadataProvider {
  String get id;

  Future<List<MetadataMatch>> search(
    String title, {
    required bool series,
    int? year,
  });
  Future<MetadataMatch> details(String id, {required bool series});
  Future<EpisodeMetadata?> episode(String seriesId, int season, int episode);
}

/// JSON decoding of provider responses runs on a worker isolate (PRIV-005).
Future<Map<String, Object?>> decodeJsonIsolated(List<int> body) {
  if (body.length > 8 << 20) {
    throw const FormatException('metadata response too large');
  }
  return Isolate.run(() {
    final v = jsonDecode(utf8.decode(body));
    if (v is! Map<String, Object?>) {
      throw const FormatException('expected a JSON object');
    }
    return v;
  });
}

/// TMDB v3 (api.themoviedb.org). [apiKey] is the user's key or the
/// project key (owner task, STATUS.md §4); v4 read tokens are sent as
/// bearer tokens.
final class TmdbClient implements MetadataProvider {
  TmdbClient(this.http, {required this.apiKey, this.language = 'en-US'});

  final HttpTransport http;
  final String apiKey;
  final String language;

  static const imageBase = 'https://image.tmdb.org/t/p/';

  @override
  String get id => 'tmdb';

  Future<Map<String, Object?>> _get(
    String path, [
    Map<String, String> q = const {},
  ]) async {
    if (apiKey.isEmpty) throw const MetadataUnavailable('no TMDB key');
    final bearer = apiKey.length > 40;
    final uri = Uri.https('api.themoviedb.org', '/3$path', {
      'language': language,
      if (!bearer) 'api_key': apiKey,
      ...q,
    });
    final res = await http.send(
      HttpRequestData(
        method: 'GET',
        uri: uri,
        headers: {
          'Accept': 'application/json',
          if (bearer) 'Authorization': 'Bearer $apiKey',
        },
      ),
    );
    if (res.statusCode == 401) {
      throw const MetadataUnavailable('TMDB key rejected');
    }
    if (res.statusCode != 200) {
      throw MetadataUnavailable('TMDB HTTP ${res.statusCode}');
    }
    return await decodeJsonIsolated(res.body);
  }

  @override
  Future<List<MetadataMatch>> search(
    String title, {
    required bool series,
    int? year,
  }) async {
    final j = await _get(series ? '/search/tv' : '/search/movie', {
      'query': title,
      if (year != null) (series ? 'first_air_date_year' : 'year'): '$year',
    });
    return [
      for (final r in (j['results'] as List<Object?>? ?? const []))
        _match(r! as Map<String, Object?>, series: series),
    ];
  }

  @override
  Future<MetadataMatch> details(String id, {required bool series}) async {
    final j = await _get(series ? '/tv/$id' : '/movie/$id', {
      'append_to_response': 'credits',
    });
    return _match(j, series: series);
  }

  @override
  Future<EpisodeMetadata?> episode(
    String seriesId,
    int season,
    int episode,
  ) async {
    try {
      final j = await _get('/tv/$seriesId/season/$season/episode/$episode');
      return EpisodeMetadata(
        season: season,
        episode: episode,
        title: j['name'] as String?,
        overview: j['overview'] as String?,
        stillUrl: _img(j['still_path'], 'w780'),
        rating: (j['vote_average'] as num?)?.toDouble(),
      );
    } on MetadataUnavailable {
      return null;
    }
  }

  MetadataMatch _match(Map<String, Object?> r, {required bool series}) {
    final date = (series ? r['first_air_date'] : r['release_date']) as String?;
    final coll = r['belongs_to_collection'];
    final credits = r['credits'] as Map<String, Object?>?;
    return MetadataMatch(
      provider: id,
      id: '${r['id']}',
      title: ((series ? r['name'] : r['title']) as String?) ?? '',
      isSeries: series,
      year: date == null || date.length < 4
          ? null
          : int.tryParse(date.substring(0, 4)),
      overview: r['overview'] as String?,
      posterUrl: _img(r['poster_path'], 'w500'),
      backdropUrl: _img(r['backdrop_path'], 'w1280'),
      rating: (r['vote_average'] as num?)?.toDouble(),
      imdbId: r['imdb_id'] as String?,
      collectionId: coll is Map<String, Object?> ? '${coll['id']}' : null,
      collectionName: coll is Map<String, Object?>
          ? coll['name'] as String?
          : null,
      cast: [
        for (final c in _maps(credits?['cast']).take(20))
          (c['name'] as String? ?? '', c['character'] as String?),
      ],
      directors: [
        for (final c in _maps(credits?['crew']))
          if (c['job'] == 'Director') c['name'] as String? ?? '',
      ],
    );
  }

  static Iterable<Map<String, Object?>> _maps(Object? list) =>
      (list is List<Object?> ? list : const <Object?>[])
          .whereType<Map<String, Object?>>();

  static String? _img(Object? path, String size) =>
      path is String && path.isNotEmpty ? '$imageBase$size$path' : null;
}

/// TheTVDB v4 (api4.thetvdb.com): login with the API key (and optional
/// subscriber PIN), then bearer token.
final class TvdbClient implements MetadataProvider {
  TvdbClient(this.http, {required this.apiKey, this.pin});

  final HttpTransport http;
  final String apiKey;
  final String? pin;
  String? _token;

  @override
  String get id => 'tvdb';

  Future<String> _login() async {
    if (apiKey.isEmpty) throw const MetadataUnavailable('no TVDB key');
    final res = await http.send(
      HttpRequestData(
        method: 'POST',
        uri: Uri.https('api4.thetvdb.com', '/v4/login'),
        headers: const {'Content-Type': 'application/json'},
        body: utf8.encode(jsonEncode({'apikey': apiKey, 'pin': ?pin})),
      ),
    );
    if (res.statusCode != 200) {
      throw MetadataUnavailable('TVDB login HTTP ${res.statusCode}');
    }
    final j = await decodeJsonIsolated(res.body);
    final data = j['data'] as Map<String, Object?>?;
    return _token =
        data?['token'] as String? ??
        (throw const MetadataUnavailable('TVDB token missing'));
  }

  Future<Map<String, Object?>> _get(
    String path, [
    Map<String, String>? q,
  ]) async {
    final token = _token ?? await _login();
    final res = await http.send(
      HttpRequestData(
        method: 'GET',
        uri: Uri.https('api4.thetvdb.com', '/v4$path', q),
        headers: {
          'Authorization': 'Bearer $token',
          'Accept': 'application/json',
        },
      ),
    );
    if (res.statusCode == 401) {
      _token = null;
      throw const MetadataUnavailable('TVDB token expired');
    }
    if (res.statusCode != 200) {
      throw MetadataUnavailable('TVDB HTTP ${res.statusCode}');
    }
    return await decodeJsonIsolated(res.body);
  }

  @override
  Future<List<MetadataMatch>> search(
    String title, {
    required bool series,
    int? year,
  }) async {
    final j = await _get('/search', {
      'query': title,
      'type': series ? 'series' : 'movie',
      if (year != null) 'year': '$year',
    });
    return [
      for (final r in (j['data'] as List<Object?>? ?? const []))
        () {
          final m = r! as Map<String, Object?>;
          return MetadataMatch(
            provider: id,
            id: '${m['tvdb_id'] ?? m['id']}',
            title: m['name'] as String? ?? '',
            isSeries: series,
            year: int.tryParse('${m['year'] ?? ''}'),
            overview: m['overview'] as String?,
            posterUrl: m['image_url'] as String?,
          );
        }(),
    ];
  }

  @override
  Future<MetadataMatch> details(String id, {required bool series}) async {
    final j = await _get(
      series ? '/series/$id/extended' : '/movies/$id/extended',
    );
    final d = j['data']! as Map<String, Object?>;
    return MetadataMatch(
      provider: this.id,
      id: id,
      title: d['name'] as String? ?? '',
      isSeries: series,
      year: int.tryParse('${d['year'] ?? ''}'),
      overview: d['overview'] as String?,
      posterUrl: d['image'] as String?,
    );
  }

  @override
  Future<EpisodeMetadata?> episode(
    String seriesId,
    int season,
    int episode,
  ) async {
    final j = await _get('/series/$seriesId/episodes/default', {
      'season': '$season',
      'episodeNumber': '$episode',
    });
    final data = j['data'] as Map<String, Object?>?;
    final eps = data?['episodes'] as List<Object?>? ?? const [];
    for (final e in eps) {
      final m = e! as Map<String, Object?>;
      if (m['seasonNumber'] == season && m['number'] == episode) {
        return EpisodeMetadata(
          season: season,
          episode: episode,
          title: m['name'] as String?,
          overview: m['overview'] as String?,
          stillUrl: m['image'] as String?,
        );
      }
    }
    return null;
  }
}
