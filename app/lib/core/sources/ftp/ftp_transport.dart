import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:mediahro/platform/platform_facades.dart';

/// A byte stream the FTP client talks over: a plain dart:io socket or a TLS
/// socket from the operating system (ADR-017).
abstract interface class FtpStream {
  Stream<Uint8List> get input;
  Future<void> write(List<int> data);

  /// Graceful end (FIN, or TLS close_notify then FIN).
  Future<void> close();
  void destroy();
}

/// Opens control and data connections. TLS never comes from a bundled
/// library: [FacadeFtpTransport] uses [TlsSocketFacade] (SSLSocket,
/// Network.framework, SChannel), plain FTP uses dart:io sockets.
abstract interface class FtpTransport {
  /// [tls] with [pin]: implicit FTPS control or a protected data channel.
  /// [sessionOf] names the control connection whose TLS session a data
  /// channel should resume (servers that require session reuse).
  Future<FtpStream> connect(
    String host,
    int port, {
    required Duration timeout,
    bool tls = false,
    String? pin,
    FtpStream? sessionOf,
  });

  /// Explicit FTPS: turns the plain control connection into TLS after the
  /// server accepted `AUTH TLS`.
  Future<FtpStream> startTls(
    FtpStream plain, {
    required String host,
    required Duration timeout,
    String? pin,
  });
}

/// The transport cannot provide TLS (no facade on this platform yet).
final class FtpTlsUnavailable implements Exception {
  const FtpTlsUnavailable(this.reason);

  final String reason;

  @override
  String toString() => 'FtpTlsUnavailable($reason)';
}

final class SocketFtpStream implements FtpStream {
  SocketFtpStream(this.socket);

  final Socket socket;

  @override
  Stream<Uint8List> get input => socket;

  @override
  Future<void> write(List<int> data) async {
    socket.add(data);
    await socket.flush();
  }

  @override
  Future<void> close() async {
    await socket.close();
  }

  @override
  void destroy() => socket.destroy();
}

Future<FtpStream> _plain(String host, int port, Duration timeout) async =>
    SocketFtpStream(await Socket.connect(host, port, timeout: timeout));

/// Plain FTP only.
final class SocketFtpTransport implements FtpTransport {
  const SocketFtpTransport();

  @override
  Future<FtpStream> connect(
    String host,
    int port, {
    required Duration timeout,
    bool tls = false,
    String? pin,
    FtpStream? sessionOf,
  }) => tls
      ? Future.error(const FtpTlsUnavailable('no TLS socket facade'))
      : _plain(host, port, timeout);

  @override
  Future<FtpStream> startTls(
    FtpStream plain, {
    required String host,
    required Duration timeout,
    String? pin,
  }) => Future.error(const FtpTlsUnavailable('no TLS socket facade'));
}

/// FTPS through the operating system's TLS (ADR-017): every connection of
/// an FTPS source is a platform socket, so the explicit `AUTH TLS` upgrade
/// happens in place and data channels resume the control session.
final class FacadeFtpTransport implements FtpTransport {
  const FacadeFtpTransport(this.tls);

  final TlsSocketFacade tls;

  @override
  Future<FtpStream> connect(
    String host,
    int port, {
    required Duration timeout,
    bool tls = false,
    String? pin,
    FtpStream? sessionOf,
  }) async => TlsFtpStream(
    tls
        ? await this.tls.connect(
            host,
            port,
            serverName: host,
            pinnedSha256: pin,
            timeout: timeout,
            resumeSessionOf: sessionOf is TlsFtpStream && sessionOf.socket.isTls
                ? sessionOf.socket.id
                : null,
          )
        : await this.tls.connectPlain(host, port, timeout: timeout),
  );

  @override
  Future<FtpStream> startTls(
    FtpStream plain, {
    required String host,
    required Duration timeout,
    String? pin,
  }) async {
    if (plain is! TlsFtpStream) {
      throw const FtpTlsUnavailable(
        'control connection is not a platform socket',
      );
    }
    return TlsFtpStream(
      await tls
          .upgrade(plain.socket.id, serverName: host, pinnedSha256: pin)
          .timeout(timeout),
    );
  }
}

final class TlsFtpStream implements FtpStream {
  TlsFtpStream(this.socket);

  final TlsSocket socket;

  @override
  Stream<Uint8List> get input => socket.input;

  @override
  Future<void> write(List<int> data) =>
      socket.write(data is Uint8List ? data : Uint8List.fromList(data));

  @override
  Future<void> close() => socket.close();

  @override
  void destroy() => unawaited(socket.close().catchError((Object _) {}));
}
