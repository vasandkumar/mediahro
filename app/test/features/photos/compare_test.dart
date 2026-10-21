import 'package:flutter/material.dart' hide ImageInfo;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediahro/app/l10n/gen/app_localizations.dart';
import 'package:mediahro/core/db/library_database.dart';
import 'package:mediahro/core/rules/rule_sql.dart' as rules;
import 'package:mediahro/features/photos/compare/compare_screen.dart';
import 'package:mediahro/features/photos/compare/compare_tray.dart';
import 'package:mediahro/features/photos/info/metadata_edit_service.dart';
import 'package:mediahro/features/photos/organise/photo_organiser.dart';
import 'package:mediahro/features/photos/organise/write_back.dart';
import 'package:mediahro/features/photos/photos_providers.dart';
import 'package:mediahro/features/photos/timeline/timeline_model.dart';
import 'package:mediahro/images/image_pipeline.dart';
import 'package:mediahro/images/pipeline/mediahro_image_pipeline.dart';
import 'package:mediahro_design/mediahro_design.dart';
import 'package:mediahro_design/testing.dart' show KTestStrings;

import '../../core/seed.dart';
import 'photos_harness.dart';

final class _Edits implements MetadataEditor {
  final List<(int, ImageMetadataEdit)> saved = [];

  /// The rating each file holds (what a write changes).
  final Map<int, int> fileRatings = {};

  @override
  Future<MetadataWriteOutcome> save(
    PhotoEntry entry,
    ImageMetadataEdit edit,
  ) async {
    saved.add((entry.id, edit));
    if (edit.rating != null) fileRatings[entry.id] = edit.rating!;
    return const MetadataWriteOutcome.file();
  }
}

