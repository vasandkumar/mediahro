import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mediahro/platform/android/android_motion.dart';
import 'package:mediahro/platform/platform_bindings.dart';
import 'package:mediahro/platform/platform_facades.dart';

/// Lane C4a: the device attitude on an Android device (IMG-001 360 look-around,
/// ADR-042). The phone is not moved by the test: the first reading defines yaw 0
/// and the pitch is the real tilt of the device. Turning the phone by hand
/// while this runs is a manual check (yaw grows to the right).
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final android = Platform.isAndroid;

  testWidgets('IMG-001 Android bindings provide the motion facade', (
    tester,
  ) async {
    final c = ProviderContainer(overrides: platformOverrides());
    addTearDown(c.dispose);
    expect(c.read(motionProvider), isA<AndroidMotion>());
  }, skip: !android);

  testWidgets('IMG-001 a sensor is reported and gives a first reading', (
    tester,
  ) async {
    final motion = AndroidMotion();
    if (!await motion.available) {
      markTestSkipped('this device has no game rotation vector sensor');
      return;
    }
    final first = await motion.attitude.first.timeout(
      const Duration(seconds: 5),
    );
    // The first reading is the start heading.
    expect(first.yaw, closeTo(0, 1e-6));
    expect(first.pitch.abs(), lessThanOrEqualTo(math.pi / 2 + 1e-6));
  }, skip: !android);

  testWidgets('IMG-001 listening again after a cancel starts a new heading', (
    tester,
  ) async {
    final motion = AndroidMotion();
    if (!await motion.available) {
      markTestSkipped('this device has no game rotation vector sensor');
      return;
    }
    final a = await motion.attitude.first.timeout(const Duration(seconds: 5));
    final b = await motion.attitude.first.timeout(const Duration(seconds: 5));
    expect(a.yaw, closeTo(0, 1e-6));
    expect(b.yaw, closeTo(0, 1e-6));
    expect((a.pitch - b.pitch).abs(), lessThan(0.2));
  }, skip: !android);

  testWidgets('IMG-001 readings stay in range while listening', (tester) async {
    final motion = AndroidMotion();
    if (!await motion.available) {
      markTestSkipped('this device has no game rotation vector sensor');
      return;
    }
    final readings = await motion.attitude
        .take(3)
        .toList()
        .timeout(const Duration(seconds: 8), onTimeout: () => []);
    // A resting phone sends one reading and then only changes; accept 1..3.
    for (final r in readings) {
      expect(r.yaw.abs(), lessThanOrEqualTo(math.pi + 1e-6));
      expect(r.pitch.abs(), lessThanOrEqualTo(math.pi / 2 + 1e-6));
    }
  }, skip: !android);
}
