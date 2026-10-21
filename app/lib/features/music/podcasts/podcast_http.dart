import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:mediahro/core/net/local_hosts.dart';
import 'package:mediahro/core/net/network_policy.dart';
import 'package:mediahro/core/sources/http/http_session.dart';
import 'package:mediahro_ffi/mediahro_ffi.dart';
import 'package:mediahro_servers/mediahro_servers.dart';
import 'package:meta/meta.dart';

/// `NetworkGateway.sendStreamed` (or a fake of it).
typedef StreamedSend = Future<HttpStreamResponse> Function(
  HttpRequestData request, {
  int maxRedirects,
});

/// The hosts one request chain may reach (the feed, each redirect hop, the
/// artwork or episode address). Only requests sent through [run] may use
/// them, and only until [close]: it is the network policy's scoped
/// allowance, not a session-wide one, so nothing stays allowed after the
/// request and no other code can borrow it.
final class ChainAllowance {
  const ChainAllowance({
    required this.allow,
    required this.close,
    required this.run,
  });

  /// Allows requests to a host (from inside [run]) until [close].
  final void Function(String host) allow;
  final void Function() close;

  /// Runs `body` with the allowance in force.
  final T Function<T>(T Function() body) run;
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
/// `NetworkGateway`, never directly, and never by handing an address to the
/// player.
///
/// Anything a feed names (redirects, artwork, episodes) is untrusted: every
/// hop of every request, including each read of an episode that is being
/// streamed, is allowed for that request chain only, with redirects followed
/// here one at a time (the gateway is asked for none). A hop to the listener's
/// own network (a private, loopback, link-local or reserved address, or a name
/// that resolves to one) is refused unless it is the host the listener gave
/// for that feed (`trusted`).
final class PodcastHttp {
  PodcastHttp({
    required this.send,
    required this.beginChain,
    Future<bool> Function(String host)? nonPublic,
    this.maxHops = 8,
    this.timeout = const Duration(seconds: 30),
  }) : nonPublic = nonPublic ?? resolvesToNonPublic;

  final StreamedSend send;

  /// Starts a request chain's allowance.
  final ChainAllowance Function() beginChain;