void main() {
  group('IMG-008 compare tray', () {
    late ProviderContainer c;
    setUp(() => c = ProviderContainer());
    tearDown(() => c.dispose());

    List<PhotoEntry> photos(int n, {Set<int> videos = const {}}) =>
        fakeEntries(days: 1, perDay: n, firstId: 1, videos: videos);

    test('IMG-008 up to four photos fit, the fifth is refused', () {
      final tray = c.read(compareTrayProvider.notifier);
      final list = photos(5);
      for (var i = 0; i < 4; i++) {
        expect(tray.toggle(list[i]), TrayChange.added);
      }
      expect(tray.toggle(list[4]), TrayChange.full);
      expect(c.read(compareTrayProvider), hasLength(4));
    });

    test('IMG-008 choosing a photo again takes it out', () {
      final tray = c.read(compareTrayProvider.notifier);
      final list = photos(2);
      tray
        ..toggle(list[0])
        ..toggle(list[1]);
      expect(tray.toggle(list[0]), TrayChange.removed);
      expect(c.read(compareTrayProvider).map((e) => e.id), [list[1].id]);
      expect(tray.contains(list[1].id), isTrue);
      tray.clear();
      expect(c.read(compareTrayProvider), isEmpty);
    });

    test('IMG-008 videos are not compared', () {
      final tray = c.read(compareTrayProvider.notifier);
      expect(tray.toggle(photos(1, videos: {1}).single), TrayChange.notAPhoto);
      expect(c.read(compareTrayProvider), isEmpty);
    });
  });

  group('IMG-008 keep and reject in the library', () {
    late LibraryDatabase db;
    late Seed seed;
    late PhotoOrganiser org;

    setUp(() {
      db = LibraryDatabase.memory();
      seed = Seed(db);
      org = PhotoOrganiser(db: db);
    });

    tearDown(() => db.close());

    Future<PhotoEntry> entry(int id) async {
      final q = db.customSelect(
        photoEntriesSql(rules.Visibility.standard),
        readsFrom: {db.items, db.imageMeta, db.ratings, db.sources},
      );
      return (await loadPhotoEntries(q)).singleWhere((e) => e.id == id);
    }

    Future<int?> ratingOf(int id) async => (await (db.select(
      db.ratings,
    )..where((r) => r.itemId.equals(id))).getSingleOrNull())?.value;

    test(
      'IMG-008 rejecting stores XMP rating -1 and drops the heart',
      () async {
        final a = await seed.item('a.jpg', kind: ItemKind.image);
        await org.setFavourite([a], value: true);
        expect((await entry(a)).favourite, isTrue);
        await org.setRejected([a], value: true);
        final e = await entry(a);
        expect(e.rejected, isTrue);
        expect(e.favourite, isFalse);
        expect(await ratingOf(a), -1);
      },
    );

    test(
      'IMG-008 un-rejecting clears the mark but keeps star ratings',
      () async {
        final a = await seed.item('a.jpg', kind: ItemKind.image);
        final b = await seed.item('b.jpg', kind: ItemKind.image);
        await org.setRejected([a], value: true);
        await org.setRating([b], 4);
        await org.setRejected([a, b], value: false);
        expect(await ratingOf(a), isNull);
        expect(await ratingOf(b), 8);
        expect((await entry(a)).rejected, isFalse);
      },
    );

    test('IMG-008 keeping makes a favourite and lifts a rejection', () async {
      final a = await seed.item('a.jpg', kind: ItemKind.image);
      await org.setRejected([a], value: true);
      await org.keep([a]);
      final e = await entry(a);
      expect(e.favourite, isTrue);
      expect(e.rejected, isFalse);
    });

    test(
      'IMG-008 a star rating replaces a rejection and the reverse',
      () async {
        final a = await seed.item('a.jpg', kind: ItemKind.image);
        await org.setRejected([a], value: true);
        await org.setRating([a], 3);
        expect(await ratingOf(a), 6);
        expect((await entry(a)).rejected, isFalse);
        await org.setRejected([a], value: true);
        expect(await ratingOf(a), -1);
        await org.setRating([a], 0);
        expect(await ratingOf(a), isNull);
      },
    );
  });

  group('IMG-008 compare screen', () {
    late _Edits edits;
    late PhotosHarness h;
    var writeBackOn = false;

    Future<void> open(
      WidgetTester tester,
      List<PhotoEntry> photos, {
      bool writeBack = false,
      ViewerImageLoader? loader,
    }) async {
      edits = _Edits();
      writeBackOn = writeBack;
      h = await PhotosHarness.create(tester);
      final seed = Seed(h.db);
      await tester.runAsync(() async {
        for (var i = 1; i <= 6; i++) {
          await seed.item('p/IMG_$i.jpg', kind: ItemKind.image);
        }
      });
      tester.view
        ..physicalSize = const Size(400, 800) * tester.view.devicePixelRatio
        ..devicePixelRatio = tester.view.devicePixelRatio;
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ...h.overrides(entries: photos, loader: loader),
            organisationWriteBackProvider.overrideWith(
              (ref) => OrganisationWriteBack(
                editor: edits,
                organiser: ref.watch(photoOrganiserProvider),
                enabled: () => writeBackOn,
                fileRating: (p) async => edits.fileRatings[p.id],
              ),
            ),
          ],
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            builder: (context, child) =>
                KStringsScope(strings: const KTestStrings(), child: child!),
            home: CompareScreen(photos: photos),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    Future<void> settle(WidgetTester tester) async {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 150)),
      );
      await tester.pumpAndSettle();
    }

    List<PhotoEntry> two() => fakeEntries(days: 1, perDay: 2, firstId: 1);

    testWidgets('IMG-008 two photos open side by side with all four modes', (
      tester,
    ) async {
      await open(tester, two());
      expect(find.byType(KCompareView), findsOneWidget);
      expect(find.byType(RawImage), findsNWidgets(2));
      for (final m in ['Side by side', 'Swipe', 'Overlay', 'Difference']) {
        expect(find.widgetWithText(ChoiceChip, m), findsOneWidget);
      }
      await tester.tap(find.text('Difference'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<KCompareView>(find.byType(KCompareView)).mode,
        KCompareMode.difference,
      );
      await tester.tap(find.text('Swipe'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<KCompareView>(find.byType(KCompareView)).mode,
        KCompareMode.swipe,
      );
      await tester.tap(find.text('Overlay'));
      await tester.pumpAndSettle();
      expect(find.byType(Slider), findsOneWidget);
    });

    testWidgets('IMG-008 three or four photos are side by side only', (
      tester,
    ) async {
      await open(tester, fakeEntries(days: 1, perDay: 4, firstId: 1));
      expect(find.byType(RawImage), findsNWidgets(4));
      expect(find.byType(ChoiceChip), findsNothing);
      expect(
        tester.widget<KCompareView>(find.byType(KCompareView)).mode,
        KCompareMode.sideBySide,
      );
    });

    testWidgets('IMG-008 reset zoom puts the shared view back', (tester) async {
      await open(tester, two());
      final view = tester.widget<KCompareView>(find.byType(KCompareView));
      final c = view.controller!
        ..value = Matrix4.identity().scaledByDouble(3, 3, 1, 1);
      await tester.tap(find.byTooltip('Reset zoom'));
      await tester.pump();
      expect(c.value, Matrix4.identity());
    });

    testWidgets('IMG-008 keep marks a favourite, again undoes it', (
      tester,
    ) async {
      await open(tester, two());
      await tester.tap(find.byTooltip('Keep IMG_1.jpg'));
      await settle(tester);
      var meta = await tester.runAsync(
        () => (h.db.select(
          h.db.imageMeta,
        )..where((m) => m.favourite.equals(true))).get(),
      );
      expect(meta!.map((m) => m.itemId), [1]);
      await tester.tap(find.byTooltip('Keep IMG_1.jpg'));
      await settle(tester);
      meta = await tester.runAsync(
        () => (h.db.select(
          h.db.imageMeta,
        )..where((m) => m.favourite.equals(true))).get(),
      );
      expect(meta, isEmpty);
    });

    testWidgets('IMG-008 reject stores the mark and can be taken back', (
      tester,
    ) async {
      await open(tester, two());
      await tester.tap(find.byTooltip('Reject IMG_2.jpg'));
      await settle(tester);
      var r = await tester.runAsync(() => h.db.select(h.db.ratings).get());
      expect(r!.single.itemId, 2);
      expect(r.single.value, -1);
      await tester.tap(find.byTooltip('Reject IMG_2.jpg'));
      await settle(tester);
      r = await tester.runAsync(() => h.db.select(h.db.ratings).get());
      expect(r, isEmpty);
    });

    testWidgets('IMG-008 keep only this one rejects the others', (
      tester,
    ) async {
      await open(tester, fakeEntries(days: 1, perDay: 3, firstId: 1));
      await tester.tap(
        find.byTooltip('Keep only IMG_2.jpg and reject the others'),
      );
      await settle(tester);
      final r = await tester.runAsync(() => h.db.select(h.db.ratings).get());
      expect({for (final x in r!) x.itemId: x.value}, {1: -1, 3: -1});
      final f = await tester.runAsync(
        () => (h.db.select(
          h.db.imageMeta,
        )..where((m) => m.favourite.equals(true))).get(),
      );
      expect(f!.map((m) => m.itemId), [2]);
    });

    testWidgets('IMG-008 earlier decisions show when it opens', (tester) async {
      final list = fakeEntries(days: 1, perDay: 2, firstId: 1, favourites: {1});
      await open(tester, list);
      // Only the kept photo shows the filled tick.
      expect(find.byIcon(Icons.check_circle), findsOneWidget);
      expect(find.byIcon(Icons.block), findsNothing);
    });

    testWidgets('IMG-008 with write-back on a rejection reaches the file', (
      tester,
    ) async {
      await open(tester, two(), writeBack: true);
      await tester.tap(find.byTooltip('Reject IMG_1.jpg'));
      await settle(tester);
      expect(edits.saved.single.$1, 1);
      expect(edits.saved.single.$2.rating, -1);
    });

    group('un-rejecting', () {
      Future<void> toggleReject(WidgetTester tester, String name) async {
        await tester.tap(find.byTooltip('Reject $name'));
        await settle(tester);
      }

      Future<int?> stars(WidgetTester tester, int id) async {
        final r = await tester.runAsync(
          () => (h.db.select(
            h.db.ratings,
          )..where((x) => x.itemId.equals(id))).getSingleOrNull(),
        );
        return r?.value;
      }

      testWidgets(
        'IMG-008 un-rejecting with write-back on gives the file its stars back',
        (tester) async {
          await open(tester, two(), writeBack: true);
          edits.fileRatings[1] = 3;
          await tester.runAsync(
            () => PhotoOrganiser(db: h.db).setRating([1], 3),
          );
          await toggleReject(tester, 'IMG_1.jpg');
          expect(edits.fileRatings[1], -1);
          await toggleReject(tester, 'IMG_1.jpg');
          expect(edits.fileRatings[1], 3);
          expect(edits.saved.last.$2.rating, 3);
          expect(await stars(tester, 1), 6);
        },
      );

      testWidgets(
        'IMG-008 a rejection with no earlier stars un-rejects to no rating',
        (tester) async {
          await open(tester, two(), writeBack: true);
          await toggleReject(tester, 'IMG_1.jpg');
          await toggleReject(tester, 'IMG_1.jpg');
          expect(edits.saved.map((e) => e.$2.rating), [-1, 0]);
          expect(await stars(tester, 1), isNull);
        },
      );

      testWidgets(
        'IMG-008 a file the rejection never reached keeps its stars',
        (tester) async {
          await open(tester, two());
          edits.fileRatings[1] = 4;
          await toggleReject(tester, 'IMG_1.jpg');
          // Write-back is switched on only after the rejection.
          writeBackOn = true;
          await toggleReject(tester, 'IMG_1.jpg');
          expect(edits.saved, isEmpty);
          expect(edits.fileRatings[1], 4);
        },
      );

      testWidgets(
        'IMG-008 with write-back off neither rejecting nor un-rejecting writes',
        (tester) async {
          await open(tester, two());
          edits.fileRatings[1] = 3;
          await toggleReject(tester, 'IMG_1.jpg');
          await toggleReject(tester, 'IMG_1.jpg');
          expect(edits.saved, isEmpty);
          expect(edits.fileRatings[1], 3);
        },
      );

      testWidgets('IMG-008 keeping a rejected photo clears the mark in its '
          'file too', (tester) async {
        await open(tester, two(), writeBack: true);
        edits.fileRatings[1] = 2;
        await tester.runAsync(() => PhotoOrganiser(db: h.db).setRating([1], 2));
        await toggleReject(tester, 'IMG_1.jpg');
        await tester.tap(find.byTooltip('Keep IMG_1.jpg'));
        await settle(tester);
        expect(edits.fileRatings[1], 2);
      });
    });

    testWidgets('IMG-008 a photo that cannot be opened is marked, not fatal', (
      tester,
    ) async {
      var n = 0;
      await open(
        tester,
        two(),
        loader: (entry) async {
          if (n++ == 0) throw Exception('gone');
          return h.take();
        },
      );
      expect(find.byType(RawImage), findsOneWidget);
      expect(find.byIcon(Icons.broken_image_outlined), findsOneWidget);
      expect(find.byTooltip('Keep IMG_1.jpg'), findsOneWidget);
    });
  });

  group('IMG-008 reaching compare', () {
    testWidgets('IMG-008 the viewer collects photos and opens compare', (
      tester,
    ) async {
      final h = await PhotosHarness.create(tester);
      await h.pump(tester, entries: fakeEntries(days: 1, firstId: 1));
      await tester.tap(find.byType(KGridTile).first);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Add to compare'));
      await tester.pumpAndSettle();
      expect(find.text('Added to compare: 1 of 4'), findsOneWidget);
      expect(find.text('Compare now'), findsNothing);
      expect(find.byTooltip('Remove from compare'), findsOneWidget);
      await tester.drag(find.byType(PageView), const Offset(-380, 0));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Add to compare'));
      await tester.pumpAndSettle();
      expect(find.text('Added to compare: 2 of 4'), findsOneWidget);
      await tester.tap(find.text('Compare now'));
      await tester.pumpAndSettle();
      expect(find.byType(CompareScreen), findsOneWidget);
      expect(find.byType(RawImage), findsNWidgets(2));
    });

    testWidgets('IMG-008 a fifth photo is refused with a message', (
      tester,
    ) async {
      final h = await PhotosHarness.create(tester);
      await h.pump(tester, entries: fakeEntries(days: 1, firstId: 1));
      await tester.tap(find.byType(KGridTile).first);
      await tester.pumpAndSettle();
      for (var i = 0; i < 4; i++) {
        await tester.tap(find.byTooltip('Add to compare'));
        await tester.pump();
        await tester.drag(find.byType(PageView), const Offset(-380, 0));
        await tester.pumpAndSettle();
      }
      await tester.tap(find.byTooltip('Add to compare'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 800));
      expect(find.text('Compare holds up to 4 photos.'), findsOneWidget);
    });

    testWidgets(
      'IMG-008 selecting two or more photos opens compare from More',
      (tester) async {
        final h = await PhotosHarness.create(tester);
        await h.pump(tester, entries: fakeEntries(days: 1, firstId: 1));
        await tester.longPress(find.byType(KGridTile).at(0));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('More'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Compare'));
        await tester.pumpAndSettle();
        expect(find.text('Choose 2 to 4 photos to compare.'), findsOneWidget);
        await tester.tap(find.byType(KGridTile).at(1));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('More'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Compare'));
        await tester.pumpAndSettle();
        expect(find.byType(CompareScreen), findsOneWidget);
      },
    );

    testWidgets('IMG-008 rejected photos are collected in an album', (
      tester,
    ) async {
      final h = await PhotosHarness.create(tester);
      final list = fakeEntries(days: 1, firstId: 1)
          .map(
            (e) => e.id == 2
                ? PhotoEntry(
                    id: e.id,
                    sourceId: e.sourceId,
                    relPath: e.relPath,
                    name: e.name,
                    ext: e.ext,
                    isVideo: false,
                    size: e.size,
                    mtime: e.mtime,
                    date: e.date,
                    rejected: true,
                  )
                : e,
          )
          .toList();
      await h.pump(tester, entries: list);
      await tester.tap(find.text('Albums'));
      await tester.pumpAndSettle();
      expect(find.text('Rejected'), findsOneWidget);
      await tester.tap(find.text('Rejected'));
      await tester.pumpAndSettle();
      expect(find.byType(KGridTile), findsOneWidget);
    });
  });
}
