import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mediahro/platform/android/android_input.dart';
import 'package:mediahro/platform/platform_bindings.dart';
import 'package:mediahro/platform/platform_facades.dart';

/// Lane C4a: accessibility preferences and gamepad axes on an Android device
/// (SYS-008, SYS-009, ADR-038). A debug-only hook (`mediahro.test/gamepad`)
/// feeds the gamepad module the joystick MotionEvents a controller sends.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final android = Platform.isAndroid;

  const hook = BasicMessageChannel<Object?>(
    'mediahro.test/gamepad',
    StandardMessageCodec(),
  );
  // android.view.MotionEvent axis codes.
  const axisX = 0;
  const axisY = 1;
  const axisHatX = 15;
  const axisLTrigger = 17;

  testWidgets('SYS-008 SYS-009 Android bindings provide both facades', (
    tester,
  ) async {
    final c = ProviderContainer(overrides: platformOverrides());
    addTearDown(c.dispose);
    expect(
      c.read(accessibilityPrefsProvider),
      isA<AndroidAccessibilityPrefs>(),
    );
    expect(c.read(gamepadProvider), isA<AndroidGamepad>());
  }, skip: !android);

  testWidgets('SYS-008 the audio description preference is answered', (
    tester,
  ) async {
    final prefs = AndroidAccessibilityPrefs();
    final requested = await prefs.audioDescriptionRequested();
    expect(requested, isA<bool>());
    final sub = prefs.audioDescriptionChanges.listen((_) {});
    await sub.cancel();
  }, skip: !android);

  testWidgets('SYS-009 connected controllers list can be read', (tester) async {
    final pads = await AndroidGamepad().connected();
    for (final p in pads) {
      expect(p.name, isNotEmpty);
    }
  }, skip: !android);

  testWidgets('SYS-009 stick, trigger and hat events arrive with dead zone', (
    tester,
  ) async {
    final pad = AndroidGamepad();
    final seen = <GamepadAxisEvent>[];
    final sub = pad.axes.listen(seen.add);
    addTearDown(sub.cancel);
    await Future<void>.delayed(const Duration(milliseconds: 300));

    // Stick right 100 %, down within the dead zone, left trigger half, hat right.
    final taken = await hook.send(<Object>[
      77,
      axisX,
      1.0,
      axisY,
      0.1,
      axisLTrigger,
      0.575,
      axisHatX,
      1.0,
    ]);
    expect(taken, isTrue);
    await Future<void>.delayed(const Duration(milliseconds: 300));

    GamepadAxisEvent? of(GamepadAxis a) {
      for (final e in seen) {
        if (e.axis == a) return e;
      }
      return null;
    }

    expect(of(GamepadAxis.leftX)!.value, closeTo(1, 1e-6));
    expect(of(GamepadAxis.leftX)!.deviceId, 77);
    expect(of(GamepadAxis.leftY), isNull); // 0.1 is inside the dead zone
    expect(of(GamepadAxis.leftTrigger)!.value, closeTo(0.5, 0.01));
    expect(of(GamepadAxis.hatX)!.value, 1);

    // The same input again is not repeated; returning to rest is sent.
    seen.clear();
    await hook.send(<Object>[77, axisX, 1.0]);
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(seen, isEmpty);
    await hook.send(<Object>[77, axisX, 0.0]);
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(seen.single.axis, GamepadAxis.leftX);
    expect(seen.single.value, 0);
  }, skip: !android);
}
