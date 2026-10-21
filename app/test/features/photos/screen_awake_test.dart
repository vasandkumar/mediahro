import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediahro/features/photos/vault/screen_awake.dart';
import 'package:mediahro/platform/platform_facades.dart';

final class _Display implements DisplayFacade {
  final List<bool> calls = [];

  @override
  Future<void> keepScreenOn({required bool on}) async => calls.add(on);

  @override
  Object? noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group(
    'PRIV-007 the screen stays on while anything in the vault needs it',
    () {
      test(
        'PRIV-007 holds are counted: the screen sleeps after the last',
        () async {
          final display = _Display();
          final awake = ScreenAwake(display);
          final move = awake.hold();
          final player = awake.hold();
          expect(awake.holds, 2);
          move.release();
          await Future<void>.delayed(Duration.zero);
          expect(display.calls, [true]);
          player.release();
          await Future<void>.delayed(Duration.zero);
          expect(display.calls, [true, false]);
        },
      );

      test(
        "PRIV-007 a hold released twice never gives back another one's",
        () async {
          final display = _Display();
          final awake = ScreenAwake(display);
          final a = awake.hold();
          final b = awake.hold();
          a
            ..release()
            ..release()
            ..release();
          expect(awake.holds, 1);
          b.release();
          await Future<void>.delayed(Duration.zero);
          expect(display.calls, [true, false]);
        },
      );

      test('PRIV-007 the whole app shares one counter', () async {
        final display = _Display();
        final c = ProviderContainer(
          overrides: [displayProvider.overrideWithValue(display)],
        );
        addTearDown(c.dispose);
        final one = c.read(screenAwakeProvider).hold();
        final two = c.read(screenAwakeProvider).hold();
        expect(c.read(screenAwakeProvider).holds, 2);
        one.release();
        two.release();
      });

      test('PRIV-007 without a display facade nothing breaks', () {
        final awake = ScreenAwake(null);
        awake.hold().release();
        expect(awake.holds, 0);
      });
    },
  );
}
