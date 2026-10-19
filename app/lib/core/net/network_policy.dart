import 'dart:async';
import 'dart:io';

import 'package:mediahro_servers/mediahro_servers.dart';
import 'package:meta/meta.dart';

/// Purpose of an outbound endpoint, shown in the privacy dashboard (CORE-015).
enum EndpointPurpose {
  configuration,
  crashReports,
  analytics,
  subtitles,
  metadata,
  lyrics,
  artwork,
  fingerprinting,
  scrobbling,
  maps,
  skipMarkers,
  userConfigured,
}

/// One entry of the network allow-list (PRIV-004, docs/05 §9). Every host the
/// app may contact on its own initiative is listed here; anything else is
/// refused unless it is a source or server the user added.
@immutable
final class NetworkEndpoint {
  const NetworkEndpoint({
    required this.id,
    required this.hosts,
    required this.purpose,
    this.policyUrl,
  });

  /// Stable id, also the privacy toggle key (`privacy.endpoint.<id>`).
  final String id;
  final List<String> hosts;
  final EndpointPurpose purpose;
  final String? policyUrl;

  bool matches(String host) => hosts.any(
    (h) => h.startsWith('*.') ? host.endsWith(h.substring(1)) : host == h,
  );
}

/// The complete allow-list. Adding an entry requires a PRIVACY.md update.
abstract final class Endpoints {
  static const config = NetworkEndpoint(
    id: 'config',
    hosts: ['api.mediahro.com'],
    purpose: EndpointPurpose.configuration,
  );
  static const sentry = NetworkEndpoint(
    id: 'crash',
    hosts: ['crash.mediahro.com'],
    purpose: EndpointPurpose.crashReports,
  );
  static const aptabase = NetworkEndpoint(
    id: 'analytics',
    hosts: ['analytics.mediahro.com'],
    purpose: EndpointPurpose.analytics,
  );
  static const openSubtitles = NetworkEndpoint(
    id: 'opensubtitles',
    hosts: ['api.opensubtitles.com', '*.opensubtitles.com'],
    purpose: EndpointPurpose.subtitles,
    policyUrl: 'https://www.opensubtitles.com/en/privacy',
  );
  static const podnapisi = NetworkEndpoint(
    id: 'podnapisi',
    hosts: ['www.podnapisi.net'],
    purpose: EndpointPurpose.subtitles,
  );
  static const subdl = NetworkEndpoint(
    id: 'subdl',
    hosts: ['api.subdl.com', 'dl.subdl.com'],
    purpose: EndpointPurpose.subtitles,
  );
  static const tmdb = NetworkEndpoint(
    id: 'tmdb',
    hosts: ['api.themoviedb.org', 'image.tmdb.org'],
    purpose: EndpointPurpose.metadata,
    policyUrl: 'https://www.themoviedb.org/privacy-policy',
  );
  static const tvdb = NetworkEndpoint(
    id: 'tvdb',
    hosts: ['api4.thetvdb.com', 'artworks.thetvdb.com'],
    purpose: EndpointPurpose.metadata,
  );
  static const lrclib = NetworkEndpoint(
    id: 'lrclib',
    hosts: ['lrclib.net'],
    purpose: EndpointPurpose.lyrics,
  );
  static const musicBrainz = NetworkEndpoint(
    id: 'musicbrainz',
    hosts: ['musicbrainz.org', 'coverartarchive.org', '*.archive.org'],
    purpose: EndpointPurpose.artwork,
  );
  static const acoustId = NetworkEndpoint(
    id: 'acoustid',
    hosts: ['api.acoustid.org'],
    purpose: EndpointPurpose.fingerprinting,
  );
  static const listenBrainz = NetworkEndpoint(
    id: 'listenbrainz',
    hosts: ['api.listenbrainz.org'],
    purpose: EndpointPurpose.scrobbling,
  );
  static const lastFm = NetworkEndpoint(
    id: 'lastfm',
    hosts: ['ws.audioscrobbler.com'],
    purpose: EndpointPurpose.scrobbling,
  );
  static const libreFm = NetworkEndpoint(
    id: 'librefm',
    hosts: ['libre.fm'],
    purpose: EndpointPurpose.scrobbling,
  );
  static const mapTiles = NetworkEndpoint(
    id: 'maptiles',
    hosts: ['tiles.mediahro.com'],
    purpose: EndpointPurpose.maps,
  );
  static const introDb = NetworkEndpoint(
    id: 'introdb',
    hosts: ['api.introdb.app'],
    purpose: EndpointPurpose.skipMarkers,
  );

  static const List<NetworkEndpoint> all = [
    config,
    sentry,
    aptabase,
    openSubtitles,
    podnapisi,
    subdl,
    tmdb,
    tvdb,
    lrclib,
    musicBrainz,
    acoustId,
    listenBrainz,
    lastFm,
    libreFm,
    mapTiles,
    introDb,
  ];
}

/// Decides whether a request may leave the device.
abstract interface class NetworkPolicy {
  bool isEnabled(NetworkEndpoint endpoint);

  /// Hosts of sources/servers the user added (always allowed for them).
  bool isUserConfiguredHost(String host);

  /// Records last use for the privacy dashboard.
  void recordUse(NetworkEndpoint endpoint, DateTime at);
}

final class NetworkBlocked implements Exception {
  const NetworkBlocked(this.host, this.reason);

  final String host;
  final String reason;

  @override
  String toString() => 'NetworkBlocked($host: $reason)';
}

/// The single outbound HTTP path for the app ([HttpTransport] for server
/// clients). Lint `no_direct_http` forbids `HttpClient` elsewhere.
final class NetworkGateway implements HttpTransport {
  NetworkGateway(this._policy, {HttpClient? client, DateTime Function()? clock})
    : _client = client ?? HttpClient(),
      _clock = clock ?? DateTime.now;

  final NetworkPolicy _policy;
  final HttpClient _client;
  final DateTime Function() _clock;

  /// Throws [NetworkBlocked] when [uri] is neither an enabled allow-list
  /// endpoint nor a user-configured host.
  NetworkEndpoint? authorize(Uri uri) {
    final host = uri.host;
    for (final e in Endpoints.all) {
      if (e.matches(host)) {
        if (!_policy.isEnabled(e)) {
          throw NetworkBlocked(host, 'endpoint "${e.id}" is turned off');
        }
        _policy.recordUse(e, _clock());
        return e;
      }
    }
    if (_policy.isUserConfiguredHost(host)) return null;
    throw NetworkBlocked(host, 'host is not on the allow-list');
  }

  @override
  Future<HttpResponseData> send(HttpRequestData request) async {
    authorize(request.uri);
    final req = await _client.openUrl(request.method, request.uri);
    request.headers.forEach(req.headers.set);
    if (request.body != null) req.add(request.body!);
    final res = await req.close();
    final body = await res.fold<List<int>>(
      <int>[],
      (acc, chunk) => acc..addAll(chunk),
    );
    final headers = <String, String>{};
    res.headers.forEach((name, values) => headers[name] = values.join(','));
    return HttpResponseData(
      statusCode: res.statusCode,
      headers: headers,
      body: body,
    );
  }

  void close() => _client.close(force: true);
}
