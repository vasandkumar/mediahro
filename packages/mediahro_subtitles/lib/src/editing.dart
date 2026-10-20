import 'package:mediahro_subtitles/src/subtitle_parser.dart';

/// Timing and structure edits for the subtitle editor (SUB-030). Every
/// operation returns a new document; times never go below zero and cues
/// stay sorted by start.
extension SubtitleEditing on SubtitleDocument {
  SubtitleDocument _with(List<SubtitleCue> cues) =>
      copyWith(cues: [...cues]..sort((a, b) => a.start.compareTo(b.start)));

  static Duration _clamp(Duration d) => d.isNegative ? Duration.zero : d;

  Iterable<int> _range(int? from, int? to) sync* {
    final a = (from ?? 0).clamp(0, cues.length);
    final b = (to ?? cues.length - 1).clamp(-1, cues.length - 1);
    for (var i = a; i <= b; i++) {
      yield i;
    }
  }

  /// Moves cues [from]…[to] (all by default) by [offset].
  SubtitleDocument shift(Duration offset, {int? from, int? to}) {
    final picked = _range(from, to).toSet();
    return _with([
      for (final (i, c) in cues.indexed)
        if (picked.contains(i))
          c.copyWith(
            start: _clamp(c.start + offset),
            end: _clamp(c.end + offset),
          )
        else
          c,
    ]);
  }

  /// Multiplies every time by [factor], e.g. 25 / 23.976 to convert
  /// subtitles timed for 23.976 fps to a 25 fps video.
  SubtitleDocument stretch(double factor) => _with([
    for (final c in cues)
      c.copyWith(start: _scale(c.start, factor), end: _scale(c.end, factor)),
  ]);

  static Duration _scale(Duration d, double f) =>
      Duration(microseconds: (d.inMicroseconds * f).round());

  /// Resync by two points: the cue that shows at [from1] should show at
  /// [to1], and [from2] at [to2]. Times in between and beyond follow the
  /// straight line through both, which fixes both an offset and a drift.
  SubtitleDocument resync({
    required Duration from1,
    required Duration to1,
    required Duration from2,
    required Duration to2,
  }) {
    final span = from2 - from1;
    if (span == Duration.zero) return shift(to1 - from1);
    final factor = (to2 - to1).inMicroseconds / span.inMicroseconds;
    Duration map(Duration t) => _clamp(
      to1 +
          Duration(microseconds: ((t - from1).inMicroseconds * factor).round()),
    );
    return _with([
      for (final c in cues) c.copyWith(start: map(c.start), end: map(c.end)),
    ]);
  }

  SubtitleDocument replaceCue(int index, SubtitleCue cue) =>
      _with([...cues]..[index] = cue);

  SubtitleDocument insertCue(SubtitleCue cue) => _with([...cues, cue]);

  SubtitleDocument removeCues(Set<int> indexes) => _with([
    for (final (i, c) in cues.indexed)
      if (!indexes.contains(i)) c,
  ]);

  /// Splits cue [index] at [at] (inside it). The text splits at its middle
  /// line break when it has one, else both halves keep it.
  SubtitleDocument split(int index, Duration at) {
    final c = cues[index];
    if (at <= c.start || at >= c.end) return this;
    final lines = c.text.split('\n');
    final half = lines.length ~/ 2;
    final (first, second) = lines.length > 1
        ? (lines.take(half).join('\n'), lines.skip(half).join('\n'))
        : (c.text, c.text);
    return _with([
      ...cues.take(index),
      c.copyWith(end: at, text: first),
      c.copyWith(start: at, text: second),
      ...cues.skip(index + 1),
    ]);
  }

  /// Joins cues [from]…[to] into one spanning them all; texts stack.
  SubtitleDocument merge(int from, int to) {
    if (to <= from) return this;
    final group = cues.sublist(from, to + 1);
    final merged = group.first.copyWith(
      end: group.map((c) => c.end).reduce((a, b) => a > b ? a : b),
      text: group.map((c) => c.text).where((t) => t.isNotEmpty).join('\n'),
    );
    return _with([...cues.take(from), merged, ...cues.skip(to + 1)]);
  }

  /// Ends each cue no later than the next one starts (overlaps from bad
  /// timing), keeping at least [minimum] on screen.
  SubtitleDocument fixOverlaps({
    Duration minimum = const Duration(milliseconds: 300),
  }) {
    final sorted = [...cues]..sort((a, b) => a.start.compareTo(b.start));
    return copyWith(
      cues: [
        for (var i = 0; i < sorted.length; i++)
          if (i + 1 < sorted.length && sorted[i].end > sorted[i + 1].start)
            sorted[i].copyWith(
              end: sorted[i + 1].start - sorted[i].start < minimum
                  ? sorted[i].start + minimum
                  : sorted[i + 1].start,
            )
          else
            sorted[i],
      ],
    );
  }

  /// Index of the cue showing at [t], or -1.
  int cueAt(Duration t) {
    for (var i = 0; i < cues.length; i++) {
      if (cues[i].start <= t && t < cues[i].end) return i;
    }
    return -1;
  }
}
