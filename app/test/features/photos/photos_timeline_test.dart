import 'package:flutter/material.dart' hide ImageInfo;
import 'package:flutter_test/flutter_test.dart';
import 'package:mediahro/features/photos/timeline/photo_grid.dart';
import 'package:mediahro/images/image_pipeline.dart';
import 'package:mediahro_design/mediahro_design.dart';

import 'photos_harness.dart';

void main() {
  testWidgets('IMG-003 the timeline groups photos under Today and Yesterday', (
    tester,
  ) async {
    final h = await PhotosHarness.create(tester);
    await h.pump(tester, entries: fakeEntries());
    expect(find.text('Today'), findsOneWidget);
    expect(find.text('Yesterday'), findsOneWidget);
    expect(find.byType(KGridTile), findsWidgets);
  });

  testWidgets('IMG-003 an empty library shows the empty state', (tester) async {
    final h = await PhotosHarness.create(tester);
    await h.pump(tester, entries: const []);
    expect(find.text('No photos yet'), findsOneWidget);
    expect(find.text('Add photos'), findsOneWidget);
    expect(find.byType(KGridTile), findsNothing);
  });

  testWidgets(
    'IMG-003 RAW, Live, Motion and HDR badges and video length show',
    (tester) async {
      final h = await PhotosHarness.create(tester);
      await h.pump(
        tester,
        entries: fakeEntries(
          days: 1,
          raw: {0},
          live: {1},
          motion: {2},
          hdr: {3},
          videos: {4},
        ),
      );
      expect(find.text('RAW'), findsOneWidget);
      expect(find.text('Live'), findsOneWidget);
      expect(find.text('Motion'), findsOneWidget);
      expect(find.text('HDR'), findsOneWidget);
      expect(find.text('1:23'), findsOneWidget);
    },
  );

  testWidgets('IMG-003 tiles have spoken labels with the kind and the date', (
    tester,
  ) async {
    final h = await PhotosHarness.create(tester);
    await h.pump(tester, entries: fakeEntries(days: 1, videos: {1}));
    final handle = tester.ensureSemantics();
    expect(find.bySemanticsLabel(RegExp('^Photo from ')), findsWidgets);
    expect(find.bySemanticsLabel(RegExp('^Video from ')), findsOneWidget);
    handle.dispose();
  });

  testWidgets(
    'IMG-003 only about a screen of thumbnails is requested up front',
    (tester) async {
      final h = await PhotosHarness.create(tester);
      await h.pump(tester, entries: fakeEntries(days: 40, perDay: 12));
      expect(h.thumbs.loads, isNotEmpty);
      // 480 photos in the library, a few dozen requested.
      expect(h.thumbs.loads.length, lessThan(120));
      // The tiles on screen were asked for at visible priority.
      expect(
        h.thumbs.loads.take(8).every((l) => l.$2 == ThumbnailPriority.visible),
        isTrue,
      );
    },
  );

  testWidgets('IMG-003 scrolling re-prioritises and releases far tiles', (
    tester,
  ) async {
    final h = await PhotosHarness.create(tester);
    h.thumbs.hold = true;
    await h.pump(tester, entries: fakeEntries(days: 60, perDay: 12));
    final before = h.thumbs.loads.length;
    await tester.fling(
      find.byType(ListView).first,
      const Offset(0, -2000),
      3000,
    );
    await tester.pumpAndSettle();
    expect(h.thumbs.loads.length, greaterThan(before));
    expect(
      h.thumbs.cancelled,
      isNotEmpty,
      reason: 'tiles that left the screen',
    );
  });

  testWidgets('IMG-003 the density menu changes the number of columns', (
    tester,
  ) async {
    final h = await PhotosHarness.create(tester);
    await h.pump(tester, entries: fakeEntries(days: 1, perDay: 24));
    final w4 = tester.getSize(find.byType(KGridTile).first).width;
    await tester.tap(find.byTooltip('Photo size'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(CheckedPopupMenuItem<int>, '2'));
    await tester.pumpAndSettle();
    final w2 = tester.getSize(find.byType(KGridTile).first).width;
    expect(w2, greaterThan(w4 * 1.7));
  });

  testWidgets('IMG-003 the layout button switches to proportional rows', (
    tester,
  ) async {
    final h = await PhotosHarness.create(tester);
    await h.pump(tester, entries: fakeEntries(days: 1, perDay: 12));
    final square = tester.getSize(find.byType(KGridTile).first);
    expect((square.width - square.height).abs(), lessThan(0.5));
    await tester.tap(find.byTooltip('Keep proportions'));
    await tester.pumpAndSettle();
    final wide = tester.getSize(find.byType(KGridTile).first);
    expect(wide.width, greaterThan(wide.height), reason: '4000×3000 photos');
    expect(find.byTooltip('Square grid'), findsOneWidget);
  });

  testWidgets('IMG-003 the scrubber jumps through the timeline', (
    tester,
  ) async {
    final h = await PhotosHarness.create(tester);
    await h.pump(tester, entries: fakeEntries(days: 90));
    final scrubber = find.byType(KTimelineScrubber);
    expect(scrubber, findsOneWidget);
    final list = tester.state<ScrollableState>(
      find.descendant(
        of: find.byType(PhotoGrid),
        matching: find.byType(Scrollable),
      ),
    );
    expect(list.position.pixels, 0);
    final box = tester.getRect(scrubber);
    await tester.dragFrom(
      Offset(box.right - 12, box.top + 24),
      Offset(0, box.height / 2),
    );
    await tester.pumpAndSettle();
    expect(list.position.pixels, greaterThan(500));
  });

  testWidgets('IMG-003 tapping a tile opens the viewer on that photo', (
    tester,
  ) async {
    final h = await PhotosHarness.create(tester);
    final entries = fakeEntries();
    await h.pump(tester, entries: entries);
    await tester.tap(find.byType(KGridTile).at(2));
    await tester.pumpAndSettle();
    expect(h.opened.map((e) => e.id), contains(entries[2].id));
    expect(find.text(entries[2].name), findsOneWidget);
  });
}
