import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mediahro/platform/android/android_purchases.dart';
import 'package:mediahro/platform/android/gen/purchases_api.pigeon.dart';
import 'package:mediahro/platform/platform_facades.dart';

/// The Dart half of lane C4a's Play Billing facade (SUP-002).
final class _FakePurchases extends PurchasesHostApi {
  bool supported = true;
  PurchaseResultMsg next = PurchaseResultMsg(
    productId: 'tip_small',
    state: PurchaseStateMsg.purchased,
    transactionId: 'GPA.1',
  );
  final calls = <String>[];

  @override
  Future<bool> isSupported() async => supported;

  @override
  Future<String?> storefrontCountry() async => 'IN';

  @override
  Future<List<StoreProductMsg>> products(List<String> ids) async => [
    StoreProductMsg(
      id: 'tip_small',
      subscription: false,
      title: 'A coffee',
      displayPrice: '₹99.00',
    ),
    StoreProductMsg(
      id: 'supporter',
      subscription: true,
      title: 'Supporter',
      displayPrice: '₹149.00',
      subscriptionPeriod: 'P1M',
    ),
  ];

  @override
  Future<PurchaseResultMsg> purchase(String productId) async {
    calls.add('purchase:$productId');
    return next;
  }

  @override
  Future<List<PurchaseResultMsg>> restore() async => [
    PurchaseResultMsg(
      productId: 'supporter',
      state: PurchaseStateMsg.restored,
      transactionId: 'GPA.2',
    ),
  ];

  @override
  Future<void> manageSubscriptions() async => calls.add('manage');
}

void main() {
  late _FakePurchases api;
  late AndroidPurchases purchases;
  late StreamController<PurchaseResultMsg> events;
  setUp(() {
    api = _FakePurchases();
    events = StreamController<PurchaseResultMsg>();
    purchases = AndroidPurchases(api: api, events: () => events.stream);
  });
  // close() completes only once a listener has seen the done event.
  tearDown(() => unawaited(events.close()));

  test('SUP-002 support and storefront country come from the store', () async {
    expect(await purchases.isSupported(), isTrue);
    expect(await purchases.storefrontCountry(), 'IN');
    api.supported = false;
    expect(await purchases.isSupported(), isFalse);
  });

  test('SUP-002 products carry the store price strings', () async {
    final products = await purchases.products({'tip_small', 'supporter'});
    expect(products.map((p) => p.id), ['tip_small', 'supporter']);
    expect(products[0].kind, StoreProductKind.consumable);
    expect(products[0].displayPrice, '₹99.00');
    expect(products[0].subscriptionPeriod, isNull);
    expect(products[1].kind, StoreProductKind.subscription);
    expect(products[1].subscriptionPeriod, 'P1M');
  });

  test('SUP-002 a purchase reports the final state', () async {
    final done = await purchases.purchase('tip_small');
    expect(done.state, PurchaseState.purchased);
    expect(done.transactionId, 'GPA.1');
    api.next = PurchaseResultMsg(
      productId: 'tip_small',
      state: PurchaseStateMsg.cancelled,
    );
    expect(
      (await purchases.purchase('tip_small')).state,
      PurchaseState.cancelled,
    );
    api.next = PurchaseResultMsg(
      productId: 'tip_small',
      state: PurchaseStateMsg.pending,
    );
    expect(
      (await purchases.purchase('tip_small')).state,
      PurchaseState.pending,
    );
  });

  test('SUP-002 restore returns the entitlements as restored', () async {
    final r = await purchases.restore();
    expect(r.single.state, PurchaseState.restored);
    expect(r.single.productId, 'supporter');
  });

  test('SUP-002 purchases finished outside a call arrive on updates', () async {
    final seen = <PurchaseResult>[];
    final sub = purchases.updates.listen(seen.add);
    events.add(
      PurchaseResultMsg(
        productId: 'supporter',
        state: PurchaseStateMsg.purchased,
        transactionId: 'GPA.3',
      ),
    );
    await Future<void>.delayed(Duration.zero);
    await sub.cancel();
    expect(seen.single.productId, 'supporter');
    expect(seen.single.state, PurchaseState.purchased);
  });

  test('SUP-002 manage subscriptions opens the store page', () async {
    await purchases.manageSubscriptions();
    expect(api.calls, ['manage']);
  });
}
