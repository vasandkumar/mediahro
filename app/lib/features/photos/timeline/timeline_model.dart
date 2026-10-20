import 'dart:math' as math;
import 'dart:ui' show Offset, Rect;

import 'package:mediahro/images/image_format.dart';
import 'package:meta/meta.dart';

/// One photo or video in the timeline: only the columns the grid and the
/// viewer need, so 100 k of them stay around 10 MB.
@immutable
final class PhotoEntry {
  PhotoEntry({
    required this.id,
    required this.sourceId,
    required this.relPath,
    required this.name,
    required this.ext,
    required this.isVideo,
    required this.size,
    required this.mtime,
    required this.date,
    this.width,
    this.height,
    this.durationMs,
    this.orientation,
    this.favourite = false,
    this.rejected = false,
    this.livePhoto = false,
    this.motionPhoto = false,
    this.hdr = false,
  }) : dayKey = date.year * 10000 + date.month * 100 + date.day;

  final int id;
  final int sourceId;
  final String relPath;
  final String name;

  /// Lower-case extension without the dot.
  final String ext;
  final bool isVideo;
  final int size;
  final DateTime mtime;

  /// Capture time, or the file time when the file has none.
  final DateTime date;

  /// `yyyymmdd` of [date] in local time, for grouping without calendar
  /// arithmetic (100 k entries group in milliseconds).
  final int dayKey;
  final int? width;
  final int? height;

  /// Video length.
  final int? durationMs;

  /// EXIF orientation 1–8 when known.
  final int? orientation;
  final bool favourite;

  /// Marked as rejected while comparing (XMP rating -1).
  final bool rejected;
  final bool livePhoto;
  final bool motionPhoto;
  final bool hdr;

  bool get isRaw => rawExtensions.contains(ext);

  /// Display aspect ratio (width / height) with orientation applied;
  /// 4:3 until the prober has read the size.
  double get aspect {
    final w = width;
    final h = height;
    if (w == null || h == null || w <= 0 || h <= 0) return 4 / 3;
    final turned = (orientation ?? 1) >= 5;
    return turned ? h / w : w / h;
  }
}

/// A run of entries under one heading (a day or a month).
@immutable
final class TimelineSection {
  const TimelineSection(this.date, this.firstEntry, this.count);

  /// First instant of the day (or month) the section covers.
  final DateTime date;
  final int firstEntry;
  final int count;
}

enum TimelineGrouping { day, month }

sealed class TimelineRow {
  const TimelineRow(this.top, this.height, this.section);

  final double top;
  final double height;
  final int section;

  double get bottom => top + height;
}

final class HeaderRow extends TimelineRow {
  const HeaderRow(super.top, super.height, super.section);
}

final class TileRow extends TimelineRow {
  const TileRow(
    super.top,
    super.height,
    super.section,
    this.firstEntry,
    this.widths,
  );

  /// Index into the entry list of the row's first tile.
  final int firstEntry;

  /// Width of each tile in the row (all equal for a square grid).
  final List<double> widths;

  int get count => widths.length;
}

/// Positions of every section heading and tile for a given width: pure
/// geometry, so scrolling, the scrubber, drag-select and prefetch can all
/// be computed without building widgets.
final class TimelineLayout {
  TimelineLayout._(
    this.entries,
    this.sections,
    this.rows,
    this.totalHeight,
    this.gap,
  );

