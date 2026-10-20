// Pigeon messages for NetworkStatusFacade, MulticastFacade and
// AuthBrowserFacade on Android (lane C4a, NET-005, NET-007, NET-018,
// NET-019, LIB-010).
//
//   dart run pigeon --input pigeons/android/network_api.dart   (from app/)
//
// Pigeon's schema is positional; named bool parameters do not map to Kotlin.
// ignore_for_file: avoid_positional_boolean_parameters

import 'package:pigeon/pigeon.dart';

@ConfigurePigeon(
  PigeonOptions(
    dartOut: 'lib/platform/android/gen/network_api.pigeon.dart',
    kotlinOut: 'android/app/src/main/kotlin/com/mediahro/mediahro/pigeon/NetworkApi.g.kt',
    kotlinOptions: KotlinOptions(
      // Shares FlutterError and the event-channel classes of StorageApi.g.kt.
      package: 'com.mediahro.mediahro.pigeon',
      includeErrorClass: false,
    ),
    dartPackageName: 'mediahro',
  ),
)
enum NetworkTransportMsg { none, wifi, ethernet, cellular, other }

class NetworkStateMsg {
  NetworkStateMsg(this.transport, this.metered, this.constrained);
  NetworkTransportMsg transport;
  bool metered;
  bool constrained;
}

@HostApi()
abstract class NetworkStatusHostApi {
  NetworkStateMsg current();
}

@HostApi()
abstract class MulticastHostApi {
  /// Returns a lease id.
  int acquire(String tag);
  void release(int leaseId);
}

@HostApi()
abstract class AuthBrowserHostApi {
  /// Completes with the redirect URI, or fails with code `cancelled`.
  @async
  String authorize(String authorizationUrl, String redirectUri);
}

@EventChannelApi(
  kotlinOptions: KotlinEventChannelOptions(includeSharedClasses: false),
)
abstract class NetworkEventsApi {
  NetworkStateMsg networkChanges();
}
