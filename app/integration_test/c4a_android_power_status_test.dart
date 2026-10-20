import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mediahro/platform/android/android_power_status.dart';
import 'package:mediahro/platform/platform_bindings.dart';
import 'package:mediahro/platform/platform_facades.dart';

/// Lane C4a: PowerStatusFacade on an Android device (ADR-033): the phone's
/// thermal status and battery saver, current value first on the stream.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final android = Platform.isAndroid;

  testWidgets('VID-038 Android bindings provide the power status', (
    tester,
  ) async {
    final c = ProviderContainer(overrides: platformOverrides());
    addTearDown(c.dispose);
    expect(c.read(powerStatusProvider), isA<AndroidPowerStatus>());
  }, skip: !android);

  testWidgets('VID-038 thermal level and battery saver, current value first', (
    tester,
  ) async {
    final power = AndroidPowerStatus();
    final now = await power.current();
    expect(ThermalLevel.values, contains(now.thermal));
    final first = await power.changes.first.timeout(const Duration(seconds: 5));
    expect(first.thermal, now.thermal);
    expect(first.batterySaver, now.batterySaver);
  }, skip: !android);
}
