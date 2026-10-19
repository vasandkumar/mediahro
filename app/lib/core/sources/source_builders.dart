import 'dart:io';

import 'package:mediahro/core/db/library_database.dart';
import 'package:mediahro/core/net/network_policy.dart';
import 'package:mediahro/core/net/persistent_network_policy.dart'
    show isLocalNetworkHost;
import 'package:mediahro/core/sources/dlna/dlna_file_system.dart';
import 'package:mediahro/core/sources/dlna/upnp.dart';
import 'package:mediahro/core/sources/ftp/ftp_file_system.dart';
import 'package:mediahro/core/sources/http/http_auth.dart';
import 'package:mediahro/core/sources/http/http_session.dart';
import 'package:mediahro/core/sources/http/webdav_file_system.dart';
import 'package:mediahro/core/sources/source_access.dart';
import 'package:mediahro_ffi/mediahro_ffi.dart';

/// Allows exactly one source's host (and nothing on the allow-list): what a
/// file system built inside a scan isolate may contact.
final class SourceOnlyPolicy implements NetworkPolicy {
  SourceOnlyPolicy(Iterable<String> hosts)
    : _hosts = {for (final h in hosts) h.toLowerCase()};

  final Set<String> _hosts;

  @override
  bool isEnabled(NetworkEndpoint endpoint) => false;

  @override
  bool isUserConfiguredHost(String host) => _hosts.contains(host.toLowerCase());

  @override
  void recordUse(NetworkEndpoint endpoint, DateTime at) {}
}

/// File system builders per protocol for [DefaultSourceResolver]. Each runs
/// wherever the scan runs (a worker isolate), so it captures only the
/// sendable [SourceSpec] and creates its own gateway for that host.
///
/// [nativeCurl] is false on Apple, where libcurl has no TLS backend and no
/// libssh2 ships (mediahro-deps): FTP/FTPS then use [FtpFileSystem] and
/// SFTP reports `unsupported` until an SSH fallback lands (STATUS §3).
Map<SourceKind, FileSystemBuilder> defaultFileSystemBuilders({
  String? keyDirectory,
  bool? nativeCurl,
}) {
  final curl = nativeCurl ?? !(Platform.isIOS || Platform.isMacOS);
  return {
    SourceKind.local: (_) => const LocalFileSystem(),
    SourceKind.smb: (s) => smbFileSystem(
      s.root,
      smbOptionsFromUri(
        s.root,
        user: s.userName,
        password: s.secret,
        guest: s.options['guest'] == 'true',
      ).withOptions(s.options),
    ),
    SourceKind.nfs: (s) => nfsFileSystem(
      s.root,
      NfsOptions(
        server: s.root.host,
        export: s.options['export'] ?? s.root.path,
        version: int.tryParse(s.options['version'] ?? '') ?? 3,
      ),
    ),
    SourceKind.webdav: (s) => WebDavFileSystem(_session(s)),
    SourceKind.ftp: (s) => curl
        ? curlFileSystem(s.root, _curl(s, keyDirectory))
        : FtpFileSystem(_ftp(s), SourceOnlyPolicy([s.root.host])),
    SourceKind.sftp: (s) => curl
        ? curlFileSystem(s.root, _curl(s, keyDirectory))
        : throw VirtualFileException(
            VirtualFileError.unsupported,
            s.root,
            'SFTP needs libssh2, which mediahro-deps does not build for Apple',
          ),
    SourceKind.dlna: (s) => DlnaFileSystem(
      _session(s, extraHosts: [Uri.parse(s.options['controlUrl'] ?? '').host]),
      UpnpService(
        serviceType: '${UpnpDevice.contentDirectory}1',
        controlUrl: Uri.parse(s.options['controlUrl'] ?? ''),
      ),
    ),
  };
}

FtpOptions _ftp(SourceSpec s) => FtpOptions(
  host: s.root.host,
  port: s.root.hasPort ? s.root.port : null,
  security: switch (s.root.scheme) {
    'ftps' => FtpSecurity.implicit,
    'ftpes' => FtpSecurity.explicit,
    _ =>
      s.options['tls'] == 'explicit' ? FtpSecurity.explicit : FtpSecurity.none,
  },
  user: s.userName,
  password: s.secret,
  certSha256: s.options['certSha256'],
);

HttpSession _session(SourceSpec s, {List<String> extraHosts = const []}) {
  final wire = WebDavFileSystem.wire(s.root);
  final hosts = [wire.host, ...extraHosts];
  final gw = NetworkGateway(SourceOnlyPolicy(hosts));
  final auth = HttpAuth(user: s.userName, password: s.secret)
    // Basic over plain HTTP only on the LAN and only if the user said so.
    ..allowInsecureBasic =
        s.options['allowInsecureBasic'] == 'true' &&
        isLocalNetworkHost(wire.host);
  if (s.options['certSha256'] case final String fp) {
    gw.trustCertificate(wire.host, fp);
  }
  return HttpSession(gw, auth: auth);
}

CurlOptions _curl(SourceSpec s, String? keyDirectory) {
  final protocol = switch (s.root.scheme) {
    'sftp' => CurlProtocol.sftp,
    'ftps' => CurlProtocol.ftps,
    'ftpes' => CurlProtocol.ftpes,
    _ => s.options['tls'] == 'explicit' ? CurlProtocol.ftpes : CurlProtocol.ftp,
  };
  final keyAuth = s.options['auth'] == 'key';
  return CurlOptions(
    protocol: protocol,
    host: s.root.host,
    port: s.root.hasPort ? s.root.port : null,
    rootPath: s.root.path.isEmpty ? '/' : Uri.decodeComponent(s.root.path),
    user: s.userName,
    password: keyAuth ? null : s.secret,
    privateKeyPem: keyAuth ? s.secret : null,
    keyPassphrase: s.options['keyPassphrase'],
    hostKeySha256: s.options['hostKeySha256'],
    allowUntrustedTls: s.options['allowUntrustedTls'] == 'true',
    keyDirectory: keyDirectory,
  );
}

extension on SmbOptions {
  SmbOptions withOptions(Map<String, String> o) => SmbOptions(
    server: server,
    share: share,
    user: user,
    password: password,
    domain: o['domain'] ?? domain,
    port: port,
    guest: guest,
    version:
        SmbVersion.values.where((v) => v.name == o['version']).firstOrNull ??
        version,
    encrypt: o['encrypt'] == 'true',
    sign: o['sign'] == 'true',
  );
}
