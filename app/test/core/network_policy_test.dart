import 'package:flutter_test/flutter_test.dart';
import 'package:mediahro/core/net/network_policy.dart';

final class _Policy implements NetworkPolicy {
  _Policy({this.enabled = const {}, this.userHosts = const {}});

  final Set<String> enabled;
  final Set<String> userHosts;
  final Map<String, DateTime> used = {};

  @override
  bool isEnabled(NetworkEndpoint endpoint) => enabled.contains(endpoint.id);

  @override
  bool isUserConfiguredHost(String host) => userHosts.contains(host);

  @override
  void recordUse(NetworkEndpoint endpoint, DateTime at) =>
      used[endpoint.id] = at;
}

void main() {
  test(
    'PRIV-004 allow-listed endpoints are blocked until their toggle is on',
    () {
      final gw = NetworkGateway(_Policy());
      expect(
        () => gw.authorize(Uri.parse('https://lrclib.net/api/get')),
        throwsA(isA<NetworkBlocked>()),
      );
      gw.close();
    },
  );

  test('ADR-048 services that need a publisher key are not on the '
      'allow-list, even with every toggle on', () {
    expect(Endpoints.all.map((e) => e.id).toSet(), {
      'config',
      'crash',
      'analytics',
      'lrclib',
      'musicbrainz',
      'listenbrainz',
      'introdb',
    });
    final gw = NetworkGateway(
      _Policy(enabled: {for (final e in Endpoints.all) e.id}),
    );
    for (final host in const [
      'api.opensubtitles.com',
      'api.subdl.com',
      'www.podnapisi.net',
      'api.themoviedb.org',
      'image.tmdb.org',
      'api4.thetvdb.com',
      'api.acoustid.org',
      'ws.audioscrobbler.com',
      'libre.fm',
      'api.trakt.tv',
    ]) {
      expect(
        () => gw.authorize(Uri.parse('https://$host/x')),
        throwsA(isA<NetworkBlocked>()),
        reason: host,
      );
    }
    gw.close();
  });

  test(
    'PRIV-004 enabled endpoint is allowed and its last use recorded (CORE-015)',
    () {
      final at = DateTime.utc(2026, 10, 19);
      final policy = _Policy(enabled: {'lrclib'});
      final gw = NetworkGateway(policy, clock: () => at);
      expect(
        gw.authorize(Uri.parse('https://lrclib.net/api/get')),
        Endpoints.lrclib,
      );
      expect(policy.used['lrclib'], at);
      gw.close();
    },
  );

  test('PRIV-004 unknown hosts are refused unless the user added them', () {
    final gw = NetworkGateway(_Policy(userHosts: {'jellyfin.home.test'}));
    expect(gw.authorize(Uri.parse('https://jellyfin.home.test/Items')), isNull);
    expect(
      () => gw.authorize(Uri.parse('https://tracker.example.com/')),
      throwsA(isA<NetworkBlocked>()),
    );
    gw.close();
  });

  test('wildcard hosts match subdomains only', () {
    expect(Endpoints.musicBrainz.matches('ia800.us.archive.org'), isTrue);
    expect(Endpoints.musicBrainz.matches('archive.org.evil.test'), isFalse);
  });

  test('endpoint ids are unique (they are privacy toggle keys)', () {
    final ids = Endpoints.all.map((e) => e.id).toList();
    expect(ids.toSet().length, ids.length);
  });
}
