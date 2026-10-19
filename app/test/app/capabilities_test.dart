import 'package:flutter_test/flutter_test.dart';
import 'package:mediahro/app/capabilities.dart';
import 'package:mediahro/app/flags.dart';

void main() {
  Capabilities caps(Flavor f, AppPlatform p) =>
      Capabilities(flavor: f, platform: p);

  test('default flavour is foss (most conservative)', () {
    expect(Flavor.current, Flavor.foss);
  });

  test('SUP-002 purchase rails only in store; donation links only in foss', () {
    for (final p in AppPlatform.values) {
      expect(caps(Flavor.store, p).platformPurchases, isTrue);
      expect(caps(Flavor.foss, p).platformPurchases, isFalse);
      expect(caps(Flavor.foss, p).donationLinks, isTrue);
      expect(caps(Flavor.direct, p).donationLinks, isFalse);
    }
  });

  test('SUP-003 store web link needs a storefront check except on Windows', () {
    expect(
      caps(Flavor.store, AppPlatform.ios).webSupportLinkNeedsStorefrontCheck,
      isTrue,
    );
    expect(
      caps(
        Flavor.store,
        AppPlatform.android,
      ).webSupportLinkNeedsStorefrontCheck,
      isTrue,
    );
    expect(
      caps(
        Flavor.store,
        AppPlatform.windows,
      ).webSupportLinkNeedsStorefrontCheck,
      isFalse,
    );
    expect(
      caps(Flavor.direct, AppPlatform.macos).webSupportLinkNeedsStorefrontCheck,
      isFalse,
    );
  });

  test(
    'CAST-001 Cast SDK only in store mobile builds; FOSS uses Open Screen',
    () {
      expect(caps(Flavor.store, AppPlatform.android).googleCastSdk, isTrue);
      expect(caps(Flavor.store, AppPlatform.ios).googleCastSdk, isTrue);
      expect(caps(Flavor.store, AppPlatform.windows).googleCastSdk, isFalse);
      expect(caps(Flavor.foss, AppPlatform.android).googleCastSdk, isFalse);
      expect(caps(Flavor.foss, AppPlatform.android).openScreenCast, isTrue);
    },
  );

  test('SYS-007 sandbox only for Mac App Store; CORE-012 self-updater only direct desktop', () {
    expect(caps(Flavor.store, AppPlatform.macos).sandboxed, isTrue);
    expect(caps(Flavor.direct, AppPlatform.macos).sandboxed, isFalse);
    expect(caps(Flavor.direct, AppPlatform.windows).selfUpdater, isTrue);
    expect(caps(Flavor.direct, AppPlatform.android).selfUpdater, isFalse);
    expect(caps(Flavor.store, AppPlatform.windows).selfUpdater, isFalse);
  });

  test('docs/09 section 4: software VVC off in store builds', () {
    expect(caps(Flavor.store, AppPlatform.windows).vvcSoftwareDecoder, isFalse);
    expect(caps(Flavor.foss, AppPlatform.android).vvcSoftwareDecoder, isTrue);
  });

  test('PRIV-001 network features default off in every flavour', () {
    for (final f in Flavor.values) {
      expect(caps(f, AppPlatform.android).networkFeaturesDefaultOn, isFalse);
    }
  });

  test('flags: unknown flags are rejected, overrides turn flags on', () {
    expect(Flags.defaults.isOn('m1.engine'), isFalse);
    expect(Flags.defaults.withOverrides('m1.engine').isOn('m1.engine'), isTrue);
    expect(() => Flags.defaults.withOverrides('nope'), throwsArgumentError);
  });
}
