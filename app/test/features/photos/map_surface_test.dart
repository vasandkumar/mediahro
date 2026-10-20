import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediahro/app/l10n/gen/app_localizations.dart';
import 'package:mediahro/features/photos/map/map_surface.dart';
import 'package:mediahro/features/photos/map/map_tiles.dart';
import 'package:mediahro/features/photos/map/web_mercator.dart';

final class FakeTiles implements MapTileSource {
  FakeTiles({this.enabled = true});

  @override
  bool enabled;
  final List<TileId> loads = [];

  @override
  Future<Uint8List?> load(TileId id) async {
    loads.add(id);
    return null;
  }
}

void main() {
  Future<MapController> pumpMap(
    WidgetTester tester, {
    MapController? controller,
    FakeTiles? tiles,
    bool disableAnimations = false,
    void Function(MapCamera, Offset)? onTap,
  }) async {
    tester.view
      ..physicalSize = const Size(400, 800)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final c =
        controller ??
        MapController(initialCenter: (lat: 48.85, lon: 2.35), initialZoom: 10);
    addTearDown(c.dispose);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(disableAnimations: disableAnimations),
          child: child!,
        ),
        home: Scaffold(
          body: MapSurface(
            controller: c,
            tiles: tiles ?? FakeTiles(),
            autofocus: true,
            onTap: onTap,
            overlay: (context, camera) => const [],
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    return c;
  }

  testWidgets('IMG-007 the map opens on the requested centre and zoom', (
    tester,
  ) async {
    final c = await pumpMap(tester);
    expect(c.camera, isNotNull);
    expect(c.camera!.center.lat, closeTo(48.85, 1e-6));
    expect(c.camera!.center.lon, closeTo(2.35, 1e-6));
    expect(c.camera!.zoom, 10);
    expect(c.camera!.size, const Size(400, 800));
  });

  testWidgets('IMG-007 the map frames the bounds it is given', (tester) async {
    final c = await pumpMap(
      tester,
      controller: MapController(
        initialBounds: const GeoBounds(north: 52, south: 48, west: 2, east: 12),
      ),
    );
    final cam = c.camera!;
    for (final (lat, lon) in [(52.0, 2.0), (48.0, 12.0)]) {
      final p = cam.toScreen(lat, lon);
      expect(p.dx, inInclusiveRange(0, 400));
      expect(p.dy, inInclusiveRange(0, 800));
    }
  });

  testWidgets('IMG-007 dragging moves the map under the finger', (
    tester,
  ) async {
    final c = await pumpMap(tester);
    final before = c.camera!;
    final spot = before.toScreen(48.9, 2.4);
    await tester.drag(find.byType(MapSurface), const Offset(80, 40));
    await tester.pumpAndSettle();
    final moved = c.camera!.toScreen(48.9, 2.4);
    // The first few pixels are touch slop.
    expect(moved.dx, greaterThan(spot.dx + 50));
    expect(moved.dy, greaterThan(spot.dy + 10));
    expect(c.camera!.zoom, 10);
  });

  testWidgets('IMG-007 a flick glides on after the finger lifts', (
    tester,
  ) async {
    final c = await pumpMap(tester);
    final start = c.camera!.center.lon;
    await tester.fling(find.byType(MapSurface), const Offset(-200, 0), 1500);
    await tester.pump();
    final during = c.camera!.center.lon;
    await tester.pumpAndSettle();
    final end = c.camera!.center.lon;
    expect(during, greaterThan(start));
    expect(end, greaterThan(during));
  });

  testWidgets('IMG-007 the mouse wheel zooms around the pointer', (
    tester,
  ) async {
    final c = await pumpMap(tester);
    const at = Offset(100, 200);
    final under = c.camera!.toGeo(at);
    final pointer = TestPointer(1, PointerDeviceKind.mouse);
    await tester.sendEventToBinding(pointer.hover(at));
    await tester.sendEventToBinding(pointer.scroll(const Offset(0, -300)));
    await tester.pump();
    expect(c.camera!.zoom, closeTo(11, 1e-6));
    final now = c.camera!.toScreen(under.lat, under.lon);
    expect(now.dx, closeTo(at.dx, 1e-3));
    expect(now.dy, closeTo(at.dy, 1e-3));
  });

  testWidgets('IMG-007 arrow keys pan and plus and minus zoom', (tester) async {
    final c = await pumpMap(tester, disableAnimations: true);
    final lon = c.camera!.center.lon;
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(c.camera!.center.lon, greaterThan(lon));
    await tester.sendKeyEvent(LogicalKeyboardKey.equal);
    await tester.pump();
    expect(c.camera!.zoom, closeTo(11, 1e-6));
    await tester.sendKeyEvent(LogicalKeyboardKey.minus);
    await tester.pump();
    expect(c.camera!.zoom, closeTo(10, 1e-6));
  });

  testWidgets('IMG-007 a double tap zooms in one level', (tester) async {
    final c = await pumpMap(tester);
    const at = Offset(150, 300);
    await tester.tapAt(at);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tapAt(at);
    await tester.pumpAndSettle();
    expect(c.camera!.zoom, closeTo(11, 1e-6));
  });

  testWidgets('IMG-007 a single tap reaches the owner with the camera', (
    tester,
  ) async {
    Offset? tapped;
    await pumpMap(tester, onTap: (_, at) => tapped = at);
    await tester.tapAt(const Offset(120, 340));
    await tester.pump(const Duration(milliseconds: 400));
    expect(tapped, const Offset(120, 340));
  });

  testWidgets('IMG-007 animateTo glides, and jumps when motion is reduced', (
    tester,
  ) async {
    final c = await pumpMap(tester);
    final target = c.camera!.zoomedAt(const Offset(200, 400), 13);
    final done = c.animateTo(target);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
    expect(c.camera!.zoom, inExclusiveRange(10, 13));
    await tester.pumpAndSettle();
    await done;
    expect(c.camera!.zoom, closeTo(13, 1e-6));
  });

  testWidgets('IMG-007 with reduced motion the map jumps', (tester) async {
    final c = await pumpMap(
      tester,
      controller: MapController(
        initialCenter: (lat: 0, lon: 0),
        initialZoom: 4,
      ),
      disableAnimations: true,
    );
    await c.animateTo(c.camera!.zoomedAt(const Offset(200, 400), 8));
    expect(c.camera!.zoom, closeTo(8, 1e-6));
  });

  testWidgets('IMG-007 a new gesture cancels a running glide', (tester) async {
    final c = await pumpMap(tester);
    final target = c.camera!.zoomedAt(const Offset(200, 400), 14);
    final done = c.animateTo(target);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.drag(find.byType(MapSurface), const Offset(60, 0));
    await tester.pumpAndSettle();
    await done;
    expect(c.camera!.zoom, lessThan(14));
  });

  testWidgets('IMG-007 the layer asks for the tiles under the view', (
    tester,
  ) async {
    final tiles = FakeTiles();
    final c = await pumpMap(tester, tiles: tiles);
    await tester.pump();
    await tester.pump();
    expect(tiles.loads, isNotEmpty);
    expect(tiles.loads.first, const TileId(10, 518, 352));
    expect(c.camera!.tiles().map((t) => t.id), containsAll(tiles.loads));
    expect(tiles.loads.toSet(), hasLength(tiles.loads.length));
  });

  testWidgets('IMG-007 the map is labelled for screen readers', (tester) async {
    await pumpMap(tester);
    expect(find.bySemanticsLabel('Photo map'), findsOneWidget);
  });
}
