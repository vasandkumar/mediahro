import 'dart:async';
import 'dart:typed_data';

import 'package:mediahro/core/net/network_policy.dart';
import 'package:mediahro/core/net/persistent_network_policy.dart'
    show isLocalNetworkHost;
import 'package:mediahro_servers/mediahro_servers.dart';
import 'package:meta/meta.dart';

/// `NetworkGateway.sendStreamed` (or a fake of it).
typedef StreamedSend = Future<HttpStreamResponse> Function(
  HttpRequestData request, {
  int maxRedirects,
});

/// The hosts one request chain may reach (the feed, each redirect hop, the
/// artwork or episode address), allowed only until [close]. It is the
/// network policy's short-lived allowance, not a session-wide one: nothing
/// stays allowed after the request, so removing a subscription revokes
/// everything at once.
final class ChainAllowance {
  const ChainAllowance({required this.allow, required this.close});

  /// Allows requests to a host until [close].
  final void Function(String host) allow;
  final void Function() close;
}

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

  /// `too large`, `too many redirects` or `private address`.
  final String reason;

  @override
  String toString() => 'PodcastHttpException($reason)';
}

/// The one way podcasts reach the network (POD-002, PRIV-004): through the
/// `NetworkGateway`, never directly.
///
/// A podcast address is one the listener typed, imported or subscribed to.
/// Podcast links also hop through tracking and CDN hosts the listener never
/// sees, so each request chain gets its own [ChainAllowance]: the host of
/// each hop is allowed as it is reached and everything is withdrawn when the
/// request is done.
///
/// A feed is written by someone else, so it cannot send the app to the
/// listener's own network: a hop to a private, loopback or link-local
/// address is refused unless that host is `trusted` for the request (the
/// feed's own host, which the listener gave) or [localAllowed] says it is the
/// host of a subscription (a podcast server on the listener's own network).
final class PodcastHttp {
  PodcastHttp({
    required this.send,
    required this.beginChain,
    this.localAllowed,
    this.maxHops = 8,
    this.timeout = const Duration(seconds: 30),
  });

  final StreamedSend send;

  /// Starts a request chain's allowance.
  final ChainAllowance Function() beginChain;

  /// Whether a private-network host is one the listener subscribed to.
  final Future<bool> Function(String host)? localAllowed;
  final int maxHops;
  final Duration timeout;

  static const _redirects = {301, 302, 303, 307, 308};

  /// GET [uri], following redirects, with at most [maxBytes] of body.
  /// [trusted] are the private-network hosts this request may reach.
  Future<FetchResult> fetch(
    Uri uri, {
    Map<String, String> headers = const {},
    int maxBytes = 8 << 20,
    Set<String> trusted = const {},
  }) async {
    final chain = beginChain();
    try {
      var u = uri;
      for (var hop = 0; hop <= maxHops; hop++) {
        await _permit(chain, u, trusted);
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
    } finally {
      chain.close();
    }
  }

  /// Follows the redirects of [uri] without reading the body and returns
  /// the address the chain ends at, with the allowance still open for it.
  /// The caller reads that address (a download, which goes on for a while)
  /// and calls [ChainAllowance.close] when it is done.
  Future<({Uri uri, ChainAllowance chain})> openChain(
    Uri uri, {
    Set<String> trusted = const {},
  }) async {
    final chain = beginChain();
    try {
      var u = uri;
      for (var hop = 0; hop <= maxHops; hop++) {
        await _permit(chain, u, trusted);
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
        if (next == null) return (uri: u, chain: chain);
        u = next;
      }
      throw const PodcastHttpException('too many redirects');
    } on Object {
      chain.close();
      rethrow;
    }
  }

  /// Allows [u]'s host for the chain, unless it is a private address nobody
  /// vouched for.
  Future<void> _permit(ChainAllowance chain, Uri u, Set<String> trusted) async {
    final host = u.host.toLowerCase();
    if (isLocalNetworkHost(host) &&
        !trusted.contains(host) &&
        !(await (localAllowed?.call(host) ?? Future.value(false)))) {
      throw const PodcastHttpException('private address');
    }
    chain.allow(host);
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
