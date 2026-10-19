// WebDAV and DLNA against real servers in the docker-compose network
// environment (docs/11 §2). Run with MEDIAHRO_NET_ENV=1; skipped otherwise.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mediahro/core/net/network_policy.dart';
import 'package:mediahro/core/sources/dlna/dlna_discovery.dart';
import 'package:mediahro/core/sources/dlna/dlna_file_system.dart';
import 'package:mediahro/core/sources/dlna/upnp.dart';
import 'package:mediahro/core/sources/ftp/ftp_file_system.dart';
import 'package:mediahro/core/sources/ftp/ftp_transport.dart';
import 'package:mediahro/core/sources/http/http_auth.dart';
import 'package:mediahro/core/sources/http/http_session.dart';
import 'package:mediahro/core/sources/http/webdav_file_system.dart';
import 'package:mediahro_ffi/mediahro_ffi.dart';

import 'tls_fakes.dart';

final bool _enabled = Platform.environment['MEDIAHRO_NET_ENV'] == '1';
final String? _skip = _enabled
    ? null
    : 'set MEDIAHRO_NET_ENV=1 with the docker environment running';
final String _host = Platform.environment['MEDIAHRO_NET_HOST'] ?? '127.0.0.1';

int seedByte(int i) => (i * 131 + 7) & 0xff;

final class _Lan implements NetworkPolicy {
  @override
  bool isEnabled(NetworkEndpoint endpoint) => false;

  @override
  bool isUserConfiguredHost(String host) => true;

  @override
  void recordUse(NetworkEndpoint endpoint, DateTime at) {}
}

Future<void> _webdavContract(
  MutableFileSystem fs,
  Uri root, {
  String films = 'Films',
}) async {
  Uri child(Uri dir, String name) => dir.replace(
    pathSegments: [...dir.pathSegments.where((s) => s.isNotEmpty), name],
  );
  final top = await fs.list(root).toList();
  expect(top.map((e) => e.name), contains(films));
  final dir = top.firstWhere((e) => e.name == films);
  final movie = (await fs.list(dir.uri).toList()).firstWhere(
    (e) => e.name.endsWith('.mkv'),
  );
  expect(movie.size, 3 << 20);
  final f = await fs.open(movie.uri);
  for (final off in [0, 999, 1 << 20, (3 << 20) - 4]) {
    final got = await f.read(off, 4);
    expect(got, [for (var i = off; i < off + got.length; i++) seedByte(i)]);
  }
  await f.close();
  final tmp = await fs.createDirectory(
    root,
    'mediahro-${DateTime.now().microsecondsSinceEpoch}',
  );
  final w = await fs.create(child(tmp, 'up.txt'));
  await w.write(utf8.encode('dav upload'));
  await w.close();
  final back = await fs.open(child(tmp, 'up.txt'));
  expect(utf8.decode(await back.read(0, 100)), 'dav upload');
  await back.close();
  await fs.rename(child(tmp, 'up.txt'), 'moved.txt');
  await fs.delete(tmp, recursive: true);
}

