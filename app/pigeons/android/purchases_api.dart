// Pigeon messages for PurchasesFacade on Android (lane C4a, SUP-002/004,
// docs/07 rule 5): Play Billing in the `store` flavour only; the other
// flavours answer isSupported = false.
//
//   dart run pigeon --input pigeons/android/purchases_api.dart   (from app/)
//
// Pigeon's schema is positional; named bool parameters do not map to Kotlin.
// ignore_for_file: avoid_positional_boolean_parameters

import 'package:pigeon/pigeon.dart';

@ConfigurePigeon(
  PigeonOptions(
    dartOut: 'lib/platform/android/gen/purchases_api.pigeon.dart',
    kotlinOut: 'android/app/src/main/kotlin/com/mediahro/mediahro/pigeon/PurchasesApi.g.kt',
    kotlinOptions: KotlinOptions(
      // Shares FlutterError and the event-channel classes of StorageApi.g.kt.
      package: 'com.mediahro.mediahro.pigeon',
      includeErrorClass: false,
    ),
    dartPackageName: 'mediahro',
  ),
)
enum PurchaseStateMsg { purchased, pending, cancelled, failed, restored }

class StoreProductMsg {
  StoreProductMsg(
    this.id,
    this.subscription,
    this.title,
    this.displayPrice,
    this.subscriptionPeriod,
  );
  String id;
  bool subscription;
  String title;
  String displayPrice;
  String? subscriptionPeriod;
}

class PurchaseResultMsg {
  PurchaseResultMsg(this.productId, this.state, this.transactionId);
  String productId;
  PurchaseStateMsg state;
  String? transactionId;
}

@HostApi()
abstract class PurchasesHostApi {
  /// Play Billing is linked in and a connection to the Play Store succeeds.
  @async
  bool isSupported();

  /// The Play account's country (ISO 3166-1 alpha-2); not stored.
  @async
  String? storefrontCountry();

  @async
  List<StoreProductMsg> products(List<String> ids);

  @async
  PurchaseResultMsg purchase(String productId);

  @async
  List<PurchaseResultMsg> restore();

  @async
  void manageSubscriptions();
}

@EventChannelApi(
  kotlinOptions: KotlinEventChannelOptions(includeSharedClasses: false),
)
abstract class PurchaseEventsApi {
  PurchaseResultMsg purchaseUpdates();
}
