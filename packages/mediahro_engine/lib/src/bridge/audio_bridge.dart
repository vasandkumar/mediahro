import 'package:flutter/services.dart';
import 'package:meta/meta.dart';

/// Result of asking the OS for a bit-perfect / rate-matched output.
@immutable
final class OutputPreference {
  const OutputPreference({
    required this.applied,
    this.sampleRate,
    this.device,
    this.bitPerfect = false,
  });

  /// True when the OS accepted the preference.
  final bool applied;

  /// Rate the device now runs at, when the OS reports it.
  final int? sampleRate;
  final String? device;

  /// True when the OS mixer is bypassed (Android bit-perfect mixer).
  final bool bitPerfect;
}

/// Native audio-output half of the engine (AUD-040, AUD-041): the parts of
/// bit-perfect playback mpv's audio outputs cannot reach. Lives in the
/// engine plugin until lane C4's AudioModule exists (B1 brief §4).
///
/// - Android 14+: `AudioManager.setPreferredMixerAttributes` with
///   `MIXER_BEHAVIOR_BIT_PERFECT` on the routed USB device, at the source
///   rate (automatic rate switching).
/// - iOS: `AVAudioSession` preferred sample rate (best available).
/// - macOS / Windows: mpv's CoreAudio hog mode and WASAPI exclusive mode do
///   this themselves (`audio-exclusive`); the bridge reports not applied.
final class AudioBridge {
  AudioBridge({MethodChannel? channel})
    // mediahro-lint: allow no_direct_channel
    : _channel = channel ?? const MethodChannel('com.mediahro.engine/audio');

  final MethodChannel _channel;

  /// Requests (or, with [bitPerfect] false, releases) a bit-perfect output
  /// at [sampleRate].
  Future<OutputPreference> prefer({
    required bool bitPerfect,
    int? sampleRate,
    int? channels,
    int? bitDepth,
  }) async {
    try {
      final r = await _channel.invokeMapMethod<String, Object?>('prefer', {
        'bitPerfect': bitPerfect,
        'sampleRate': ?sampleRate,
        'channels': ?channels,
        'bitDepth': ?bitDepth,
      });
      return OutputPreference(
        applied: r?['applied'] == true,
        sampleRate: r?['sampleRate'] as int?,
        device: r?['device'] as String?,
        bitPerfect: r?['bitPerfect'] == true,
      );
    } on MissingPluginException {
      return const OutputPreference(applied: false);
    } on PlatformException {
      return const OutputPreference(applied: false);
    }
  }
}
