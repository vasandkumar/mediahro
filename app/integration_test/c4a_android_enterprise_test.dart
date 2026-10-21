import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mediahro/platform/android/android_enterprise.dart';
import 'package:mediahro/platform/platform_bindings.dart';
import 'package:mediahro/platform/platform_facades.dart';

/// Lane C4a: managed configuration and kiosk on an Android device (B2B-001,
/// B2B-002). The phone is not enrolled, so the managed map is empty; the
/// kiosk is never entered here because lock task mode pins the owner's screen.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final android = Platform.isAndroid;

  testWidgets('B2B-001 Android bindings provide managed config and kiosk', (
    tester,
  ) async {
    final c = ProviderContainer(overrides: platformOverrides());
    addTearDown(c.dispose);
    expect(c.read(managedConfigProvider), isA<AndroidManagedConfig>());
    expect(c.read(kioskProvider), isA<AndroidKiosk>());
  }, skip: !android);

  testWidgets('B2B-001 an unmanaged phone has no managed values', (
    tester,
  ) async {
    expect(await AndroidManagedConfig().read(), isEmpty);
  }, skip: !android);

  testWidgets('B2B-001 the change stream can be listened to and cancelled', (
    tester,
  ) async {
    final sub = AndroidManagedConfig().changes.listen((_) {});
    await sub.cancel();
  }, skip: !android);

  testWidgets('B2B-002 kiosk is supported and reports inactive', (
    tester,
  ) async {
    final kiosk = AndroidKiosk();
    expect(await kiosk.isSupported(), isTrue);
    expect(await kiosk.isActive.first, isFalse);
  }, skip: !android);

  testWidgets('B2B-002 start on boot works only in the enterprise build', (
    tester,
  ) async {
    // store, direct and foss builds have no boot receiver and answer with an
    // UnsupportedError; the enterprise build completes. (Not anyOf(completes, ...):
    // an async matcher inside anyOf reports its failure after the test has ended.)
    final outcome = await AndroidKiosk()
        .setStartOnBoot(enabled: false)
        .then<Object?>((_) => null, onError: (Object e) => e);
    expect(outcome, anyOf(isNull, isA<UnsupportedError>()));
  }, skip: !android);
}
