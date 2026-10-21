import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mediahro/platform/android/android_purchases.dart';
import 'package:mediahro/platform/platform_bindings.dart';
import 'package:mediahro/platform/platform_facades.dart';

/// Lane C4a: PurchasesFacade on an Android device (SUP-002). A side-loaded
/// build is not known to Play, so no product exists: this checks the rail is
/// wired and fails safely, not that a payment goes through (that is the
/// owner's internal-testing track with licence testers).
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final android = Platform.isAndroid;

  testWidgets('SUP-002 Android bindings provide purchases', (tester) async {
    final c = ProviderContainer(overrides: platformOverrides());
    addTearDown(c.dispose);
    expect(c.read(purchasesProvider), isA<AndroidPurchases>());
  }, skip: !android);

  testWidgets('SUP-002 support is answered without an exception', (
    tester,
  ) async {
    final p = AndroidPurchases();
    final supported = await p.isSupported();
    if (!supported) {
      // foss, direct and enterprise flavours, or no Play Store on the device.
      expect(await p.products({'tip_small'}), isEmpty);
      return;
    }
    final country = await p.storefrontCountry();
    if (country != null) expect(country, hasLength(2));
    expect(await p.products({'mediahro_unknown_product'}), isEmpty);
  }, skip: !android);

  testWidgets('SUP-002 purchasing an unknown product fails with a code', (
    tester,
  ) async {
    final p = AndroidPurchases();
    await expectLater(
      p.purchase('mediahro_unknown_product'),
      throwsA(isA<PlatformException>()),
    );
  }, skip: !android);

  testWidgets('SUP-002 updates is a stream that can be listened to', (
    tester,
  ) async {
    final sub = AndroidPurchases().updates.listen((_) {});
    await sub.cancel();
  }, skip: !android);
}
