import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mediahro/core/net/network_policy.dart';
import 'package:mediahro/features/settings/core_settings.dart';
import 'package:mediahro/features/settings/settings_store.dart';

/// A source or server host the user added; always allowed for that source
/// (PRIV-004) and listed in the dashboard for transparency.
@immutable
final class UserConfiguredHost {
  const UserConfiguredHost({required this.host, this.lastUsed});

  final String host;
  final DateTime? lastUsed;
}

/// What the privacy dashboard (CORE-015) reads besides the toggles: last
/// use per endpoint, the user-configured hosts, endpoints that managed
/// configuration forces off, and LAN discovery. In the app this is
/// `PolicyPrivacyUsage` over lane B2's `PersistentNetworkPolicy`.
abstract interface class PrivacyUsage implements Listenable {
  DateTime? lastUsed(NetworkEndpoint endpoint);
  List<UserConfiguredHost> userConfiguredHosts();

  /// Managed configuration (B2B-001) forces [endpoint] off.
  bool isForcedOff(NetworkEndpoint endpoint);

  /// Local-network discovery of shares and servers (NET-001); null when the
  /// policy does not offer the switch.
  bool? get lanDiscovery;
  Future<void> setLanDiscovery({required bool enabled});
}

/// Used until B2's recorder is wired: nothing recorded yet.
final class NoPrivacyUsage extends ChangeNotifier implements PrivacyUsage {
  @override
  DateTime? lastUsed(NetworkEndpoint endpoint) => null;

  @override
  List<UserConfiguredHost> userConfiguredHosts() => const [];

  @override
  bool isForcedOff(NetworkEndpoint endpoint) => false;

  @override
  bool? get lanDiscovery => null;

  @override
  Future<void> setLanDiscovery({required bool enabled}) async {}
}

/// In-memory recorder: a ready-made [PrivacyUsage] that B2's policy can
/// call from `recordUse`, and the test double.
final class RecordingPrivacyUsage extends ChangeNotifier
    implements PrivacyUsage {
  final Map<String, DateTime> _endpoints = {};
  final Map<String, DateTime?> _hosts = {};
  final Set<String> forcedOff = {};
  bool? _lan;

  @override
  bool isForcedOff(NetworkEndpoint endpoint) => forcedOff.contains(endpoint.id);

  @override
  bool? get lanDiscovery => _lan;

  @override
  Future<void> setLanDiscovery({required bool enabled}) async {
    _lan = enabled;
    notifyListeners();
  }

  void record(NetworkEndpoint endpoint, DateTime at) {
    _endpoints[endpoint.id] = at;
    notifyListeners();
  }

  void recordHost(String host, {DateTime? at}) {
    _hosts[host] = at ?? _hosts[host];
    notifyListeners();
  }

  @override
  DateTime? lastUsed(NetworkEndpoint endpoint) => _endpoints[endpoint.id];

  @override
  List<UserConfiguredHost> userConfiguredHosts() => [
    for (final e in _hosts.entries)
      UserConfiguredHost(host: e.key, lastUsed: e.value),
  ]..sort((a, b) => a.host.compareTo(b.host));
}

final privacyUsageProvider = Provider<PrivacyUsage>((ref) {
  final usage = NoPrivacyUsage();
  ref.onDispose(usage.dispose);
  return usage;
});

/// The toggle state B2's `NetworkPolicy.isEnabled` should read:
/// `settings.get(endpointToggle(endpoint))`. Every endpoint starts off in
/// every flavour (PRIV-001, PRIV-004).
SettingKey<bool> endpointToggle(NetworkEndpoint endpoint) =>
    CoreSettings.endpoint(endpoint.id);

/// Telemetry endpoints shown in the "off unless you turn it on" group.
const Set<String> telemetryEndpointIds = {'crash', 'analytics'};
