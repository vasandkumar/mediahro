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
final class FakeTlsSocketFacade implements TlsSocketFacade {
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
