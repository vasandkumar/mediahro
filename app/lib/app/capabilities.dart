import 'package:flutter/foundation.dart';

/// Build flavours (docs/05 §11), chosen at compile time with
/// `--dart-define=MEDIAHRO_FLAVOR=<name>` plus the matching Gradle flavour.
enum Flavor {
  /// App Store, Mac App Store, Google Play, Microsoft Store.
  store,

  /// Notarised macOS DMG, Windows installer + winget.
  direct,

  /// F-Droid and GitHub releases: no proprietary SDKs.
  foss,

  /// MDM / custom app distribution.
  enterprise;

  static Flavor parse(String value) =>
      Flavor.values.asNameMap()[value] ??
      (throw ArgumentError.value(value, 'MEDIAHRO_FLAVOR'));

  /// Defaults to `foss`, the most conservative flavour (no proprietary SDKs,
  /// every network toggle off).
  static final Flavor current = parse(
    const String.fromEnvironment('MEDIAHRO_FLAVOR', defaultValue: 'foss'),
  );
}

enum AppPlatform {
  android,
  ios,
  macos,
  windows;

  static AppPlatform fromTarget(TargetPlatform p) => switch (p) {
    TargetPlatform.android => android,
    TargetPlatform.iOS => ios,
    TargetPlatform.macOS => macos,
    TargetPlatform.windows => windows,
    // Linux desktop is 1.2 (ADR-010); treat as desktop-direct for dev runs.
    TargetPlatform.linux || TargetPlatform.fuchsia => windows,
  };
}

/// The only place feature code learns about flavour differences
/// (docs/05 §11). Feature code must never read [Flavor] directly.
@immutable
final class Capabilities {
  const Capabilities({required this.flavor, required this.platform});

  factory Capabilities.current() => Capabilities(
    flavor: Flavor.current,
    platform: AppPlatform.fromTarget(defaultTargetPlatform),
  );

  final Flavor flavor;
  final AppPlatform platform;

  bool get _mobile =>
      platform == AppPlatform.android || platform == AppPlatform.ios;
  bool get _desktop => !_mobile;
  bool get _apple =>
      platform == AppPlatform.ios || platform == AppPlatform.macos;

  /// Store purchase rails: StoreKit 2, Play Billing, Microsoft Store (SUP-002).
  bool get platformPurchases => flavor == Flavor.store;

  /// Liberapay / GitHub Sponsors links instead of IAP (SUP-002, F-Droid).
  bool get donationLinks => flavor == Flavor.foss;

  /// Whether the web supporter link may be shown at all (SUP-003). The
  /// storefront check for Apple/Google store builds happens at runtime in
  /// the supporter feature.
  bool get webSupportLinkPossible => flavor != Flavor.enterprise;

  /// Web link in store builds requires a storefront check (US, or EU after
  /// accepting terms); Microsoft Store allows the declared web checkout.
  bool get webSupportLinkNeedsStorefrontCheck =>
      flavor == Flavor.store && platform != AppPlatform.windows;

  /// Official Google Cast SDK (CAST-001): store flavour on Android and iOS.
  bool get googleCastSdk => flavor == Flavor.store && _mobile;

  /// Open Screen / CASTv2 sender: desktop and FOSS builds.
  bool get openScreenCast => !googleCastSdk;

  bool get airPlay => _apple;

  /// Platform ML (ML Kit on Android Play builds; Vision/Windows ML always OS).
  bool get platformMl =>
      flavor != Flavor.foss || platform != AppPlatform.android;

  /// Mac App Store sandbox and security-scoped bookmarks (SYS-007).
  bool get sandboxed => flavor == Flavor.store && platform == AppPlatform.macos;

  /// Sparkle-style signed updater (CORE-012): direct desktop builds only.
  bool get selfUpdater => flavor == Flavor.direct && _desktop;

  /// Software VVC decoder (docs/09 §4): on in direct/foss, off in store until counsel clears.
  bool get vvcSoftwareDecoder => flavor != Flavor.store;

  /// Managed configuration defaults and kiosk boot auto-start (B2B-001/002).
  bool get enterpriseDefaults => flavor == Flavor.enterprise;

  /// Every optional network feature starts disabled; FOSS additionally
  /// keeps third-party endpoints off until enabled one by one (PRIV-004).
  bool get networkFeaturesDefaultOn => false;
}
