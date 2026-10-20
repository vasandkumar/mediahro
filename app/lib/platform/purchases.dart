import 'package:meta/meta.dart';

/// Tips through the platform's own payment rail (SUP-002, docs/07 rule 5):
/// StoreKit 2 (I M), Play Billing (A, `store` flavour), Microsoft Store (W).
/// Consumable tips and an optional auto-renewing supporter subscription; no
/// product unlocks anything but cosmetics (SUP-004).
abstract interface class PurchasesFacade {
  /// Whether this build/flavour has a store rail (`foss` and `direct` builds
  /// use links instead; see `Capabilities`).
  Future<bool> isSupported();

  /// Store country (ISO 3166-1 alpha-2) of the signed-in account, used to
  /// gate external payment links per storefront rules (docs/07 §2, §3).
  Future<String?> storefrontCountry();

  Future<List<StoreProduct>> products(Set<String> ids);

  /// Starts the store's purchase sheet. Completes when the store reports a
  /// final state; a user cancel is [PurchaseState.cancelled], not an error.
  Future<PurchaseResult> purchase(String productId);

  /// Restores non-consumable and subscription entitlements.
  Future<List<PurchaseResult>> restore();

  /// Purchases finished outside a [purchase] call (deferred approval,
  /// renewals, purchases started from the store page).
  Stream<PurchaseResult> get updates;

  /// Opens the store's subscription management page.
  Future<void> manageSubscriptions();
}

enum StoreProductKind { consumable, subscription }

@immutable
final class StoreProduct {
  const StoreProduct({
    required this.id,
    required this.kind,
    required this.title,
    required this.displayPrice,
    this.subscriptionPeriod,
  });

  final String id;
  final StoreProductKind kind;

  /// Store-localised title and price string; shown as given.
  final String title;
  final String displayPrice;

  /// ISO 8601 duration for subscriptions (`P1M`, `P1Y`).
  final String? subscriptionPeriod;
}

enum PurchaseState { purchased, pending, cancelled, failed, restored }

@immutable
final class PurchaseResult {
  const PurchaseResult({
    required this.productId,
    required this.state,
    this.transactionId,
  });

  final String productId;
  final PurchaseState state;
  final String? transactionId;
}
