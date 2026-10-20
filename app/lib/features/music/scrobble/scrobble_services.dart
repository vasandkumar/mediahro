import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:mediahro/platform/platform_facades.dart';
import 'package:mediahro_servers/mediahro_servers.dart';
import 'package:meta/meta.dart';

/// One listen to report (MUS-009).
@immutable
final class ScrobbleTrack {
  const ScrobbleTrack({
    required this.artist,
    required this.title,
    required this.playedAt,
    this.album,
    this.albumArtist,
    this.duration,
    this.trackNumber,
    this.recordingMbid,
    this.releaseMbid,
  });

  final String artist;
  final String title;
  final String? album;
  final String? albumArtist;
  final Duration? duration;
  final int? trackNumber;
  final String? recordingMbid;
  final String? releaseMbid;

  /// When playback started (UTC).
  final DateTime playedAt;

  Map<String, Object?> toJson() => {
    'artist': artist,
    'title': title,
    'album': ?album,
    'albumArtist': ?albumArtist,
    'durationMs': ?duration?.inMilliseconds,
    'track': ?trackNumber,
    'recordingMbid': ?recordingMbid,
    'releaseMbid': ?releaseMbid,
    'playedAt': playedAt.millisecondsSinceEpoch,
  };

  static ScrobbleTrack? fromJson(Object? j) {
    if (j is! Map<String, Object?>) return null;
    final artist = j['artist'];
    final title = j['title'];
    final at = j['playedAt'];
    if (artist is! String || title is! String || at is! int) return null;
    return ScrobbleTrack(
      artist: artist,
      title: title,
      album: j['album'] as String?,
      albumArtist: j['albumArtist'] as String?,
      duration: j['durationMs'] is int
          ? Duration(milliseconds: j['durationMs']! as int)
          : null,
      trackNumber: j['track'] as int?,
      recordingMbid: j['recordingMbid'] as String?,
      releaseMbid: j['releaseMbid'] as String?,
      playedAt: DateTime.fromMillisecondsSinceEpoch(at, isUtc: true),
    );
  }
}

/// Why a submission failed; [auth] stops retries until the user signs in
/// again, everything else is retried later.
final class ScrobbleError implements Exception {
  const ScrobbleError(this.message, {this.auth = false});

  final String message;
  final bool auth;

  @override
  String toString() => 'ScrobbleError($message, auth: $auth)';
}

/// A scrobbling service account.
abstract interface class ScrobbleService {
  /// `listenbrainz`, `lastfm` or `librefm` (also the PRIV-004 endpoint id).
  String get id;

  /// Signed in (a token or session key is stored).
  Future<bool> connected();

  Future<void> nowPlaying(ScrobbleTrack t);

  /// Submits up to [batchSize] listens; throws [ScrobbleError].
  Future<void> submit(List<ScrobbleTrack> listens);

  int get batchSize;

  Future<void> signOut();
}

const _jsonHeaders = {'content-type': 'application/json'};

/// ListenBrainz (https://listenbrainz.readthedocs.io): a user token from
/// listenbrainz.org/settings, kept in secure storage.
final class ListenBrainzService implements ScrobbleService {
  ListenBrainzService(this.http, this.secure);

  final HttpTransport http;
  final SecureStorageFacade secure;

  static const tokenKey = 'music.scrobble.listenbrainz.token';
  static final _base = Uri.https('api.listenbrainz.org', '/1/');

  @override
  String get id => 'listenbrainz';

  @override
  int get batchSize => 100;

  @override
  Future<bool> connected() async => (await secure.read(tokenKey)) != null;

  /// Checks [token] and stores it; returns the user name.
  Future<String> signIn(String token) async {
    final res = await http.send(
      HttpRequestData(
        method: 'GET',
        uri: _base.resolve('validate-token'),
        headers: {'authorization': 'Token ${token.trim()}'},
      ),
    );
    final j = _json(res.body);
    if (res.statusCode != 200 || j?['valid'] != true) {
      throw const ScrobbleError('invalid token', auth: true);
    }
    await secure.write(tokenKey, token.trim());
    return j?['user_name'] as String? ?? '';
  }

