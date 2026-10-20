import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mediahro/platform/android/android_display.dart';
import 'package:mediahro/platform/android/gen/display_api.pigeon.dart';
import 'package:mediahro/platform/display.dart';

/// The Dart half of lane C4a's DisplayFacade and PipFacade.
final class _FakeDisplay extends DisplayHostApi {
  final calls = <Object?>[];

  @override
  Future<List<DisplayInfoMsg>> displays() async => [
    DisplayInfoMsg(
      id: '0',
      name: 'Built-in',
      refreshRate: 90,
      supportedRefreshRates: [60, 90],
      hdr: true,
      peakNits: 800,
      isExternal: false,
    ),
  ];

  @override
  Future<void> setWindowBrightness(double? value) async => calls.add(value);

  @override
  Future<void> setOrientationLock(OrientationLockMsg lock) async =>
      calls.add(lock);
}

void main() {
  test('VID-070 display info maps through', () async {
    final d = (await AndroidDisplay(
      api: _FakeDisplay(),
      events: Stream.empty,
    ).displays()).single;
    expect(d.refreshRate, 90);
    expect(d.supportedRefreshRates, [60, 90]);
    expect(d.hdr, isTrue);
    expect(d.peakNits, 800);
    expect(d.isExternal, isFalse);
  });

  test('VID-067 brightness is clamped to 0–1; null restores', () async {
    final api = _FakeDisplay();
    final d = AndroidDisplay(api: api, events: Stream.empty);
    await d.setWindowBrightness(1.4);
    await d.setWindowBrightness(-0.2);
    await d.setWindowBrightness(null);
    expect(api.calls, [1.0, 0.0, null]);
  });

  test('SYS-011 orientation locks map one to one', () async {
    final api = _FakeDisplay();
    final d = AndroidDisplay(api: api, events: Stream.empty);
    for (final lock in OrientationLock.values) {
      await d.setOrientationLock(lock);
    }
    expect(api.calls, OrientationLockMsg.values);
  });

  test('VID-067 PiP state stream maps to bools', () async {
    final events = StreamController<PipStateMsg>();
    final pip = AndroidPip(api: PipHostApi(), events: () => events.stream);
    final got = <bool>[];
    final sub = pip.isActive.listen(got.add);
    events
      ..add(PipStateMsg(active: true))
      ..add(PipStateMsg(active: false));
    await pumpEventQueue();
    await sub.cancel();
    expect(got, [true, false]);
  });
}
