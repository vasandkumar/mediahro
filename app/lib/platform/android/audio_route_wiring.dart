import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderException;
import 'package:mediahro/engine/engine_pool.dart';
import 'package:mediahro/platform/android/audio_route_watcher.dart';
import 'package:mediahro/platform/platform_facades.dart';
import 'package:mediahro_engine/mediahro_engine.dart';

/// Tells every playback engine when the OS audio route changes (AUD-043,
/// ADR-045): the music engine and the video engine are re-checked, so a DoP or
/// exclusive output never plays noise into a different device. Read once at
/// app start (`ref.read(audioRouteWiringProvider)`); it lives as long as the
/// container. Does nothing when the audio-output facade is unavailable.
///
/// The engines are read when the route changes, not when this provider is
/// built, so it creates no engine at start-up.
final audioRouteWiringProvider = Provider<AudioRouteWatcher?>((ref) {
  final AudioOutputFacade output;
  try {
    output = ref.watch(audioOutputProvider);
  } on PlatformCapabilityUnavailable {
    return null;
  } on ProviderException catch (e) {
    // Riverpod 3 wraps what a provider threw when another provider reads it.
    if (e.exception is PlatformCapabilityUnavailable) return null;
    rethrow;
  }
  final watcher = AudioRouteWatcher(
    output: output,
    onChange: () async {
      for (final role in EngineRole.values) {
        try {
          await ref.read(playbackEngineProvider(role)).audioRouteChanged();
        } on Object {
          // One engine failing its re-check must not skip the other.
        }
      }
    },
  );
  ref.onDispose(watcher.dispose);
  return watcher;
});
