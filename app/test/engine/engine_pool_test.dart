import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediahro/engine/engine_pool.dart';
import 'package:mediahro/engine/unavailable_engine.dart';
import 'package:mediahro_engine/mediahro_engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('CORE-011 without libmpv every role reports libraryMissing', () {
    final c = ProviderContainer(
      overrides: [libmpvAvailableProvider.overrideWithValue(false)],
    );
    addTearDown(c.dispose);
    for (final role in EngineRole.values) {
      final e = c.read(playbackEngineProvider(role));
      expect(e, isA<UnavailableEngine>());
      expect(e.current.error?.code, EngineErrorCode.libraryMissing);
    }
  });

  test(
    'docs/05 §4.4 pool: MpvEngine for video, crossfading pair for music',
    () {
      final c = ProviderContainer(
        overrides: [libmpvAvailableProvider.overrideWithValue(true)],
      );
      addTearDown(c.dispose);
      final video = c.read(playbackEngineProvider(EngineRole.video));
      final music = c.read(playbackEngineProvider(EngineRole.music));
      expect(video, isA<MpvEngine>());
      expect(video.role, EngineRole.video);
      expect(music, isA<CrossfadingEngine>());
      expect(music.role, EngineRole.music);
      expect(
        identical(video, c.read(playbackEngineProvider(EngineRole.video))),
        isTrue,
        reason: 'one engine per role',
      );
    },
  );
}
