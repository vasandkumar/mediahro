import 'package:flutter/services.dart';
import 'package:mediahro/platform/android/gen/enterprise_api.pigeon.dart';
import 'package:mediahro/platform/enterprise.dart';

/// [ManagedConfigFacade] on Android (B2B-001): Android Enterprise app
/// restrictions through `RestrictionsManager` (`ManagedConfigModule.kt`).
/// The keys MDM consoles show are declared in `res/xml/app_restrictions.xml`;
/// any other key the MDM sets is passed through. Read-only.
final class AndroidManagedConfig implements ManagedConfigFacade {
  AndroidManagedConfig({
    ManagedConfigHostApi? api,
    Stream<ManagedSnapshotMsg> Function()? events,
  }) : _api = api ?? ManagedConfigHostApi(),
       _events = events ?? managedChanges;

  final ManagedConfigHostApi _api;
  final Stream<ManagedSnapshotMsg> Function() _events;

  @override
  Future<Map<String, ManagedValue>> read() async => _map(await _api.read());

  @override
  Stream<Map<String, ManagedValue>> get changes => _events().map(_map);

  static Map<String, ManagedValue> _map(ManagedSnapshotMsg snapshot) => {
    for (final e in snapshot.entries) e.key: ?_value(e),
  };

  static ManagedValue? _value(ManagedEntryMsg e) => switch (e.kind) {
    ManagedKindMsg.string => switch (e.stringValue) {
      final v? => ManagedString(v),
      _ => null,
    },
    ManagedKindMsg.boolean => switch (e.boolValue) {
      final v? => ManagedBool(v),
      _ => null,
    },
    ManagedKindMsg.integer => switch (e.intValue) {
      final v? => ManagedInt(v),
      _ => null,
    },
    ManagedKindMsg.list => switch (e.listValue) {
      final v? => ManagedList(v),
      _ => null,
    },
  };
}

/// [KioskFacade] on Android (B2B-002): lock task mode (screen pinning unless
/// the device owner allow-listed the app), immersive full screen, screen kept
/// on and a crash watchdog (`KioskModule.kt`). [setStartOnBoot] works in the
/// enterprise build only and throws [UnsupportedError] elsewhere.
final class AndroidKiosk implements KioskFacade {
  AndroidKiosk({KioskHostApi? api, Stream<bool> Function()? events})
    : _api = api ?? KioskHostApi(),
      _events = events ?? kioskStates;

  final KioskHostApi _api;
  final Stream<bool> Function() _events;

  @override
  Future<bool> isSupported() => _api.isSupported();

  @override
  Future<void> enter() => _api.enter();

  @override
  Future<void> exit() => _api.exit();

  @override
  Stream<bool> get isActive => _events().distinct();

  @override
  Future<void> setStartOnBoot({required bool enabled}) async {
    try {
      await _api.setStartOnBoot(enabled);
    } on PlatformException catch (e) {
      if (e.code == 'unsupported') throw UnsupportedError(e.message ?? e.code);
      rethrow;
    }
  }
}
