import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediahro/platform/android/android_network.dart';
import 'package:mediahro/platform/android/gen/network_api.pigeon.dart';
import 'package:mediahro/platform/auth_browser.dart';
import 'package:mediahro/platform/network_status.dart';

/// The Dart half of lane C4a's network facades.
final class _FakeMulticast extends MulticastHostApi {
  final released = <int>[];

  @override
  Future<int> acquire(String tag) async => 7;

  @override
  Future<void> release(int leaseId) async => released.add(leaseId);
}

final class _FakeAuth extends AuthBrowserHostApi {
  _FakeAuth([this.error]);

  final PlatformException? error;

  @override
  Future<String> authorize(String authorizationUrl, String redirectUri) async {
    if (error case final e?) throw e;
    return '$redirectUri?code=1';
  }
}

void main() {
  final idp = Uri.parse('https://idp.example/auth');

  test(
    'NET-018 network states map through and repeat only on change',
    () async {
      final events = StreamController<NetworkStateMsg>();
      final status = AndroidNetworkStatus(events: () => events.stream);
      final got = <NetworkState>[];
      final sub = status.changes().listen(got.add);
      NetworkStateMsg wifi() => NetworkStateMsg(
        transport: NetworkTransportMsg.wifi,
        metered: false,
        constrained: false,
      );
      events
        ..add(wifi())
        ..add(wifi())
        ..add(
          NetworkStateMsg(
            transport: NetworkTransportMsg.cellular,
            metered: true,
            constrained: true,
          ),
        );
      await pumpEventQueue();
      await sub.cancel();
      expect(got, const [
        NetworkState(transport: NetworkTransport.wifi, metered: false),
        NetworkState(
          transport: NetworkTransport.cellular,
          metered: true,
          constrained: true,
        ),
      ]);
    },
  );

  test('NET-005 a lease releases its lock once', () async {
    final api = _FakeMulticast();
    final lease = await AndroidMulticast(api: api).acquire('t');
    await lease.release();
    await lease.release();
    expect(api.released, [7]);
  });

  test('NET-007 the redirect comes back as a URI', () async {
    final back = await AndroidAuthBrowser(api: _FakeAuth())
        .authorize(idp, AndroidAuthBrowser.redirectUri);
    expect(back.queryParameters['code'], '1');
  });

  test('NET-007 a closed tab is AuthCancelled; other errors pass', () async {
    await expectLater(
      AndroidAuthBrowser(api: _FakeAuth(PlatformException(code: 'cancelled')))
          .authorize(idp, AndroidAuthBrowser.redirectUri),
      throwsA(isA<AuthCancelled>()),
    );
    await expectLater(
      AndroidAuthBrowser(api: _FakeAuth(PlatformException(code: 'noBrowser')))
          .authorize(idp, AndroidAuthBrowser.redirectUri),
      throwsA(isA<PlatformException>()),
    );
  });
}
