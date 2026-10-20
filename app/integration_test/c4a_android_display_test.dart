import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mediahro/platform/android/android_display.dart';
import 'package:mediahro/platform/platform_bindings.dart';
import 'package:mediahro/platform/platform_facades.dart';

/// Lane C4a: DisplayFacade and PipFacade on an Android device. A debug-only
/// hook (`mediahro.test/window`) reads back the activity window's flags,
/// brightness, requested orientation, preferred display mode and PiP state.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final android = Platform.isAndroid;

  const hook = BasicMessageChannel<Object?>(
    'mediahro.test/window',
    StandardMessageCodec(),
  );
  Future<Map<Object?, Object?>> window() async =>
      (await hook.send(null))! as Map<Object?, Object?>;

  Future<void> eventually(
    Future<bool> Function() check, {
    String reason = '',
  }) async {
    final deadline = DateTime.now().add(const Duration(seconds: 10));
    while (!await check()) {
      if (DateTime.now().isAfter(deadline)) {
        fail('timed out: $reason, window: ${await window()}');
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  }

  late AndroidDisplay display;
  late AndroidPip pip;
  setUp(() {
    if (!android) return;
    display = AndroidDisplay();
    pip = AndroidPip();
  });

  testWidgets('VID-071 Android bindings provide Display and Pip', (
    tester,
  ) async {
    final c = ProviderContainer(overrides: platformOverrides());
    addTearDown(c.dispose);
    expect(c.read(displayProvider), isA<AndroidDisplay>());
    expect(c.read(pipProvider), isA<AndroidPip>());
  }, skip: !android);

  testWidgets(
    'VID-070 displays list the built-in screen with its refresh rates',
    (tester) async {
      final displays = await display.displays();
      final main = displays.firstWhere((d) => d.id == '0');
      expect(main.isExternal, isFalse);
      expect(main.name, isNotEmpty);
      expect(main.refreshRate, greaterThan(0));
      expect(
        main.supportedRefreshRates.any(
          (r) => (r - main.refreshRate).abs() < 0.02,
        ),
        isTrue,
        reason: '$main rates ${main.supportedRefreshRates}',
      );
    },
    skip: !android,
  );

  testWidgets(
    'VID-036 frame-rate matching selects a display mode; restore clears it',
    (tester) async {
      final main = (await display.displays()).firstWhere((d) => d.id == '0');
      final rate = main.supportedRefreshRates.first;
      expect(await display.matchFrameRate('0', rate), isTrue);
      expect((await window())['preferredModeId'], isNot(0));
      await display.restoreDisplayMode('0');
      expect((await window())['preferredModeId'], 0);
      // No mode runs at 1000 Hz or a multiple of it; other displays are not ours.
      expect(await display.matchFrameRate('0', 1000), isFalse);
      expect(await display.matchFrameRate('42', rate), isFalse);
    },
    skip: !android,
  );

  testWidgets('VID-067 player keeps the screen on and sets window brightness', (
    tester,
  ) async {
    await display.keepScreenOn(on: true);
    expect((await window())['keepScreenOn'], isTrue);
    await display.keepScreenOn(on: false);
    expect((await window())['keepScreenOn'], isFalse);

    await display.setWindowBrightness(0.3);
    expect((await window())['brightness']! as double, closeTo(0.3, 0.001));
    await display.setWindowBrightness(null);
    expect((await window())['brightness'], -1.0, reason: 'system brightness');
  }, skip: !android);

  testWidgets(
    'SYS-011 orientation locks set the requested orientation, followVideo by shape',
    (tester) async {
      // ActivityInfo.SCREEN_ORIENTATION_*.
      const unspecified = -1;
      const userLandscape = 11;
      const userPortrait = 12;
      addTearDown(() => display.setOrientationLock(OrientationLock.auto));
      await display.setOrientationLock(OrientationLock.landscape);
      expect((await window())['orientation'], userLandscape);
      await display.setOrientationLock(OrientationLock.portrait);
      expect((await window())['orientation'], userPortrait);
      await display.setOrientationLock(OrientationLock.followVideo);
      expect((await window())['orientation'], userLandscape, reason: '16:9');
      // ADR-028: the player reports the video's shape.
      await pip.setAspectRatio(9 / 16);
      await display.setOrientationLock(OrientationLock.followVideo);
      expect((await window())['orientation'], userPortrait, reason: '9:16');
      await pip.setAspectRatio(4 / 3);
      await display.setOrientationLock(OrientationLock.followVideo);
      expect((await window())['orientation'], userLandscape, reason: '4:3');
      await display.setOrientationLock(OrientationLock.auto);
      expect((await window())['orientation'], unspecified);
    },
    skip: !android,
  );

  testWidgets(
    'VID-067 picture-in-picture enters and exits, reported by isActive',
    (tester) async {
      expect(await pip.isSupported(), isTrue);
      final states = <bool>[];
      final sub = pip.isActive.listen(states.add);
      addTearDown(sub.cancel);

      expect(await pip.enter(aspectRatio: 16 / 9), isTrue);
      await eventually(
        () async => (await window())['inPip'] == true,
        reason: 'in PiP',
      );
      await eventually(() async => states.contains(true), reason: 'isActive');

      await pip.exit();
      await eventually(
        () async => (await window())['inPip'] == false,
        reason: 'back to full screen',
      );
      await eventually(
        () async => states.isNotEmpty && !states.last,
        reason: 'isActive false, $states',
      );

      await pip.setAutoEnter(enabled: true);
      await pip.setAutoEnter(enabled: false);
    },
    skip: !android,
  );
}
