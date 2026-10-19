import 'dart:async';
import 'dart:io';

// `crypto` is resolved through the workspace until the orchestrator adds it
// to app/pubspec.yaml (PR "Orchestrator changes needed").
// ignore: depend_on_referenced_packages
import 'package:crypto/crypto.dart';
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

  /// Watched-state sync (LIB-010, opt-in per account).
  static const trakt = NetworkEndpoint(
    id: 'trakt',
    hosts: ['api.trakt.tv'],
    purpose: EndpointPurpose.scrobbling,
    policyUrl: 'https://trakt.tv/privacy',
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
    trakt,
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

/// A streamed response (downloads, range reads of network files).
final class HttpStreamResponse {
  HttpStreamResponse(this.statusCode, this.headers, this.body);

  final int statusCode;

  /// Lower-case header names.
  final Map<String, String> headers;
  final Stream<List<int>> body;
}

/// A server presented a certificate the platform does not trust. The user
/// may accept it after comparing [sha256] (docs/05 §9); the app then calls
/// [NetworkGateway.trustCertificate].
final class CertificateNotTrusted implements Exception {
  const CertificateNotTrusted(this.host, this.sha256, {this.subject});

  final String host;

  /// Upper-case hex SHA-256 of the DER certificate, colon-separated.
  final String sha256;
  final String? subject;

  @override
  String toString() => 'CertificateNotTrusted($host, $sha256)';
}

/// The single outbound HTTP path for the app ([HttpTransport] for server
/// clients). Lint `no_direct_http` forbids `HttpClient` elsewhere.
final class NetworkGateway implements HttpTransport {
  NetworkGateway(
    this._policy, {
    HttpClient? client,
    DateTime Function()? clock,
    Map<String, String> trustedCertificates = const {},
    this.userAgent = 'Mediahro',
    Duration connectionTimeout = const Duration(seconds: 15),
  }) : _client = client ?? HttpClient(),
       _clock = clock ?? DateTime.now,
       _trusted = Map.of(trustedCertificates) {
    _client
      ..connectionTimeout = connectionTimeout
      ..userAgent = userAgent
      ..badCertificateCallback = _onBadCertificate;
  }

  final NetworkPolicy _policy;
  final HttpClient _client;
  final DateTime Function() _clock;
  final String userAgent;

  /// host → accepted certificate fingerprint (self-signed servers).
  final Map<String, String> _trusted;
  final Map<String, (String, String)> _rejected = {};

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

  /// Accepts [sha256] for [host] after the user confirmed it.
  void trustCertificate(String host, String sha256) =>
      _trusted[host.toLowerCase()] = sha256.toUpperCase();

  Map<String, String> get trustedCertificates => Map.unmodifiable(_trusted);

  bool _onBadCertificate(X509Certificate cert, String host, int port) {
    final fp = certificateFingerprint(cert.der);
    if (_trusted[host.toLowerCase()] == fp) return true;
    _rejected[host.toLowerCase()] = (fp, cert.subject);
    return false;
  }

  @override
  Future<HttpResponseData> send(HttpRequestData request) async {
    final res = await sendStreamed(request);
    final body = await res.body.fold<List<int>>(
      <int>[],
      (acc, chunk) => acc..addAll(chunk),
    );
    return HttpResponseData(
      statusCode: res.statusCode,
      headers: res.headers,
      body: body,
    );
  }

  /// Like [send] without buffering the body (downloads, NET-018; range
  /// reads, docs/05 §9). Redirects are followed only to hosts that pass
  /// [authorize] too.
  Future<HttpStreamResponse> sendStreamed(
    HttpRequestData request, {
    int maxRedirects = 5,
  }) async {
    var uri = request.uri;
    var method = request.method;
    for (var hop = 0; ; hop++) {
      authorize(uri);
      final HttpClientResponse res;
      try {
        final req = await _client.openUrl(method, uri);
        req.followRedirects = false;
        request.headers.forEach(req.headers.set);
        if (request.body != null && method != 'GET') req.add(request.body!);
        res = await req.close();
      } on HandshakeException {
        final r = _rejected.remove(uri.host.toLowerCase());
        if (r != null) {
          throw CertificateNotTrusted(uri.host, r.$1, subject: r.$2);
        }
        rethrow;
      }
      if (res.isRedirect && hop < maxRedirects) {
        final loc = res.headers.value(HttpHeaders.locationHeader);
        await res.drain<void>();
        if (loc == null) break;
        uri = uri.resolve(loc);
        if (res.statusCode == 303) method = 'GET';
        continue;
      }
      final headers = <String, String>{};
      res.headers.forEach((name, values) => headers[name] = values.join(','));
      return HttpStreamResponse(res.statusCode, headers, res);
    }
    throw HttpException('too many redirects', uri: uri);
  }

  void close() => _client.close(force: true);
}

/// Upper-case, colon-separated SHA-256 of a DER certificate.
String certificateFingerprint(List<int> der) => sha256
    .convert(der)
    .bytes
    .map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase())
    .join(':');
