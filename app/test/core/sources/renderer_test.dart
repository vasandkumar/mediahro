import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mediahro/core/net/network_policy.dart';
import 'package:mediahro/core/sources/discovery/ssdp.dart';
import 'package:mediahro/core/sources/dlna/renderer.dart';
import 'package:mediahro/core/sources/dlna/upnp.dart';
import 'package:mediahro/core/sources/http/http_session.dart';
import 'package:mediahro/platform/platform_facades.dart';

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
    // NOTIFYs are handled concurrently, so their arrival order here is not
    // their send order: record each with its SEQ and wait for the one that
    // carries the PLAYING change instead of taking the latest.
    final events = <(String?, String)>[];
    final playing = Completer<void>();
    callback.listen((r) async {
      final body = await r
          .cast<List<int>>()
          .transform(const SystemEncoding().decoder)
          .join();
      events.add((r.headers.value('seq'), body));
      r.response.statusCode = 200;
      await r.response.close();
      if (body.contains('PLAYING') && !playing.isCompleted) {
        playing.complete();
      }
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
    await playing.future.timeout(
      const Duration(seconds: 10),
      onTimeout: () => fail('no LastChange with PLAYING; got $events'),
    );
    // The initial event (SEQ 0) carries the state before the change.
    expect(events.map((e) => e.$1), contains('0'));
    expect(
      events.where((e) => e.$2.contains('PLAYING')).map((e) => e.$1),
      everyElement(isNot('0')),
    );
    client.close(force: true);
    await callback.close(force: true);
  });

  test(
    'NET-005 GENA event keys count from 0 per subscription and arrive in order',
    () async {
      final callback = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final seqs = <String, List<int>>{};
      final enough = Completer<void>();
      callback.listen((r) async {
        await r.drain<void>();
        final sid = r.headers.value('sid')!;
        (seqs[sid] ??= []).add(int.parse(r.headers.value('seq')!));
        r.response.statusCode = 200;
        await r.response.close();
        if (seqs.length == 2 &&
            seqs.values.every((l) => l.length >= 3) &&
            !enough.isCompleted) {
          enough.complete();
        }
      });
      final client = HttpClient();
      for (final service in ['avt', 'rc']) {
        final req = await client.openUrl(
          'SUBSCRIBE',
          renderer.location.resolve('/$service/event'),
        );
        req.headers
          ..set('CALLBACK', '<http://127.0.0.1:${callback.port}/cb>')
          ..set('NT', 'upnp:event')
          ..set('TIMEOUT', 'Second-300');
        await (await req.close()).drain<void>();
      }
      await sink.play();
      await sink.setVolume(40);
      await sink.pause();
      await enough.future.timeout(
        const Duration(seconds: 10),
        onTimeout: () => fail('too few events: $seqs'),
      );
      for (final l in seqs.values) {
        expect(l.take(3), [0, 1, 2], reason: '$seqs');
      }
      client.close(force: true);
      await callback.close(force: true);
    },
  );

  test(
    'NET-005 the renderer holds the multicast lease only while running',
    () async {
      final leases = <String>[];
      var released = 0;
      final r = DlnaRenderer(
        friendlyName: 'Lease',
        uuid: 'lease-1',
        sink: sink,
        gateway: gw,
        ssdpListenPort: 0,
        advertiseAddress: InternetAddress.loopbackIPv4,
        multicast: _Multicast(leases.add, () => released++),
      );
      await r.start();
      await r.start();
      expect(leases, ['mediahro-dlna-renderer'], reason: 'one lease per run');
      await r.stop();
      expect(released, 1);
      await r.stop();
      expect(released, 1);
    },
  );

  test('NET-005 UPnP time format', () {
    expect(
      formatUpnpTime(const Duration(hours: 1, minutes: 2, seconds: 3)),
      '1:02:03',
    );
  });
}

final class _Multicast implements MulticastFacade {
  _Multicast(this.onAcquire, this.onRelease);

  final void Function(String) onAcquire;
  final void Function() onRelease;

  @override
  Future<MulticastLease> acquire(String tag) async {
    onAcquire(tag);
    return _Lease(onRelease);
  }
}

final class _Lease implements MulticastLease {
  _Lease(this.onRelease);

  final void Function() onRelease;

  @override
  Future<void> release() async => onRelease();
}
