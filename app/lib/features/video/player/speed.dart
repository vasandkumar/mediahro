/// Playback speed rules (VID-062): 0.25–4.0× in 0.05 steps; the engine
/// keeps pitch with scaletempo2.
abstract final class PlaybackSpeed {
  static const double min = 0.25;
  static const double max = 4;
  static const double step = 0.05;

  /// Keyboard `[` / `]` step (docs/06 §6.2).
  static const double nudge = 0.1;

  /// Quick presets in the speed sheet.
  static const List<double> presets = [0.5, 0.75, 1, 1.25, 1.5, 1.75, 2, 3];

  /// Clamps to the range and snaps to the 0.05 grid.
  static double normalize(double rate) {
    final clamped = rate.clamp(min, max);
    final snapped = (clamped / step).round() * step;
    // Two decimals: 1.1500000000000001 → 1.15.
    return double.parse(snapped.toStringAsFixed(2)).clamp(min, max);
  }
}

/// Where a chosen speed is remembered (VID-062).
enum SpeedMemory {
  /// Each item keeps its own speed; new items start at 1×.
  perItem,

  /// One speed for everything: the last one chosen.
  global,

  /// Every item starts at 1×.
  off,
}
