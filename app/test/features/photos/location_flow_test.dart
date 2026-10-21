import 'dart:io';

import 'package:flutter/material.dart' hide ImageInfo;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:mediahro/app/l10n/gen/app_localizations.dart';
import 'package:mediahro/features/photos/info/metadata_edit_service.dart';
import 'package:mediahro/features/photos/map/gazetteer.dart';
import 'package:mediahro/features/photos/map/gazetteer_providers.dart';
import 'package:mediahro/features/photos/map/geo_point.dart' show GeoPoint;
import 'package:mediahro/features/photos/map/location_actions.dart';
import 'package:mediahro/features/photos/map/location_picker.dart';
import 'package:mediahro/features/photos/photos_providers.dart';
import 'package:mediahro/features/photos/timeline/timeline_model.dart';
import 'package:mediahro/images/image_pipeline.dart';
import 'package:mediahro/images/pipeline/mediahro_image_pipeline.dart';
import 'package:mediahro_design/mediahro_design.dart';

import 'photos_harness.dart';

final class _Edits implements MetadataEditor {
  final List<(int, ImageMetadataEdit)> saved = [];
  final Set<int> failing = {};

  @override
  Future<MetadataWriteOutcome> save(
    PhotoEntry entry,
    ImageMetadataEdit edit,
  ) async {
    if (failing.contains(entry.id)) throw const FileSystemException('locked');
    saved.add((entry.id, edit));
    return const MetadataWriteOutcome.file();
  }
}

