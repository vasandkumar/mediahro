import 'dart:ui' as ui;

import 'package:flutter/material.dart' hide ImageInfo;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediahro/app/app.dart';
import 'package:mediahro/app/router.dart';
import 'package:mediahro/features/photos/photos_providers.dart';
import 'package:mediahro/features/photos/timeline/timeline_model.dart';
import 'package:mediahro/features/photos/viewer/photo_viewer.dart';
import 'package:mediahro/features/photos/viewer/viewer_image.dart';
import 'package:mediahro/features/photos/viewer/viewer_surface.dart';
import 'package:mediahro/features/photos/viewer/zoom_math.dart';
import 'package:mediahro/features/settings/settings_providers.dart';
import 'package:mediahro/images/image_pipeline.dart';
import 'package:mediahro_design/mediahro_design.dart';

import '../../helpers.dart';
import 'photos_harness.dart';

void main() {
  late List<PhotoEntry> entries;
  late List<ui.Image> spare;

  /// Opens the viewer on the first photo, which shows the picture [first]
  /// makes; the other photos get the harness pictures.
  Future<PhotosHarness> open(
    WidgetTester tester, {
    required ViewerImage Function(PhotosHarness h) first,
    ViewerPageLoader? pages,
  }) async {
    final h = await PhotosHarness.create(tester);
    spare = [for (var i = 0; i < 8; i++) await _pic(tester)];
    entries = fakeEntries(days: 1);
    tester.view
      ..physicalSize = const Size(400, 800) * tester.view.devicePixelRatio
      ..devicePixelRatio = tester.view.devicePixelRatio;
    addTearDown(tester.view.resetPhysicalSize);
    final store = await tester.runAsync(memoryStore) ?? (throw StateError('s'));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsStoreProvider.overrideWithValue(store),
          ...h.overrides(
            entries: entries,
            loader: (e) async => e.id == 0 ? first(h) : h.take(),
          ),
          if (pages != null) viewerPageLoaderProvider.overrideWithValue(pages),
        ],
        child: MediahroApp(
          router: buildRouter(
            initialLocation: '/photos',
            fullScreenRoutes: photoRoutes,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(KGridTile).first);
    await tester.pumpAndSettle();
    return h;
  }

  ViewerImage multiPage(PhotosHarness h, {int pages = 3}) {
    final p = h.take();
    return ViewerImage(
      base: p.base,
      fullSize: p.fullSize,
      info: ImageInfo(width: 4000, height: 3000, format: 'tiff', pages: pages),
    );
  }

  group('IMG-001 multi-page TIFF', () {
    testWidgets(
      'IMG-001 a TIFF with pages shows which page and steps through them',
      (tester) async {
        final asked = <int>[];
        await open(
          tester,
          first: multiPage,
          pages: (entry, page) async {
            asked.add(page);
            return ViewerImage(
              base: spare.removeLast(),
              fullSize: const ui.Size(4000, 3000),
              info: const ImageInfo(
                width: 4000,
                height: 3000,
                format: 'tiff',
                pages: 3,
              ),
            );
          },
        );
        expect(find.text('Page 1 of 3'), findsOneWidget);
        expect(
          tester
              .widget<IconButton>(
                find.widgetWithIcon(IconButton, Icons.chevron_left),
              )
              .onPressed,
          isNull,
        );
        await tester.tap(find.byTooltip('Next page'));
        await tester.pumpAndSettle();
        expect(find.text('Page 2 of 3'), findsOneWidget);
        await tester.tap(find.byTooltip('Next page'));
        await tester.pumpAndSettle();
        expect(find.text('Page 3 of 3'), findsOneWidget);
        expect(
          tester
              .widget<IconButton>(
                find.widgetWithIcon(IconButton, Icons.chevron_right),
              )
              .onPressed,
          isNull,
        );
        await tester.tap(find.byTooltip('Previous page'));
        await tester.pumpAndSettle();
        expect(find.text('Page 2 of 3'), findsOneWidget);
        expect(asked, [1, 2, 1]);
      },
    );

    testWidgets('IMG-001 a single-page photo shows no page controls', (
      tester,
    ) async {
      await open(tester, first: (h) => h.take());
      expect(find.byTooltip('Next page'), findsNothing);
      expect(find.textContaining('Page '), findsNothing);
    });

    testWidgets('IMG-001 moving to another photo starts at its first page', (
      tester,
    ) async {
      await open(
        tester,
        first: multiPage,
        pages: (entry, page) async => ViewerImage(
          base: spare.removeLast(),
          fullSize: const ui.Size(4000, 3000),
          info: const ImageInfo(
            width: 4000,
            height: 3000,
            format: 'tiff',
            pages: 3,
          ),
        ),
      );
      await tester.tap(find.byTooltip('Next page'));
      await tester.pumpAndSettle();
      await tester.drag(find.byType(PageView), const Offset(-380, 0));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Next page'), findsNothing);
      await tester.drag(find.byType(PageView), const Offset(380, 0));
      await tester.pumpAndSettle();
      expect(find.text('Page 1 of 3'), findsOneWidget);
    });
  });

  group('IMG-001 panoramas', () {
    ViewerImage pano(PhotosHarness h, {double w = 8000, double hgt = 2000}) {
      final p = h.take();
      return ViewerImage(
        base: p.base,
        fullSize: ui.Size(w, hgt),
        info: ImageInfo(
          width: w.round(),
          height: hgt.round(),
          format: 'jpeg',
          isPanorama: true,
        ),
      );
    }

    FitMode shown(WidgetTester tester) =>
        tester.widget<ViewerSurface>(find.byType(ViewerSurface).first).mode;

    testWidgets(
      'IMG-001 a wide panorama opens filling the height so it can be panned',
      (tester) async {
        await open(tester, first: pano);
        expect(shown(tester), FitMode.fill);
        // The button offers the whole picture back.
        await tester.tap(find.byTooltip('Fit to screen'));
        await tester.pumpAndSettle();
        expect(shown(tester), FitMode.fit);
        await tester.tap(find.byTooltip('Fill screen'));
        await tester.pumpAndSettle();
        expect(shown(tester), FitMode.fill);
      },
    );

    testWidgets('IMG-001 a panorama tag on an ordinary shape changes nothing', (
      tester,
    ) async {
      await open(tester, first: (h) => pano(h, w: 4000, hgt: 3000));
      expect(shown(tester), FitMode.fit);
    });

    testWidgets('IMG-001 a wide photo without the panorama tag is not filled', (
      tester,
    ) async {
      await open(
        tester,
        first: (h) {
          final p = h.take();
          return ViewerImage(
            base: p.base,
            fullSize: const ui.Size(8000, 2000),
            info: const ImageInfo(width: 8000, height: 2000, format: 'jpeg'),
          );
        },
      );
      expect(shown(tester), FitMode.fit);
    });

    testWidgets('IMG-001 the next photo is back to fit', (tester) async {
      await open(tester, first: pano);
      await tester.drag(find.byType(PageView), const Offset(-380, 0));
      await tester.pumpAndSettle();
      expect(shown(tester), FitMode.fit);
    });
  });
}

/// A small picture made with the real engine.
Future<ui.Image> _pic(WidgetTester tester) async =>
    (await tester.runAsync(() async {
      final rec = ui.PictureRecorder();
      ui.Canvas(rec).drawRect(
        const ui.Rect.fromLTWH(0, 0, 8, 6),
        ui.Paint()..color = const Color(0xFF336699),
      );
      return await rec.endRecording().toImage(8, 6);
    }))!;
