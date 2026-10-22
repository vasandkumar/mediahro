import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:mediahro/core/net/network_policy.dart';
import 'package:mediahro/core/net/persistent_network_policy.dart';
import 'package:mediahro/features/settings/privacy/privacy_source.dart';
import 'package:mediahro/features/settings/settings_store.dart';

/// The privacy dashboard's view of lane B2's [PersistentNetworkPolicy]
/// (CORE-015). The policy reads its toggles from settings
/// (`privacy.endpoint.<id>`, see `endpointToggle`); this adapter tells it
/// when they change and relays its last-use and host updates to the UI.
final class PolicyPrivacyUsage extends ChangeNotifier implements PrivacyUsage {
  PolicyPrivacyUsage(this._policy, this._settings) {
    _sub = _policy.changes.listen((_) => notifyListeners());
    _settings.addListener(_policy.notifyTogglesChanged);
  }

  final PersistentNetworkPolicy _policy;
  final SettingsStore _settings;
  late final StreamSubscription<void> _sub;

  @override
  DateTime? lastUsed(NetworkEndpoint endpoint) => _policy.lastUsed(endpoint);

  @override
  List<UserConfiguredHost> userConfiguredHosts() => [
    for (final h in _policy.userConfiguredHosts())
      UserConfiguredHost(host: h, lastUsed: _policy.hostLastUsed(h)),
  ];

  @override
  List<FeedHostRow> feedHosts() {
    final byHost = <String, List<String>>{};
    for (final e in _policy.feedHostEntries) {
      (byHost[e.host] ??= []).add(e.label);
    }
    return [
      for (final e in byHost.entries) FeedHostRow(host: e.key, labels: e.value),
    ]..sort((a, b) => a.host.compareTo(b.host));
  }

  @override
  Future<bool> removeFeedHost(String host) async =>
      await _policy.removeFeedHost(host) != null;

  @override
  bool isForcedOff(NetworkEndpoint endpoint) => _policy.isForcedOff(endpoint);

  @override
  bool? get lanDiscovery => _policy.lanDiscovery;

  @override
  Future<void> setLanDiscovery({required bool enabled}) =>
      _policy.setLanDiscovery(enabled: enabled);

  @override
  void dispose() {
    unawaited(_sub.cancel());
    _settings.removeListener(_policy.notifyTogglesChanged);
    super.dispose();
  }
}