  /// Lays out [entries] (newest first) for a viewport [width].
  ///
  /// With [justified] false the grid is square with [columns] columns
  /// (IMG-003: 1–6 on phones, up to 12 on desktop); with true each row is
  /// filled with the photos' real aspect ratios at about [targetRowHeight].
  factory TimelineLayout.build(
    List<PhotoEntry> entries, {
    required double width,
    int columns = 3,
    bool justified = false,
    double gap = 2,
    double headerHeight = 48,
    double targetRowHeight = 120,
    TimelineGrouping grouping = TimelineGrouping.day,
  }) {
    final sections = <TimelineSection>[];
    final byMonth = grouping == TimelineGrouping.month;
    int key(PhotoEntry e) => byMonth ? e.dayKey ~/ 100 : e.dayKey;
    DateTime startOf(PhotoEntry e) => byMonth
        ? DateTime(e.date.year, e.date.month)
        : DateTime(e.date.year, e.date.month, e.date.day);
    var start = 0;
    for (var i = 1; i <= entries.length; i++) {
      if (i == entries.length || key(entries[i]) != key(entries[start])) {
        sections.add(
          TimelineSection(startOf(entries[start]), start, i - start),
        );
        start = i;
      }
    }
    final rows = <TimelineRow>[];
    var y = 0.0;
    final cols = math.max(1, columns);
    final cell = (width - gap * (cols - 1)) / cols;
    for (var s = 0; s < sections.length; s++) {
      final sec = sections[s];
      rows.add(HeaderRow(y, headerHeight, s));
      y += headerHeight;
      var i = sec.firstEntry;
      final end = sec.firstEntry + sec.count;
      while (i < end) {
        if (!justified) {
          final n = math.min(cols, end - i);
          rows.add(TileRow(y, cell, s, i, List.filled(n, cell)));
          y += cell + gap;
          i += n;
        } else {
          var sum = 0.0;
          var j = i;
          while (j < end) {
            sum += entries[j].aspect;
            j++;
            final needed = (j - i - 1) * gap;
            if (sum * targetRowHeight + needed >= width) break;
          }
          final n = j - i;
          final avail = width - (n - 1) * gap;
          final full = sum * targetRowHeight + (n - 1) * gap >= width;
          // A short last row keeps the target height instead of stretching.
          final h = full ? avail / sum : targetRowHeight;
          rows.add(
            TileRow(y, h, s, i, [
              for (var k = i; k < j; k++) entries[k].aspect * h,
            ]),
          );
          y += h + gap;
          i = j;
        }
      }
    }
    return TimelineLayout._(entries, sections, rows, y, gap);
  }

  final List<PhotoEntry> entries;
  final List<TimelineSection> sections;
  final List<TimelineRow> rows;
  final double totalHeight;
  final double gap;

  /// Index of the row containing scroll [offset] (clamped).
  int rowAt(double offset) {
    if (rows.isEmpty) return 0;
    var lo = 0;
    var hi = rows.length - 1;
    while (lo < hi) {
      final mid = (lo + hi + 1) >> 1;
      if (rows[mid].top <= offset) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    return lo;
  }

  /// The entry under a point in scroll coordinates, or null on a heading
  /// or in a gap.
  int? entryAt(Offset p) {
    if (rows.isEmpty || p.dy < 0 || p.dy > totalHeight) return null;
    final row = rows[rowAt(p.dy)];
    if (row is! TileRow || p.dy > row.bottom) return null;
    var x = 0.0;
    for (var k = 0; k < row.count; k++) {
      if (p.dx >= x && p.dx <= x + row.widths[k]) return row.firstEntry + k;
      x += row.widths[k] + gap;
    }
    return null;
  }

  /// Rectangle of entry [index] in scroll coordinates.
  Rect rectOf(int index) {
    for (final r in rows) {
      if (r is TileRow &&
          index >= r.firstEntry &&
          index < r.firstEntry + r.count) {
        var x = 0.0;
        for (var k = 0; k < index - r.firstEntry; k++) {
          x += r.widths[k] + gap;
        }
        return Rect.fromLTWH(
          x,
          r.top,
          r.widths[index - r.firstEntry],
          r.height,
        );
      }
    }
    return Rect.zero;
  }

  /// Entries whose rows intersect [from, to] in scroll coordinates.
  ({int first, int last})? entriesBetween(double from, double to) {
    if (entries.isEmpty || rows.isEmpty) return null;
    var first = -1;
    var last = -1;
    for (var r = rowAt(from); r < rows.length && rows[r].top <= to; r++) {
      final row = rows[r];
      if (row is! TileRow) continue;
      if (first < 0) first = row.firstEntry;
      last = row.firstEntry + row.count - 1;
    }
    return first < 0 ? null : (first: first, last: last);
  }

  /// The section a scroll [offset] falls in (for the scrubber label).
  TimelineSection? sectionAt(double offset) =>
      rows.isEmpty ? null : sections[rows[rowAt(offset)].section];

  /// Scroll offset of the start of section [index].
  double offsetOfSection(int index) {
    for (final r in rows) {
      if (r is HeaderRow && r.section == index) return r.top;
    }
    return 0;
  }
}
