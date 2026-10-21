import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart' hide ImageInfo;
import 'package:flutter_test/flutter_test.dart';
import 'package:mediahro/core/db/library_database.dart';
import 'package:mediahro/features/photos/timeline/source_filter.dart';
import 'package:mediahro/features/photos/timeline/timeline_model.dart';
import 'package:mediahro_design/mediahro_design.dart';

import 'photos_harness.dart';

/// [entries] moved to source [id].
List<PhotoEntry> onSource(List<PhotoEntry> entries, int id) => [
  for (final e in entries)
    PhotoEntry(
      id: e.id,
      sourceId: id,
      relPath: e.relPath,
      name: e.name,
      ext: e.ext,
      isVideo: e.isVideo,
      size: e.size,
      mtime: e.mtime,
      date: e.date,
      width: e.width,
      height: e.height,
    ),
];

Future<int> addSource(
  LibraryDatabase db,
  String name,
  SourceKind kind, {
  ScanJobState? lastScan,
}) async {
  final id = await db
      .into(db.sources)
      .insert(
        SourcesCompanion.insert(
          kind: kind,
          name: name,
          rootUri: 'file:///$name/',
          addedAt: DateTime.utc(2026),
        ),
      );
  if (lastScan != null) {
    await db
        .into(db.scanJobs)
        .insert(ScanJobsCompanion.insert(sourceId: id, state: Value(lastScan)));
  }
  return id;
}

void main() {
  group('IMG-016 which sources the timeline lists', () {
    final phone = fakeEntries(days: 1, perDay: 5);
    final nas = onSource(fakeEntries(days: 1, perDay: 3, firstId: 100), 2);

    test('IMG-016 sources are counted from the photos, biggest first', () {
      final s = timelineSources([...phone, ...nas], const [], (id) => 'S$id');
      expect(s.map((e) => (e.id, e.count, e.name)), [
        (1, 5, 'S1'),
        (2, 3, 'S2'),
      ]);
    });

    test('IMG-016 a filter that names no listed source shows everything', () {
      final all = [...phone, ...nas];
      final s = timelineSources(all, const [], (id) => 'S$id');
      expect(filterBySource(all, null, s), hasLength(8));
      expect(filterBySource(all, 2, s), hasLength(3));
      expect(filterBySource(all, 9, s), hasLength(8));
    });
  });

  group('IMG-016 the source chips on the timeline', () {
    testWidgets('IMG-016 one source: no chips', (tester) async {
      final h = await PhotosHarness.create(tester);
      await tester.runAsync(() => addSource(h.db, 'Phone', SourceKind.local));
      await h.pump(tester, entries: fakeEntries(days: 1, perDay: 4));
      expect(find.byType(ChoiceChip), findsNothing);
      expect(find.byType(KGridTile), findsWidgets);
    });

    testWidgets('IMG-016 two sources: the chips filter the grid', (
      tester,
    ) async {
      final h = await PhotosHarness.create(tester);
      await tester.runAsync(() async {
        await addSource(h.db, 'Phone', SourceKind.local);
        await addSource(h.db, 'NAS', SourceKind.webdav);
      });
      final phone = fakeEntries(days: 1, perDay: 5);
      final nas = onSource(fakeEntries(days: 1, perDay: 3, firstId: 100), 2);
      await h.pump(
        tester,
        entries: [...phone, ...nas],
        size: const Size(800, 800),
      );
      expect(find.text('All sources'), findsOneWidget);
      expect(find.text('Phone (5)'), findsOneWidget);
      expect(find.text('NAS (3)'), findsOneWidget);
      expect(find.byType(KGridTile), findsNWidgets(8));

      await tester.tap(find.text('NAS (3)'));
      await tester.pumpAndSettle();
      expect(find.byType(KGridTile), findsNWidgets(3));

      await tester.tap(find.text('Phone (5)'));
      await tester.pumpAndSettle();
      expect(find.byType(KGridTile), findsNWidgets(5));

      await tester.tap(find.text('All sources'));
      await tester.pumpAndSettle();
      expect(find.byType(KGridTile), findsNWidgets(8));
    });

    testWidgets('IMG-016 a source that could not be reached says so', (
      tester,
    ) async {
      final h = await PhotosHarness.create(tester);
      await tester.runAsync(() async {
        await addSource(h.db, 'Phone', SourceKind.local);
        await addSource(
          h.db,
          'NAS',
          SourceKind.webdav,
          lastScan: ScanJobState.failed,
        );
      });
      final handle = tester.ensureSemantics();
      final phone = fakeEntries(days: 1, perDay: 5);
      final nas = onSource(fakeEntries(days: 1, perDay: 3, firstId: 100), 2);
      await h.pump(
        tester,
        entries: [...phone, ...nas],
        size: const Size(800, 800),
      );
      expect(find.byIcon(Icons.cloud_off_outlined), findsOneWidget);
      expect(
        find.bySemanticsLabel(RegExp('^NAS, not reachable')),
        findsOneWidget,
      );
      // Its photos are still listed, from what the library knows.
      await tester.tap(find.text('NAS (3)'));
      await tester.pumpAndSettle();
      expect(find.byType(KGridTile), findsNWidgets(3));
      handle.dispose();
    });

    testWidgets('IMG-016 the chips are big enough to touch', (tester) async {
      final h = await PhotosHarness.create(tester);
      await tester.runAsync(() async {
        await addSource(h.db, 'Phone', SourceKind.local);
        await addSource(h.db, 'NAS', SourceKind.webdav);
      });
      await h.pump(
        tester,
        entries: [
          ...fakeEntries(days: 1, perDay: 2),
          ...onSource(fakeEntries(days: 1, perDay: 2, firstId: 100), 2),
        ],
      );
      for (final chip in tester.widgetList<ChoiceChip>(
        find.byType(ChoiceChip),
      )) {
        final size = tester.getSize(find.byWidget(chip));
        expect(size.height >= 32, isTrue);
      }
      final bar = tester.getSize(find.byType(SourceFilterBar));
      expect(bar.height, greaterThanOrEqualTo(44));
    });
  });
}
