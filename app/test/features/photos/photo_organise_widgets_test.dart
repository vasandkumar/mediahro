import 'package:flutter/material.dart' hide ImageInfo;
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:mediahro/core/db/library_database.dart';
import 'package:mediahro/features/photos/organise/albums_tab.dart';
import 'package:mediahro/features/photos/organise/photo_organiser.dart';
import 'package:mediahro/features/photos/photos_providers.dart';
import 'package:mediahro_design/mediahro_design.dart';

import '../../core/seed.dart';
import 'photos_harness.dart';

void main() {
  /// Seeds one image row per entry so the organiser's writes have targets.
  Future<void> seedFor(PhotosHarness h, int n) async {
    final seed = Seed(h.db);
    for (var i = 1; i <= n; i++) {
      await seed.item('p/IMG_$i.jpg', kind: ItemKind.image);
    }
  }

  Future<T> real<T>(WidgetTester tester, Future<T> Function() body) async =>
      (await tester.runAsync(body)) as T;

  Future<void> settleDb(WidgetTester tester) async {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 150)),
    );
    await tester.pumpAndSettle();
  }

  Future<PhotosHarness> open(
    WidgetTester tester, {
    int days = 1,
    int perDay = 6,
    Set<int> favourites = const {},
    String Function(int)? folder,
    List<Override> extra = const [],
  }) async {
    final h = await PhotosHarness.create(tester);
    await real(tester, () => seedFor(h, days * perDay));
    await h.pump(
      tester,
      entries: fakeEntries(
        days: days,
        perDay: perDay,
        firstId: 1,
        favourites: favourites,
        folder: folder,
      ),
      extra: extra,
    );
    return h;
  }

  Future<void> longPress(WidgetTester tester, int tile) async {
    await tester.longPress(find.byType(KGridTile).at(tile));
    await tester.pumpAndSettle();
  }

  group('IMG-005 selection', () {
    testWidgets('IMG-005 a long press starts selecting, taps add and remove', (
      tester,
    ) async {
      await open(tester);
      expect(find.textContaining('selected'), findsNothing);
      await longPress(tester, 1);
      expect(find.text('1 selected'), findsOneWidget);
      await tester.tap(find.byType(KGridTile).at(3));
      await tester.pumpAndSettle();
      expect(find.text('2 selected'), findsOneWidget);
      await tester.tap(find.byType(KGridTile).at(3));
      await tester.pumpAndSettle();
      expect(find.text('1 selected'), findsOneWidget);
      await tester.tap(find.byTooltip('Clear selection'));
      await tester.pumpAndSettle();
      expect(find.textContaining('selected'), findsNothing);
    });

    testWidgets('IMG-005 while selecting a tap does not open the viewer', (
      tester,
    ) async {
      final h = await open(tester);
      await longPress(tester, 0);
      await tester.tap(find.byType(KGridTile).at(1));
      await tester.pumpAndSettle();
      expect(h.opened, isEmpty);
    });

    testWidgets('IMG-005 dragging across tiles selects the range', (
      tester,
    ) async {
      await open(tester);
      final first = tester.getCenter(find.byType(KGridTile).at(0));
      final last = tester.getCenter(find.byType(KGridTile).at(2));
      final g = await tester.startGesture(first);
      await tester.pump(const Duration(milliseconds: 700));
      await g.moveTo(last);
      await tester.pump();
      await g.up();
      await tester.pumpAndSettle();
      expect(find.text('3 selected'), findsOneWidget);
    });

    testWidgets('IMG-005 select all picks everything in the view', (
      tester,
    ) async {
      await open(tester);
      await longPress(tester, 0);
      await tester.tap(find.byTooltip('Select all'));
      await tester.pumpAndSettle();
      expect(find.text('6 selected'), findsOneWidget);
    });

    testWidgets('IMG-005 the selection bar is announced to screen readers', (
      tester,
    ) async {
      await open(tester);
      final handle = tester.ensureSemantics();
      await longPress(tester, 0);
      expect(
        tester.getSemantics(find.text('1 selected')),
        matchesSemantics(label: '1 selected', isLiveRegion: true),
      );
      handle.dispose();
    });
  });

  group('IMG-005 actions', () {
    testWidgets('IMG-005 the heart marks the selected photos as favourites', (
      tester,
    ) async {
      final h = await open(tester);
      await longPress(tester, 0);
      await tester.tap(find.byType(KGridTile).at(1));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Add to favourites'));
      await settleDb(tester);
      final rows = await real(
        tester,
        () => (h.db.select(
          h.db.imageMeta,
        )..where((m) => m.favourite.equals(true))).get(),
      );
      expect(rows.map((r) => r.itemId).toSet(), {
        // The two selected tiles, newest first: ids 1 and 2.
        1,
        2,
      });
      expect(
        find.textContaining('selected'),
        findsNothing,
        reason: 'selection ends',
      );
    });

    testWidgets('IMG-005 favourites show a heart on their tile', (
      tester,
    ) async {
      await open(tester, favourites: {2});
      expect(find.byIcon(Icons.favorite), findsOneWidget);
    });

    testWidgets(
      'IMG-005 the heart turns into remove when all selected are favourites',
      (tester) async {
        await open(tester, favourites: {1});
        await longPress(tester, 0);
        expect(find.byTooltip('Remove from favourites'), findsOneWidget);
      },
    );

    testWidgets('IMG-005 Add to album can create a new album', (tester) async {
      final h = await open(tester);
      await longPress(tester, 0);
      await tester.tap(find.byType(KGridTile).at(1));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Add to album'));
      await settleDb(tester);
      await tester.tap(find.text('New album').last);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Trip');
      await tester.pump();
      await tester.tap(find.text('Create'));
      await settleDb(tester);
      // The album exists but creating from this flow adds the photos next.
      final albums = await real(
        tester,
        () => PhotoOrganiser(db: h.db).albums(),
      );
      expect(albums.map((a) => a.name), ['Trip']);
    });

    testWidgets(
      'IMG-005 Add to album adds to an existing album and says how many',
      (tester) async {
        final h = await open(tester);
        final album = await real(
          tester,
          () => PhotoOrganiser(db: h.db).createAlbum('Trip', items: [1]),
        );
        await longPress(tester, 0);
        await tester.tap(find.byType(KGridTile).at(1));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Add to album'));
        await settleDb(tester);
        await tester.tap(find.text('Trip'));
        await settleDb(tester);
        expect(
          find.text('Added 1 photo'),
          findsOneWidget,
          reason: 'photo 1 was already in it',
        );
        final ids = await real(
          tester,
          () => PhotoOrganiser(db: h.db).albumItemIds(album),
        );
        expect(ids.toSet(), {1, 2});
      },
    );

    testWidgets('IMG-005 Rate sets the stars', (tester) async {
      final h = await open(tester);
      await longPress(tester, 0);
      await tester.tap(find.byTooltip('More'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Rate'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('4 stars'));
      await settleDb(tester);
      final r = await real(tester, () => h.db.select(h.db.ratings).get());
      expect((r.single.itemId, r.single.value), (1, 8));
    });

    testWidgets('IMG-005 Colour label', (tester) async {
      final h = await open(tester);
      await longPress(tester, 0);
      await tester.tap(find.byTooltip('More'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Colour label'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Green'));
      await settleDb(tester);
      final l = await real(tester, () => h.db.select(h.db.labels).get());
      expect(l.single.color, LabelColor.green);
    });

    testWidgets('IMG-005 Tags can be added and removed', (tester) async {
      final h = await open(tester);
      await longPress(tester, 0);
      await tester.tap(find.byTooltip('More'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Tags'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'sunset');
      await tester.tap(find.byTooltip('Add a tag'));
      await settleDb(tester);
      expect(find.widgetWithText(InputChip, 'sunset'), findsOneWidget);
      final tags = await real(tester, () => h.db.select(h.db.tags).get());
      expect(tags.map((t) => t.name), ['sunset']);
      await tester.tap(find.byTooltip('Delete'));
      await settleDb(tester);
      expect(find.widgetWithText(InputChip, 'sunset'), findsNothing);
      final left = await real(tester, () => h.db.select(h.db.itemTags).get());
      expect(left, isEmpty);
    });
  });

  group('IMG-005 albums tab', () {
    testWidgets('IMG-005 the Albums tab lists Favourites and the albums', (
      tester,
    ) async {
      await open(
        tester,
        favourites: {1, 3},
        extra: [
          photoAlbumsProvider.overrideWith(
            (ref) => Stream.value(const [
              PhotoAlbum(
                id: 7,
                name: 'Trip',
                count: 12,
                smart: false,
                coverItemId: 1,
              ),
              PhotoAlbum(id: 8, name: '5 stars', count: 3, smart: true),
            ]),
          ),
        ],
      );
      await tester.tap(find.text('Albums'));
      await tester.pumpAndSettle();
      expect(find.text('Favourites'), findsOneWidget);
      expect(find.text('2 photos'), findsOneWidget);
      expect(find.text('Trip'), findsOneWidget);
      expect(find.text('12 photos'), findsOneWidget);
      expect(find.text('Smart album · 3 photos'), findsOneWidget);
    });

    testWidgets('IMG-005 an empty Albums tab says how to start', (
      tester,
    ) async {
      await open(
        tester,
        extra: [
          photoAlbumsProvider.overrideWith((ref) => Stream.value(const [])),
        ],
      );
      await tester.tap(find.text('Albums'));
      await tester.pumpAndSettle();
      expect(find.textContaining('No albums yet'), findsOneWidget);
      expect(find.text('New album'), findsOneWidget);
    });

    testWidgets('IMG-005 the Favourites view shows the favourite photos', (
      tester,
    ) async {
      await open(tester, favourites: {2, 4});
      await tester.tap(find.text('Albums'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Favourites'));
      await tester.pumpAndSettle();
      expect(find.byType(KGridTile), findsNWidgets(2));
    });

    testWidgets('IMG-005 an album opens to its photos', (tester) async {
      final entries = fakeEntries(firstId: 1);
      await open(
        tester,
        extra: [
          photoAlbumsProvider.overrideWith(
            (ref) => Stream.value(const [
              PhotoAlbum(
                id: 7,
                name: 'Trip',
                count: 2,
                smart: false,
                coverItemId: 1,
              ),
            ]),
          ),
          photoAlbumEntriesProvider(7)
              .overrideWith((ref) => Stream.value([entries[0], entries[1]])),
        ],
      );
      await tester.tap(find.text('Albums'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Trip'));
      await tester.pumpAndSettle();
      expect(find.byType(KGridTile), findsNWidgets(2));
      expect(find.byTooltip('More'), findsOneWidget);
    });

    testWidgets('IMG-005 an empty album explains how to fill it', (
      tester,
    ) async {
      await open(
        tester,
        extra: [
          photoAlbumsProvider.overrideWith(
            (ref) => Stream.value(const [
              PhotoAlbum(id: 7, name: 'Blank', count: 0, smart: false),
            ]),
          ),
          photoAlbumEntriesProvider(7)
              .overrideWith((ref) => Stream.value(const [])),
        ],
      );
      await tester.tap(find.text('Albums'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Blank'));
      await tester.pumpAndSettle();
      expect(find.textContaining('This album is empty'), findsOneWidget);
    });
  });

  group('IMG-005 folders tab', () {
    testWidgets(
      'IMG-005 Folders shows sub-folders and the photos in a folder',
      (tester) async {
        await open(tester, folder: (id) => id <= 3 ? 'Trips/Paris' : 'Camera');
        await tester.tap(find.text('Folders'));
        await tester.pumpAndSettle();
        expect(find.text('Camera'), findsOneWidget);
        expect(find.text('Trips'), findsOneWidget);
        expect(find.text('3 photos'), findsNWidgets(2));
        await tester.tap(find.text('Trips'));
        await tester.pumpAndSettle();
        expect(find.text('Paris'), findsOneWidget);
        await tester.tap(find.text('Paris'));
        await tester.pumpAndSettle();
        expect(find.byType(KGridTile), findsNWidgets(3));
      },
    );
  });
}
