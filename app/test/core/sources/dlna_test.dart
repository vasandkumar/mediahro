import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mediahro/core/net/network_policy.dart';
import 'package:mediahro/core/sources/discovery/ssdp.dart';
import 'package:mediahro/core/sources/dlna/dlna_discovery.dart';
import 'package:mediahro/core/sources/dlna/dlna_file_system.dart';
import 'package:mediahro/core/sources/dlna/upnp.dart';
import 'package:mediahro/core/sources/http/http_session.dart';
import 'package:mediahro_ffi/mediahro_ffi.dart';

import 'fake_upnp.dart';

final class _Lan implements NetworkPolicy {
  @override
  bool isEnabled(NetworkEndpoint endpoint) => false;

  @override
  bool isUserConfiguredHost(String host) => host == '127.0.0.1';

  @override
  void recordUse(NetworkEndpoint endpoint, DateTime at) {}
}

void main() {
  late FakeMediaServer server;
  late NetworkGateway gw;
  late HttpSession session;

  setUp(() async {
    server = await FakeMediaServer.start();
    gw = NetworkGateway(_Lan());
    session = HttpSession(gw);
  });
  tearDown(() async {
    gw.close();
    await server.close();
  });

  test(
    'NET-005 SSDP discovery finds the media server and reads its description',
    () async {
      final found = await discoverMediaServers(
        session,
        timeout: const Duration(milliseconds: 500),
        target: InternetAddress.loopbackIPv4,
        port: server.ssdpPort,
      ).toList();
      expect(found, hasLength(1));
      final d = found.single;
      expect(d.friendlyName, 'Fake NAS');
      expect(d.udn, 'uuid:fake-1');
      expect(d.iconUrl!.path, '/icon.png');
      expect(
        d.service(UpnpDevice.contentDirectory)!.controlUrl.path,
        '/cd/control',
      );
      expect(server.searches, greaterThanOrEqualTo(1));
    },
  );

  test(
    'NET-005 browse by path with paging and unique names; play by range reads',
    () async {
      final d = await fetchDevice(session, server.location);
      final fs = DlnaFileSystem(
        session,
        d.service(UpnpDevice.contentDirectory)!,
        pageSize: 2,
      );
      final root = Uri.parse('dlna://fake-1/');
      expect((await fs.list(root).toList()).map((e) => e.name), [
        'Video',
        'Music',
      ]);
      final video = await fs.list(root.resolve('Video/')).toList();
      expect(video.map((e) => e.name), [
        'Movie.mkv',
        'Movie.mkv [2]',
        'Clip & Co.mp4',
      ]);
      expect(video.first.size, 4096);
      final music = await fs.list(root.resolve('Music/')).toList();
      expect(music, hasLength(5), reason: 'paged in 2s');
      final f = await fs.open(video[1].uri);
      expect(await f.read(10, 3), [10, 11, 12]);
      expect(await f.length(), 4096);
      final o = await fs.describe(video.first.uri);
      expect(
        o!.duration,
        const Duration(minutes: 1, seconds: 2, milliseconds: 500),
      );
      final browses = server.browses;
      await fs.list(root.resolve('Video/')).toList();
      expect(server.browses, browses, reason: 'containers are cached');
      await expectLater(
        fs.list(root.resolve('Nope/')).toList(),
        throwsA(
          isA<VirtualFileException>().having(
            (e) => e.error,
            'error',
            VirtualFileError.notFound,
          ),
        ),
      );
    },
  );

  test('NET-005 SSDP parser handles responses and rejects garbage', () {
    final m = parseSsdp(
      'HTTP/1.1 200 OK\r\nLocation: http://x/d.xml\r\nst: upnp:rootdevice\r\nUSN: uuid:1\r\n\r\n'
          .codeUnits,
      InternetAddress.loopbackIPv4,
    )!;
    expect(
      (m.location, m.st, m.usn),
      ('http://x/d.xml', 'upnp:rootdevice', 'uuid:1'),
    );
    expect(parseSsdp('hello'.codeUnits, InternetAddress.loopbackIPv4), isNull);
    expect(
      String.fromCharCodes(ssdpSearch('ssdp:all')),
      contains('MAN: "ssdp:discover"'),
    );
  });
}
