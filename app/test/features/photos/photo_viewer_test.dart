import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart' hide ImageInfo;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:mediahro/app/app.dart';
import 'package:mediahro/app/router.dart';
import 'package:mediahro/features/library/widgets.dart';
import 'package:mediahro/features/photos/info/metadata_edit_service.dart';
import 'package:mediahro/features/photos/photos_providers.dart';
import 'package:mediahro/features/photos/timeline/timeline_model.dart';
import 'package:mediahro/features/photos/viewer/photo_viewer.dart';
import 'package:mediahro/features/photos/viewer/viewer_image.dart';
import 'package:mediahro/features/settings/settings_providers.dart';
import 'package:mediahro/images/image_pipeline.dart';
import 'package:mediahro/images/pipeline/mediahro_image_pipeline.dart';
import 'package:mediahro_design/mediahro_design.dart';

import '../../core/seed.dart';
import '../../helpers.dart';
import 'photos_harness.dart';

/// Records the edit instead of writing a file.
final class _RecordingEdits implements MetadataEditor {
  final List<(int, ImageMetadataEdit)> saved = [];
  Exception? failure;

  @override
  Future<MetadataWriteOutcome> save(
    PhotoEntry entry,
    ImageMetadataEdit edit,
  ) async {
    final f = failure;
    if (f != null) throw f;
    saved.add((entry.id, edit));
    return const MetadataWriteOutcome.file();
  }
}

