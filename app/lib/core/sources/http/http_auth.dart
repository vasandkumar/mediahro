import 'dart:convert';
import 'dart:math';

// `crypto` is resolved through the workspace until the orchestrator adds it
// to app/pubspec.yaml (PR "Orchestrator changes needed").
// ignore: depend_on_referenced_packages
import 'package:crypto/crypto.dart';

/// HTTP authentication for user-added servers: Basic (HTTPS only, unless
/// the user allowed plain HTTP on the LAN), Digest (RFC 7616, MD5 and
/// SHA-256, qop=auth) and bearer tokens (cloud drives).
final class HttpAuth {
  HttpAuth({this.user, this.password, this.bearer, Random? random})
    : _random = random ?? Random.secure();

  final String? user;
  final String? password;

  /// OAuth access token; wins over user/password.
  String? bearer;
  final Random _random;
  _DigestChallenge? _digest;
  int _nc = 0;

  bool get hasCredentials => bearer != null || user != null;

  /// Header for the first attempt (pre-emptive when the scheme is known).
  String? headerFor(String method, Uri uri) {
    final b = bearer;
    if (b != null) return 'Bearer $b';
    final d = _digest;
    if (d != null) return _digestHeader(d, method, uri);
    if (user != null && uri.scheme == 'https') return _basic();
    return null;
  }

  /// Learns from a 401 `WWW-Authenticate` header. Returns whether a retry
  /// with [headerFor] can succeed.
  bool challenge(String? wwwAuthenticate, {required bool secure}) {
    if (wwwAuthenticate == null || user == null || bearer != null) return false;
    final h = wwwAuthenticate.trim();
    final lower = h.toLowerCase();
    final digestAt = lower.indexOf('digest ');
    if (digestAt >= 0) {
      final params = parseAuthParams(h.substring(digestAt + 7));
      final algo = (params['algorithm'] ?? 'MD5').toUpperCase();
      if (algo != 'MD5' &&
          algo != 'SHA-256' &&
          algo != 'MD5-SESS' &&
          algo != 'SHA-256-SESS') {
        return false;
      }
      final first = _digest == null;
      final stale = params['stale']?.toLowerCase() == 'true';
      _digest = _DigestChallenge(
        realm: params['realm'] ?? '',
        nonce: params['nonce'] ?? '',
        opaque: params['opaque'],
        qop:
            (params['qop'] ?? '')
                .split(',')
                .map((s) => s.trim())
                .contains('auth')
            ? 'auth'
            : null,
        algorithm: algo,
      );
      _nc = 0;
      return first || stale;
    }
    if (lower.startsWith('basic') || lower.contains(' basic')) {
      // Basic over plain HTTP only for LAN servers the user marked so.
      _basicAllowedInsecure = !secure && allowInsecureBasic;
      return secure || allowInsecureBasic;
    }
    return false;
  }

  /// User consent for Basic over plain HTTP (LAN WebDAV without TLS).
  bool allowInsecureBasic = false;
  bool _basicAllowedInsecure = false;

  /// Header to use after [challenge] for Basic.
  String? retryHeader(String method, Uri uri) {
    final d = _digest;
    if (d != null) return _digestHeader(d, method, uri);
    if (user != null && (uri.scheme == 'https' || _basicAllowedInsecure)) {
      return _basic();
    }
    return null;
  }

  String _basic() =>
      'Basic ${base64Encode(utf8.encode('$user:${password ?? ''}'))}';

  String _digestHeader(_DigestChallenge c, String method, Uri uri) {
    final hash = c.algorithm.startsWith('SHA-256') ? sha256 : md5;
    String h(String s) => hash.convert(utf8.encode(s)).toString();
    final cnonce = List.generate(
      16,
      (_) => _random.nextInt(16).toRadixString(16),
    ).join();
    final nc = (++_nc).toRadixString(16).padLeft(8, '0');
    var ha1 = h('$user:${c.realm}:${password ?? ''}');
    if (c.algorithm.endsWith('-SESS')) ha1 = h('$ha1:${c.nonce}:$cnonce');
    final path = uri.hasQuery ? '${uri.path}?${uri.query}' : uri.path;
    final ha2 = h('$method:$path');
    final response = c.qop == null
        ? h('$ha1:${c.nonce}:$ha2')
        : h('$ha1:${c.nonce}:$nc:$cnonce:${c.qop}:$ha2');
    final parts = <String>[
      'username="${_q(user!)}"',
      'realm="${_q(c.realm)}"',
      'nonce="${_q(c.nonce)}"',
      'uri="${_q(path)}"',
      'algorithm=${c.algorithm}',
      'response="$response"',
      if (c.opaque != null) 'opaque="${_q(c.opaque!)}"',
      if (c.qop != null) ...['qop=${c.qop}', 'nc=$nc', 'cnonce="$cnonce"'],
    ];
    return 'Digest ${parts.join(', ')}';
  }

  static String _q(String s) =>
      s.replaceAll(r'\', r'\\').replaceAll('"', r'\"');
}

final class _DigestChallenge {
  const _DigestChallenge({
    required this.realm,
    required this.nonce,
    required this.algorithm,
    this.opaque,
    this.qop,
  });

  final String realm;
  final String nonce;
  final String? opaque;
  final String? qop;
  final String algorithm;
}

/// `key=value, key="quoted, value"` pairs of an auth header.
Map<String, String> parseAuthParams(String s) {
  final out = <String, String>{};
  var i = 0;
  while (i < s.length) {
    while (i < s.length && (s[i] == ' ' || s[i] == ',')) {
      i++;
    }
    final eq = s.indexOf('=', i);
    if (eq < 0) break;
    final key = s.substring(i, eq).trim().toLowerCase();
    i = eq + 1;
    String value;
    if (i < s.length && s[i] == '"') {
      final b = StringBuffer();
      i++;
      while (i < s.length && s[i] != '"') {
        if (s[i] == r'\' && i + 1 < s.length) i++;
        b.write(s[i]);
        i++;
      }
      i++;
      value = b.toString();
    } else {
      final end = s.indexOf(',', i);
      value = s.substring(i, end < 0 ? s.length : end).trim();
      i = end < 0 ? s.length : end;
    }
    out[key] = value;
  }
  return out;
}
