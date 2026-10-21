import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:mediahro/core/db/library_database.dart';
import 'package:mediahro/core/net/local_hosts.dart';
import 'package:mediahro/core/net/network_policy.dart';
import 'package:mediahro/core/sources/cloud/cloud_providers.dart';
import 'package:mediahro/core/sources/source_access.dart' show decodeOptions;
import 'package:meta/meta.dart';

export 'package:mediahro/core/net/local_hosts.dart' show isLocalNetworkHost;

/// The state of one allow-list endpoint for the privacy dashboard
/// (CORE-015, owned by lane B3) and PRIV-004.
@immutable
final class EndpointState {
  const EndpointState(this.endpoint, {required this.enabled, this.lastUsed});

  final NetworkEndpoint endpoint;
  final bool enabled;
  final DateTime? lastUsed;
}

/// One host the user's own action allowed: a podcast subscription or a radio
/// station (PRIV-004). Listed in the privacy dashboard with what added it.
@immutable
final class FeedHostEntry {
  const FeedHostEntry({
    required this.origin,
    required this.owner,
    required this.label,
  });

  /// `scheme://host[:port]`, normalised: lower case, default port dropped.
  final String origin;

  /// What added it, `podcast:<id>` or `radio:<id>`.
  final String owner;

  /// The feed's or station's name, for the dashboard.
  final String label;

  String get host => Uri.parse(origin).host;

  Map<String, Object?> toJson() => {
    'origin': origin,
    'owner': owner,
    'label': label,
  };

  @override
  bool operator ==(Object other) =>
      other is FeedHostEntry &&
      other.origin == origin &&
      other.owner == owner &&
      other.label == label;

  @override
  int get hashCode => Object.hash(origin, owner, label);
}

/// Where subscriptions and stations record that the user asked for their
/// host. Only an explicit user action calls [addFeedHost] (subscribing,
/// adding a station, importing a file the user picked); [removeFeedOwner]
/// takes the host away again unless another entry still uses it.
abstract interface class FeedHostRegistry {
  Future<void> addFeedHost(
    Uri url, {
    required String owner,
    required String label,
  });

  Future<void> removeFeedOwner(String owner);

  /// Forgets the owners with [prefix] (`podcast`, `radio`) whose id is not in
  /// [existingIds]: what was removed while no registry was listening.
  Future<void> pruneFeedOwners(String prefix, Set<String> existingIds);
}

/// Unsubscribes or deletes what an owner names (the part after the prefix),
/// when the user removes a host in the privacy dashboard.
typedef FeedOwnerRemover = Future<void> Function(String id);

