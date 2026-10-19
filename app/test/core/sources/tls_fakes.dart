import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:mediahro/core/net/network_policy.dart'
    show certificateFingerprint;
import 'package:mediahro/core/sources/ftp/ftp_transport.dart';
import 'package:mediahro/platform/platform_facades.dart';

// Test stand-ins for the operating system's TLS (ADR-017). Production TLS
// comes from TlsSocketFacade (C4); these use dart:io only inside tests.

Future<SecureSocket> _secure(
  String host,
  String? pin,
  Future<SecureSocket> Function(bool Function(X509Certificate) onBad) open,
) async {
  String? seen;
  try {
    return await open((c) {
      seen = certificateFingerprint(c.der);
      return seen == pin;
    });
  } on HandshakeException {
    if (seen case final fp?) throw UntrustedCertificate(host, fp);
    rethrow;
  }
}

/// A [TlsSocketFacade] as C4 will provide it, minus the upgrade path.
final class FakeTlsSocketFacade implements TlsSocketFacade {
  final List<(String, int, String?)> connects = [];

  @override
  Future<TlsSocket> connect(
    String host,
    int port, {
    String? serverName,
    String? pinnedSha256,
    List<String> alpn = const [],
    Duration timeout = const Duration(seconds: 15),
  }) async {
    connects.add((host, port, pinnedSha256));
    final s = await _secure(
      host,
      pinnedSha256,
      (onBad) => SecureSocket.connect(
        host,
        port,
        onBadCertificate: onBad,
        timeout: timeout,
      ),
    );
    return _FakeTlsSocket(s, 'tls-${connects.length}');
  }

  @override
  Future<TlsSocket> upgrade(
    String connectionId, {
    String? serverName,
    String? pinnedSha256,
  }) => throw UnimplementedError('no plain facade connections');
}

final class _FakeTlsSocket implements TlsSocket {
  _FakeTlsSocket(this._s, this.id);

  final SecureSocket _s;

  @override
  final String id;

  @override
  String get peerCertificateSha256 => _s.peerCertificate == null
      ? ''
      : certificateFingerprint(_s.peerCertificate!.der);

  @override
  Stream<Uint8List> get input => _s;

  @override
  Future<void> write(Uint8List data) async {
    _s.add(data);
    await _s.flush();
  }

  @override
  Future<void> close() => _s.close();
}

/// A transport that can also upgrade (explicit FTPS), standing in for the
/// facade once it offers plain connections; exercises the protocol logic.
final class StandInTlsTransport implements FtpTransport {
  const StandInTlsTransport();

  @override
  Future<FtpStream> connect(
    String host,
    int port, {
    required Duration timeout,
    bool tls = false,
    String? pin,
    FtpStream? sessionOf,
  }) async => SocketFtpStream(
    tls
        ? await _secure(
            host,
            pin,
            (onBad) => SecureSocket.connect(
              host,
              port,
              onBadCertificate: onBad,
              timeout: timeout,
            ),
          )
        : await Socket.connect(host, port, timeout: timeout),
  );

  @override
  Future<FtpStream> startTls(
    FtpStream plain, {
    required String host,
    required Duration timeout,
    String? pin,
  }) async => SocketFtpStream(
    await _secure(
      host,
      pin,
      (onBad) => SecureSocket.secure(
        (plain as SocketFtpStream).socket,
        host: host,
        onBadCertificate: onBad,
      ).timeout(timeout),
    ),
  );
}
