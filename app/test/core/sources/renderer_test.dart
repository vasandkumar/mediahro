import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mediahro/core/net/network_policy.dart';
import 'package:mediahro/core/sources/discovery/ssdp.dart';
import 'package:mediahro/core/sources/dlna/renderer.dart';
import 'package:mediahro/core/sources/dlna/upnp.dart';
import 'package:mediahro/core/sources/http/http_session.dart';

final class _Lan implements NetworkPolicy {
  @override
  bool isEnabled(NetworkEndpoint endpoint) => false;

  @override
  bool isUserConfiguredHost(String host) => host == '127.0.0.1';

  @override
  void recordUse(NetworkEndpoint endpoint, DateTime at) {}
}

final class _Sink implements RendererSink {
  RendererStatus _s = const RendererStatus();
  final _c = StreamController<RendererStatus>.broadcast();
  final calls = <String>[];

  void _set(RendererStatus s) {
    _s = s;
    _c.add(s);
  }

  @override
  RendererStatus get status => _s;

  @override
  Stream<RendererStatus> get changes => _c.stream;

  @override
  Future<void> load(Uri uri, {required String metadata}) async {
    calls.add('load $uri');
    _set(
      _s.copyWith(
        uri: uri,
        metadata: metadata,
        state: TransportState.stopped,
        duration: const Duration(minutes: 90),
      ),
    );
  }

  @override
  Future<void> play() async {
    calls.add('play');
    _set(_s.copyWith(state: TransportState.playing));
  }

  @override
  Future<void> pause() async => _set(_s.copyWith(state: TransportState.paused));

  @override
  Future<void> stop() async => _set(_s.copyWith(state: TransportState.stopped));

  @override
  Future<void> seek(Duration position) async {
    calls.add('seek $position');
    _set(_s.copyWith(position: position));
  }

  @override
  Future<void> setVolume(int volume) async => _set(_s.copyWith(volume: volume));

  @override
  Future<void> setMute({required bool muted}) async =>
      _set(_s.copyWith(muted: muted));
}

void main() {
  late DlnaRenderer renderer;
  late _Sink sink;
  late NetworkGateway gw;
  final allowed = <String>[];

  setUp(() async {
    sink = _Sink();
    gw = NetworkGateway(_Lan());
    renderer = DlnaRenderer(
      friendlyName: 'Living room <Mediahro>',
      uuid: '1234-abcd',
      sink: sink,
      gateway: gw,
      allowHost: allowed.add,
      ssdpListenPort: 0,
      advertiseAddress: InternetAddress.loopbackIPv4,
    );
    await renderer.start();
  });
  tearDown(() async {
    await renderer.stop();
    gw.close();
  });

  test('NET-005 renderer answers SSDP searches and describes itself as a MediaRenderer', () async {
    final hits = await ssdpDiscover(
      'urn:schemas-upnp-org:device:MediaRenderer:1',
      timeout: const Duration(milliseconds: 400),
      target: InternetAddress.loopbackIPv4,
      port: renderer.boundSsdpPort,
    ).toList();
    expect(hits.single.location, renderer.location.toString());
    expect(
      hits.single.usn,
      'uuid:1234-abcd::urn:schemas-upnp-org:device:MediaRenderer:1',
    );
    final d = await fetchDevice(HttpSession(gw), renderer.location);
    expect(d.friendlyName, 'Living room <Mediahro>');
    expect(d.deviceType, 'urn:schemas-upnp-org:device:MediaRenderer:1');
    expect(d.services.map((s) => s.serviceType.split(':')[3]).toSet(), {
      'AVTransport',
      'RenderingControl',
      'ConnectionManager',
    });
  });

  test(
    'NET-005 control points push, play, seek and query state; volume and mute',
    () async {
      final session = HttpSession(gw);
      final d = await fetchDevice(session, renderer.location);
      final avt = d.service('urn:schemas-upnp-org:service:AVTransport')!;
      final rc = d.service('urn:schemas-upnp-org:service:RenderingControl')!;
      await soapCall(session, avt, 'SetAVTransportURI', {
        'InstanceID': '0',
        'CurrentURI': 'http://192.168.1.5:8200/MediaItems/22.mkv',
        'CurrentURIMetaData': '<DIDL-Lite/>',
      });
      await soapCall(session, avt, 'Play', {'InstanceID': '0', 'Speed': '1'});
      await soapCall(session, avt, 'Seek', {
        'InstanceID': '0',
        'Unit': 'REL_TIME',
        'Target': '0:10:05',
      });
      expect(sink.calls, [
        'load http://192.168.1.5:8200/MediaItems/22.mkv',
        'play',
        'seek 0:10:05.000000',
      ]);
      expect(allowed, ['192.168.1.5']);
      final info = await soapCall(session, avt, 'GetTransportInfo', {
        'InstanceID': '0',
      });
      expect(info['CurrentTransportState'], 'PLAYING');
      final pos = await soapCall(session, avt, 'GetPositionInfo', {
        'InstanceID': '0',
      });
      expect((pos['RelTime'], pos['TrackDuration']), ('0:10:05', '1:30:00'));
      await soapCall(session, rc, 'SetVolume', {
        'InstanceID': '0',
        'Channel': 'Master',
        'DesiredVolume': '30',
      });
      expect(
        (await soapCall(session, rc, 'GetVolume', {
          'InstanceID': '0',
          'Channel': 'Master',
        }))['CurrentVolume'],
        '30',
      );
      await expectLater(
        soapCall(session, avt, 'SetAVTransportURI', {
          'InstanceID': '0',
          'CurrentURI': 'file:///etc/passwd',
          'CurrentURIMetaData': '',
        }),
        throwsA(isA<UpnpError>()),
      );
      await expectLater(
        soapCall(session, avt, 'Record', {'InstanceID': '0'}),
        throwsA(isA<UpnpError>()),
      );
    },
  );

  test('NET-005 GENA subscriptions receive LastChange events', () async {
    final callback = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final events = <String>[];
    final got = Completer<void>();
    callback.listen((r) async {
      events.add(
        await r
            .cast<List<int>>()
            .transform(const SystemEncoding().decoder)
            .join(),
      );
      r.response.statusCode = 200;
      await r.response.close();
      if (events.length >= 2 && !got.isCompleted) got.complete();
    });
    final client = HttpClient();
    final req = await client.openUrl(
      'SUBSCRIBE',
      renderer.location.resolve('/avt/event'),
    );
    req.headers
      ..set('CALLBACK', '<http://127.0.0.1:${callback.port}/cb>')
      ..set('NT', 'upnp:event')
      ..set('TIMEOUT', 'Second-300');
    final res = await req.close();
    await res.drain<void>();
    expect(res.headers.value('sid'), startsWith('uuid:'));
    await sink.play();
    await got.future.timeout(const Duration(seconds: 3));
    expect(events.last, contains('PLAYING'));
    client.close(force: true);
    await callback.close(force: true);
  });

  test('NET-005 UPnP time format', () {
    expect(
      formatUpnpTime(const Duration(hours: 1, minutes: 2, seconds: 3)),
      '1:02:03',
    );
  });
}