  @override
  Future<void> signOut() => secure.delete(tokenKey);

  @override
  Future<void> nowPlaying(ScrobbleTrack t) =>
      _post('playing_now', [_listen(t, withTime: false)]);

  @override
  Future<void> submit(List<ScrobbleTrack> listens) => _post(
    listens.length == 1 ? 'single' : 'import',
    [for (final l in listens) _listen(l, withTime: true)],
  );

  Future<void> _post(String type, List<Map<String, Object?>> payload) async {
    final token = await secure.read(tokenKey);
    if (token == null) throw const ScrobbleError('not signed in', auth: true);
    final res = await http.send(
      HttpRequestData(
        method: 'POST',
        uri: _base.resolve('submit-listens'),
        headers: {..._jsonHeaders, 'authorization': 'Token $token'},
        body: utf8.encode(
          jsonEncode({'listen_type': type, 'payload': payload}),
        ),
      ),
    );
    if (res.statusCode == 401) {
      throw const ScrobbleError('token rejected', auth: true);
    }
    if (res.statusCode != 200) {
      throw ScrobbleError('HTTP ${res.statusCode}');
    }
  }

  Map<String, Object?> _listen(ScrobbleTrack t, {required bool withTime}) => {
    if (withTime) 'listened_at': t.playedAt.millisecondsSinceEpoch ~/ 1000,
    'track_metadata': {
      'artist_name': t.artist,
      'track_name': t.title,
      'release_name': ?t.album,
      'additional_info': {
        'media_player': 'Mediahro',
        'submission_client': 'Mediahro',
        'duration_ms': ?t.duration?.inMilliseconds,
        'tracknumber': ?t.trackNumber,
        'recording_mbid': ?t.recordingMbid,
        'release_mbid': ?t.releaseMbid,
      },
    },
  };
}

/// Last.fm and Libre.fm (Audioscrobbler 2.0 API, signed calls): signed in
/// once with `auth.getMobileSession`; only the session key is stored.
final class AudioscrobblerService implements ScrobbleService {
  AudioscrobblerService({
    required this.id,
    required this.http,
    required this.secure,
    required this.apiBase,
    required this.apiKey,
    required this.apiSecret,
  });

  /// Libre.fm accepts any client key; a build may set its own.
  factory AudioscrobblerService.libreFm(
    HttpTransport http,
    SecureStorageFacade secure,
  ) => AudioscrobblerService(
    id: 'librefm',
    http: http,
    secure: secure,
    apiBase: Uri.https('libre.fm', '/2.0/'),
    apiKey: const String.fromEnvironment(
      'LIBREFM_API_KEY',
      defaultValue: 'mediahro0000000000000000000000ab',
    ),
    apiSecret: const String.fromEnvironment(
      'LIBREFM_API_SECRET',
      defaultValue: 'mediahro0000000000000000000000cd',
    ),
  );

  /// Last.fm: keys from the build (`LASTFM_API_KEY`, `LASTFM_API_SECRET`,
  /// an owner task); null when the build has none.
  static AudioscrobblerService? lastFm(
    HttpTransport http,
    SecureStorageFacade secure,
  ) {
    const key = String.fromEnvironment('LASTFM_API_KEY');
    const secret = String.fromEnvironment('LASTFM_API_SECRET');
    if (key.isEmpty || secret.isEmpty) return null;
    return AudioscrobblerService(
      id: 'lastfm',
      http: http,
      secure: secure,
      apiBase: Uri.https('ws.audioscrobbler.com', '/2.0/'),
      apiKey: key,
      apiSecret: secret,
    );
  }

  @override
  final String id;
  final HttpTransport http;
  final SecureStorageFacade secure;
  final Uri apiBase;
  final String apiKey;
  final String apiSecret;

