import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mediahro/core/db/library_database.dart';
import 'package:mediahro/core/net/network_policy.dart';
import 'package:mediahro/core/net/persistent_network_policy.dart';
import 'package:mediahro_servers/mediahro_servers.dart';

void main() {
  late LibraryDatabase db;

  setUp(() => db = LibraryDatabase.memory());
  tearDown(() => db.close());

  test(
    'PRIV-004 every endpoint starts off; toggles and last use persist',
    () async {
      final p = await PersistentNetworkPolicy.load(db);
      expect(p.endpoints.every((e) => !e.enabled), isTrue);
      await p.setEnabled(Endpoints.lrclib, enabled: true);
      final at = DateTime.utc(2026, 10, 19, 8);
      p.recordUse(Endpoints.lrclib, at);
      await p.flush();
      final again = await PersistentNetworkPolicy.load(db);
      final lrclib = again.endpoints.firstWhere(
        (e) => e.endpoint == Endpoints.lrclib,
      );
      expect(lrclib.enabled, isTrue);
      expect(lrclib.lastUsed, at);
      again.applyManagedOverlay({'lrclib'});
      expect(again.isEnabled(Endpoints.lrclib), isFalse);
      await p.dispose();
      await again.dispose();
    },
  );

  test('PRIV-004 hosts of added sources and servers are allowed; LAN discovery is switchable', () async {
    await db
        .into(db.sources)
        .insert(
          SourcesCompanion.insert(
            kind: SourceKind.webdav,
            name: 'Cloud',
            rootUri: 'davs://Cloud.Example.org/remote.php/dav/files/me/',
            addedAt: DateTime.utc(2026),
          ),
        );
    final p = await PersistentNetworkPolicy.load(db);
    expect(p.isUserConfiguredHost('cloud.example.org'), isTrue);
    expect(p.isUserConfiguredHost('192.168.1.20'), isTrue);
    expect(p.isUserConfiguredHost('nas.local'), isTrue);
    expect(p.isUserConfiguredHost('fd00::1'), isTrue);
    expect(p.isUserConfiguredHost('8.8.8.8'), isFalse);
    expect(p.isUserConfiguredHost('tracker.example.com'), isFalse);
    p.allowForSession('stream.example.com');
    expect(p.isUserConfiguredHost('stream.example.com'), isTrue);
    await p.setLanDiscovery(enabled: false);
    expect(p.isUserConfiguredHost('192.168.1.20'), isFalse);
    await p.dispose();
  });

  test(
    'PRIV-004 an allow scope is for the code running inside it, until '
    'it is closed; it adds nothing to the session or the dashboard',
    () async {
      final p = await PersistentNetworkPolicy.load(db);
      await p.setLanDiscovery(enabled: false);
      final a = p.beginAllowScope();
      final b = p.beginAllowScope();
      a.allow('CDN.Example.com');
      b.allow('other.example.com');
      // Nothing outside the scope, whatever else is going on, can use it.
      expect(p.isUserConfiguredHost('cdn.example.com'), isFalse);
      expect(p.userConfiguredHosts(), isEmpty);
      expect(a.run(() => p.isUserConfiguredHost('cdn.example.com')), isTrue);
      // Not another scope's hosts either.
      expect(a.run(() => p.isUserConfiguredHost('other.example.com')), isFalse);
      expect(b.run(() => p.isUserConfiguredHost('cdn.example.com')), isFalse);
      // It follows the work started inside it, across awaits.
      final later = await a.run(() async {
        await Future<void>.delayed(Duration.zero);
        return p.isUserConfiguredHost('cdn.example.com');
      });
      expect(later, isTrue);
      // A scope left open does not leak to code that was not started in it.
      final outside = Future<bool>(
        () => p.isUserConfiguredHost('cdn.example.com'),
      );
      expect(await outside, isFalse);
      a.close();
      expect(a.run(() => p.isUserConfiguredHost('cdn.example.com')), isFalse);
      expect(b.run(() => p.isUserConfiguredHost('other.example.com')), isTrue);
      b
        ..close()
        // Closing twice is harmless; the LAN switch is not bypassed.
        ..close();
      expect(b.run(() => p.isUserConfiguredHost('192.168.1.20')), isFalse);
      await p.dispose();
    },
  );

  test('CORE-015 dashboard API: injected toggles, last use per endpoint and per user host, change signal', () async {
    await db
        .into(db.sources)
        .insert(
          SourcesCompanion.insert(
            kind: SourceKind.smb,
            name: 'NAS',
            rootUri: 'smb://nas.local/media/',
            addedAt: DateTime.utc(2026),
          ),
        );
    final on = <String>{'musicbrainz'};
    final p = await PersistentNetworkPolicy.load(db, isToggledOn: on.contains);
    expect(p.isEnabled(Endpoints.musicBrainz), isTrue);
    expect(p.isEnabled(Endpoints.lrclib), isFalse);
    var changes = 0;
    final sub = p.changes.listen((_) => changes++);
    on.add('lrclib');
    p.notifyTogglesChanged();
    expect(p.isEnabled(Endpoints.lrclib), isTrue);
    expect(p.userConfiguredHosts(), ['nas.local']);
    final at = DateTime.utc(2026, 10, 19, 9);
    final gw = NetworkGateway(p, clock: () => at)
      ..authorize(Uri.parse('https://musicbrainz.org/ws/x'))
      ..authorize(Uri.parse('http://nas.local/x'));
    expect(p.lastUsed(Endpoints.musicBrainz), at);
    expect(p.hostLastUsed('NAS.local'), at);
    await Future<void>.delayed(Duration.zero);
    expect(changes, greaterThanOrEqualTo(3));
    p.applyManagedOverlay({'musicbrainz'});
    expect(p.isForcedOff(Endpoints.musicBrainz), isTrue);
    expect(p.isEnabled(Endpoints.musicBrainz), isFalse);
    gw.close();
    await sub.cancel();
    await p.dispose();
  });

  group('NET-006 gateway', () {
    late HttpServer server;
    late NetworkGateway gw;
    late PersistentNetworkPolicy policy;

    setUp(() async {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0)
        ..listen((r) async {
          switch (r.uri.path) {
            case '/bytes':
              final range = r.headers.value('range');
              r.response.statusCode = range == null ? 200 : 206;
              r.response.write(range == null ? 'abcdef' : 'cd');
            case '/hop':
              r.response.statusCode = 302;
              r.response.headers.set(
                'location',
                'https://tracker.example.com/x',
              );
            case '/local':
              r.response.statusCode = 301;
              r.response.headers.set('location', '/bytes');
            case '/ua':
              r.response.write(r.headers.value('user-agent'));
          }
          await r.response.close();
        });
      policy = await PersistentNetworkPolicy.load(db);
      gw = NetworkGateway(policy);
    });
    tearDown(() async {
      gw.close();
      await server.close(force: true);
      await policy.dispose();
    });

    Uri u(String path) => Uri.parse('http://127.0.0.1:${server.port}$path');

    test('streams bodies and passes range headers', () async {
      final res = await gw.sendStreamed(
        HttpRequestData(
          method: 'GET',
          uri: u('/bytes'),
          headers: const {'Range': 'bytes=2-3'},
        ),
      );
      expect(res.statusCode, 206);
      expect(utf8.decode(await res.body.expand((c) => c).toList()), 'cd');
    });

    test('follows redirects only to allowed hosts', () async {
      final ok = await gw.send(
        HttpRequestData(method: 'GET', uri: u('/local')),
      );
      expect(utf8.decode(ok.body), 'abcdef');
      expect(
        () => gw.send(HttpRequestData(method: 'GET', uri: u('/hop'))),
        throwsA(isA<NetworkBlocked>()),
      );
    });

    test('sends a neutral user agent', () async {
      final res = await gw.send(HttpRequestData(method: 'GET', uri: u('/ua')));
      expect(utf8.decode(res.body), 'Mediahro');
    });
  });

  test(
    'NET-003 self-signed certificates are identified by SHA-256 fingerprint',
    () {
      expect(
        certificateFingerprint(utf8.encode('abc')),
        'BA:78:16:BF:8F:01:CF:EA:41:41:40:DE:5D:AE:22:23:B0:03:61:A3:96:17:7A:9C:B4:10:FF:61:F2:00:15:AD',
      );
      final gw = NetworkGateway(_AllowAll())
        ..trustCertificate('NAS.local', 'aa:bb');
      expect(gw.trustedCertificates, {'nas.local': 'AA:BB'});
      gw.close();
    },
  );
}

final class _AllowAll implements NetworkPolicy {
  @override
  bool isEnabled(NetworkEndpoint endpoint) => true;

  @override
  bool isUserConfiguredHost(String host) => true;

  @override
  void recordUse(NetworkEndpoint endpoint, DateTime at) {}
}
