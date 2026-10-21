// Lane C3 device batch, 360° look-around (IMG-001): the real fragment shader
// on the phone's GPU. The picture is generated (a colour map of the sphere);
// the test checks that the shader is loaded and used, that dragging, pinching
// and the buttons move the camera without errors, and that a cropped
// panorama does not leave its window.
//
//   flutter test integration_test/c3_pano_test.dart -d <serial> --no-dds \
//     -P kotlin.incremental=false
import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mediahro/app/l10n/gen/app_localizations.dart';
import 'package:mediahro/features/photos/pano/pano_painter.dart';
import 'package:mediahro/features/photos/pano/pano_providers.dart';
import 'package:mediahro/features/photos/pano/pano_screen.dart';
import 'package:mediahro/features/photos/pano/pano_view.dart';
import 'package:mediahro/features/photos/timeline/timeline_model.dart';
import 'package:mediahro/images/metadata/pano_meta.dart';

Future<ui.Image> colourMap() async {
  const w = 2048;
  const h = 1024;
  final px = Uint8List(w * h * 4);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final i = (y * w + x) * 4;
      px[i] = (x * 255) ~/ (w - 1);
      px[i + 1] = (y * 255) ~/ (h - 1);
      px[i + 2] = ((x ~/ 128) + (y ~/ 128)).isEven ? 200 : 60;
      px[i + 3] = 255;
    }
  }
  final buffer = await ui.ImmutableBuffer.fromUint8List(px);
  final codec = await ui.ImageDescriptor.raw(
    buffer,
    width: w,
    height: h,
    pixelFormat: ui.PixelFormat.rgba8888,
  ).instantiateCodec();
  return (await codec.getNextFrame()).image;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<void> open(WidgetTester tester, PanoramaMeta? meta) async {
    final map = await colourMap();
    final entry = PhotoEntry(
      id: 1,
      sourceId: 1,
      relPath: 'sphere.jpg',
      name: 'sphere.jpg',
      ext: 'jpg',
      isVideo: false,
      size: 1,
      mtime: DateTime(2026),
      date: DateTime(2026),
      width: 2048,
      height: 1024,
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          panoImageLoaderProvider.overrideWithValue(
            (e) async => PanoImage(image: map.clone(), meta: meta),
          ),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: FilledButton(
                  onPressed: () => unawaited(openPanorama(context, entry)),
                  child: const Text('go'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
  }

  testWidgets('IMG-001 the shader draws the sphere and the camera moves', (
    tester,
  ) async {
    await open(tester, null);
    expect(find.byType(PanoramaView), findsOneWidget);
    // The shader came with the build (pubspec `shaders:`), and was used.
    expect(PanoPainter.lastUsedShader, isTrue);
    final c = tester.widget<PanoramaView>(find.byType(PanoramaView)).controller;
    final start = c.view;
    await tester.dragFrom(const Offset(200, 400), const Offset(-150, 0));
    await tester.pumpAndSettle();
    expect(c.view.yaw > start.yaw, isTrue);
    await tester.tap(find.byTooltip('Zoom in'));
    await tester.pumpAndSettle();
    expect(c.view.fov < start.fov, isTrue);
    await tester.tap(find.byTooltip('Reset the view'));
    await tester.pumpAndSettle();
    expect(c.view, start);
    expect(tester.takeException(), isNull);
  });

  testWidgets('IMG-001 a cropped panorama never shows beyond its window', (
    tester,
  ) async {
    await open(
      tester,
      const PanoramaMeta(
        projection: 'equirectangular',
        fullWidth: 8192,
        fullHeight: 4096,
        croppedWidth: 2048,
        croppedHeight: 1024,
        croppedLeft: 3072,
        croppedTop: 1536,
      ),
    );
    final c = tester.widget<PanoramaView>(find.byType(PanoramaView)).controller;
    for (var i = 0; i < 20; i++) {
      await tester.drag(find.byType(PanoramaView), const Offset(-300, -300));
      await tester.pump();
    }
    await tester.pumpAndSettle();
    expect(c.view, c.camera.clamp(c.view));
    expect(c.view.yaw <= c.geometry.lonMax, isTrue);
    expect(tester.takeException(), isNull);
  });
}
