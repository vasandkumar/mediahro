import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mediahro/platform/android/android_network.dart';
import 'package:mediahro/platform/platform_bindings.dart';
import 'package:mediahro/platform/platform_facades.dart';

/// Lane C4a: NetworkStatusFacade, MulticastFacade and AuthBrowserFacade on
/// an Android device. The sign-in tests open a Custom Tab on a local address
/// (nothing leaves the device). A debug-only hook (`mediahro.test/net`)
/// fires the provider's redirect as a VIEW intent, or returns to the app
/// the way closing the tab does.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final android = Platform.isAndroid;

  const hook = BasicMessageChannel<Object?>(
    'mediahro.test/net',
    StandardMessageCodec(),
  );
  Future<Object?> op(String name, [Object? arg]) => hook.send([name, arg]);

  // A local address: the tab shows an error page, and no request leaves
  // the device.
  final signInPage = Uri.parse('http://127.0.0.1:9/authorize?state=xyz');

  testWidgets('NET-019 Android bindings provide the network facades', (
    tester,
  ) async {
    final c = ProviderContainer(overrides: platformOverrides());
    addTearDown(c.dispose);
    expect(c.read(networkStatusProvider), isA<AndroidNetworkStatus>());
    expect(c.read(multicastProvider), isA<AndroidMulticast>());
    expect(c.read(authBrowserProvider), isA<AndroidAuthBrowser>());
  }, skip: !android);

  testWidgets(
    'NET-019 current network state, also first on the change stream',
    (tester) async {
      final status = AndroidNetworkStatus();
      final now = await status.current();
      expect(NetworkTransport.values, contains(now.transport));
      if (now.transport == NetworkTransport.cellular) {
        expect(now.metered, isTrue);
      }
      final first = await status.changes().first.timeout(
        const Duration(seconds: 5),
      );
      expect(first, now);
    },
    skip: !android,
  );

  testWidgets('NET-005 multicast leases hold the Wi-Fi lock until released', (
    tester,
  ) async {
    final multicast = AndroidMulticast();
    final before = (await op('multicastHeld'))! as int;
    final a = await multicast.acquire('mediahro-ssdp');
    final b = await multicast.acquire('mediahro-mdns');
    expect(await op('multicastHeld'), before + 2);
    await a.release();
    await a.release(); // A second release is a no-op.
    expect(await op('multicastHeld'), before + 1);
    await b.release();
    expect(await op('multicastHeld'), before);
  }, skip: !android);

  testWidgets('NET-007 sign-in completes on the app redirect', (tester) async {
    final browser = AndroidAuthBrowser();
    final result = browser.authorize(
      signInPage,
      AndroidAuthBrowser.redirectUri,
    );
    unawaited(result.then((_) {}, onError: (Object _) {}));
    await Future<void>.delayed(const Duration(seconds: 2));
    await op(
      'redirect',
      '${AndroidAuthBrowser.redirectUri}?code=abc&state=xyz',
    );
    final back = await result.timeout(const Duration(seconds: 10));
    expect(back.scheme, 'com.mediahro.app');
    expect(back.path, '/oauth2redirect');
    expect(back.queryParameters, {'code': 'abc', 'state': 'xyz'});
  }, skip: !android);

  testWidgets('NET-007 closing the browser without a redirect cancels', (
    tester,
  ) async {
    final browser = AndroidAuthBrowser();
    final result = browser.authorize(
      signInPage,
      AndroidAuthBrowser.redirectUri,
    );
    unawaited(result.then((_) {}, onError: (Object _) {}));
    await Future<void>.delayed(const Duration(seconds: 2));
    await op('returnToApp');
    await expectLater(
      result.timeout(const Duration(seconds: 10)),
      throwsA(isA<AuthCancelled>()),
    );
  }, skip: !android);

  testWidgets('NET-007 redirects outside the app scheme are refused', (
    tester,
  ) async {
    await expectLater(
      AndroidAuthBrowser().authorize(
        signInPage,
        Uri.parse('http://127.0.0.1:8123/callback'),
      ),
      throwsA(
        isA<PlatformException>().having(
          (e) => e.code,
          'code',
          'unsupportedRedirect',
        ),
      ),
    );
  }, skip: !android);
}
