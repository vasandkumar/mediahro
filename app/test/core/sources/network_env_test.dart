// WebDAV and DLNA against real servers in the docker-compose network
// environment (docs/11 §2). Run with MEDIAHRO_NET_ENV=1; skipped otherwise.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mediahro/core/net/network_policy.dart';
import 'package:mediahro/core/sources/dlna/dlna_discovery.dart';
import 'package:mediahro/core/sources/dlna/dlna_file_system.dart';
import 'package:mediahro/core/sources/dlna/upnp.dart';
import 'package:mediahro/core/sources/http/http_auth.dart';
import 'package:mediahro/core/sources/http/http_session.dart';
import 'package:mediahro/core/sources/http/webdav_file_system.dart';
import 'package:mediahro_ffi/mediahro_ffi.dart';

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
  WebDavFileSystem fs,
  Uri root, {
  String films = 'Films',
}) async {
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
  final w = await fs.create(tmp.resolve('up.txt'));
  await w.write(utf8.encode('dav upload'));
  await w.close();
  final back = await fs.open(tmp.resolve('up.txt'));
  expect(utf8.decode(await back.read(0, 100)), 'dav upload');
  await back.close();
  await fs.rename(tmp.resolve('up.txt'), 'moved.txt');
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
}
