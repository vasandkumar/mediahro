import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mediahro/platform/android/android_motion.dart';
import 'package:mediahro/platform/android/gen/motion_api.pigeon.dart';
import 'package:mediahro/platform/motion.dart';

/// The Dart half of lane C4a's device attitude (IMG-001, ADR-042).
final class _FakeMotion extends MotionHostApi {
  bool sensor = true;

  @override
  Future<bool> available() async => sensor;
}

void main() {
  test('IMG-001 availability comes from the sensor', () async {
    final api = _FakeMotion();
    final motion = AndroidMotion(api: api);
    expect(await motion.available, isTrue);
    api.sensor = false;
    expect(await motion.available, isFalse);
  });

  test('IMG-001 attitude maps yaw and pitch and starts on listen', () async {
    var listens = 0;
    final controller = StreamController<MotionAttitudeMsg>(
      onListen: () => listens++,
    );
    addTearDown(() => unawaited(controller.close()));
    final motion = AndroidMotion(
      api: _FakeMotion(),
      events: () => controller.stream,
    );
    // Nothing is listened to until a consumer asks.
    final stream = motion.attitude;
    expect(listens, 0);
    final seen = <MotionAttitude>[];
    final sub = stream.listen(seen.add);
    controller
      ..add(MotionAttitudeMsg(yaw: 0, pitch: 0.25))
      ..add(MotionAttitudeMsg(yaw: -1.5, pitch: -0.5));
    await Future<void>.delayed(Duration.zero);
    await sub.cancel();
    expect(listens, 1);
    expect(seen, const [
      MotionAttitude(yaw: 0, pitch: 0.25),
      MotionAttitude(yaw: -1.5, pitch: -0.5),
    ]);
  });

  test('IMG-001 cancelling the listener cancels the native stream', () async {
    var cancelled = false;
    final controller = StreamController<MotionAttitudeMsg>(
      onCancel: () => cancelled = true,
    );
    addTearDown(() => unawaited(controller.close()));
    final sub = AndroidMotion(
      api: _FakeMotion(),
      events: () => controller.stream,
    ).attitude.listen((_) {});
    expect(cancelled, isFalse);
    await sub.cancel();
    expect(cancelled, isTrue);
  });
}
