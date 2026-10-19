import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart'
    show ProviderFamily, StreamProviderFamily;
import 'package:mediahro/engine/unavailable_engine.dart';
import 'package:mediahro_engine/mediahro_engine.dart';

/// Whether libmpv can be loaded in this build (deps.lock archives bundled
/// by the engine plugin). Overridable in tests.
final libmpvAvailableProvider = Provider<bool>((ref) => MpvEngine.isAvailable);

/// Creates engines for the pool (docs/05 §4.4): `MpvEngine` with the
/// platform render bridge for video, a crossfading pair of music cores for
/// music (AUD-002/003). Without libmpv every engine reports `libraryMissing`
/// instead of failing (CORE-011).
final playbackEngineFactoryProvider = Provider<PlaybackEngineFactory>((ref) {
  if (!ref.watch(libmpvAvailableProvider)) return UnavailableEngine.new;
  final bridge = RenderBridge();
  final audio = AudioBridge();
  return (role) => switch (role) {
    EngineRole.video => MpvEngine(
      EngineRole.video,
      config: MpvEngineConfig(renderBridge: bridge, audioBridge: audio),
    ),
    EngineRole.music => CrossfadingEngine(
      () => MpvEngine(
        EngineRole.music,
        config: MpvEngineConfig(audioBridge: audio),
      ),
    ),
  };
});

/// One engine per role so a film can pause while a track plays (docs/05 §4.4).
final ProviderFamily<PlaybackEngine, EngineRole> playbackEngineProvider =
    Provider.family<PlaybackEngine, EngineRole>((ref, role) {
      final engine = ref.watch(playbackEngineFactoryProvider)(role);
      ref.onDispose(engine.dispose);
      return engine;
    });

/// Resume points every 5 s while playing and on every transition
/// (CORE-011); the library persists them.
final StreamProviderFamily<PlaybackCheckpoint, EngineRole>
playbackCheckpointsProvider =
    StreamProvider.family<PlaybackCheckpoint, EngineRole>((ref, role) {
      final checkpointer = PlaybackCheckpointer(
        ref.watch(playbackEngineProvider(role)),
      );
      ref.onDispose(checkpointer.dispose);
      return checkpointer.checkpoints;
    });
