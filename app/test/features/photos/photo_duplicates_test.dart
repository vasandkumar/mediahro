import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter/material.dart' hide ImageInfo;
import 'package:flutter_test/flutter_test.dart';
import 'package:mediahro/core/db/library_database.dart';
import 'package:mediahro/core/library/duplicates.dart';
import 'package:mediahro/features/photos/duplicates/duplicates_screen.dart';
import 'package:mediahro/features/photos/duplicates/photo_duplicates.dart';
import 'package:mediahro/features/photos/photos_providers.dart';
import 'package:mediahro/features/photos/timeline/timeline_model.dart';
import 'package:mediahro/images/image_pipeline.dart';
import 'package:mediahro/images/pipeline/image_worker.dart';
import 'package:mediahro/images/pipeline/mediahro_image_pipeline.dart';
import 'package:mediahro/images/pipeline/thumbnail_cache.dart';
import 'package:mediahro/images/pipeline/worker_pool.dart';
import 'package:mediahro_design/mediahro_design.dart';

import '../../core/seed.dart';
import '../../images/pipeline_fakes.dart';
import 'disk_support.dart';
import 'photos_harness.dart';
import 'trash_screen_test.dart' show FakeTrash;

/// A fake-format picture ([w, h, rgba...]) from a brightness function.
Uint8List picture(int w, int h, int Function(int x, int y) value) {
  final b = Uint8List(2 + w * h * 4)
    ..[0] = w
    ..[1] = h;
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final v = value(x, y).clamp(0, 255);
      final o = 2 + (y * w + x) * 4;
      b[o] = v;
      b[o + 1] = v;
      b[o + 2] = v;
      b[o + 3] = 255;
    }
  }
  return b;
}

DecodedImage decoded(int w, int h, int Function(int x, int y) value) {
  final p = picture(w, h, value);
  return DecodedImage(width: w, height: h, pixels: Uint8List.sublistView(p, 2));
}