  String get _sessionKey => 'music.scrobble.$id.session';

  @override
  int get batchSize => 50;

  @override
  Future<bool> connected() async => (await secure.read(_sessionKey)) != null;

  /// Signs in; the password is sent once to the service over HTTPS and
  /// never stored. Returns the user name.
  Future<String> signIn(String user, String password) async {
    final res = await _call({
      'method': 'auth.getMobileSession',
      'username': user,
      'password': password,
    });
    final session = res['session'];
    if (session is! Map<String, Object?> || session['key'] is! String) {
      throw const ScrobbleError('no session', auth: true);
    }
    await secure.write(_sessionKey, session['key']! as String);
    return session['name'] as String? ?? user;
  }

  @override
  Future<void> signOut() => secure.delete(_sessionKey);

  @override
  Future<void> nowPlaying(ScrobbleTrack t) async {
    final sk = await secure.read(_sessionKey);
    if (sk == null) throw const ScrobbleError('not signed in', auth: true);
    await _call({
      'method': 'track.updateNowPlaying',
      'sk': sk,
      'artist': t.artist,
      'track': t.title,
      'album': ?t.album,
      'albumArtist': ?t.albumArtist,
      'duration': ?t.duration?.inSeconds.toString(),
      'trackNumber': ?t.trackNumber?.toString(),
      'mbid': ?t.recordingMbid,
    });
  }

  @override
  Future<void> submit(List<ScrobbleTrack> listens) async {
    final sk = await secure.read(_sessionKey);
    if (sk == null) throw const ScrobbleError('not signed in', auth: true);
    final params = <String, String>{'method': 'track.scrobble', 'sk': sk};
    for (final (i, t) in listens.indexed) {
      params['artist[$i]'] = t.artist;
      params['track[$i]'] = t.title;
      params['timestamp[$i]'] = '${t.playedAt.millisecondsSinceEpoch ~/ 1000}';
      if (t.album != null) params['album[$i]'] = t.album!;
      if (t.albumArtist != null) params['albumArtist[$i]'] = t.albumArtist!;
      if (t.duration != null) {
        params['duration[$i]'] = '${t.duration!.inSeconds}';
      }
      if (t.trackNumber != null) params['trackNumber[$i]'] = '${t.trackNumber}';
      if (t.recordingMbid != null) params['mbid[$i]'] = t.recordingMbid!;
    }
    await _call(params);
  }

  /// A signed POST (`api_sig` = md5 of sorted params + secret).
  Future<Map<String, Object?>> _call(Map<String, String> params) async {
    final p = {...params, 'api_key': apiKey};
    final sig = md5
        .convert(
          utf8.encode(
            '${(p.keys.toList()..sort()).map((k) => '$k${p[k]}').join()}$apiSecret',
          ),
        )
        .toString();
    final body = Uri(queryParameters: {...p, 'api_sig': sig, 'format': 'json'})
        .query;
    final res = await http.send(
      HttpRequestData(
        method: 'POST',
        uri: apiBase,
        headers: const {'content-type': 'application/x-www-form-urlencoded'},
        body: utf8.encode(body),
      ),
    );
    final j = _json(res.body) ?? const <String, Object?>{};
    final err = j['error'];
    if (err is int) {
      // 4 auth failed, 9 invalid session, 10 invalid key, 26 suspended key.
      throw ScrobbleError(
        '${j['message'] ?? 'error $err'}',
        auth: const {4, 9, 10, 14, 26}.contains(err),
      );
    }
    if (res.statusCode != 200) throw ScrobbleError('HTTP ${res.statusCode}');
    return j;
  }
}

Map<String, Object?>? _json(List<int> body) {
  try {
    final j = jsonDecode(utf8.decode(body, allowMalformed: true));
    return j is Map<String, Object?> ? j : null;
  } on FormatException {
    return null;
  }
}