void main() {
  late List<PhotoEntry> entries;

  Future<PhotosHarness> openViewer(
    WidgetTester tester, {
    int index = 1,
    List<PhotoEntry>? list,
    List<Override> extra = const [],
  }) async {
    final h = await PhotosHarness.create(tester);
    entries = list ?? fakeEntries();
    tester.view
      ..physicalSize = const Size(400, 800) * tester.view.devicePixelRatio
      ..devicePixelRatio = tester.view.devicePixelRatio;
    addTearDown(tester.view.resetPhysicalSize);
    final store = await tester.runAsync(memoryStore) ?? (throw StateError('s'));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsStoreProvider.overrideWithValue(store),
          ...h.overrides(entries: entries),
          ...extra,
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
    await tester.tap(find.byType(KGridTile).at(index));
    await tester.pumpAndSettle();
    return h;
  }

  Finder chromeFade() => find.ancestor(
    of: find.byTooltip('Back'),
    matching: find.byType(AnimatedOpacity),
  );

  testWidgets(
    'IMG-004 the viewer opens on the tapped photo with its name and date',
    (tester) async {
      await openViewer(tester, index: 2);
      expect(find.text(entries[2].name), findsOneWidget);
      expect(find.byTooltip('Details'), findsOneWidget);
      final handle = tester.ensureSemantics();
      expect(find.bySemanticsLabel(RegExp('3 of 18')), findsOneWidget);
      handle.dispose();
    },
  );

  testWidgets('IMG-004 swiping moves to the next photo', (tester) async {
    await openViewer(tester, index: 2);
    await tester.drag(find.byType(PageView), const Offset(-380, 0));
    await tester.pumpAndSettle();
    expect(find.text(entries[3].name), findsOneWidget);
    await tester.drag(find.byType(PageView), const Offset(380, 0));
    await tester.pumpAndSettle();
    expect(find.text(entries[2].name), findsOneWidget);
  });

  testWidgets('IMG-004 the arrow keys page through the photos', (tester) async {
    await openViewer(tester, index: 2);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(find.text(entries[3].name), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
    expect(find.text(entries[2].name), findsOneWidget);
  });

  testWidgets('IMG-004 tapping the picture hides and shows the controls', (
    tester,
  ) async {
    await openViewer(tester);
    expect(tester.widget<AnimatedOpacity>(chromeFade().first).opacity, 1);
    await tester.tapAt(const Offset(200, 400));
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.widget<AnimatedOpacity>(chromeFade().first).opacity, 0);
    await tester.tapAt(const Offset(200, 400));
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.widget<AnimatedOpacity>(chromeFade().first).opacity, 1);
  });

  testWidgets('IMG-004 the controls hide on their own after a few seconds', (
    tester,
  ) async {
    await openViewer(tester);
    await tester.pump(const Duration(seconds: 5));
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.widget<AnimatedOpacity>(chromeFade().first).opacity, 0);
  });

  testWidgets(
    'IMG-004 plus and minus zoom, the readout shows the percentage, 0 resets',
    (tester) async {
      await openViewer(tester);
      expect(find.textContaining('%'), findsNothing);
      await tester.sendKeyEvent(LogicalKeyboardKey.equal);
      await tester.pumpAndSettle();
      expect(find.textContaining('%'), findsOneWidget);
      final first = tester.widget<Text>(find.textContaining('%')).data!;
      await tester.sendKeyEvent(LogicalKeyboardKey.equal);
      await tester.pumpAndSettle();
      final second = tester.widget<Text>(find.textContaining('%')).data!;
      expect(
        int.parse(second.replaceAll('%', '')),
        greaterThan(int.parse(first.replaceAll('%', ''))),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.digit0);
      await tester.pumpAndSettle();
      expect(find.textContaining('%'), findsNothing);
    },
  );

  testWidgets('IMG-004 key 1 goes to 1:1 (100 %)', (tester) async {
    await openViewer(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.digit1);
    await tester.pumpAndSettle();
    final pct = tester.widget<Text>(find.textContaining('%')).data!;
    expect(pct, '100%');
  });

  testWidgets('IMG-004 double tap zooms in and a second cycle returns to fit', (
    tester,
  ) async {
    await openViewer(tester);
    Future<void> doubleTap() async {
      await tester.tapAt(const Offset(200, 400));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tapAt(const Offset(200, 400));
      await tester.pumpAndSettle();
    }

    await doubleTap();
    expect(find.textContaining('%'), findsOneWidget);
    await doubleTap();
    await doubleTap();
    expect(
      find.textContaining('%'),
      findsNothing,
      reason: 'fit → 1:1 → 4× → fit',
    );
  });

  testWidgets(
    'IMG-004 a pinch zooms and panning stops page swipes while zoomed',
    (tester) async {
      await openViewer(tester, index: 2);
      final a = await tester.startGesture(const Offset(150, 400), pointer: 1);
      final b = await tester.startGesture(const Offset(250, 400), pointer: 2);
      await tester.pump();
      await a.moveTo(const Offset(60, 400));
      await b.moveTo(const Offset(340, 400));
      await tester.pump();
      await a.up();
      await b.up();
      await tester.pumpAndSettle();
      expect(find.textContaining('%'), findsOneWidget);
      // Zoomed: a horizontal drag pans instead of paging.
      await tester.drag(find.byType(PageView), const Offset(-300, 0));
      await tester.pumpAndSettle();
      expect(find.text(entries[2].name), findsOneWidget);
    },
  );

  testWidgets('IMG-004 fit and fill toggle from the toolbar', (tester) async {
    await openViewer(tester);
    expect(find.byTooltip('Fill screen'), findsOneWidget);
    await tester.tap(find.byTooltip('Fill screen'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Fit to screen'), findsOneWidget);
    await tester.tap(find.byTooltip('Rotate'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('IMG-004 the filmstrip jumps to a photo', (tester) async {
    await openViewer(tester, index: 0);
    final strip = find.byWidgetPredicate(
      (w) => w is Semantics && w.properties.label == 'Go to photo 4',
    );
    expect(strip, findsWidgets);
    await tester.tap(strip.first);
    await tester.pumpAndSettle();
    expect(find.text(entries[3].name), findsOneWidget);
  });

  testWidgets(
    'IMG-004 a photo that cannot be opened shows an error with a retry',
    (tester) async {
      final h = await PhotosHarness.create(tester);
      h.loadError = Exception('unreadable');
      entries = fakeEntries();
      final store =
          await tester.runAsync(memoryStore) ?? (throw StateError('s'));
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            settingsStoreProvider.overrideWithValue(store),
            ...h.overrides(entries: entries),
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
      expect(
        find.text(
          "The file may be damaged, or this device can't read its format.",
        ),
        findsWidgets,
      );
      h.loadError = null;
      await tester.tap(find.text('Try again').first);
      await tester.pumpAndSettle();
      expect(find.text('Try again'), findsNothing);
    },
  );

  group('IMG-006 details', () {
    testWidgets('IMG-006 the info button lists the file facts and metadata', (
      tester,
    ) async {
      await openViewer(tester);
      await tester.tap(find.byTooltip('Details'));
      await tester.pumpAndSettle();
      expect(find.text('Samsung SM-M176B'), findsOneWidget);
      expect(find.text('Main 5.4mm f/1.8'), findsOneWidget);
      expect(find.text('12.97500, 77.59583'), findsOneWidget);
      expect(find.text('4000 × 3000 · 12.0 MP'), findsOneWidget);
      expect(find.text('4 stars'), findsOneWidget);
      expect(find.text('lake'), findsOneWidget);
      expect(find.text('Morning light'), findsOneWidget);
      expect(find.text('Edit details'), findsOneWidget);
    });

    testWidgets('IMG-006 every other tag is available under All metadata', (
      tester,
    ) async {
      await openViewer(tester);
      await tester.tap(find.byTooltip('Details'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('All metadata'));
      await tester.pumpAndSettle();
      expect(find.text('EXIF:ISOSpeedRatings'), findsOneWidget);
      expect(find.text('125'), findsOneWidget);
    });

    testWidgets('IMG-006 editing saves only what changed', (tester) async {
      final edits = _RecordingEdits();
      await openViewer(
        tester,
        extra: [metadataEditServiceProvider.overrideWithValue(edits)],
      );
      await tester.tap(find.byTooltip('Details'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Edit details'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Title'),
        'Sunrise at the lake',
      );
      await tester.tap(find.byTooltip('5 stars'));
      await tester.pump();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(edits.saved, hasLength(1));
      final edit = edits.saved.single.$2;
      expect(edit.title, 'Sunrise at the lake');
      expect(edit.rating, 5);
      expect(edit.description, isNull);
      expect(edit.keywords, isNull);
      expect(edit.captured, isNull);
      expect(edit.location, isNull);
      expect(edit.clearLocation, isFalse);
      expect(find.text('Details saved.'), findsOneWidget);
    });

    testWidgets('IMG-006 an edit can remove the location', (tester) async {
      final edits = _RecordingEdits();
      await openViewer(
        tester,
        extra: [metadataEditServiceProvider.overrideWithValue(edits)],
      );
      await tester.tap(find.byTooltip('Details'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Edit details'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove location'));
      await tester.pump();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(edits.saved.single.$2.clearLocation, isTrue);
    });

    testWidgets('IMG-006 coordinates are validated', (tester) async {
      final edits = _RecordingEdits();
      await openViewer(
        tester,
        extra: [metadataEditServiceProvider.overrideWithValue(edits)],
      );
      await tester.tap(find.byTooltip('Details'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Edit details'));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextField, 'Latitude'), '91');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Enter a latitude from −90 to 90 and a longitude from −180 to 180.',
        ),
        findsOneWidget,
      );
      expect(edits.saved, isEmpty);
    });

    testWidgets('IMG-006 a failed save says so and keeps the sheet', (
      tester,
    ) async {
      final edits = _RecordingEdits()..failure = Exception('read-only');
      await openViewer(
        tester,
        extra: [metadataEditServiceProvider.overrideWithValue(edits)],
      );
      await tester.tap(find.byTooltip('Details'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Edit details'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('3 stars'));
      await tester.pump();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(
        find.text("Couldn't save the details. The source may be read-only."),
        findsOneWidget,
      );
    });

    testWidgets('IMG-006 cancelling the dialog writes nothing', (tester) async {
      final edits = _RecordingEdits();
      await openViewer(
        tester,
        extra: [metadataEditServiceProvider.overrideWithValue(edits)],
      );
      await tester.tap(find.byTooltip('Details'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Edit details'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(edits.saved, isEmpty);
    });
  });

  testWidgets('IMG-001 a RAW shows its preview, then the developed picture', (
    tester,
  ) async {
    final h = await PhotosHarness.create(tester);
    entries = fakeEntries(days: 1);
    final developed = Completer<ViewerImage?>();
    final preview = h.take();
    final store = await tester.runAsync(memoryStore) ?? (throw StateError('s'));
    var first = true;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsStoreProvider.overrideWithValue(store),
          ...h.overrides(
            entries: entries,
            loader: (entry) async {
              if (!first) return h.take();
              first = false;
              return ViewerImage(
                base: preview.base,
                fullSize: preview.fullSize,
                info: preview.info,
                previewOnly: true,
                develop: () => developed.future,
              );
            },
          ),
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
    expect(find.text("Showing the camera's preview"), findsOneWidget);
    developed.complete(h.take());
    await tester.pumpAndSettle();
    expect(find.text("Showing the camera's preview"), findsNothing);
  });

  testWidgets('IMG-004 a video shows a play button that opens the player', (
    tester,
  ) async {
    final seen = <int>[];
    final list = fakeEntries(days: 1, videos: {1});
    final h = await PhotosHarness.create(tester);
    await tester.runAsync(() => Seed(h.db).item('IMG_1.mp4'));
    entries = list;
    final store = await tester.runAsync(memoryStore) ?? (throw StateError('s'));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsStoreProvider.overrideWithValue(store),
          ...h.overrides(entries: entries),
          openItemActionProvider.overrideWithValue(
            (context, item) => seen.add(item.id),
          ),
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
    await tester.tap(find.byType(KGridTile).at(1));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.play_circle_outline), findsOneWidget);
    await tester.tap(find.byIcon(Icons.play_circle_outline));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await tester.pumpAndSettle();
    expect(seen, [1]);
  });

  group('IMG-001 animated images', () {
    // Two 1×1 frames (red then blue), 100 ms each.
    final gif = Uint8List.fromList([
      ...'GIF89a'.codeUnits, 1, 0, 1, 0, 0x80, 0, 0, //
      255, 0, 0, 0, 0, 255, // palette
      0x21, 0xF9, 4, 0, 10, 0, 0, 0, //
      0x2C, 0, 0, 0, 0, 1, 0, 1, 0, 0, 2, 2, 0x44, 1, 0,
      0x21, 0xF9, 4, 0, 10, 0, 0, 0,
      0x2C, 0, 0, 0, 0, 1, 0, 1, 0, 0, 2, 2, 0x4C, 1, 0,
      0x3B,
    ]);

    test('IMG-001 the animation yields each frame with its delay', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      final codec = await ui.instantiateImageCodec(gif);
      final a = ImageAnimation(codec);
      expect(a.frameCount, 2);
      final (f1, d1) = await a.next();
      final (f2, _) = await a.next();
      final (f3, _) = await a.next();
      expect(d1, const Duration(milliseconds: 100));
      expect((f1.width, f1.height), (1, 1));
      for (final f in [f1, f2, f3]) {
        f.dispose();
      }
      a.dispose();
    });

    testWidgets('IMG-001 an animated image gets a pause and play button', (
      tester,
    ) async {
      final h = await PhotosHarness.create(tester);
      entries = fakeEntries(days: 1);
      final codec = await tester.runAsync(() => ui.instantiateImageCodec(gif));
      final first = h.take();
      final store =
          await tester.runAsync(memoryStore) ?? (throw StateError('s'));
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            settingsStoreProvider.overrideWithValue(store),
            ...h.overrides(
              entries: entries,
              loader: (e) async => e.id != 0
                  ? h.take()
                  : ViewerImage(
                      base: first.base,
                      fullSize: first.fullSize,
                      info: first.info,
                      animation: ImageAnimation(codec!),
                    ),
            ),
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
      expect(find.byTooltip('Pause animation'), findsOneWidget);
      await tester.tap(find.byTooltip('Pause animation'));
      await tester.pump();
      expect(find.byTooltip('Play animation'), findsOneWidget);
    });
  });
}