void main() {
  group('IMG-013 greyscale thumbnail', () {
    test('IMG-013 a flat picture is flat', () {
      final g = grey32Of(decoded(64, 48, (x, y) => 90));
      expect(g, hasLength(1024));
      expect(g.every((v) => v == 90), isTrue);
    });

    test('IMG-013 left dark, right light stays left dark, right light', () {
      final g = grey32Of(decoded(64, 32, (x, y) => x < 32 ? 0 : 255));
      expect(g[5 * 32 + 2], 0);
      expect(g[5 * 32 + 30], 255);
    });

    test('IMG-013 colours are weighted like the eye sees them', () {
      final px = Uint8List.fromList([0, 255, 0, 255]);
      final green = grey32Of(DecodedImage(width: 1, height: 1, pixels: px));
      final blue = grey32Of(
        DecodedImage(
          width: 1,
          height: 1,
          pixels: Uint8List.fromList([0, 0, 255, 255]),
        ),
      );
      expect(green.first, greaterThan(blue.first * 4));
    });

    test('IMG-013 tiny and zero-size pictures do not fail', () {
      expect(grey32Of(decoded(2, 2, (x, y) => 200)).first, 200);
      expect(
        grey32Of(DecodedImage(width: 0, height: 0, pixels: Uint8List(0))),
        hasLength(1024),
      );
    });
  });

  group('IMG-013 scanner', () {
    late Directory dir;
    late LibraryDatabase db;
    late MediahroImagePipeline pipeline;
    late Seed seed;
    late PhotoDuplicateScanner scanner;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('mediahro-dups');
      db = LibraryDatabase.memory();
      seed = Seed(db);
      final io = DiskIo();
      pipeline = MediahroImagePipeline(
        worker: ImageWorkerClient(
          IsolateWorkerPool(size: 1, factory: fakeWorker),
        ),
        cache: ThumbnailCache(db: db, directory: Directory('${dir.path}/.t')),
        io: io,
        fallback: FakeUiFallback(),
      );
      scanner = PhotoDuplicateScanner(
        db: db,
        files: DiskFiles(dir, io),
        pipeline: pipeline,
      );
    });

    tearDown(() async {
      await pipeline.dispose();
      await db.close();
      dir.deleteSync(recursive: true);
    });

    Future<int> add(
      String rel,
      Uint8List bytes, {
      ItemKind kind = ItemKind.image,
    }) async {
      File('${dir.path}/$rel')
        ..createSync(recursive: true)
        ..writeAsBytesSync(bytes);
      return await seed.item(rel, kind: kind, size: bytes.length);
    }

    // A gradient with structure that survives small changes.
    final base = picture(64, 48, (x, y) => (x * 4 + y) % 256);
    final slightlyDarker = picture(64, 48, (x, y) => ((x * 4 + y) % 256) - 6);
    final different = picture(
      64,
      48,
      (x, y) => ((63 - x) * 4 + (47 - y) * 3) % 256 > 127 ? 255 : 0,
    );

    test('IMG-013 identical files form an exact group', () async {
      final a = await add('a.jpg', base);
      final b = await add('copies/a.jpg', base);
      await add('other.jpg', different);
      final r = await scanner.scan(exact: true, similar: false);
      final exact = r.groups
          .where((g) => g.kind == DuplicateKind.exact)
          .toList();
      expect(exact, hasLength(1));
      expect(exact.single.items.map((i) => i.id), unorderedEquals([a, b]));
    });

    test('IMG-013 a slightly different copy is found as similar', () async {
      final a = await add('a.jpg', base);
      final b = await add('b.jpg', slightlyDarker);
      final c = await add('c.jpg', different);
      final r = await scanner.scan(exact: false, similar: true);
      expect(r.groups, hasLength(1));
      final ids = r.groups.single.items.map((i) => i.id).toSet();
      expect(ids, {a, b});
      expect(ids, isNot(contains(c)));
    });

    test('IMG-013 exact and similar together do not repeat a group', () async {
      await add('a.jpg', base);
      await add('b.jpg', base);
      final r = await scanner.scan(exact: true, similar: true);
      expect(r.groups, hasLength(1));
      expect(r.groups.single.kind, DuplicateKind.exact);
    });

    test(
      'IMG-013 hashes are kept, so the next scan has nothing to do',
      () async {
        await add('a.jpg', base);
        await add('b.jpg', slightlyDarker);
        expect(await scanner.pending(), 2);
        await scanner.scan(exact: false, similar: true);
        expect(await scanner.pending(), 0);
        final rows = await db.select(db.imageMeta).get();
        expect(rows.where((m) => m.phash != null), hasLength(2));
        var calls = 0;
        await scanner.scan(
          exact: false,
          similar: true,
          onProgress: (_, _) => calls++,
        );
        expect(calls, 0);
      },
    );

    test('IMG-013 progress counts the photos looked at', () async {
      await add('a.jpg', base);
      await add('b.jpg', slightlyDarker);
      await add('c.jpg', different);
      final seen = <(int, int)>[];
      await scanner.scan(
        exact: false,
        similar: true,
        onProgress: (d, t) => seen.add((d, t)),
      );
      expect(seen.map((e) => e.$2).toSet(), {3});
      expect(seen.map((e) => e.$1), [0, 1, 2]);
    });

    test('IMG-013 stopping returns what was found so far', () async {
      await add('a.jpg', base);
      await add('b.jpg', base);
      await add('c.jpg', slightlyDarker);
      await add('d.jpg', different);
      var n = 0;
      final r = await scanner.scan(
        exact: true,
        similar: true,
        onProgress: (_, _) => n++,
        cancelled: () => n >= 1,
      );
      expect(r.stopped, isTrue);
      expect(
        r.groups.where((g) => g.kind == DuplicateKind.exact),
        hasLength(1),
      );
    });

    test('IMG-013 a photo that cannot be read is skipped, not fatal', () async {
      await add('a.jpg', base);
      await seed.item('gone.jpg', kind: ItemKind.image, size: 99);
      final r = await scanner.scan(exact: false, similar: true);
      expect(r.groups, isEmpty);
    });

    test('IMG-013 the vault and missing photos are never listed', () async {
      final a = await add('a.jpg', base);
      final b = await add('b.jpg', base);
      await (db.update(db.items)..where((i) => i.id.equals(b))).write(
        const ItemsCompanion(vault: Value(true)),
      );
      final r = await scanner.scan(exact: true, similar: false);
      expect(r.groups, isEmpty);
      expect(a, isNot(b));
    });
  });

  group('IMG-013 screens', () {
    final photos = fakeEntries(days: 1, firstId: 1);

    late List<ItemRow> items;

    ItemRow itemOf(PhotoEntry e) => items.firstWhere((i) => i.id == e.id);

    Future<PhotosHarness> open(
      WidgetTester tester,
      _FakeScanner scanner,
    ) async {
      final h = await PhotosHarness.create(tester);
      final seed = Seed(h.db);
      items = (await tester.runAsync(() async {
        for (final e in photos) {
          await seed.item(e.relPath, kind: ItemKind.image);
        }
        return await h.db.select(h.db.items).get();
      }))!;
      await h.pump(
        tester,
        entries: photos,
        extra: [photoDuplicateScannerProvider.overrideWithValue(scanner)],
      );
      await tester.tap(find.text('Albums'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Duplicates'));
      await tester.pumpAndSettle();
      return h;
    }

    testWidgets('IMG-013 the screen explains and offers both kinds', (
      tester,
    ) async {
      await open(tester, _FakeScanner());
      expect(find.byType(PhotoDuplicatesScreen), findsOneWidget);
      expect(
        find.textContaining('nothing is deleted on its own'),
        findsOneWidget,
      );
      expect(find.widgetWithText(FilterChip, 'Exact copies'), findsOneWidget);
      expect(find.widgetWithText(FilterChip, 'Look the same'), findsOneWidget);
    });

    testWidgets('IMG-013 nothing selected means nothing to find', (
      tester,
    ) async {
      await open(tester, _FakeScanner());
      await tester.tap(find.widgetWithText(FilterChip, 'Exact copies'));
      await tester.tap(find.widgetWithText(FilterChip, 'Look the same'));
      await tester.pump();
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Find duplicates'),
            )
            .onPressed,
        isNull,
      );
    });

    testWidgets('IMG-013 groups are listed after a scan', (tester) async {
      final scanner = _FakeScanner();
      await open(tester, scanner);
      scanner.result = DuplicateScan([
        DuplicateGroup(DuplicateKind.exact, [
          itemOf(photos[0]),
          itemOf(photos[1]),
        ]),
        DuplicateGroup(DuplicateKind.perceptualImage, [
          itemOf(photos[2]),
          itemOf(photos[3]),
          itemOf(photos[4]),
        ]),
      ]);
      await tester.tap(find.text('Find duplicates'));
      await tester.pumpAndSettle();
      expect(scanner.exact, isTrue);
      expect(scanner.similar, isTrue);
      expect(find.text('2 photos, identical files'), findsOneWidget);
      expect(find.text('3 photos, look the same'), findsOneWidget);
    });

    testWidgets('IMG-013 an empty result says so', (tester) async {
      await open(tester, _FakeScanner());
      await tester.tap(find.text('Find duplicates'));
      await tester.pumpAndSettle();
      expect(find.text('No duplicates'), findsOneWidget);
    });

    testWidgets('IMG-013 progress shows while looking, and Stop stops', (
      tester,
    ) async {
      final scanner = _FakeScanner(hold: true);
      await open(tester, scanner);
      await tester.tap(find.text('Find duplicates'));
      await tester.pump();
      scanner.progress?.call(3, 10);
      await tester.pump();
      expect(find.text('Looking at photos: 3 of 10'), findsOneWidget);
      await tester.tap(find.text('Stop'));
      await tester.pump();
      expect(scanner.cancelled?.call(), isTrue);
      scanner.finish(const DuplicateScan([], stopped: true));
      await tester.pumpAndSettle();
      expect(
        find.text('Stopped before the end.'),
        findsNothing,
        reason: 'an empty stopped scan shows the empty message',
      );
    });

    testWidgets('IMG-013 a group opens side by side with the biggest kept', (
      tester,
    ) async {
      final scanner = _FakeScanner();
      final h = await open(tester, scanner);
      scanner.result = DuplicateScan([
        DuplicateGroup(DuplicateKind.exact, [
          itemOf(photos[0]),
          itemOf(photos[1]),
        ]),
      ]);
      await tester.tap(find.text('Find duplicates'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('2 photos, identical files'));
      await tester.pumpAndSettle();
      expect(find.byType(DuplicateReviewScreen), findsOneWidget);
      expect(find.byType(KCompareView), findsOneWidget);
      expect(find.byType(RawImage), findsNWidgets(2));
      expect(find.text('Delete 1 other'), findsOneWidget);
      expect(h.opened, hasLength(2));
    });

    testWidgets('IMG-013 deleting the others goes through Recently deleted', (
      tester,
    ) async {
      final trash = FakeTrash();
      final scanner = _FakeScanner();
      final h = await PhotosHarness.create(tester);
      final seed = Seed(h.db);
      items = (await tester.runAsync(() async {
        for (final e in photos) {
          await seed.item(e.relPath, kind: ItemKind.image);
        }
        return await h.db.select(h.db.items).get();
      }))!;
      await h.pump(
        tester,
        entries: photos,
        extra: [
          photoDuplicateScannerProvider.overrideWithValue(scanner),
          appTrashProvider.overrideWithValue(trash),
        ],
      );
      scanner.result = DuplicateScan([
        DuplicateGroup(DuplicateKind.exact, [
          itemOf(photos[0]),
          itemOf(photos[1]),
        ]),
      ]);
      await tester.tap(find.text('Albums'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Duplicates'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Find duplicates'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('2 photos, identical files'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete 1 other'));
      await tester.pumpAndSettle();
      expect(find.text('Delete this photo?'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Delete').last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpAndSettle();
      expect(trash.moved, hasLength(1));
      // Back on the list, the group is gone.
      expect(find.byType(DuplicateReviewScreen), findsNothing);
      expect(find.text('2 photos, identical files'), findsNothing);
    });

    testWidgets('IMG-013 at least one photo must be kept', (tester) async {
      final scanner = _FakeScanner();
      await open(tester, scanner);
      scanner.result = DuplicateScan([
        DuplicateGroup(DuplicateKind.exact, [
          itemOf(photos[0]),
          itemOf(photos[1]),
        ]),
      ]);
      await tester.tap(find.text('Find duplicates'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('2 photos, identical files'));
      await tester.pumpAndSettle();
      final keeps = find.byType(Switch);
      expect(keeps, findsNWidgets(2));
      Future<void> setAll({required bool on}) async {
        for (var n = 0; n < 2; n++) {
          if (tester.widget<Switch>(keeps.at(n)).value != on) {
            await tester.tap(keeps.at(n));
            await tester.pump();
          }
        }
      }

      // Nothing kept: nothing may be deleted.
      await setAll(on: false);
      expect(find.text('Keep at least one'), findsOneWidget);
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton).last).onPressed,
        isNull,
      );
      // Everything kept leaves nothing to delete.
      await setAll(on: true);
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton).last).onPressed,
        isNull,
      );
    });
  });
}

final class _FakeScanner implements DuplicateScanner {
  _FakeScanner({this.hold = false});

  DuplicateScan result = const DuplicateScan([]);
  final bool hold;
  bool? exact;
  bool? similar;
  void Function(int, int)? progress;
  bool Function()? cancelled;
  final _done = Completer<DuplicateScan>();

  void finish(DuplicateScan r) => _done.complete(r);

  @override
  Future<DuplicateScan> scan({
    required bool exact,
    required bool similar,
    void Function(int done, int total)? onProgress,
    bool Function()? cancelled,
  }) {
    this.exact = exact;
    this.similar = similar;
    progress = onProgress;
    this.cancelled = cancelled;
    return hold ? _done.future : Future.value(result);
  }
}
