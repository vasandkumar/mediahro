import 'package:meta/meta.dart';

/// The device's network state for connection health and metered-network
/// warnings (NET-019) and download policies (NET-018).
///
/// Lane C4 implements it in Phase C:
/// - Android: `ConnectivityManager` network callbacks
///   (`NET_CAPABILITY_NOT_METERED`, transport types).
/// - iOS / macOS: `NWPathMonitor` (`isExpensive`, `isConstrained` for Low Data
///   Mode, interface types).
/// - Windows: `NetworkInformation.GetInternetConnectionProfile()` with
///   `ConnectionCost` (`NetworkCostType`, roaming, over data limit).
abstract interface class NetworkStatusFacade {
  /// The current state (NET-019 health check, NET-018 "Wi-Fi only").
  Future<NetworkState> current();

  /// Emits whenever transport, cost or constraint changes (NET-018 pauses
  /// metered downloads; NET-019 refreshes its warning).
  Stream<NetworkState> changes();
}

@immutable
final class NetworkState {
  const NetworkState({
    required this.transport,
    required this.metered,
    this.constrained = false,
  });

  final NetworkTransport transport;

  /// The user pays per byte or has a data cap (mobile data, hotspot,
  /// a network marked metered).
  final bool metered;

  /// The OS asks apps to save data (iOS Low Data Mode, Android Data Saver,
  /// Windows over data limit).
  final bool constrained;

  @override
  bool operator ==(Object other) =>
      other is NetworkState &&
      other.transport == transport &&
      other.metered == metered &&
      other.constrained == constrained;

  @override
  int get hashCode => Object.hash(transport, metered, constrained);
}

enum NetworkTransport { none, wifi, ethernet, cellular, other }

/// Multicast reception for LAN discovery: SSDP (NET-005 DLNA servers and
/// the opt-in renderer), mDNS / DNS-SD and WS-Discovery (NET-001 shares).
///
/// Lane C4 implements it in Phase C:
/// - Android: `WifiManager.MulticastLock` (Wi-Fi drops multicast without
///   it), with `CHANGE_WIFI_MULTICAST_STATE`.
/// - iOS: nothing to acquire, but sockets only receive multicast with the
///   `com.apple.developer.networking.multicast` entitlement (owner task,
///   STATUS §4); returns a no-op lease.
/// - macOS / Windows: no-op lease.
abstract interface class MulticastFacade {
  /// Holds multicast reception until the lease is released. [tag] names the
  /// holder in system diagnostics (e.g. `mediahro-ssdp`).
  Future<MulticastLease> acquire(String tag);
}

abstract interface class MulticastLease {
  /// Releases this hold; reception stops once no lease is held.
  Future<void> release();
}