  /// Whether `host` is on the listener's own network (looked up for names).
  final Future<bool> Function(String host) nonPublic;
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
      final (res, u) = await _get(chain, uri, headers, trusted);
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
    } finally {
      chain.close();
    }
  }

  /// Opens the episode at [uri] as a file for the player and the download
  /// manager. The file holds its request chain's allowance until it is
  /// closed, and every read goes through the same checks as the first one,
  /// so an address that starts redirecting inside the network later is
  /// refused too.
  Future<VirtualFile> openFile(
    Uri uri, {
    Set<String> trusted = const {},
  }) async {
    final chain = beginChain();
    try {
      final file = _PodcastFile._(this, chain, uri, trusted);
      await file._probe();
      return file;
    } on Object {
      chain.close();
      rethrow;
    }
  }

  /// One GET with its redirects followed through [_permit], returning the
  /// answer and where it came from.
  Future<(HttpStreamResponse, Uri)> _get(
    ChainAllowance chain,
    Uri uri,
    Map<String, String> headers,
    Set<String> trusted,
  ) async {
    var u = uri;
    for (var hop = 0; hop <= maxHops; hop++) {
      await _permit(chain, u, trusted);
      final res = await chain.run(
        () => send(
          HttpRequestData(method: 'GET', uri: u, headers: headers),
          maxRedirects: 0,
        ).timeout(timeout),
      );
      final next = _next(res, u);
      if (next == null) return (res, u);
      await res.body.drain<void>();
      u = next;
    }
    throw const PodcastHttpException('too many redirects');
  }

  /// Allows [u]'s host for the chain, unless it is on the listener's own
  /// network and not one they gave.
  Future<void> _permit(ChainAllowance chain, Uri u, Set<String> trusted) async {
    final host = normalizeHost(u.host);
    if (!trusted.contains(host) && await nonPublic(host)) {
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

/// An episode read by ranges through [PodcastHttp]: seekable when the server
/// honours `Range`, with a small block cache so the player's small reads stay
/// cheap.
final class _PodcastFile implements VirtualFile {
  _PodcastFile._(this._http, this._chain, this.uri, this._trusted) : _url = uri;

  static const int _blockSize = 256 << 10;
  static const int _maxBlocks = 16;

  final PodcastHttp _http;
  final ChainAllowance _chain;
  final Set<String> _trusted;

  @override
  final Uri uri;

  /// Where the reads go: where the redirects of the address ended.
  Uri _url;
  int? _length;
  bool _seekable = false;
  bool _closed = false;
  final _blocks = <int, Uint8List>{};
  Future<void> _turn = Future.value();

  @override
  bool get isSeekable => _seekable;

  @override
  Future<int?> length() async => _length;

  Future<void> _probe() => _guard(() async {
    final (res, at) = await _http._get(_chain, _url, const {
      'range': 'bytes=0-0',
    }, _trusted);
    _url = at;
    await res.body.drain<void>();
    HttpSession.check(res.statusCode, uri);
    if (res.statusCode == 206) {
      _seekable = true;
      final total = RegExp(r'/(\d+)$')
          .firstMatch(res.headers['content-range'] ?? '')
          ?.group(1);
      _length = total == null ? null : int.parse(total);
    } else {
      _length = int.tryParse(res.headers['content-length'] ?? '');
      _seekable = res.headers['accept-ranges']?.toLowerCase() == 'bytes';
    }
  });

  /// Maps what can go wrong to the file errors the callers understand.
  Future<T> _guard<T>(Future<T> Function() body) async {
    try {
      return await body();
    } on PodcastHttpException catch (e) {
      throw VirtualFileException(
        e.reason == 'private address'
            ? VirtualFileError.permissionDenied
            : VirtualFileError.io,
        uri,
        e.reason,
      );
    } on NetworkBlocked catch (e) {
      throw VirtualFileException(VirtualFileError.permissionDenied, uri, '$e');
    } on TimeoutException catch (e) {
      throw VirtualFileException(VirtualFileError.timeout, uri, '$e');
    } on SocketException catch (e) {
      throw VirtualFileException(VirtualFileError.unreachable, uri, e.message);
    } on HttpException catch (e) {
      throw VirtualFileException(VirtualFileError.io, uri, e.message);
    }
  }

  @override
  Future<Uint8List> read(int offset, int length) {
    if (_closed) {
      return Future.error(VirtualFileException(VirtualFileError.closed, uri));
    }
    RangeError.checkNotNegative(offset, 'offset');
    RangeError.checkNotNegative(length, 'length');
    // One request at a time: the reads share where the redirects ended.
    final turn = _turn.then((_) => _guard(() => _read(offset, length)));
    _turn = turn.then((_) {}, onError: (Object _) {});
    return turn;
  }

  Future<Uint8List> _read(int offset, int length) async {
    if (_closed) throw VirtualFileException(VirtualFileError.closed, uri);
    final size = _length;
    var end = offset + length;
    if (size != null && end > size) end = size;
    if (end <= offset) return Uint8List(0);
    if (!_seekable && offset != 0) {
      throw VirtualFileException(
        VirtualFileError.unsupported,
        uri,
        'server does not support ranges',
      );
    }
    // Large reads bypass the cache.
    if (end - offset > _blockSize * 4) return await _range(offset, end - 1);
    final out = BytesBuilder(copy: false);
    for (var b = offset ~/ _blockSize; b * _blockSize < end; b++) {
      final block = await _block(b);
      final from = b * _blockSize;
      final s = offset > from ? offset - from : 0;
      final e = end - from < block.length ? end - from : block.length;
      if (s >= e) break;
      out.add(Uint8List.sublistView(block, s, e));
      if (block.length < _blockSize) break;
    }
    return out.takeBytes();
  }

  Future<Uint8List> _block(int index) async {
    final cached = _blocks.remove(index);
    if (cached != null) {
      _blocks[index] = cached; // LRU touch
      return cached;
    }
    final start = index * _blockSize;
    var last = start + _blockSize - 1;
    final size = _length;
    if (size != null && last >= size) last = size - 1;
    final data = await _range(start, last);
    _blocks[index] = data;
    while (_blocks.length > _maxBlocks) {
      _blocks.remove(_blocks.keys.first);
    }
    return data;
  }

  Future<Uint8List> _range(int first, int last) async {
    final (res, at) = await _http._get(_chain, _url, {
      'range': 'bytes=$first-$last',
    }, _trusted);
    _url = at;
    if (res.statusCode == 416) {
      await res.body.drain<void>();
      return Uint8List(0);
    }
    HttpSession.check(res.statusCode, uri);
    final want = last - first + 1;
    final b = BytesBuilder(copy: false);
    var skipped = 0;
    await for (final chunk in res.body.timeout(_http.timeout)) {
      var c = chunk;
      if (res.statusCode == 200 && skipped < first) {
        // The server ignored the range: skip to [first].
        final need = first - skipped;
        if (c.length <= need) {
          skipped += c.length;
          continue;
        }
        c = c.sublist(need);
        skipped = first;
      }
      b.add(c);
      if (b.length >= want) break;
    }
    final bytes = b.takeBytes();
    return bytes.length > want ? Uint8List.sublistView(bytes, 0, want) : bytes;
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _blocks.clear();
    _chain.close();
  }
}
