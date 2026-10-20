import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:mediahro/core/sources/http/http_session.dart';
import 'package:mediahro/platform/auth_browser.dart';
import 'package:meta/meta.dart';

/// OAuth 2.0 endpoints of a provider (authorization code + PKCE, RFC 7636).
@immutable
final class OAuthConfig {
  const OAuthConfig({
    required this.authorize,
    required this.token,
    required this.scopes,
    required this.clientId,
    this.extraAuthParams = const {},
    this.scopeSeparator = ' ',
  });

  final Uri authorize;
  final Uri token;
  final List<String> scopes;

  /// Public client id (owner task: registered per provider, STATUS.md §4);
  /// no client secret ships in the app.
  final String clientId;
  final Map<String, String> extraAuthParams;
  final String scopeSeparator;
}

@immutable
final class OAuthTokens {
  const OAuthTokens({
    required this.accessToken,
    required this.expiresAt,
    this.refreshToken,
  });

  factory OAuthTokens.decode(String json) {
    final m = jsonDecode(json) as Map<String, Object?>;
    return OAuthTokens(
      accessToken: m['access']! as String,
      refreshToken: m['refresh'] as String?,
      expiresAt: DateTime.parse(m['exp']! as String),
    );
  }

  final String accessToken;
  final String? refreshToken;
  final DateTime expiresAt;

  bool expiredAt(DateTime now) =>
      !now.isBefore(expiresAt.subtract(const Duration(minutes: 1)));

  /// Stored as the credential secret (SecureStorageFacade only, PRIV-006).
  String encode() => jsonEncode({
    'access': accessToken,
    'refresh': refreshToken,
    'exp': expiresAt.toUtc().toIso8601String(),
  });
}

final class OAuthError implements Exception {
  const OAuthError(this.code, [this.description]);

  final String code;
  final String? description;

  @override
  String toString() =>
      'OAuthError($code${description == null ? '' : ': $description'})';
}

/// PKCE authorization-code flow and token refresh over [HttpSession]
/// (NetworkGateway, ADR-014).
final class OAuthClient {
  OAuthClient(
    this.config,
    this.session, {
    Random? random,
    DateTime Function()? clock,
  }) : _random = random ?? Random.secure(),
       _clock = clock ?? DateTime.now;

  final OAuthConfig config;
  final HttpSession session;
  final Random _random;
  final DateTime Function() _clock;

  /// Runs the full sign-in with [browser]; [redirectUri] must be registered
  /// for the client id (custom scheme on mobile, loopback on desktop).
  Future<OAuthTokens> signIn(AuthBrowserFacade browser, Uri redirectUri) async {
    final verifier = _randomString(64);
    final state = _randomString(24);
    final url = authorizationUrl(redirectUri, verifier: verifier, state: state);
    final back = await browser.authorize(url, redirectUri);
    final q = back.queryParameters;
    if (q['error'] != null) {
      throw OAuthError(q['error']!, q['error_description']);
    }
    if (q['state'] != state) throw const OAuthError('state_mismatch');
    final code = q['code'];
    if (code == null) throw const OAuthError('no_code');
    return await _tokenRequest({
      'grant_type': 'authorization_code',
      'code': code,
      'redirect_uri': redirectUri.toString(),
      'code_verifier': verifier,
    });
  }

  Uri authorizationUrl(
    Uri redirectUri, {
    required String verifier,
    required String state,
  }) => config.authorize.replace(
    queryParameters: {
      ...config.authorize.queryParameters,
      'response_type': 'code',
      'client_id': config.clientId,
      'redirect_uri': redirectUri.toString(),
      'scope': config.scopes.join(config.scopeSeparator),
      'state': state,
      'code_challenge': pkceChallenge(verifier),
      'code_challenge_method': 'S256',
      ...config.extraAuthParams,
    },
  );

  Future<OAuthTokens> refresh(OAuthTokens tokens) async {
    final r = tokens.refreshToken;
    if (r == null) throw const OAuthError('no_refresh_token');
    final fresh = await _tokenRequest({
      'grant_type': 'refresh_token',
      'refresh_token': r,
    });
    // Some providers do not rotate refresh tokens.
    return fresh.refreshToken == null
        ? OAuthTokens(
            accessToken: fresh.accessToken,
            expiresAt: fresh.expiresAt,
            refreshToken: r,
          )
        : fresh;
  }

  Future<OAuthTokens> _tokenRequest(Map<String, String> form) async {
    final body = Uri(queryParameters: {...form, 'client_id': config.clientId})
        .query;
    final (status, _, bytes) = await session.fetch(
      'POST',
      config.token,
      extra: {
        'Content-Type': 'application/x-www-form-urlencoded',
        'Accept': 'application/json',
      },
      body: utf8.encode(body),
      maxBytes: 64 * 1024,
    );
    final Object? j;
    try {
      j = jsonDecode(utf8.decode(bytes));
    } on FormatException {
      throw OAuthError('bad_response', 'HTTP $status');
    }
    if (j is! Map<String, Object?>) throw const OAuthError('bad_response');
    if (status != 200 || j['access_token'] == null) {
      throw OAuthError(
        '${j['error'] ?? 'http_$status'}',
        j['error_description'] as String?,
      );
    }
    final expires = (j['expires_in'] as num?)?.toInt() ?? 3600;
    return OAuthTokens(
      accessToken: j['access_token']! as String,
      refreshToken: j['refresh_token'] as String?,
      expiresAt: _clock().add(Duration(seconds: expires)),
    );
  }

  String _randomString(int n) {
    const chars =
        'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~';
    return String.fromCharCodes(
      List.generate(n, (_) => chars.codeUnitAt(_random.nextInt(chars.length))),
    );
  }
}

/// S256 code challenge (RFC 7636 §4.2).
String pkceChallenge(String verifier) => base64Url
    .encode(sha256.convert(ascii.encode(verifier)).bytes)
    .replaceAll('=', '');

/// Desktop redirect target: a one-shot HTTP listener on 127.0.0.1
/// (RFC 8252 §7.3). [next] answers the browser with `doneHtml`.
final class LoopbackRedirect {
  LoopbackRedirect._(this._server);

  static Future<LoopbackRedirect> start() async => LoopbackRedirect._(
    await HttpServer.bind(InternetAddress.loopbackIPv4, 0),
  );

  final HttpServer _server;

  Uri get redirectUri => Uri.parse('http://127.0.0.1:${_server.port}/callback');

  /// Completes with the first request to `/callback`.
  Future<Uri> next({
    required String doneHtml,
    Duration timeout = const Duration(minutes: 5),
  }) async {
    try {
      await for (final r in _server.timeout(timeout)) {
        if (r.uri.path != '/callback') {
          r.response.statusCode = 404;
          await r.response.close();
          continue;
        }
        r.response.headers.contentType = ContentType.html;
        r.response.write(doneHtml);
        await r.response.close();
        return r.requestedUri;
      }
      throw const OAuthError('cancelled');
    } on TimeoutException {
      throw const OAuthError('timeout');
    } finally {
      await _server.close(force: true);
    }
  }
}
