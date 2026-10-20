import 'package:mediahro/platform/accessibility_prefs.dart';
import 'package:mediahro/platform/android/gen/input_api.pigeon.dart'
    hide audioDescriptionChanges;
import 'package:mediahro/platform/android/gen/input_api.pigeon.dart'
    as native
    show audioDescriptionChanges;
import 'package:mediahro/platform/gamepad.dart';

/// [AccessibilityPrefsFacade] on Android (SYS-008, ADR-038): the audio
/// description preference from `AccessibilityManager` on Android 13+ (false
/// below), with changes (`InputModules.kt`).
final class AndroidAccessibilityPrefs implements AccessibilityPrefsFacade {
  AndroidAccessibilityPrefs({
    AccessibilityPrefsHostApi? api,
    Stream<bool> Function()? events,
  }) : _api = api ?? AccessibilityPrefsHostApi(),
       _events = events ?? native.audioDescriptionChanges;

  final AccessibilityPrefsHostApi _api;
  final Stream<bool> Function() _events;

  @override
  Future<bool> audioDescriptionRequested() => _api.audioDescriptionRequested();

  @override
  Stream<bool> get audioDescriptionChanges => _events();
}

/// [GamepadFacade] on Android (SYS-009, ADR-038): sticks, triggers and the
/// hat from `MotionEvent` (SOURCE_JOYSTICK / SOURCE_GAMEPAD), which Flutter
/// ignores, and controller connect/disconnect. The dead zone is applied
/// natively; buttons stay Flutter key events.
final class AndroidGamepad implements GamepadFacade {
  AndroidGamepad({
    GamepadHostApi? api,
    Stream<GamepadChangeMsg> Function()? connectionEvents,
    Stream<GamepadAxisEventMsg> Function()? axisEvents,
  }) : _api = api ?? GamepadHostApi(),
       _connections = connectionEvents ?? gamepadConnections,
       _axes = axisEvents ?? gamepadAxes;

  final GamepadHostApi _api;
  final Stream<GamepadChangeMsg> Function() _connections;
  final Stream<GamepadAxisEventMsg> Function() _axes;

  @override
  Future<List<GamepadInfo>> connected() async => [
    for (final g in await _api.connected()) _info(g),
  ];

  @override
  Stream<GamepadChange> get connections => _connections().map(
    (c) => GamepadChange(
      kind: c.added
          ? GamepadConnectionKind.added
          : GamepadConnectionKind.removed,
      gamepad: _info(c.gamepad),
    ),
  );

  @override
  Stream<GamepadAxisEvent> get axes => _axes().map(
    (e) => GamepadAxisEvent(
      deviceId: e.deviceId,
      axis: GamepadAxis.values[e.axis.index],
      value: e.value,
    ),
  );

  static GamepadInfo _info(GamepadInfoMsg g) => GamepadInfo(
    id: g.id,
    name: g.name,
    vendorId: g.vendorId,
    productId: g.productId,
  );
}
