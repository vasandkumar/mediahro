/// Media durations as `1:23:45`, `3:07` or `0:05` (docs/06 §8). Hours appear
/// when the value (or [reference], e.g. the item's total length) reaches one
/// hour, so elapsed and total line up.
String formatMediaDuration(Duration d, {Duration? reference}) {
  final negative = d.isNegative;
  final abs = d.abs();
  final h = abs.inHours;
  final m = abs.inMinutes.remainder(60);
  final s = abs.inSeconds.remainder(60);
  final showHours = h > 0 || (reference != null && reference.inHours > 0);
  final ss = s.toString().padLeft(2, '0');
  final body = showHours
      ? '$h:${m.toString().padLeft(2, '0')}:$ss'
      : '${abs.inMinutes}:$ss';
  return negative ? '\u2212$body' : body;
}

/// Remaining time shown as a negative duration (`−3:07`).
String formatRemaining(Duration position, Duration total) =>
    formatMediaDuration(position - total, reference: total);
