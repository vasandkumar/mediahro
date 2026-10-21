import 'dart:async';
import 'dart:typed_data';

import 'package:mediahro/core/net/network_policy.dart';
import 'package:mediahro_servers/mediahro_servers.dart';
import 'package:meta/meta.dart';

/// `NetworkGateway.sendStreamed` (or a fake of it).
typedef StreamedSend = Future<HttpStreamResponse> Function(
  HttpRequestData request, {
  int maxRedirects,
});

@immutable
final class FetchResult {
  const FetchResult(this.status, this.headers, this.body, this.uri);

  final int status;

  /// Lower-case names.
  final Map<String, String> headers;
  final Uint8List body;

  /// Where the answer came from, after redirects.
  final Uri uri;
}

final class PodcastHttpException implements Exception {
  const PodcastHttpException(this.reason);

  final String reason;

  @override
  String toString() => 'PodcastHttpException($reason)';
}

/// The one way podcasts reach the network (POD-002, PRIV-004): through the
/// `NetworkGateway`, never directly.
///
/// A podcast address is one the listener typed, imported or subscribed to,
/// like a URL typed into "open URL" (CORE-005), so its host is allowed for
/// the session. Podcast links also hop through tracking and CDN hosts the
/// listener never sees. Every hop is allowed one by one as it is followed,
/// instead of any host being allowed ahead of time.
final class PodcastHttp {
  PodcastHttp({
    required this.send,
    required this.allowHost,
    this.maxHops = 8,
    this.timeout = const Duration(seconds: 30),
  });

  final StreamedSend send;

  /// Allows requests to a host for this session.
  final void Function(String host) allowHost;
  final int maxHops;
  final Duration timeout;

  static const _redirects = {301, 302, 303, 307, 308};

  /// GET [uri], following redirects, with at most [maxBytes] of body.
  Future<FetchResult> fetch(
    Uri uri, {
    Map<String, String> headers = const {},
    int maxBytes = 8 << 20,
  }) async {
    var u = uri;
    for (var hop = 0; hop <= maxHops; hop++) {
      allowHost(u.host);
      final res = await send(
        HttpRequestData(method: 'GET', uri: u, headers: headers),
        maxRedirects: 0,
      ).timeout(timeout);
      final next = _next(res, u);
      if (next != null) {
        await res.body.drain<void>();
        u = next;
        continue;
      }
      final out = BytesBuilder(copy: false);
      var total = 0;
      await for (final chunk in res.body.timeout(timeout)) {
        total += chunk.length;
        if (total > maxBytes) {
          throw const PodcastHttpException('too large');
        }
        out.add(chunk);
      }
      return FetchResult(res.statusCode, res.headers, out.takeBytes(), u);
    }
    throw const PodcastHttpException('too many redirects');
  }

  /// Follows the redirects of [uri] without reading the body, allowing each
  /// host on the way, so that the download manager's own request (which
  /// follows redirects only to allowed hosts) gets through. Returns the
  /// address the chain ends at.
  Future<Uri> allowChain(Uri uri) async {
    var u = uri;
    for (var hop = 0; hop <= maxHops; hop++) {
      allowHost(u.host);
      final res = await send(
        HttpRequestData(
          method: 'GET',
          uri: u,
          headers: const {'range': 'bytes=0-0'},
        ),
        maxRedirects: 0,
      ).timeout(timeout);
      final next = _next(res, u);
      await res.body.drain<void>();
      if (next == null) return u;
      u = next;
    }
    throw const PodcastHttpException('too many redirects');
  }

  Uri? _next(HttpStreamResponse res, Uri from) {
    if (!_redirects.contains(res.statusCode)) return null;
    final loc = res.headers['location'];
    if (loc == null || loc.isEmpty) return null;
    final to = from.resolve(loc);
    if (to.scheme != 'http' && to.scheme != 'https') return null;
    return to;
  }
}
