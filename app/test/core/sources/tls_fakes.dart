import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:mediahro/core/net/network_policy.dart'
    show certificateFingerprint;
import 'package:mediahro/platform/platform_facades.dart';

// A stand-in for the operating system's TLS (ADR-017). Production TLS comes
// from TlsSocketFacade (C4: SSLSocket, Network.framework, SChannel); this
// fake uses dart:io inside tests only.

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

/// A [TlsSocketFacade] as C4 provides it: plain sockets it can upgrade in
/// place, pinned TLS connections and session-reuse requests (recorded).
///
/// dart:io never reports a peer's close_notify; it ends a stream only on
/// TCP EOF. OS TLS (SSLSocket, Network.framework, SChannel) ends it on
/// close_notify, and FTPS servers such as vsftpd send close_notify on a data
/// channel and then wait for the client's before closing TCP. With
/// [opensslDataChannels] (Linux, real servers) data channels go through
/// `openssl s_client`, which ends its output on close_notify like the OS
/// does, trusting the certificate the control connection pinned.
final class FakeTlsSocketFacade implements TlsSocketFacade {
  FakeTlsSocketFacade({this.opensslDataChannels = false});

  final bool opensslDataChannels;
  final List<(String, int, String?)> connects = [];
  final List<String> plainConnects = [];
  final List<String> upgrades = [];
  final List<String?> resumed = [];
  final Map<String, _FakeTlsSocket> _sockets = {};
  var _ids = 0;

  _FakeTlsSocket _register(Socket s, {required bool tls}) {
    final f = _FakeTlsSocket(s, 'sock-${++_ids}', isTls: tls);
    _sockets[f.id] = f;
    return f;
  }

  @override
  Future<TlsSocket> connect(
    String host,
    int port, {
    String? serverName,
    String? pinnedSha256,
    List<String> alpn = const [],
    Duration timeout = const Duration(seconds: 15),
    String? resumeSessionOf,
  }) async {
    connects.add((host, port, pinnedSha256));
    resumed.add(resumeSessionOf);
    final control = resumeSessionOf == null ? null : _sockets[resumeSessionOf];
    if (opensslDataChannels && control != null) {
      final cert = switch (control._s) {
        final SecureSocket t => t.peerCertificate,
        _ => null,
      };
      if (cert != null &&
          (pinnedSha256 == null ||
              certificateFingerprint(cert.der) == pinnedSha256)) {
        return await _OpensslTlsSocket.connect(
          host,
          port,
          cert,
          'sock-${++_ids}',
          timeout,
        );
      }
    }
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
    return _register(s, tls: true);
  }

  @override
  Future<TlsSocket> connectPlain(
    String host,
    int port, {
    Duration timeout = const Duration(seconds: 15),
  }) async {
    plainConnects.add('$host:$port');
    return _register(
      await Socket.connect(host, port, timeout: timeout),
      tls: false,
    );
  }

  @override
  Future<TlsSocket> upgrade(
    String connectionId, {
    String? serverName,
    String? pinnedSha256,
  }) async {
    upgrades.add(connectionId);
    final plain = _sockets.remove(connectionId);
    if (plain == null || plain.isTls) {
      throw StateError('no plain socket $connectionId');
    }
    final host = serverName ?? plain._s.remoteAddress.address;
    final s = await _secure(
      host,
      pinnedSha256,
      (onBad) =>
          SecureSocket.secure(plain._s, host: host, onBadCertificate: onBad),
    );
    return _register(s, tls: true);
  }
}

final class _FakeTlsSocket implements TlsSocket {
  _FakeTlsSocket(this._s, this.id, {required this.isTls});

  final Socket _s;

  @override
  final String id;

  @override
  final bool isTls;

  // Stand-in value: dart:io does not report the negotiated protocol (the
  // real facade does); the network-env suite checks it with openssl.
  @override
  String get protocolVersion => isTls ? 'TLSv1.3' : '';

  @override
  String get peerCertificateSha256 => switch (_s) {
    final SecureSocket t when t.peerCertificate != null =>
      certificateFingerprint(t.peerCertificate!.der),
    _ => '',
  };

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

/// A TLS client connection through `openssl s_client`, trusting exactly
/// the given certificate (self-signed: it is its own root). Its output ends when the
/// server sends close_notify; closing stdin sends ours.
final class _OpensslTlsSocket implements TlsSocket {
  _OpensslTlsSocket._(this._p, this.id, this._fingerprint, this._dir);

  static Future<TlsSocket> connect(
    String host,
    int port,
    X509Certificate cert,
    String id,
    Duration timeout,
  ) async {
    final dir = Directory.systemTemp.createTempSync('mediahro-tls');
    final ca = File('${dir.path}/ca.pem')..writeAsStringSync(cert.pem);
    final p = await Process.start('openssl', [
      's_client',
      '-connect',
      '$host:$port',
      '-CAfile',
      ca.path,
      '-verify_return_error',
      '-partial_chain',
      '-quiet',
      '-no_ign_eof',
    ]).timeout(timeout);
    unawaited(p.stderr.drain<void>());
    return _OpensslTlsSocket._(p, id, certificateFingerprint(cert.der), dir);
  }

  final Process _p;
  final String _fingerprint;
  final Directory _dir;

  @override
  final String id;

  @override
  bool get isTls => true;

  @override
  String get protocolVersion => 'TLSv1.3';

  @override
  String get peerCertificateSha256 => _fingerprint;

  @override
  Stream<Uint8List> get input =>
      _p.stdout.map((b) => b is Uint8List ? b : Uint8List.fromList(b));

  @override
  Future<void> write(Uint8List data) async {
    _p.stdin.add(data);
    await _p.stdin.flush();
  }

  @override
  Future<void> close() async {
    try {
      await _p.stdin.close();
      await _p.exitCode.timeout(const Duration(seconds: 5));
    } on TimeoutException {
      _p.kill();
    } finally {
      if (_dir.existsSync()) _dir.deleteSync(recursive: true);
    }
  }
}