/// [NetworkPolicy] backed by the profile database (`setting` table):
///
/// * every allow-list endpoint is **off** until the user turns it on, in
///   every flavour (PRIV-001, PRIVACY.md "all off by default");
/// * a managed-config overlay (B2B-001) may force endpoints off;
/// * hosts of sources and servers the user added are allowed for them;
/// * LAN discovery (SSDP, mDNS description fetches) may reach private and
///   link-local addresses when [lanDiscovery] is on.
///
/// The toggles may live elsewhere: pass `isToggledOn` to [load] (the B3 settings
/// store's `privacy.endpoint.<id>` keys, wired in main.dart) and call
/// [notifyTogglesChanged] when they change; [setEnabled] is then unused.
final class PersistentNetworkPolicy
    implements NetworkPolicy, HostUseRecorder, FeedHostRegistry {
  PersistentNetworkPolicy._(
    this._db,
    this._toggles,
    this._lastUsed,
    this._isToggledOn,
  );

  static Future<PersistentNetworkPolicy> load(
    LibraryDatabase db, {
    bool Function(String endpointId)? isToggledOn,
  }) async {
    final rows = await (db.select(
      db.settingsTable,
    )..where((s) => s.key.like('privacy.%'))).get();
    final toggles = <String, bool>{};
    final used = <String, DateTime>{};
    final feeds = <FeedHostEntry>[];
    var lan = true;
    for (final r in rows) {
      if (r.key.startsWith(_toggle)) {
        toggles[r.key.substring(_toggle.length)] = r.value == 'on';
      } else if (r.key.startsWith(_used)) {
        final at = DateTime.tryParse(r.value);
        if (at != null) used[r.key.substring(_used.length)] = at;
      } else if (r.key == _lanKey) {
        lan = r.value == 'on';
      } else if (r.key == _feedHostsKey) {
        feeds.addAll(_decodeFeedHosts(r.value));
      }
    }
    final p = PersistentNetworkPolicy._(db, toggles, used, isToggledOn)
      .._lan = lan
      .._feedHosts.addAll(feeds);
    await p.refreshUserHosts();
    return p;
  }

  static const _toggle = 'privacy.endpoint.';
  static const _used = 'privacy.lastUsed.';
  static const _lanKey = 'privacy.lanDiscovery';
  static const _feedHostsKey = 'privacy.feedHosts';

  final LibraryDatabase _db;
  final Map<String, bool> _toggles;
  final Map<String, DateTime> _lastUsed;
  final bool Function(String endpointId)? _isToggledOn;
  final Map<String, DateTime> _hostLastUsed = {};
  final Set<String> _userHosts = {};
  final Set<String> _sessionHosts = {};
  final List<FeedHostEntry> _feedHosts = [];
  final Map<String, FeedOwnerRemover> _ownerRemovers = {};

  /// Cloud drives with a connected account (or signing in now).
  final Set<CloudProvider> _providers = {};
  final Set<CloudProvider> _sessionProviders = {};
  Set<String> _forcedOff = const {};
  bool _lan = true;
  Timer? _flush;
  final Map<String, DateTime> _pendingUse = {};
  final _changes = StreamController<void>.broadcast();

  /// Fires when a toggle, a last-used time or the user hosts change.
  Stream<void> get changes => _changes.stream;

  bool get lanDiscovery => _lan;

  List<EndpointState> get endpoints => [
    for (final e in Endpoints.all)
      EndpointState(e, enabled: isEnabled(e), lastUsed: _lastUsed[e.id]),
  ];

  @override
  bool isEnabled(NetworkEndpoint endpoint) =>
      !_forcedOff.contains(endpoint.id) &&
      (_isToggledOn?.call(endpoint.id) ?? _toggles[endpoint.id] ?? false);

  /// Managed configuration forces [endpoint] off (the dashboard shows the
  /// toggle locked).
  bool isForcedOff(NetworkEndpoint endpoint) =>
      _forcedOff.contains(endpoint.id);

  /// Last time a request to [endpoint] left the device (CORE-015).
  DateTime? lastUsed(NetworkEndpoint endpoint) => _lastUsed[endpoint.id];

  /// Hosts of sources and servers the user added, sorted (CORE-015).
  List<String> userConfiguredHosts() => (_userHosts.toList()..sort());

  /// Last request to a user-added host, if any.
  DateTime? hostLastUsed(String host) => _hostLastUsed[host.toLowerCase()];

  /// Records a request to a user-added host (NetworkGateway calls this).
  @override
  void recordHostUse(String host, DateTime at) {
    _hostLastUsed[host.toLowerCase()] = at;
    _changes.add(null);
  }

  /// Call when the injected toggles changed so listeners refresh.
  void notifyTogglesChanged() => _changes.add(null);

  Future<void> setEnabled(
    NetworkEndpoint endpoint, {
    required bool enabled,
  }) async {
    _toggles[endpoint.id] = enabled;
    await _put('$_toggle${endpoint.id}', enabled ? 'on' : 'off');
    _changes.add(null);
  }

  Future<void> setLanDiscovery({required bool enabled}) async {
    _lan = enabled;
    await _put(_lanKey, enabled ? 'on' : 'off');
    _changes.add(null);
  }

  /// Managed configuration (B2B-001) wins over user toggles.
  void applyManagedOverlay(Set<String> forcedOff) {
    _forcedOff = Set.unmodifiable(forcedOff);
    _changes.add(null);
  }

  @override
  bool isUserConfiguredHost(String host) {
    final h = host.toLowerCase();
    if (_userHosts.contains(h) || _sessionHosts.contains(h)) return true;
    if (_feedHosts.any((e) => e.host == h)) return true;
    // Only code running inside an allowance's own request chain.
    if (Zone.current[_scopeKey] case final AllowScope scope
        when scope.allows(h)) {
      return true;
    }
    if (_providers.any((p) => cloudHostMatches(p, h))) return true;
    return _lan && isLocalNetworkHost(h);
  }

  /// The hosts podcasts and stations asked for, with what added each one,
  /// sorted by host.
  List<FeedHostEntry> get feedHostEntries =>
      List.of(_feedHosts)..sort((a, b) => a.origin.compareTo(b.origin));

  /// `scheme://host[:port]` for [url], or null when it is not a plain
  /// http(s) address: no wildcards, no address ranges, no other scheme.
  static String? normalizeOrigin(Uri url) {
    final scheme = url.scheme.toLowerCase();
    final host = url.host.toLowerCase();
    if ((scheme != 'http' && scheme != 'https') || host.isEmpty) return null;
    if (host.contains('*') || host.contains('/') || host.contains(' ')) {
      return null;
    }
    final defaultPort = scheme == 'https' ? 443 : 80;
    final port = url.hasPort && url.port != defaultPort ? ':${url.port}' : '';
    return '$scheme://${host.contains(':') ? '[$host]' : host}$port';
  }

  @override
  Future<void> addFeedHost(
    Uri url, {
    required String owner,
    required String label,
  }) async {
    final origin = normalizeOrigin(url);
    if (origin == null) return;
    final entry = FeedHostEntry(origin: origin, owner: owner, label: label);
    // An owner has one address at a time: editing a station's URL to
    // another origin takes the old origin away.
    final count = _feedHosts.length;
    _feedHosts.removeWhere((e) => e.owner == owner && e.origin != origin);
    var changed = _feedHosts.length != count;
    final i = _feedHosts.indexWhere((e) => e.owner == owner);
    if (i >= 0) {
      if (_feedHosts[i] != entry) {
        _feedHosts[i] = entry;
        changed = true;
      }
    } else {
      _feedHosts.add(entry);
      changed = true;
    }
    if (changed) await _saveFeedHosts();
  }

  @override
  Future<void> removeFeedOwner(String owner) => _removeOwners([owner]);

  @override
  Future<void> pruneFeedOwners(String prefix, Set<String> existingIds) async {
    final p = '$prefix:';
    final before = _feedHosts.length;
    _feedHosts.removeWhere(
      (e) =>
          e.owner.startsWith(p) &&
          !existingIds.contains(e.owner.substring(p.length)),
    );
    if (_feedHosts.length != before) await _saveFeedHosts();
  }

  /// Registers what removing an owner with [prefix] (`podcast`, `radio`)
  /// means: unsubscribing or deleting the station.
  void registerOwnerRemover(String prefix, FeedOwnerRemover remover) =>
      _ownerRemovers[prefix] = remover;

  /// The user removes [host] in the privacy dashboard: everything that
  /// added it (whatever its scheme and port) is unsubscribed or deleted, and
  /// the host goes. Returns the owners removed, or null, changing nothing,
  /// while the feature that owns one of them has not registered what removing
  /// it means (the app is still starting): removing only the host would not
  /// stick, because the subscription would record it again.
  Future<List<String>?> removeFeedHost(String host) async {
    final h = host.toLowerCase();
    final owners = [
      for (final e in _feedHosts)
        if (e.host == h) e.owner,
    ];
    String prefix(String owner) {
      final colon = owner.indexOf(':');
      return colon < 0 ? '' : owner.substring(0, colon);
    }

    if (owners.any((o) => !_ownerRemovers.containsKey(prefix(o)))) return null;
    for (final owner in owners) {
      await _ownerRemovers[prefix(owner)]!(
        owner.substring(prefix(owner).length + 1),
      );
    }
    // Whatever no remover took care of goes too.
    await _removeOwners(owners);
    return owners;
  }

  Future<void> _removeOwners(List<String> owners) async {
    final before = _feedHosts.length;
    _feedHosts.removeWhere((e) => owners.contains(e.owner));
    if (_feedHosts.length != before) await _saveFeedHosts();
  }

  Future<void> _saveFeedHosts() async {
    await _put(
      _feedHostsKey,
      jsonEncode([for (final e in _feedHosts) e.toJson()]),
    );
    _changes.add(null);
  }

  static List<FeedHostEntry> _decodeFeedHosts(String json) {
    try {
      final j = jsonDecode(json);
      if (j is! List<Object?>) return const [];
      return [
        for (final e in j)
          if (e is Map<String, Object?> &&
              e['origin'] is String &&
              e['owner'] is String &&
              normalizeOrigin(Uri.parse(e['origin']! as String)) == e['origin'])
            FeedHostEntry(
              origin: e['origin']! as String,
              owner: e['owner']! as String,
              label: e['label'] is String ? e['label']! as String : '',
            ),
      ];
    } on FormatException {
      return const [];
    }
  }

  /// Allows [host] for this session: a URL the user typed or pasted
  /// (CORE-005) or a share picked from discovery before it is saved.
  void allowForSession(String host) {
    _sessionHosts.add(host.toLowerCase());
  }

  /// Starts an allowance for one request chain (a feed, its redirects, the
  /// artwork or episode it points to). The hosts passed to
  /// [AllowScope.allow] are allowed to code running inside [AllowScope.run]
  /// and to nothing else (no other feature, no other request, however long
  /// the scope stays open), and not after [AllowScope.close]. Nothing is
  /// added to the session or to the dashboard.
  AllowScope beginAllowScope() => AllowScope._();

  /// Allows a cloud provider's hosts while the user signs in (NET-007).
  void allowProviderForSession(CloudProvider provider) {
    _sessionProviders.add(provider);
    _providers.add(provider);
  }

  /// Re-reads hosts of saved sources and server accounts.
  Future<void> refreshUserHosts() async {
    final sources = await _db.select(_db.sources).get();
    final servers = await _db.select(_db.serverAccounts).get();
    _providers
      ..clear()
      ..addAll(_sessionProviders)
      ..addAll([
        for (final s in sources)
          if (s.kind == SourceKind.cloud)
            ?cloudProvider(decodeOptions(s.options)['provider'] ?? ''),
      ]);
    _userHosts
      ..clear()
      ..addAll([
        for (final s in sources) ?_host(s.rootUri),
        for (final a in servers) ?_host(a.baseUrl),
        for (final s in sources)
          if (decodeHostOption(s.options) case final String extra) extra,
      ]);
    _changes.add(null);
  }

  @override
  void recordUse(NetworkEndpoint endpoint, DateTime at) {
    _lastUsed[endpoint.id] = at;
    _pendingUse[endpoint.id] = at;
    // Batched: a burst of requests costs one write.
    _flush ??= Timer(const Duration(seconds: 2), () => unawaited(flush()));
    _changes.add(null);
  }

  /// Writes pending last-used times (also called on app pause).
  Future<void> flush() async {
    _flush?.cancel();
    _flush = null;
    final pending = Map.of(_pendingUse);
    _pendingUse.clear();
    for (final e in pending.entries) {
      await _put('$_used${e.key}', e.value.toUtc().toIso8601String());
    }
  }

  Future<void> dispose() async {
    await flush();
    await _changes.close();
  }

  Future<void> _put(String key, String value) => _db
      .into(_db.settingsTable)
      .insertOnConflictUpdate(
        SettingsTableCompanion.insert(key: key, value: value),
      );

  static String? _host(String uri) {
    final h = Uri.tryParse(uri)?.host;
    return h == null || h.isEmpty ? null : h.toLowerCase();
  }
}

const _scopeKey = #mediahro.net.allowScope;

/// The hosts one request chain may reach. Only work started through [run]
/// can use them (the policy looks for the scope in the current zone), and
/// only until [close].
final class AllowScope {
  AllowScope._();

  final Set<String> _hosts = {};
  bool _closed = false;

  void allow(String host) {
    if (!_closed) _hosts.add(normalizeHost(host));
  }

  bool allows(String host) => !_closed && _hosts.contains(normalizeHost(host));

  /// Runs [body] with this allowance in force.
  T run<T>(T Function() body) => runZoned(body, zoneValues: {_scopeKey: this});

  void close() {
    _closed = true;
    _hosts.clear();
  }
}

/// `host` option of a source (e.g. the OAuth API host of a cloud drive).
String? decodeHostOption(String optionsJson) {
  final m = RegExp(r'"apiHost"\s*:\s*"([^"]+)"').firstMatch(optionsJson);
  return m?.group(1)?.toLowerCase();
}
