import 'dart:io';

import 'package:flutter/material.dart' hide ImageInfo;
import 'package:flutter_test/flutter_test.dart';
import 'package:mediahro/features/photos/photos_providers.dart';
import 'package:mediahro/features/photos/timeline/timeline_model.dart';
import 'package:mediahro/features/photos/trash/app_trash.dart';
import 'package:mediahro_design/mediahro_design.dart';

import 'photos_harness.dart';

/// A bin that keeps its list in memory.
final class FakeTrash implements PhotoTrash {
  FakeTrash([List<TrashedPhoto>? start]) : items = [...?start];

  final List<TrashedPhoto> items;
  final List<TrashedPhoto> restored = [];
  final List<PhotoEntry> moved = [];
  bool failMoves = false;

  @override
  Duration get keepFor => const Duration(days: 30);

  @override
  Future<List<TrashedPhoto>> list() async => [...items];

  @override
  File fileOf(TrashedPhoto t) => File('/nonexistent/${t.id}.bin');

  @override
  Future<TrashOutcome> moveToTrash(List<PhotoEntry> photos) async {
    if (failMoves) {
      return TrashOutcome(failed: [for (final p in photos) p.name]);
    }
    moved.addAll(photos);
    final out = [
      for (final p in photos)
        TrashedPhoto(
          id: 'new_${p.id}',
          name: p.name,
          origin: Uri.parse('file:///x/${p.name}'),
          size: p.size,
          deletedAt: DateTime.now(),
          itemId: p.id,
          isVideo: p.isVideo,
        ),
    ];
    items.insertAll(0, out);
    return TrashOutcome(moved: out);
  }

  @override
  Future<int> restore(List<TrashedPhoto> list) async {
    restored.addAll(list);
    items.removeWhere((t) => list.any((x) => x.id == t.id));
    return list.length;
  }

  @override
  Future<void> deleteForever(List<TrashedPhoto> list) async =>
      items.removeWhere((t) => list.any((x) => x.id == t.id));

  @override
  Future<void> empty() async => items.clear();

  @override
  Future<int> purge() async => 0;
}

TrashedPhoto _old(int n, {int daysAgo = 0}) => TrashedPhoto(
  id: 'old_$n',
  name: 'OLD_$n.jpg',
  origin: Uri.parse('file:///x/OLD_$n.jpg'),
  size: 100,
  deletedAt: DateTime.now().subtract(Duration(days: daysAgo)),
  itemId: 100 + n,
  isVideo: false,
);