void main() {
  late Gazetteer gazetteer;

  setUpAll(() {
    gazetteer = Gazetteer.parse(
      File('assets/gazetteer/places.bin').readAsBytesSync(),
    );
  });

  List<Override> mapOverrides({bool search = true}) => [
    gazetteerProvider.overrideWith((ref) async => search ? gazetteer : null),
  ];

  group('IMG-007 location picker', () {
    PickedLocation? result;
    var returned = false;

    Future<void> openPicker(
      WidgetTester tester, {
      GeoPoint? initial,
      List<Override>? overrides,
    }) async {
      result = null;
      returned = false;
      tester.view
        ..physicalSize = const Size(400, 800)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        ProviderScope(
          overrides: overrides ?? mapOverrides(),
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: FilledButton(
                    onPressed: () async {
                      result = await pickLocation(context, initial: initial);
                      returned = true;
                    },
                    child: const Text('open'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    testWidgets('IMG-007 the position starts as the photo has it', (
      tester,
    ) async {
      await openPicker(tester, initial: (lat: 48.85, lon: 2.35));
      expect(find.text('Choose a location'), findsOneWidget);
      expect(find.text('48.85000, 2.35000'), findsOneWidget);
      await tester.tap(find.text('Use this location'));
      await tester.pumpAndSettle();
      expect(returned, isTrue);
      expect(result!.lat, closeTo(48.85, 1e-6));
      expect(result!.lon, closeTo(2.35, 1e-6));
    });

    testWidgets('IMG-007 closing the picker chooses nothing', (tester) async {
      await openPicker(tester, initial: (lat: 48.85, lon: 2.35));
      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
      expect(returned, isTrue);
      expect(result, isNull);
    });

    testWidgets('IMG-007 searching a city picks its position', (tester) async {
      await openPicker(tester, initial: (lat: 0, lon: 0));
      await tester.enterText(find.byType(TextField).first, 'sao paulo');
      await tester.pump();
      expect(find.text('São Paulo'), findsOneWidget);
      expect(find.text('Brazil'), findsWidgets);
      await tester.tap(find.text('São Paulo').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Use this location'));
      await tester.pumpAndSettle();
      expect(result!.lat, closeTo(-23.55, 0.3));
      expect(result!.lon, closeTo(-46.63, 0.3));
    });

    testWidgets('IMG-007 a search with no match says so', (tester) async {
      await openPicker(tester);
      await tester.enterText(find.byType(TextField).first, 'qqqqzzzz');
      await tester.pump();
      expect(find.text('No city matches.'), findsOneWidget);
    });

    testWidgets('IMG-007 a typed latitude and longitude is used as typed', (
      tester,
    ) async {
      await openPicker(tester);
      final use = find.widgetWithText(FilledButton, 'Use this location');
      expect(tester.widget<FilledButton>(use).onPressed, isNull);
      await tester.enterText(find.byType(TextField).last, '-33.8688, 151.2093');
      await tester.pump();
      await tester.tap(use);
      await tester.pumpAndSettle();
      expect(result!.lat, closeTo(-33.8688, 1e-6));
      expect(result!.lon, closeTo(151.2093, 1e-6));
    });

    testWidgets('IMG-007 letters for the hemispheres are understood', (
      tester,
    ) async {
      await openPicker(tester);
      await tester.enterText(
        find.byType(TextField).last,
        '33.8688 S 151.2093 E',
      );
      await tester.pump();
      await tester.tap(find.text('Use this location'));
      await tester.pumpAndSettle();
      expect(result!.lat, closeTo(-33.8688, 1e-6));
      expect(result!.lon, closeTo(151.2093, 1e-6));
    });

    testWidgets('IMG-007 text that is not a position says so', (tester) async {
      await openPicker(tester);
      await tester.enterText(find.byType(TextField).last, '95, 10');
      await tester.pump();
      expect(find.textContaining("isn't a position"), findsOneWidget);
      final use = find.widgetWithText(FilledButton, 'Use this location');
      expect(tester.widget<FilledButton>(use).onPressed, isNull);
    });

    testWidgets('IMG-007 a chosen city shows its name and country', (
      tester,
    ) async {
      await openPicker(tester);
      await tester.enterText(find.byType(TextField).first, 'tokyo');
      await tester.pump();
      await tester.tap(find.text('Tokyo').first);
      await tester.pumpAndSettle();
      expect(find.text('Tokyo, Japan'), findsOneWidget);
    });

    testWidgets('IMG-007 a build without the gazetteer has no search box', (
      tester,
    ) async {
      await openPicker(
        tester,
        initial: (lat: 48.85, lon: 2.35),
        overrides: mapOverrides(search: false),
      );
      expect(find.byType(TextField), findsOneWidget);
      await tester.tap(find.text('Use this location'));
      await tester.pumpAndSettle();
      expect(result, isNotNull);
    });
  });

  group('IMG-007 setting the location of photos', () {
    Future<(PhotosHarness, _Edits, List<PhotoEntry>)> open(
      WidgetTester tester, {
      Set<int> videos = const {},
    }) async {
      final h = await PhotosHarness.create(tester);
      final edits = _Edits();
      final entries = fakeEntries(days: 1, firstId: 1, videos: videos);
      await h.pump(
        tester,
        entries: entries,
        extra: [
          metadataEditServiceProvider.overrideWithValue(edits),
          ...mapOverrides(),
        ],
      );
      return (h, edits, entries);
    }

    Future<void> select(WidgetTester tester, List<int> tiles) async {
      await tester.longPress(find.byType(KGridTile).at(tiles.first));
      await tester.pumpAndSettle();
      for (final t in tiles.skip(1)) {
        await tester.tap(find.byType(KGridTile).at(t));
        await tester.pumpAndSettle();
      }
    }

    Future<void> choose(WidgetTester tester, String item) async {
      await tester.tap(find.byTooltip('More'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(item));
      await tester.pumpAndSettle();
    }

    testWidgets('IMG-007 selected photos all get the chosen location', (
      tester,
    ) async {
      final (_, edits, entries) = await open(tester);
      await select(tester, [0, 1, 2]);
      await choose(tester, 'Set location');
      await tester.enterText(find.byType(TextField).first, 'paris');
      await tester.pump();
      await tester.tap(find.text('Paris').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Use this location'));
      await tester.pumpAndSettle();
      expect(edits.saved.map((s) => s.$1), [
        entries[0].id,
        entries[1].id,
        entries[2].id,
      ]);
      for (final (_, edit) in edits.saved) {
        expect(edit.location!.$1, closeTo(48.85, 0.2));
        expect(edit.location!.$2, closeTo(2.35, 0.2));
        expect(edit.clearLocation, isFalse);
      }
      expect(find.text('Location changed on 3 photos.'), findsOneWidget);
      expect(find.textContaining('selected'), findsNothing);
    });

    testWidgets('IMG-007 videos in the selection are left alone', (
      tester,
    ) async {
      final (_, edits, entries) = await open(tester, videos: {2});
      await select(tester, [0, 1]);
      await choose(tester, 'Set location');
      await tester.enterText(find.byType(TextField).last, '48.85, 2.35');
      await tester.pump();
      await tester.tap(find.text('Use this location'));
      await tester.pumpAndSettle();
      expect(edits.saved, hasLength(1));
      expect(edits.saved.single.$1, entries[0].id);
    });

    testWidgets('IMG-007 only videos selected says there is nothing to do', (
      tester,
    ) async {
      final (_, edits, _) = await open(tester, videos: {1, 2});
      await select(tester, [0]);
      await choose(tester, 'Set location');
      expect(find.text('Choose a location'), findsNothing);
      expect(find.text('Videos have no location to change.'), findsOneWidget);
      expect(edits.saved, isEmpty);
    });

    testWidgets('IMG-007 backing out of the picker changes nothing', (
      tester,
    ) async {
      final (_, edits, _) = await open(tester);
      await select(tester, [0, 1]);
      await choose(tester, 'Set location');
      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
      expect(edits.saved, isEmpty);
      expect(find.text('2 selected'), findsOneWidget);
    });

    testWidgets('IMG-007 removing the location asks first', (tester) async {
      final (_, edits, entries) = await open(tester);
      await select(tester, [0, 1]);
      await choose(tester, 'Remove location');
      expect(find.text('Remove the location?'), findsOneWidget);
      expect(find.textContaining('These 2 photos lose'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(edits.saved, isEmpty);
      await choose(tester, 'Remove location');
      await tester.tap(find.text('Remove'));
      await tester.pumpAndSettle();
      expect(edits.saved.map((s) => s.$1), [entries[0].id, entries[1].id]);
      expect(edits.saved.every((s) => s.$2.clearLocation), isTrue);
      expect(find.text('Location changed on 2 photos.'), findsOneWidget);
    });

    testWidgets('IMG-007 a file that cannot be written is reported', (
      tester,
    ) async {
      final (_, edits, entries) = await open(tester);
      edits.failing.add(entries[1].id);
      await select(tester, [0, 1, 2]);
      await choose(tester, 'Remove location');
      await tester.tap(find.text('Remove'));
      await tester.pumpAndSettle();
      expect(edits.saved, hasLength(2));
      expect(
        find.textContaining('Location changed on 2 photos.'),
        findsOneWidget,
      );
      expect(
        find.textContaining('1 photo could not be changed.'),
        findsOneWidget,
      );
    });

    testWidgets('IMG-007 the edit dialog can choose a location', (
      tester,
    ) async {
      final (_, edits, _) = await open(tester);
      await tester.tap(find.byType(KGridTile).first);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Details'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Edit details'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Search or type a location'));
      await tester.tap(find.text('Search or type a location'));
      await tester.pumpAndSettle();
      expect(find.text('Latitude, longitude'), findsOneWidget);
      // Opens on the photo's own position.
      expect(find.text('12.97500, 77.59583'), findsOneWidget);
      await tester.enterText(find.byType(TextField).first, 'tokyo');
      await tester.pump();
      await tester.tap(find.text('Tokyo').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Use this location'));
      await tester.pumpAndSettle();
      expect(find.text('Choose a location'), findsNothing);
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      final edit = edits.saved.single.$2;
      expect(edit.location!.$1, closeTo(35.68, 0.3));
      expect(edit.location!.$2, closeTo(139.69, 0.3));
    });
  });

  group('IMG-007 bulk location changes', () {
    test('IMG-007 one failing file does not stop the others', () async {
      final edits = _Edits()..failing.add(2);
      final photos = fakeEntries(days: 1, perDay: 4, firstId: 1);
      final progress = <int>[];
      final out = await changeLocation(
        edits,
        photos,
        location: (lat: 1.5, lon: 2.5),
        onProgress: progress.add,
      );
      expect(out, (changed: 3, failed: 1));
      expect(progress, [1, 2, 3, 4]);
      expect(edits.saved.map((s) => s.$1), [1, 3, 4]);
      expect(edits.saved.first.$2.location, (1.5, 2.5));
    });

    test('IMG-007 no location means remove it', () async {
      final edits = _Edits();
      await changeLocation(edits, fakeEntries(days: 1, perDay: 1, firstId: 1));
      expect(edits.saved.single.$2.clearLocation, isTrue);
      expect(edits.saved.single.$2.location, isNull);
    });
  });
}
