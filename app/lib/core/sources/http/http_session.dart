import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:mediahro/core/net/network_policy.dart';
import 'package:mediahro/core/sources/http/http_auth.dart';
import 'package:mediahro_ffi/mediahro_ffi.dart';
import 'package:mediahro_servers/mediahro_servers.dart';

/// One user-added HTTP-family server: the gateway, credentials, custom
/// headers / user agent (NET-006) and error mapping to [VirtualFileError].
final class HttpSession {
  HttpSession(
    this.gateway, {
    HttpAuth? auth,
    this.headers = const {},
    this.timeout = const Duration(seconds: 30),
  }) : auth = auth ?? HttpAuth();

  final NetworkGateway gateway;
  final HttpAuth auth;
  final Map<String, String> headers;
  final Duration timeout;

  /// Sends with auth retry on 401. The response body is streamed.
  Future<HttpStreamResponse> send(
    String method,
    Uri uri, {
    Map<String, String> extra = const {},
    List<int>? body,
    Stream<List<int>> Function()? bodyStream,
    int? contentLength,
  }) async {
    for (var attempt = 0; attempt < 2; attempt++) {
      final authHeader = attempt == 0
          ? auth.headerFor(method, uri)
          : auth.retryHeader(method, uri);
      final req = HttpRequestData(
        method: method,
        uri: uri,
        headers: {
          ...headers,
          ...extra,
          'Authorization': ?authHeader,
          // A known-length body goes out with Content-Length, not chunked:
          // UPnP servers (MiniDLNA and most TVs and NASes) reject chunked
          // SOAP requests with 400 (NET-005).
          if (body != null && bodyStream == null && method != 'GET')
            'Content-Length': '${body.length}',
        },
        body: body,
      );
      final HttpStreamResponse res;
      try {
        res = await gateway
            .sendStreamed(
              req,
              bodyStream: bodyStream?.call(),
              contentLength: contentLength,
            )
            .timeout(timeout);
      } on TimeoutException catch (e) {
        throw VirtualFileException(VirtualFileError.timeout, uri, '$e');
      } on CertificateNotTrusted catch (e) {
        throw VirtualFileException(
          VirtualFileError.untrustedCertificate,
          uri,
          e.sha256,
        );
      } on NetworkBlocked catch (e) {
        throw VirtualFileException(
          VirtualFileError.permissionDenied,
          uri,
          '$e',
        );
      } on SocketException catch (e) {
        throw VirtualFileException(
          VirtualFileError.unreachable,
          uri,
          e.message,
        );
      } on HttpException catch (e) {
        throw VirtualFileException(VirtualFileError.io, uri, e.message);
      }
      if (res.statusCode == 401 && attempt == 0) {
        await res.body.drain<void>();
        if (auth.challenge(
          res.headers['www-authenticate'],
          secure: uri.scheme == 'https',
        )) {
          continue;
        }
        throw VirtualFileException(
          VirtualFileError.authenticationRequired,
          uri,
        );
      }
      return res;
    }
    throw VirtualFileException(VirtualFileError.authenticationRequired, uri);
  }

  /// Sends and reads the whole (bounded) body.
  Future<(int, Map<String, String>, Uint8List)> fetch(
    String method,
    Uri uri, {
    Map<String, String> extra = const {},
    List<int>? body,
    int maxBytes = 16 << 20,
  }) async {
    final res = await send(method, uri, extra: extra, body: body);
    final b = BytesBuilder(copy: false);
    await for (final chunk in res.body) {
      b.add(chunk);
      if (b.length > maxBytes) {
        throw VirtualFileException(
          VirtualFileError.io,
          uri,
          'response too large',
        );
      }
    }
    return (res.statusCode, res.headers, b.takeBytes());
  }

  /// Maps an HTTP status to a file error (null for success).
  static VirtualFileError? errorFor(int status) => switch (status) {
    >= 200 && < 300 => null,
    401 => VirtualFileError.authenticationRequired,
    403 => VirtualFileError.permissionDenied,
    404 || 410 => VirtualFileError.notFound,
    405 || 501 => VirtualFileError.unsupported,
    408 || 504 => VirtualFileError.timeout,
    409 || 412 => VirtualFileError.alreadyExists,
    507 => VirtualFileError.noSpace,
    _ => VirtualFileError.io,
  };

  static void check(int status, Uri uri) {
    final e = errorFor(status);
    if (e != null) throw VirtualFileException(e, uri, 'HTTP $status');
  }
}