void main() {
  late FakeTrash trash;

  Future<PhotosHarness> open(
    WidgetTester tester, {
    List<TrashedPhoto> inBin = const [],
  }) async {
    trash = FakeTrash(inBin);
    final h = await PhotosHarness.create(tester);
    await h.pump(
      tester,
      entries: fakeEntries(days: 1, firstId: 1),
      extra: [appTrashProvider.overrideWithValue(trash)],
    );
    return h;
  }

  Future<void> toTrashScreen(WidgetTester tester) async {
    await tester.ensureVisible(find.text('Albums'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Albums'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Recently deleted'));
    await tester.pumpAndSettle();
  }

  Future<void> deleteSelected(WidgetTester tester) async {
    await tester.tap(find.byTooltip('More'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
  }

  testWidgets('IMG-014 the Albums tab leads to Recently deleted', (
    tester,
  ) async {
    await open(tester);
    await tester.tap(find.text('Albums'));
    await tester.pumpAndSettle();
    expect(find.text('Recently deleted'), findsOneWidget);
    expect(find.text('Nothing here'), findsOneWidget);
    await tester.tap(find.text('Recently deleted'));
    await tester.pumpAndSettle();
    expect(find.text('Nothing deleted'), findsOneWidget);
    expect(find.textContaining('30 days'), findsOneWidget);
  });

  testWidgets('IMG-014 the tile counts what is in the bin', (tester) async {
    await open(tester, inBin: [_old(1), _old(2)]);
    await tester.tap(find.text('Albums'));
    await tester.pumpAndSettle();
    expect(find.text('2 photos'), findsOneWidget);
  });

  testWidgets('IMG-014 deleting asks, moves the photo, and can be undone', (
    tester,
  ) async {
    await open(tester);
    await tester.longPress(find.byType(KGridTile).first);
    await tester.pumpAndSettle();
    await deleteSelected(tester);
    expect(find.text('Delete this photo?'), findsOneWidget);
    expect(find.textContaining('30 days'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(trash.moved.single.name, 'IMG_1.jpg');
    expect(find.text('1 photo deleted.'), findsOneWidget);
    await tester.tap(find.text('Undo'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(trash.restored.single.name, 'IMG_1.jpg');
    expect(trash.items, isEmpty);
  });

  testWidgets('IMG-014 cancelling the question deletes nothing', (
    tester,
  ) async {
    await open(tester);
    await tester.longPress(find.byType(KGridTile).first);
    await tester.pumpAndSettle();
    await deleteSelected(tester);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(trash.moved, isEmpty);
  });

  testWidgets('IMG-014 several selected photos are deleted together', (
    tester,
  ) async {
    await open(tester);
    await tester.longPress(find.byType(KGridTile).at(0));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(KGridTile).at(1));
    await tester.pumpAndSettle();
    await deleteSelected(tester);
    expect(find.text('Delete 2 photos?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(trash.moved, hasLength(2));
    expect(find.text('2 photos deleted.'), findsOneWidget);
  });

  testWidgets('IMG-014 photos that cannot be deleted are reported', (
    tester,
  ) async {
    await open(tester);
    trash.failMoves = true;
    await tester.longPress(find.byType(KGridTile).first);
    await tester.pumpAndSettle();
    await deleteSelected(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('1 photo could not be deleted.'), findsOneWidget);
    expect(find.text('Undo'), findsNothing);
  });

  testWidgets('IMG-014 the viewer can delete the photo it shows', (
    tester,
  ) async {
    await open(tester);
    await tester.tap(find.byType(KGridTile).first);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('More'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(trash.moved.single.name, 'IMG_1.jpg');
  });

  testWidgets('IMG-014 the bin shows what can be restored, with days left', (
    tester,
  ) async {
    await open(tester, inBin: [_old(1), _old(2, daysAgo: 20)]);
    await toTrashScreen(tester);
    expect(find.text('30 days left'), findsOneWidget);
    expect(find.text('10 days left'), findsOneWidget);
  });

  testWidgets('IMG-014 restore brings photos back', (tester) async {
    await open(tester, inBin: [_old(1), _old(2)]);
    await toTrashScreen(tester);
    await tester.tap(find.byType(InkWell).first);
    await tester.pump();
    expect(find.text('1 selected'), findsOneWidget);
    await tester.tap(find.byTooltip('Restore'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('1 photo restored.'), findsOneWidget);
    expect(trash.items, hasLength(1));
  });

  testWidgets('IMG-014 deleting for good asks first', (tester) async {
    await open(tester, inBin: [_old(1), _old(2)]);
    await toTrashScreen(tester);
    await tester.tap(find.byType(InkWell).first);
    await tester.pump();
    await tester.tap(find.byTooltip('Delete for good'));
    await tester.pumpAndSettle();
    expect(find.textContaining("can't be undone"), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(trash.items, hasLength(2));
    await tester.tap(find.byTooltip('Delete for good'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete for good'));
    await tester.pumpAndSettle();
    expect(trash.items, hasLength(1));
  });

  testWidgets('IMG-014 empty clears the whole bin after a question', (
    tester,
  ) async {
    await open(tester, inBin: [_old(1), _old(2), _old(3)]);
    await toTrashScreen(tester);
    await tester.tap(find.text('Empty'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete for good'));
    await tester.pumpAndSettle();
    expect(trash.items, isEmpty);
    expect(find.text('Nothing deleted'), findsOneWidget);
  });
}
