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

    /// Reuses the TLS session of an existing socket (FTPS data channels;
    /// vsftpd, FileZilla Server and ProFTPD require session reuse).
    String? resumeSessionOf,
  });

  /// Opens a plain TCP connection owned by the platform, for protocols that
  /// start in clear text and switch to TLS (FTPS explicit `AUTH TLS`). Pass
  /// its [TlsSocket.id] to [upgrade].
  Future<TlsSocket> connectPlain(
    String host,
    int port, {
    Duration timeout = const Duration(seconds: 15),
  });

  /// Upgrades a plain connection from [connectPlain] in place (FTPS explicit
  /// `AUTH TLS`).
  Future<TlsSocket> upgrade(
    String connectionId, {
    String? serverName,
    String? pinnedSha256,
  });
}

abstract interface class TlsSocket {
  /// Opaque id, also accepted by [TlsSocketFacade.upgrade] for data channels.
  String get id;

  /// False for a [TlsSocketFacade.connectPlain] socket not yet upgraded.
  bool get isTls;

  /// Negotiated protocol, `TLSv1.2` or `TLSv1.3`; empty while [isTls] is
  /// false. From `SSLSession.getProtocol()` (A), `sec_protocol_metadata_get_
  /// negotiated_tls_protocol_version` (I M), `SecPkgContext_ConnectionInfo`
  /// (W). NET-004 asserts TLS 1.2 or newer; CAST-001 likewise.
  String get protocolVersion;

  /// SHA-256 of the peer certificate, shown for trust-on-first-use prompts;
  /// empty while [isTls] is false.
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

/// Mutual-TLS listener for Mediahro-to-Mediahro sharing (NET-017, ADR-025)
/// on the OS TLS stack: SSLServerSocket (A), Network.framework NWListener
/// (I M), SChannel (W). The identity is a device key pair generated and kept
/// in the OS key store; peers are paired by QR and pinned by fingerprint.
abstract interface class TlsServerFacade {
  /// Creates (or returns) this device's identity under [label]; the private
  /// key never leaves the OS key store.
  Future<TlsIdentity> identity(String label);

  /// Listens on [port] (0 = any) and accepts only peers whose certificate
  /// SHA-256 is in [trustedPeers]; others are rejected in the handshake.
  Future<TlsListener> listen(
    TlsIdentity identity, {
    required Set<String> trustedPeers,
    int port = 0,
  });

  /// Connects to a paired peer presenting [identity] as the client
  /// certificate and pinning the peer's [peerSha256].
  Future<TlsSocket> connectMutual(
    String host,
    int port, {
    required TlsIdentity identity,
    required String peerSha256,
  });
}

@immutable
final class TlsIdentity {
  const TlsIdentity({required this.label, required this.certificateSha256});

  final String label;
  final String certificateSha256;
}

abstract interface class TlsListener {
  int get port;
  Stream<TlsSocket> get connections;

  /// Replaces the trusted set (pairing added or revoked).
  Future<void> setTrustedPeers(Set<String> sha256s);
  Future<void> close();
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
    this.keyPassphraseSecretRef,
    this.knownHostKeySha256,
  });

  final String host;
  final int port;
  final String username;

  /// Keys into `SecureStorageFacade` (PRIV-006); secrets never cross as values.
  final String? passwordSecretRef;
  final String? privateKeySecretRef;

  /// Passphrase of an encrypted private key, also a secure-storage ref.
  final String? keyPassphraseSecretRef;

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
  Future<void> mkdir(String path);

  /// Streams a new or replaced file (FILE-002 copy/move, FILE-005 upload).
  Future<SftpWriteSink> openWrite(String path, {bool truncate = true});
  Future<void> close();
}

abstract interface class SftpWriteSink {
  Future<void> write(Uint8List data);

  /// Flushes and closes; the file is complete only after this resolves.
  Future<void> close();

  /// Closes and removes the partial file.
  Future<void> abort();
}
