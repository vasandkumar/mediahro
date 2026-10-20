/// Detects a hardware video decoder that stopped producing frames while
/// mpv still reports playback (VID-002, VID-005).
///
/// Seen on Exynos `c2.exynos.h264.decoder`: a seek near the start while
/// playing flushes MediaCodec twice within milliseconds, the codec drops to
/// its uninitialised state, and video and position freeze with mpv still
/// `playing`. The engine then rebuilds the decoder in software for the rest
/// of the item, once; mpv resumes at the last shown frame.
final class StallGuard {
  StallGuard({this.threshold = const Duration(seconds: 3)});

  /// How long playback may make no progress before the decoder is rebuilt.
  final Duration threshold;

  Duration? _position;
  Duration _still = Duration.zero;
  bool _recovered = false;

  /// Feeds one observation [elapsed] after the previous one; true when the
  /// decoder should be rebuilt now. Only a playing item with video on a
  /// hardware decoder counts, and only once per item.
  bool check({
    required Duration elapsed,
    required Duration position,
    required bool playing,
    required bool hardwareVideo,
  }) {
    if (!playing || !hardwareVideo || position != _position) {
      _position = position;
      _still = Duration.zero;
      return false;
    }
    _still += elapsed;
    if (_recovered || _still < threshold) return false;
    _recovered = true;
    _still = Duration.zero;
    return true;
  }

  /// A new item: progress and the once-per-item limit start over.
  void reset() {
    _position = null;
    _still = Duration.zero;
    _recovered = false;
  }
}
