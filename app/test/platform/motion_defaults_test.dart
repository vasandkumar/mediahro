import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediahro/platform/platform_facades.dart';

void main() {
  test('IMG-001 motion defaults to unavailable with no readings', () async {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final motion = c.read(motionProvider);
    expect(motion, isA<UnsupportedMotion>());
    expect(await motion.available, isFalse);
    expect(await motion.attitude.isEmpty, isTrue);
  });

  test('IMG-001 attitude compares by value', () {
    const a = MotionAttitude(yaw: 0.5, pitch: -0.25);
    const b = MotionAttitude(yaw: 0.5, pitch: -0.25);
    const c = MotionAttitude(yaw: 0.5, pitch: 0.25);
    expect(a, b);
    expect(a.hashCode, b.hashCode);
    expect(a, isNot(c));
  });
}
