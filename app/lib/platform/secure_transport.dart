import 'dart:typed_data';

import 'package:meta/meta.dart';

/// TLS sockets from the operating system (ADR-017, docs/07 rule 12):
/// SSLSocket (A), Network.framework (I M), SChannel StreamSocket (W).
/// Used for FTPS (NET-004) and the Open Screen / CASTv2 sender (CAST-001)
/// so no third-party TLS library ships.
abstract interface class TlsSocketFacade {
  /// Opens a TLS connection. [pinnedSha256] accepts a self-signed
  /// certificate the user confirmed by fingerprint (docs/05 §9).
  Future<TlsSocket> connect(
    String host,
    int port, {
    String? serverName,
    String? pinnedSha256,
    List<String> alpn = const [],
    Duration timeout = const Duration(seconds: 15),
  });

  /// Upgrades an existing plain connection (FTPS explicit `AUTH TLS`).
  Future<TlsSocket> upgrade(
    String connectionId, {
    String? serverName,
    String? pinnedSha256,
  });
}

abstract interface class TlsSocket {
  /// Opaque id, also accepted by [TlsSocketFacade.upgrade] for data channels.
  String get id;

  /// SHA-256 of the peer certificate, shown for trust-on-first-use prompts.
  String get peerCertificateSha256;
  Stream<Uint8List> get input;
  Future<void> write(Uint8List data);
  Future<void> close();
}

/// Thrown when the peer certificate is untrusted and not pinned; carries the
/// fingerprint for the confirmation prompt.
final class UntrustedCertificate implements Exception {
  const UntrustedCertificate(this.host, this.sha256);

  final String host;
  final String sha256;

  @override
  String toString() => 'UntrustedCertificate($host, $sha256)';
}

/// SFTP over the platform's own SSH implementation (ADR-017): sshj over JCA
/// (A), SwiftNIO SSH over CryptoKit (I M), libssh2 with WinCNG (W).
abstract interface class SftpFacade {
  Future<SftpSession> connect(SftpEndpoint endpoint);
}

@immutable
final class SftpEndpoint {
  const SftpEndpoint({
    required this.host,
    required this.username,
    this.port = 22,
    this.passwordSecretRef,
    this.privateKeySecretRef,
    this.knownHostKeySha256,
  });

  final String host;
  final int port;
  final String username;

  /// Keys into `SecureStorageFacade` (PRIV-006); secrets never cross as values.
  final String? passwordSecretRef;
  final String? privateKeySecretRef;

  /// Host key the user confirmed; null on first connect.
  final String? knownHostKeySha256;
}

@immutable
final class SftpEntry {
  const SftpEntry({
    required this.path,
    required this.isDirectory,
    this.size,
    this.modified,
  });

  final String path;
  final bool isDirectory;
  final int? size;
  final DateTime? modified;
}

abstract interface class SftpSession {
  String get hostKeySha256;
  Future<List<SftpEntry>> list(String path);
  Future<SftpEntry> stat(String path);

  /// Random-access read for the `VirtualFile` contract (docs/05 §9).
  Future<Uint8List> read(String path, int offset, int length);
  Future<void> rename(String from, String to);
  Future<void> delete(String path);
  Future<void> close();
}
