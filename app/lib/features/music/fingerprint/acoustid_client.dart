import 'dart:async';
import 'dart:convert';

import 'package:mediahro/features/music/fingerprint/fingerprint_service.dart';
import 'package:mediahro_servers/mediahro_servers.dart';
import 'package:meta/meta.dart';

/// The application key for AcoustID (an owner task, STATUS §4), given at
/// build time with `--dart-define=MEDIAHRO_ACOUSTID_KEY=…`. Empty in a build
/// without one, which switches song identification off.
const acoustIdKey = String.fromEnvironment('MEDIAHRO_ACOUSTID_KEY');

/// One possible identity of a song, from AcoustID and MusicBrainz.
@immutable
final class SongMatch {
  const SongMatch({
    required this.recordingId,
    required this.title,
    required this.score,
    this.artist,
    this.album,
    this.year,
  });

  /// MusicBrainz recording id.
  final String recordingId;
  final String title;
  final String? artist;
  final String? album;
  final int? year;

  /// 0…1, how well the fingerprint matches.
  final double score;
}

enum AcoustIdFailure { rateLimited, invalidKey, invalidFingerprint, server }

final class AcoustIdException implements Exception {
  const AcoustIdException(this.reason, [this.detail]);

  final AcoustIdFailure reason;
  final String? detail;

  @override
  String toString() =>
      'AcoustIdException($reason${detail == null ? '' : ': $detail'})';
}

/// AcoustID's lookup (MUS-010, https://acoustid.org/webservice): sends the
/// fingerprint and the song's length, never the audio, never tag text.
/// Opt-in per PRIV-004: the transport is the `NetworkGateway`, which refuses
/// the request while the user has the endpoint off. Free use is limited to
/// three requests per second, so calls are spaced.
final class AcoustIdClient {
  AcoustIdClient({
    required this.transport,
    this.apiKey = acoustIdKey,
    this.minGap = const Duration(milliseconds: 350),
    DateTime Function()? clock,
    Future<void> Function(Duration)? delay,
  }) : _clock = clock ?? DateTime.now,
       _delay = delay ?? Future<void>.delayed;

  final HttpTransport transport;
  final String apiKey;
  final Duration minGap;
  final DateTime Function() _clock;
  final Future<void> Function(Duration) _delay;
  DateTime? _last;

  /// False in a build without the application key.
  bool get available => apiKey.isNotEmpty;

  /// Matches for [fp], best first; empty when AcoustID does not know it.
  Future<List<SongMatch>> lookup(AudioFingerprint fp) async {
    if (!available) {
      throw const AcoustIdException(AcoustIdFailure.invalidKey, 'no key');
    }
    final last = _last;
    if (last != null) {
      final wait = minGap - _clock().difference(last);
      if (wait > Duration.zero) await _delay(wait);
    }
    _last = _clock();
    final body = [
      for (final e in {
        'client': apiKey,
        'format': 'json',
        'meta': 'recordings releasegroups releases',
        'duration': '${fp.durationSeconds}',
        'fingerprint': fp.encoded,
      }.entries)
        '${e.key}=${Uri.encodeQueryComponent(e.value)}',
    ].join('&');
    final res = await transport.send(
      HttpRequestData(
        method: 'POST',
        uri: Uri.https('api.acoustid.org', '/v2/lookup'),
        headers: const {
          'content-type': 'application/x-www-form-urlencoded',
          'accept': 'application/json',
        },
        body: utf8.encode(body),
      ),
    );
    if (res.statusCode == 429 || res.statusCode == 503) {
      throw const AcoustIdException(AcoustIdFailure.rateLimited);
    }
    final json = _json(res.body);
    if (json == null) {
      throw AcoustIdException(AcoustIdFailure.server, '${res.statusCode}');
    }
    if (json['status'] != 'ok') {
      final err = json['error'];
      final code = err is Map ? err['code'] : null;
      throw switch (code) {
        4 => const AcoustIdException(AcoustIdFailure.invalidKey),
        3 || 2 => const AcoustIdException(AcoustIdFailure.invalidFingerprint),
        _ => AcoustIdException(
          AcoustIdFailure.server,
          err is Map ? '${err['message']}' : null,
        ),
      };
    }
    return parseMatches(json);
  }

  /// The matches in an AcoustID `lookup` response, best first, without
  /// duplicates.
  static List<SongMatch> parseMatches(Map<String, Object?> json) {
    final out = <SongMatch>[];
    final seen = <String>{};
    final results = json['results'];
    if (results is! List) return out;
    for (final r in results.whereType<Map<String, Object?>>()) {
      final score = (r['score'] as num?)?.toDouble() ?? 0;
      final recordings = r['recordings'];
      if (recordings is! List) continue;
      for (final rec in recordings.whereType<Map<String, Object?>>()) {
        final id = rec['id'];
        final title = rec['title'];
        if (id is! String || title is! String || title.trim().isEmpty) continue;
        final (album, year) = _album(rec);
        final m = SongMatch(
          recordingId: id,
          title: title.trim(),
          artist: _artists(rec['artists']),
          album: album,
          year: year,
          score: score,
        );
        if (seen.add('${m.title}|${m.artist}|${m.album}')) out.add(m);
      }
    }
    // Stable: equal scores keep AcoustID's order.
    final ranked = out.indexed.toList()
      ..sort((a, b) {
        final c = b.$2.score.compareTo(a.$2.score);
        return c != 0 ? c : a.$1.compareTo(b.$1);
      });
    return [for (final e in ranked) e.$2];
  }

  /// "A & B": names joined with MusicBrainz's join phrases.
  static String? _artists(Object? v) {
    if (v is! List) return null;
    final b = StringBuffer();
    for (final a in v.whereType<Map<String, Object?>>()) {
      final name = a['name'];
      if (name is! String || name.trim().isEmpty) continue;
      b.write(name.trim());
      final join = a['joinphrase'];
      if (join is String) b.write(join);
    }
    final s = b.toString().trim();
    return s.isEmpty ? null : s;
  }

  /// The album of a recording: the first release group of type Album
  /// without secondary types (no compilations or live albums), else any
  /// album, else the first group; and the earliest year among its releases.
  static (String?, int?) _album(Map<String, Object?> rec) {
    final groups = [
      if (rec['releasegroups'] case final List<Object?> l)
        ...l.whereType<Map<String, Object?>>(),
    ];
    if (groups.isEmpty) return (null, null);
    bool isAlbum(Map<String, Object?> g) => g['type'] == 'Album';
    bool plain(Map<String, Object?> g) =>
        g['secondarytypes'] is! List || (g['secondarytypes']! as List).isEmpty;
    final g =
        groups.where((g) => isAlbum(g) && plain(g)).firstOrNull ??
        groups.where(isAlbum).firstOrNull ??
        groups.first;
    final title = g['title'];
    final years = [
      for (final rel in [
        if (g['releases'] case final List<Object?> l)
          ...l.whereType<Map<String, Object?>>(),
      ])
        if (rel['date'] case {'year': final int y}) y,
    ]..sort();
    return (
      title is String && title.trim().isNotEmpty ? title.trim() : null,
      years.firstOrNull,
    );
  }

  static Map<String, Object?>? _json(List<int> body) {
    try {
      final j = jsonDecode(utf8.decode(body, allowMalformed: true));
      return j is Map<String, Object?> ? j : null;
    } on FormatException {
      return null;
    }
  }
}
