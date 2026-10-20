import 'package:flutter_test/flutter_test.dart';
import 'package:mediahro/features/photos/timeline/timeline_model.dart';

PhotoEntry entry(
  int id,
  DateTime date, {
  int? w,
  int? h,
  int? orientation,
  String ext = 'jpg',
}) => PhotoEntry(
  id: id,
  sourceId: 1,
  relPath: 'p/$id.$ext',
  name: '$id.$ext',
  ext: ext,
  isVideo: false,
  size: 1000,
  mtime: date,
  date: date,
  width: w,
  height: h,
  orientation: orientation,
);

/// [perDay] photos per day for [days] days, newest first.
List<PhotoEntry> days(int days, int perDay) {
  var id = 0;
  return [
    for (var d = 0; d < days; d++)
      for (var k = 0; k < perDay; k++)
        entry(id++, DateTime(2026, 10, 20 - d, 12, 59 - k)),
  ];
}

void main() {
  group('IMG-003 timeline layout', () {
    test(
      'IMG-003 sections follow the day and rows follow the column count',
      () {
        final l = TimelineLayout.build(days(3, 7), width: 300);
        expect(l.sections, hasLength(3));
        expect(l.sections.map((s) => s.count), [7, 7, 7]);
        // header + ceil(7/3)=3 rows per section
        expect(l.rows, hasLength(3 * 4));
        final firstTiles = l.rows[1] as TileRow;
        expect(firstTiles.count, 3);
        expect(firstTiles.widths.first, closeTo((300 - 2 * 2) / 3, 1e-9));
        final last = l.rows[3] as TileRow;
        expect(
          last.count,
          1,
          reason: 'the last row of a day holds the remainder',
        );
      },
    );

    test('IMG-003 month grouping merges the days of a month', () {
      final l = TimelineLayout.build(
        days(5, 4),
        width: 300,
        grouping: TimelineGrouping.month,
      );
      expect(l.sections, hasLength(1));
      expect(l.sections.single.count, 20);
      expect(l.sections.single.date, DateTime(2026, 10));
    });

    test('IMG-003 total height is the sum of headings, rows and gaps', () {
      final l = TimelineLayout.build(days(2, 6), width: 302, headerHeight: 40);
      const cell = (302 - 4) / 3;
      // 2 sections × (header + 2 rows of cell + gap)
      expect(l.totalHeight, closeTo(2 * (40 + 2 * (cell + 2)), 1e-9));
    });

    test('IMG-003 rowAt finds the row for any offset, clamped at the ends', () {
      final l = TimelineLayout.build(days(10, 9), width: 300);
      expect(l.rowAt(-50), 0);
      expect(l.rowAt(l.totalHeight + 999), l.rows.length - 1);
      for (final i in [0, 5, 17, l.rows.length - 1]) {
        expect(l.rowAt(l.rows[i].top), i);
        expect(l.rowAt(l.rows[i].top + l.rows[i].height - 0.5), i);
      }
    });

    test('IMG-003 entryAt hits tiles, not headings or gaps', () {
      final l = TimelineLayout.build(days(1, 6), width: 302);
      final r = l.rectOf(4);
      expect(l.entryAt(r.center), 4);
      expect(l.entryAt(const Offset(10, 10)), isNull, reason: 'the heading');
      final gapX = l.rectOf(0).right + 1;
      expect(l.entryAt(Offset(gapX, l.rectOf(0).center.dy)), isNull);
      expect(l.entryAt(const Offset(-5, 100)), isNull);
    });

    test('IMG-003 entriesBetween gives the entry range of a viewport', () {
      final l = TimelineLayout.build(days(20, 12), width: 300);
      final r = l.entriesBetween(500, 900)!;
      expect(r.first, lessThanOrEqualTo(r.last));
      final firstRect = l.rectOf(r.first);
      expect(firstRect.bottom, greaterThan(500 - l.rows[l.rowAt(500)].height));
      expect(l.entriesBetween(0, 100), isNotNull);
      expect(l.entriesBetween(0, 1), isNull, reason: 'only a heading in view');
      expect(
        TimelineLayout.build([], width: 300).entriesBetween(0, 100),
        isNull,
      );
    });

    test('IMG-003 sectionAt and offsetOfSection agree (scrubber)', () {
      final l = TimelineLayout.build(days(30, 5), width: 300);
      for (var s = 0; s < l.sections.length; s += 7) {
        final off = l.offsetOfSection(s);
        expect(l.sectionAt(off), l.sections[s]);
      }
    });

    test(
      'IMG-003 layout of 100 000 items builds quickly and keeps exact totals',
      () {
        final entries = days(2000, 50);
        expect(entries, hasLength(100000));
        final sw = Stopwatch()..start();
        final l = TimelineLayout.build(entries, width: 400, columns: 4);
        expect(sw.elapsedMilliseconds, lessThan(500));
        final counted = l.rows.whereType<TileRow>().fold<int>(
          0,
          (n, r) => n + r.count,
        );
        expect(counted, 100000);
      },
    );
  });

  group('IMG-003 justified rows', () {
    test('IMG-003 full rows span the width exactly', () {
      final es = [
        for (var i = 0; i < 12; i++)
          entry(
            i,
            DateTime(2026, 10, 20, 12, 59 - i),
            w: 4000,
            h: i.isEven ? 3000 : 6000,
          ),
      ];
      final l = TimelineLayout.build(es, width: 360, justified: true);
      for (final r in l.rows.whereType<TileRow>().toList()..removeLast()) {
        final total =
            r.widths.fold<double>(0, (a, b) => a + b) + (r.count - 1) * 2;
        expect(total, closeTo(360, 1e-6));
      }
    });

    test('IMG-003 a short last row keeps the target height', () {
      final es = [
        entry(0, DateTime(2026, 10, 20), w: 100, h: 100),
        entry(1, DateTime(2026, 10, 20), w: 100, h: 100),
      ];
      final l = TimelineLayout.build(
        es,
        width: 360,
        justified: true,
        targetRowHeight: 100,
      );
      final row = l.rows.last as TileRow;
      expect(row.height, 100);
      expect(row.widths, [100, 100]);
    });

    test('IMG-003 rotated EXIF orientations swap the aspect ratio', () {
      final e = entry(0, DateTime(2026), w: 4000, h: 3000, orientation: 6);
      expect(e.aspect, closeTo(3 / 4, 1e-9));
      expect(entry(1, DateTime(2026)).aspect, closeTo(4 / 3, 1e-9));
    });
  });

  test('IMG-001 RAW entries are recognised by extension', () {
    expect(entry(0, DateTime(2026), ext: 'cr3').isRaw, isTrue);
    expect(entry(0, DateTime(2026)).isRaw, isFalse);
  });
}
