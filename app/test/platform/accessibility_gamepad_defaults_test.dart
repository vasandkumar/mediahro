import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediahro/platform/platform_facades.dart';

void main() {
  test('SYS-008 audio description defaults to not requested', () async {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final prefs = c.read(accessibilityPrefsProvider);
    expect(prefs, isA<UnsupportedAccessibilityPrefs>());
    expect(await prefs.audioDescriptionRequested(), isFalse);
    expect(await prefs.audioDescriptionChanges.isEmpty, isTrue);
  });

  test('SYS-009 gamepad defaults to no controllers and no events', () async {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final pad = c.read(gamepadProvider);
    expect(pad, isA<UnsupportedGamepad>());
    expect(await pad.connected(), isEmpty);
    expect(await pad.connections.isEmpty, isTrue);
    expect(await pad.axes.isEmpty, isTrue);
  });

  test('SYS-009 axis event carries device, axis and value', () {
    const e = GamepadAxisEvent(
      deviceId: 3,
      axis: GamepadAxis.leftTrigger,
      value: 0.5,
    );
    expect(e.deviceId, 3);
    expect(e.axis, GamepadAxis.leftTrigger);
    expect(e.value, 0.5);
  });
}
