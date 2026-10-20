import 'dart:typed_data';

import 'package:meta/meta.dart';

/// One analysis window of the audio being played, for visualisers (AUD-046,
/// ADR-027). Emitted by `PlaybackEngine.audioTap` about 30 times a second
/// while playing.
///
/// Every field the engine can provide is filled. A platform that cannot hand
/// over PCM cheaply leaves [samples] null and still provides [bands], [rms]
/// and [peak].
@immutable
final class AudioTapFrame {
  const AudioTapFrame({
    required this.position,
    required this.sampleRate,
    this.samples,
    this.bands,
    this.rms = const [],
    this.peak = const [],
  });

  /// Playback position at the end of the window.
  final Duration position;

  /// Rate of [samples], in Hz.
  final int sampleRate;

  /// The window, downmixed to mono, float32 in -1…1, oldest sample first.
  final Float32List? samples;

  /// 64 log-spaced band magnitudes from 20 Hz to Nyquist, 0…1 (1 = full
  /// scale), lowest band first.
  final Float32List? bands;

  /// RMS level per output channel over the window, 0…1.
  final List<double> rms;

  /// Peak level per output channel over the window, 0…1.
  final List<double> peak;
}
