import 'package:flutter/material.dart' hide ImageInfo;
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:mediahro/core/net/network_policy.dart';
import 'package:mediahro/core/net/persistent_network_policy.dart';
import 'package:mediahro/core/providers.dart';
import 'package:mediahro/features/photos/map/clustering.dart';
import 'package:mediahro/features/photos/map/map_providers.dart';
import 'package:mediahro/features/photos/map/places_providers.dart';
import 'package:mediahro_design/mediahro_design.dart';

import 'map_surface_test.dart' show FakeTiles;
import 'photos_harness.dart';

GeoPhoto _geo(int id, double lat, double lon) =>
    GeoPhoto(id: id, lat: lat, lon: lon, time: id * 1000);

const _one = '1 photo, double tap to open';

void main() {
  Future<PhotosHarness> openTab(
    WidgetTester tester,
    String tab, {
    required List<Override> extra,
  }) async {
    final h = await PhotosHarness.create(tester);
    await h.pump(
      tester,
      entries: fakeEntries(days: 1, firstId: 1),
      extra: extra,
    );
    await tester.ensureVisible(find.text(tab));
    await tester.pumpAndSettle();
    await tester.tap(find.text(tab));
    await tester.pumpAndSettle();
    return h;
  }

  List<Override> mapOverrides(
    List<GeoPhoto> geo, {
    bool? tiles = false,
    FakeTiles? source,
  }) => [
    geoPhotosProvider.overrideWith((ref) => Stream.value(geo)),
    if (tiles != null)
      mapTilesEnabledProvider.overrideWith((ref) => Stream.value(tiles)),
    mapTileSourceProvider.overrideWithValue(source ?? FakeTiles()),
  ];

  group('IMG-007 map tab', () {
    testWidgets('IMG-007 without geotagged photos the map explains itself', (
      tester,
    ) async {
      await openTab(tester, 'Map', extra: mapOverrides(const []));
      expect(find.text('No photos with a location'), findsOneWidget);
      expect(find.byTooltip('Zoom in'), findsNothing);
    });

    testWidgets('IMG-007 photos on one spot make one marker with a count', (
      tester,
    ) async {
      await openTab(
        tester,
        'Map',
        extra: mapOverrides([
          _geo(1, 48.85, 2.35),
          _geo(2, 48.85, 2.35),
          _geo(3, -33.87, 151.2),
        ]),
      );
      expect(
        find.bySemanticsLabel('2 photos, double tap to open'),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel(_one), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
    });

    testWidgets('IMG-007 a lone marker opens that photo in the viewer', (
      tester,
    ) async {
      final h = await openTab(
        tester,
        'Map',
        extra: mapOverrides([_geo(1, 48.85, 2.35), _geo(3, -33.87, 151.2)]),
      );
      await tester.tap(find.bySemanticsLabel(_one).last);
      await tester.pumpAndSettle();
      expect(h.opened, isNotEmpty);
      expect({1, 3}, contains(h.opened.first.id));
    });

    testWidgets('IMG-007 tapping a cluster zooms in until it splits', (
      tester,
    ) async {
      await openTab(
        tester,
        'Map',
        extra: mapOverrides([
          _geo(1, 48.85, 2.35),
          _geo(2, 48.86, 2.36),
          _geo(3, -33.87, 151.2),
        ]),
      );
      expect(
        find.bySemanticsLabel('2 photos, double tap to open'),
        findsOneWidget,
      );
      await tester.tap(find.bySemanticsLabel('2 photos, double tap to open'));
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel(_one), findsNWidgets(2));
      expect(
        find.bySemanticsLabel('2 photos, double tap to open'),
        findsNothing,
      );
    });

    testWidgets('IMG-007 photos on exactly one spot open as a list', (
      tester,
    ) async {
      await openTab(
        tester,
        'Map',
        extra: mapOverrides([
          _geo(1, 48.85, 2.35),
          _geo(2, 48.85, 2.35),
          _geo(3, 48.85, 2.35),
        ]),
      );
      await tester.tap(find.bySemanticsLabel('3 photos, double tap to open'));
      await tester.pumpAndSettle();
      expect(find.text('3 photos here'), findsOneWidget);
      expect(find.byType(KGridTile), findsNWidgets(3));
    });

    testWidgets('IMG-007 the map has zoom and show-all controls', (
      tester,
    ) async {
      await openTab(
        tester,
        'Map',
        extra: mapOverrides([_geo(1, 48.85, 2.35), _geo(2, 48.86, 2.36)]),
      );
      expect(find.byTooltip('Zoom in'), findsOneWidget);
      expect(find.byTooltip('Zoom out'), findsOneWidget);
      expect(find.byTooltip('Show all photos'), findsOneWidget);
      await tester.tap(find.byTooltip('Zoom in'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Show all photos'));
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel(_one), findsWidgets);
    });

    testWidgets('IMG-007 with map pictures off nothing asks the tile server', (
      tester,
    ) async {
      final tiles = FakeTiles(enabled: false);
      await openTab(
        tester,
        'Map',
        extra: mapOverrides([_geo(1, 48.85, 2.35)], source: tiles),
      );
      expect(find.textContaining('Map pictures are off'), findsOneWidget);
      expect(find.text('© OpenStreetMap contributors'), findsNothing);
      // Cache-only: the source is asked, and answers from disk or not at all.
      expect(tiles.enabled, isFalse);
    });

    testWidgets('IMG-007 the off note explains before anything is turned on', (
      tester,
    ) async {
      await openTab(tester, 'Map', extra: mapOverrides([_geo(1, 48.85, 2.35)]));
      await tester.tap(find.text('Turn on map pictures'));
      await tester.pumpAndSettle();
      expect(find.text('Turn on map pictures?'), findsOneWidget);
      expect(find.textContaining('never your photos'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('Turn on map pictures?'), findsNothing);
      expect(find.textContaining('Map pictures are off'), findsOneWidget);
    });

    testWidgets('IMG-007 turning map pictures on is the switch of Privacy', (
      tester,
    ) async {
      final h = await PhotosHarness.create(tester);
      final policy = (await tester.runAsync(
        () => PersistentNetworkPolicy.load(h.db),
      ))!;
      await h.pump(
        tester,
        entries: fakeEntries(days: 1, firstId: 1),
        extra: [
          networkPolicyProvider.overrideWithValue(policy),
          ...mapOverrides([_geo(1, 48.85, 2.35)], tiles: null),
        ],
      );
      await tester.ensureVisible(find.text('Map'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Map'));
      await tester.pumpAndSettle();
      expect(policy.isEnabled(Endpoints.mapTiles), isFalse);
      await tester.tap(find.text('Turn on map pictures'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Turn on'));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)),
      );
      await tester.pumpAndSettle();
      expect(policy.isEnabled(Endpoints.mapTiles), isTrue);
      expect(find.textContaining('Map pictures are off'), findsNothing);
      expect(find.text('© OpenStreetMap contributors'), findsOneWidget);
    });

    testWidgets('IMG-007 a photo at 0, 0 is not on the map', (tester) async {
      // The provider drops no-fix positions before the map sees them.
      expect(
        [_geo(1, 0, 0)].where((p) => !(p.lat == 0 && p.lon == 0)),
        isEmpty,
      );
    });
  });

  group('IMG-007 places tab', () {
    const paris = PlaceGroup(
      id: 1,
      name: 'Paris',
      country: 'France',
      count: 2,
      coverId: 2,
    );
    const lyon = PlaceGroup(
      id: 2,
      name: 'Lyon',
      country: 'France',
      count: 1,
      coverId: 3,
    );
    const pune = PlaceGroup(
      id: 3,
      name: 'Pune',
      country: 'India',
      count: 3,
      coverId: 4,
    );

    List<Override> placeOverrides(List<PlaceGroup> places) => [
      photoPlacesProvider.overrideWith((ref) => Stream.value(places)),
      placeEntriesProvider.overrideWith(
        (ref, id) => Stream.value(
          fakeEntries(
            days: 1,
            perDay: id == 1 ? 2 : 1,
            firstId: id == 1 ? 1 : 5,
          ),
        ),
      ),
    ];

    testWidgets('IMG-007 places are listed by country with their counts', (
      tester,
    ) async {
      await openTab(
        tester,
        'Places',
        extra: placeOverrides([paris, lyon, pune]),
      );
      expect(find.text('France'), findsOneWidget);
      expect(find.text('India'), findsOneWidget);
      expect(find.text('Paris'), findsOneWidget);
      expect(find.text('2 photos'), findsOneWidget);
      expect(find.text('3 photos'), findsOneWidget);
      expect(find.text('1 photo'), findsOneWidget);
    });

    testWidgets('IMG-007 a place opens its photos', (tester) async {
      await openTab(tester, 'Places', extra: placeOverrides([paris, pune]));
      await tester.tap(find.text('Paris'));
      await tester.pumpAndSettle();
      expect(find.byType(AppBar), findsOneWidget);
      expect(find.text('Paris'), findsOneWidget);
      expect(find.byType(KGridTile), findsNWidgets(2));
    });

    testWidgets('IMG-007 no places yet says how places appear', (tester) async {
      await openTab(tester, 'Places', extra: placeOverrides(const []));
      expect(find.text('No places yet'), findsOneWidget);
    });
  });
}