void main() {
  late NetworkGateway gw;
  setUp(() => gw = NetworkGateway(_Lan()));
  tearDown(() => gw.close());

  group('NET-003 WebDAV', () {
    test('Apache mod_dav with Digest auth', () async {
      final fs = WebDavFileSystem(
        HttpSession(
          gw,
          auth: HttpAuth(user: 'test', password: 'testpass'),
        ),
      );
      await _webdavContract(fs, Uri.parse('dav://$_host:8080/digest/'));
    });

    test(
      'Apache mod_dav with Basic auth on a LAN server the user allowed',
      () async {
        final fs = WebDavFileSystem(
          HttpSession(
            gw,
            auth: HttpAuth(user: 'test', password: 'testpass')
              ..allowInsecureBasic = true,
          ),
        );
        await _webdavContract(fs, Uri.parse('dav://$_host:8080/basic/'));
      },
    );

    test('Nextcloud', () async {
      final fs = WebDavFileSystem(
        HttpSession(
          gw,
          auth: HttpAuth(user: 'test', password: 'testpass-Nextcloud-1')
            ..allowInsecureBasic = true,
        ),
      );
      final root = Uri.parse('dav://$_host:8081/remote.php/dav/files/test/');
      // Nextcloud starts empty: upload a seeded file first.
      final dir = await fs.createDirectory(root, 'Films');
      final w = await fs.create(dir.resolve('Movie.mkv'));
      await w.write([for (var i = 0; i < 3 << 20; i++) seedByte(i)]);
      await w.close();
      await _webdavContract(fs, root);
      await fs.delete(dir, recursive: true);
    });
  }, skip: _skip);

  group('NET-005 DLNA', () {
    test('MiniDLNA is discovered over SSDP and browsed and played', () async {
      final session = HttpSession(gw);
      final devices = await discoverMediaServers(
        session,
        timeout: const Duration(seconds: 4),
      ).toList();
      final d = devices.firstWhere(
        (d) => d.friendlyName == 'Mediahro Test DLNA',
      );
      final fs = DlnaFileSystem(
        session,
        d.service(UpnpDevice.contentDirectory)!,
      );
      final root = Uri.parse('dlna://${d.udn}/');
      final top = await fs.list(root).toList();
      expect(top, isNotEmpty);
      // MiniDLNA: Video → Folders → Films → Movie One (2024).mkv
      VirtualEntry? movie;
      Future<void> walk(Uri u, int depth) async {
        if (movie != null || depth > 4) return;
        for (final e in await fs.list(u).toList()) {
          if (!e.isDirectory && e.name.contains('Movie One')) {
            movie = e;
            return;
          }
          if (e.isDirectory) await walk(e.uri, depth + 1);
        }
      }

      await walk(root, 0);
      expect(movie, isNotNull);
      final f = await fs.open(movie!.uri);
      expect(await f.read(100, 4), [
        for (var i = 100; i < 104; i++) seedByte(i),
      ]);
      await f.close();
    });
  }, skip: _skip);

  group(
    'NET-004 FTP/FTPS client against vsftpd (TLS from the OS stand-in)',
    () {
      // Production TLS is TlsSocketFacade (ADR-017, C4); tests stand in.
      final osTls = FacadeFtpTransport(FakeTlsSocketFacade());
      Uri root(String scheme, int port) =>
          Uri(scheme: scheme, host: _host, port: port, path: '/');

      Future<void> extra(FtpFileSystem fs, Uri r) async {
        final big = await fs.open(r.replace(path: '/Large/sparse-5g.bin'));
        expect(await big.length(), 5 << 30);
        expect(await big.read((5 << 30) - 1, 1), [0x5A], reason: '64-bit REST');
        await big.close();
        final names = await fs.list(r).map((e) => e.name).toList();
        expect(names, contains('Spaces & Ünïcode'));
        await fs.close();
      }

      Future<String> fingerprint(FtpOptions o, Uri r) async {
        try {
          await FtpFileSystem(o, _Lan(), transport: osTls).stat(r);
        } on VirtualFileException catch (e) {
          expect(e.error, VirtualFileError.untrustedCertificate);
          return e.detail!;
        }
        fail('the self-signed certificate was accepted without a pin');
      }

      test('plain FTP', () async {
        final r = root('ftp', 21);
        final fs = FtpFileSystem(
          FtpOptions(host: _host, user: 'test', password: 'testpass'),
          _Lan(),
        );
        await _webdavContract(fs, r);
        await extra(fs, r);
      });

      for (final (name, scheme, port, security) in [
        ('explicit FTPS (AUTH TLS)', 'ftpes', 21, FtpSecurity.explicit),
        ('implicit FTPS on 990', 'ftps', 990, FtpSecurity.implicit),
      ]) {
        test('$name with a pinned self-signed certificate', () async {
          final r = root(scheme, port);
          FtpOptions options([String? pin]) => FtpOptions(
            host: _host,
            port: port,
            security: security,
            user: 'test',
            password: 'testpass',
            certSha256: pin,
          );
          final fs = FtpFileSystem(
            options(await fingerprint(options(), r)),
            _Lan(),
            transport: osTls,
          );
          await _webdavContract(fs, r);
          await extra(fs, r);
        });
      }
    },
    skip: _skip,
  );
}
