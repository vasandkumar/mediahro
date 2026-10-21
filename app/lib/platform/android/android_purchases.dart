import 'dart:async';

import 'package:flutter/services.dart';
import 'package:mediahro/platform/android/gen/purchases_api.pigeon.dart';
import 'package:mediahro/platform/purchases.dart';

/// [PurchasesFacade] on Android: Play Billing in the `store` flavour
/// (`PurchasesBinding.kt`). Tips are consumed as soon as they are paid so
/// they can be bought again; the supporter subscription is acknowledged.
/// The `direct`, `foss` and `enterprise` flavours link no billing library:
/// [isSupported] is false and the rest is unavailable.
///
/// A purchase the user cancels is [PurchaseState.cancelled]; a store that
/// cannot be reached throws a [PlatformException] with code `unavailable`.
final class AndroidPurchases implements PurchasesFacade {
  AndroidPurchases({
    PurchasesHostApi? api,
    Stream<PurchaseResultMsg> Function()? events,
  }) : _api = api ?? PurchasesHostApi(),
       _events = events ?? purchaseUpdates;

  final PurchasesHostApi _api;
  final Stream<PurchaseResultMsg> Function() _events;

  @override
  Future<bool> isSupported() => _api.isSupported();

  @override
  Future<String?> storefrontCountry() => _api.storefrontCountry();

  @override
  Future<List<StoreProduct>> products(Set<String> ids) async => [
    for (final p in await _api.products(ids.toList()))
      StoreProduct(
        id: p.id,
        kind: p.subscription
            ? StoreProductKind.subscription
            : StoreProductKind.consumable,
        title: p.title,
        displayPrice: p.displayPrice,
        subscriptionPeriod: p.subscriptionPeriod,
      ),
  ];

  @override
  Future<PurchaseResult> purchase(String productId) async =>
      _result(await _api.purchase(productId));

  @override
  Future<List<PurchaseResult>> restore() async => [
    for (final r in await _api.restore()) _result(r),
  ];

  @override
  late final Stream<PurchaseResult> updates = _events().map(_result);

  @override
  Future<void> manageSubscriptions() => _api.manageSubscriptions();

  static PurchaseResult _result(PurchaseResultMsg m) => PurchaseResult(
    productId: m.productId,
    state: PurchaseState.values[m.state.index],
    transactionId: m.transactionId,
  );
}
