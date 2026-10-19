import 'package:intl/intl.dart';

/// `1:23:45` / `4:05` (docs/06 §8 "durations as 1:23:45").
String formatDuration(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes.remainder(60);
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return h > 0 ? '$h:${m.toString().padLeft(2, '0')}:$s' : '$m:$s';
}

/// Binary units with one decimal, locale number format (docs/06 §8):
/// `512 B`, `1.5 KiB`, `3.2 GiB`. Unit symbols are not translated (SI/IEC).
String formatBytes(int bytes, {String? locale}) {
  const units = ['B', 'KiB', 'MiB', 'GiB', 'TiB', 'PiB'];
  var v = bytes.toDouble();
  var u = 0;
  while (v >= 1024 && u < units.length - 1) {
    v /= 1024;
    u++;
  }
  final f = NumberFormat(u == 0 ? '0' : '0.0', locale);
  return '${f.format(v)} ${units[u]}';
}

/// `1080p`, `2160p (4K)` style label from a frame height.
String? resolutionLabel(int? height) {
  if (height == null || height <= 0) return null;
  if (height >= 4320) return '8K';
  if (height >= 2160) return '4K';
  if (height >= 1440) return '1440p';
  if (height >= 1080) return '1080p';
  if (height >= 720) return '720p';
  return '${height}p';
}

/// A count or year in the user's locale digits and grouping.
String formatCount(int n, {String? locale, bool grouping = true}) => grouping
    ? NumberFormat.decimalPattern(locale).format(n)
    : NumberFormat('0', locale).format(n);
