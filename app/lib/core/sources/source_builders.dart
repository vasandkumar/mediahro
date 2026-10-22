import 'package:mediahro/core/db/library_database.dart';
import 'package:mediahro/core/files/media_store_file_system.dart';
import 'package:mediahro/core/files/saf_file_system.dart';
import 'package:mediahro/core/net/network_policy.dart';
import 'package:mediahro/core/net/persistent_network_policy.dart'
    show isLocalNetworkHost;
import 'package:mediahro/core/sources/dlna/dlna_file_system.dart';
import 'package:mediahro/core/sources/dlna/upnp.dart';
import 'package:mediahro/core/sources/ftp/ftp_file_system.dart';
import 'package:mediahro/core/sources/ftp/ftp_transport.dart';
import 'package:mediahro/core/sources/http/http_auth.dart';
import 'package:mediahro/core/sources/http/http_session.dart';
import 'package:mediahro/core/sources/http/webdav_file_system.dart';
import 'package:mediahro/core/sources/sftp/sftp_file_system.dart';
import 'package:mediahro/core/sources/source_access.dart';
import 'package:mediahro/platform/platform_facades.dart';
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

/// File system builders per protocol for [DefaultSourceResolver]. Most run
/// wherever the scan runs (a worker isolate), so they capture only the
/// sendable [SourceSpec] and create their own gateway for that host.
///
/// FTP/FTPS and SFTP follow ADR-017 (OS crypto only): FTPS takes TLS from
/// [tls] and SFTP runs on [sftp]; both facades live on the main isolate, so
/// those kinds are in [mainIsolateSourceKinds]. Without a facade the source
/// reports `unsupported` ("not available on this device").
///
/// Local sources dispatch on the root's scheme (LIB-002): `saf` (Android
/// SAF tree, via [storage]) → [SafFileSystem], `mediastore` (Android device
/// media) → [MediaStoreFileSystem], anything else → [LocalFileSystem]
/// (desktop folders and Apple security-scoped roots, read with dart:io).
Map<SourceKind, FileSystemBuilder> defaultFileSystemBuilders({
  TlsSocketFacade? tls,
  SftpFacade? sftp,
  StorageFacade? storage,
  FdIo? fdIo,
}) {
  return {
    SourceKind.local: (s) => switch (s.root.scheme) {
      'saf' => SafFileSystem(
        _storage(storage, s),
        tree: Uri.parse(s.options['safTree'] ?? ''),
        root: s.root,
        io: fdIo,
      ),
      // Video, audio and pictures (screenshots, camera) of the device.
      'mediastore' => MediaStoreFileSystem(_storage(storage, s), io: fdIo),
      _ => const LocalFileSystem(),
    },
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
    SourceKind.ftp: (s) => FtpFileSystem(
      _ftp(s),
      SourceOnlyPolicy([s.root.host]),
      // Plain FTP stays on dart:io; FTPS is entirely the OS TLS stack.
      transport: tls == null || _ftp(s).security == FtpSecurity.none
          ? const SocketFtpTransport()
          : FacadeFtpTransport(tls),
    ),
    SourceKind.sftp: (s) => sftp == null
        ? throw VirtualFileException(
            VirtualFileError.unsupported,
            s.root,
            'no SFTP facade on this platform yet',
          )
        : SftpFileSystem(sftp, sftpEndpoint(s)),
    SourceKind.dlna: (s) => DlnaFileSystem(
      _session(s, extraHosts: [Uri.parse(s.options['controlUrl'] ?? '').host]),
      UpnpService(
        serviceType: '${UpnpDevice.contentDirectory}1',
        controlUrl: Uri.parse(s.options['controlUrl'] ?? ''),
      ),
    ),
  };
}

StorageFacade _storage(StorageFacade? s, SourceSpec spec) =>
    s ??
    (throw VirtualFileException(
      VirtualFileError.unsupported,
      spec.root,
      'device storage needs the platform storage facade',
    ));

/// Sources whose file systems talk to platform facades.
const Set<SourceKind> mainIsolateSourceKinds = {
  SourceKind.ftp,
  SourceKind.sftp,
};

/// The facade endpoint of an SFTP source: secrets by reference only.
SftpEndpoint sftpEndpoint(SourceSpec s) {
  final key = s.credentialKey;
  final keyAuth = s.options['auth'] == 'key';
  return SftpEndpoint(
    host: s.root.host,
    port: s.root.hasPort ? s.root.port : 22,
    username: s.userName ?? '',
    passwordSecretRef: key == null || keyAuth
        ? null
        : SftpSecretRefs(key).password,
    privateKeySecretRef: key == null || !keyAuth
        ? null
        : SftpSecretRefs(key).privateKey,
    // For key auth always; an absent entry means the key is not encrypted.
    keyPassphraseSecretRef: key == null || !keyAuth
        ? null
        : SftpSecretRefs(key).keyPassphrase,
    knownHostKeySha256: s.options['hostKeySha256'],
  );
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
