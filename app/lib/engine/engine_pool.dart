import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderFamily;
import 'package:mediahro/engine/unavailable_engine.dart';
import 'package:mediahro_engine/mediahro_engine.dart';

/// Creates engines for the pool. Lane B1 overrides this with `MpvEngine`;
/// until then every engine reports `libraryMissing`.
final playbackEngineFactoryProvider = Provider<PlaybackEngineFactory>(
  (ref) => UnavailableEngine.new,
);

/// One engine per role so a film can pause while a track plays (docs/05 §4.4).
final ProviderFamily<PlaybackEngine, EngineRole> playbackEngineProvider =
    Provider.family<PlaybackEngine, EngineRole>((ref, role) {
      final engine = ref.watch(playbackEngineFactoryProvider)(role);
      ref.onDispose(engine.dispose);
      return engine;
    });
