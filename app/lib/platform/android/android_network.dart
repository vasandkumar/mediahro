import 'package:flutter/services.dart';
import 'package:mediahro/platform/android/gen/network_api.pigeon.dart';
import 'package:mediahro/platform/auth_browser.dart';
import 'package:mediahro/platform/network_status.dart';

/// [NetworkStatusFacade] on Android (NET-018, NET-019): the default
/// network's transport, metered state and Data Saver
/// (`NetworkStatusModule.kt`).
final class AndroidNetworkStatus implements NetworkStatusFacade {
  AndroidNetworkStatus({
    NetworkStatusHostApi? api,
    Stream<NetworkStateMsg> Function()? events,
  }) : _api = api ?? NetworkStatusHostApi(),
       _events = events ?? networkChanges;

  final NetworkStatusHostApi _api;
  final Stream<NetworkStateMsg> Function() _events;

  @override
  Future<NetworkState> current() async => _state(await _api.current());

  @override
  Stream<NetworkState> changes() => _events().map(_state).distinct();

  static NetworkState _state(NetworkStateMsg m) => NetworkState(
    transport: NetworkTransport.values[m.transport.index],
    metered: m.metered,
    constrained: m.constrained,
  );
}

/// [MulticastFacade] on Android (NET-001/005): one Wi-Fi multicast lock
/// per lease (`MulticastModule`).
final class AndroidMulticast implements MulticastFacade {
  AndroidMulticast({MulticastHostApi? api}) : _api = api ?? MulticastHostApi();

  final MulticastHostApi _api;

  @override
  Future<MulticastLease> acquire(String tag) async =>
      _Lease(_api, await _api.acquire(tag));
}

final class _Lease implements MulticastLease {
  _Lease(this._api, this._id);

  final MulticastHostApi _api;
  final int _id;
  bool _released = false;

  @override
  Future<void> release() async {
    if (_released) return;
    _released = true;
    await _api.release(_id);
  }
}

/// [AuthBrowserFacade] on Android (NET-007, LIB-010; RFC 8252): a Custom
/// Tab that completes on the app's custom-scheme redirect
/// `<applicationId>:/oauth2redirect` (`AuthBrowserModule.kt`). Register
/// [redirectUri] (or the enterprise build's id) with each OAuth client.
final class AndroidAuthBrowser implements AuthBrowserFacade {
  AndroidAuthBrowser({AuthBrowserHostApi? api})
    : _api = api ?? AuthBrowserHostApi();

  /// The redirect for the `store`, `direct` and `foss` builds; the
  /// `enterprise` build uses `com.mediahro.app.enterprise:/oauth2redirect`.
  static final Uri redirectUri = Uri.parse('com.mediahro.app:/oauth2redirect');

  final AuthBrowserHostApi _api;

  @override
  Future<Uri> authorize(Uri authorizationUrl, Uri redirectUri) async {
    try {
      return Uri.parse(
        await _api.authorize('$authorizationUrl', '$redirectUri'),
      );
    } on PlatformException catch (e) {
      if (e.code == 'cancelled') throw const AuthCancelled();
      rethrow;
    }
  }
}
