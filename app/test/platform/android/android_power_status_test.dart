import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mediahro/platform/android/android_power_status.dart';
import 'package:mediahro/platform/android/gen/power_api.pigeon.dart';
import 'package:mediahro/platform/power_status.dart';

/// The Dart half of lane C4a's power status (ADR-033).
final class _FakePower extends PowerStatusHostApi {
  @override
  Future<PowerStatusMsg> current() async =>
      PowerStatusMsg(thermal: ThermalLevelMsg.serious, batterySaver: true);
}

void main() {
  test('VID-038 thermal levels and battery saver map through', () async {
    final events = StreamController<PowerStatusMsg>();
    final power = AndroidPowerStatus(
      api: _FakePower(),
      events: () => events.stream,
    );
    final now = await power.current();
    expect(now.thermal, ThermalLevel.serious);
    expect(now.batterySaver, isTrue);
    final got = <ThermalLevel>[];
    final sub = power.changes.listen((s) => got.add(s.thermal));
    for (final l in ThermalLevelMsg.values) {
      events.add(PowerStatusMsg(thermal: l, batterySaver: false));
    }
    await pumpEventQueue();
    await sub.cancel();
    expect(got, ThermalLevel.values);
  });
}
