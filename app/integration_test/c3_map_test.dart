// Lane C3 device batch, map (IMG-007): the bundled gazetteer is packaged in the
// APK, the map draws real tile pictures and takes touch input on the Samsung.
// Needs `assets/gazetteer/` in app/pubspec.yaml (orchestrator change in the PR).
//
//   flutter test integration_test/c3_map_test.dart -d <serial> --no-dds \
//     -P kotlin.incremental=false
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mediahro/app/l10n/gen/app_localizations.dart';
import 'package:mediahro/features/photos/map/clustering.dart';
import 'package:mediahro/features/photos/map/gazetteer.dart';
import 'package:mediahro/features/photos/map/map_providers.dart';
import 'package:mediahro/features/photos/map/map_surface.dart';
import 'package:mediahro/features/photos/map/map_tiles.dart';
import 'package:mediahro/features/photos/map/web_mercator.dart';

/// A 256 px tile with a diagonal, made on the device.
Future<Uint8List> _tilePng() async {
  final rec = ui.PictureRecorder();
  Canvas(rec)
    ..drawRect(
      const Rect.fromLTWH(0, 0, 256, 256),
      Paint()..color = const Color(0xFFCFE8CF),
    )
    ..drawLine(
      Offset.zero,
      const Offset(256, 256),
      Paint()
        ..color = const Color(0xFF225522)
        ..strokeWidth = 4,
    );
  final img = await rec.endRecording().toImage(256, 256);
  final data = await img.toByteData(format: ui.ImageByteFormat.png);
  return data!.buffer.asUint8List();
}

final class _Tiles implements MapTileSource {
  _Tiles(this.png);

  final Uint8List png;
  final List<TileId> loads = [];

  @override
  bool get enabled => true;

  @override
  Future<Uint8List?> load(TileId id) async {
    loads.add(id);
    return png;
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('IMG-007 the gazetteer is packaged and names places', (
    tester,
  ) async {
    final data = await rootBundle.load(gazetteerAsset);
    final g = Gazetteer.parse(
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
    );
    expect(g.length, greaterThan(30000));
    expect(g.nearest(12.9716, 77.5946)!.name, 'Bengaluru');
    expect(g.nearest(48.8566, 2.3522)!.country, 'France');
    expect(g.search('zurich').first.country, 'Switzerland');
  });

  testWidgets('IMG-007 the map draws tiles, pans and zooms by touch', (
    tester,
  ) async {
    final tiles = _Tiles(await tester.runAsync(_tilePng) ?? Uint8List(0));
    final controller = MapController(
      initialCenter: (lat: 48.85, lon: 2.35),
      initialZoom: 9,
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: MapSurface(
              controller: controller,
              tiles: tiles,
              autofocus: true,
              overlay: (context, camera) => [
                for (final c in clusterPhotos([
                  GeoPhoto(id: 1, lat: 48.85, lon: 2.35, time: 1),
                ], camera))
                  Positioned(
                    left: camera.toScreen(c.lat, c.lon).dx - 8,
                    top: camera.toScreen(c.lat, c.lon).dy - 8,
                    child: const Icon(Icons.circle, size: 16),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    for (var i = 0; i < 20 && tiles.loads.length < 4; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump();
    }
    expect(tiles.loads, isNotEmpty);
    expect(tester.takeException(), isNull);

    final before = controller.camera!;
    await tester.drag(find.byType(MapSurface), const Offset(-120, 0));
    await tester.pumpAndSettle();
    expect(controller.camera!.center.lon, greaterThan(before.center.lon));

    final zoom = controller.camera!.zoom;
    final centre = tester.getCenter(find.byType(MapSurface));
    final a = await tester.startGesture(centre - const Offset(40, 0));
    final b = await tester.startGesture(centre + const Offset(40, 0));
    await a.moveBy(const Offset(-60, 0));
    await b.moveBy(const Offset(60, 0));
    await a.up();
    await b.up();
    await tester.pumpAndSettle();
    expect(controller.camera!.zoom, greaterThan(zoom));
    expect(tester.takeException(), isNull);
  });
}
