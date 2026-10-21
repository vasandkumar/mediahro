import 'dart:typed_data';

import 'package:flutter/material.dart' hide ImageInfo;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediahro/app/l10n/gen/app_localizations.dart';
import 'package:mediahro/features/photos/edit/apply_look_flow.dart';
import 'package:mediahro/features/photos/edit/crop_overlay.dart';
import 'package:mediahro/features/photos/edit/curve_editor.dart';
import 'package:mediahro/features/photos/edit/draw_layer.dart';
import 'package:mediahro/features/photos/edit/editor_screen.dart';
import 'package:mediahro/features/photos/edit/photo_editor_service.dart';
import 'package:mediahro/features/photos/photos_providers.dart';
import 'package:mediahro/features/photos/timeline/timeline_model.dart';
import 'package:mediahro/images/edit/edit_engine.dart';
import 'package:mediahro/images/edit/edit_recipe.dart';
import 'package:mediahro/images/image_pipeline.dart';
import 'package:mediahro/images/pipeline/pixel_codec.dart';

import 'photos_harness.dart';

final class FakeEditor implements PhotoEditor {
  FakeEditor({this.saved = EditRecipe.none, this.replaceable = true});

  final EditRecipe saved;
  final bool replaceable;
  bool failLoad = false;
  bool failSave = false;
  EditRecipe lastRendered = EditRecipe.none;
  int renders = 0;
  final List<EditRecipe> stored = [];
  final List<EditRecipe> copies = [];
  final List<EditRecipe> replaced = [];

  PixelFrame frame() {
    const w = 64;
    const h = 48;
    final p = Uint8List(w * h * 4);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final o = (y * w + x) * 4;
        p[o] = x * 4;
        p[o + 1] = y * 5;
        p[o + 2] = 120;
        p[o + 3] = 255;
      }
    }
    return PixelFrame(width: w, height: h, rgba: p);
  }

  @override
  Future<PixelFrame> loadProxy(
    PhotoEntry entry, {
    int edge = editPreviewEdge,
  }) async {
    if (failLoad) throw StateError('unreadable');
    return frame();
  }

  @override
  Future<PixelFrame> render(PixelFrame proxy, EditRecipe recipe) async {
    renders++;
    lastRendered = recipe;
    return applyRecipe(proxy, recipe);
  }

  @override
  Future<EditRecipe> savedRecipe(PhotoEntry entry) async => saved;

  @override
  Future<void> storeRecipe(PhotoEntry entry, EditRecipe recipe) async =>
      stored.add(recipe);

  @override
  bool canReplace(PhotoEntry entry) => replaceable;

  @override
  Future<String> saveCopy(PhotoEntry entry, EditRecipe recipe) async {
    if (failSave) throw StateError('read-only');
    copies.add(recipe);
    return '${entry.name}_edited.jpg';
  }

  @override
  Future<void> replaceOriginal(PhotoEntry entry, EditRecipe recipe) async {
    if (failSave) throw StateError('read-only');
    replaced.add(recipe);
  }
}

void main() {
  late FakeEditor editor;
  final entry = fakeEntries(days: 1, perDay: 1, firstId: 1).single;

  Future<void> settle(WidgetTester tester) async {
    await tester.pump(const Duration(milliseconds: 60));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 80)),
    );
    await tester.pump();
  }

  Future<ProviderContainer> open(WidgetTester tester, FakeEditor e) async {
    editor = e;
    tester.view
      ..physicalSize = const Size(400, 900)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    late BuildContext context;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [photoEditorProvider.overrideWithValue(e)],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (c) {
              context = c;
              return Scaffold(
                body: Center(
                  child: FilledButton(
                    onPressed: () => openEditor(c, entry),
                    child: const Text('edit'),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
    await tester.tap(find.text('edit'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await settle(tester);
    await tester.pump(const Duration(milliseconds: 400));
    return ProviderScope.containerOf(context);
  }

  testWidgets('IMG-009 the editor opens on the photo with the light tools', (
    tester,
  ) async {
    await open(tester, FakeEditor());
    expect(find.text(entry.name), findsOneWidget);
    expect(find.byType(RawImage), findsOneWidget);
    for (final t in ['Crop', 'Light', 'Colour', 'Detail', 'Curves', 'Draw']) {
      expect(find.text(t), findsWidgets);
    }
    for (final s in [
      'Exposure',
      'Contrast',
      'Highlights',
      'Shadows',
      'Whites',
      'Blacks',
    ]) {
      expect(find.text(s), findsOneWidget);
    }
    expect(find.byTooltip('Undo'), findsOneWidget);
    expect(
      tester
          .widget<IconButton>(find.widgetWithIcon(IconButton, Icons.undo))
          .onPressed,
      isNull,
    );
  });

  testWidgets('IMG-009 a slider changes the preview and can be undone', (
    tester,
  ) async {
    await open(tester, FakeEditor());
    final before = editor.renders;
    await tester.drag(find.byType(Slider).first, const Offset(80, 0));
    await settle(tester);
    expect(editor.renders, greaterThan(before));
    expect(editor.lastRendered.amount(AdjustKind.exposure), greaterThan(0.1));
    await tester.tap(find.byTooltip('Undo'));
    await settle(tester);
    expect(editor.lastRendered.amount(AdjustKind.exposure), 0);
    await tester.tap(find.byTooltip('Redo'));
    await settle(tester);
    expect(editor.lastRendered.amount(AdjustKind.exposure), greaterThan(0.1));
  });

  testWidgets('IMG-009 one drag is one undo step, not hundreds', (
    tester,
  ) async {
    await open(tester, FakeEditor());
    await tester.drag(find.byType(Slider).first, const Offset(100, 0));
    await settle(tester);
    await tester.tap(find.byTooltip('Undo'));
    await settle(tester);
    expect(editor.lastRendered.isIdentity, isTrue);
    expect(
      tester
          .widget<IconButton>(find.widgetWithIcon(IconButton, Icons.undo))
          .onPressed,
      isNull,
    );
  });

  testWidgets('IMG-009 double tapping a name puts its slider back to zero', (
    tester,
  ) async {
    await open(
      tester,
      FakeEditor(saved: const EditRecipe(adjust: {AdjustKind.contrast: 0.5})),
    );
    expect(find.text('50'), findsOneWidget);
    await tester.tap(find.text('Contrast'));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(find.text('Contrast'));
    await settle(tester);
    expect(editor.lastRendered.amount(AdjustKind.contrast), 0);
  });

  testWidgets('IMG-009 the edit left last time is restored', (tester) async {
    await open(
      tester,
      FakeEditor(saved: const EditRecipe(adjust: {AdjustKind.exposure: 0.3})),
    );
    expect(find.text('30'), findsOneWidget);
    expect(editor.lastRendered.amount(AdjustKind.exposure), 0.3);
  });

  testWidgets('IMG-009 colour, detail and curves have their own controls', (
    tester,
  ) async {
    await open(tester, FakeEditor());
    await tester.tap(find.text('Colour'));
    await tester.pump();
    for (final s in ['Temperature', 'Tint', 'Saturation', 'Vibrance']) {
      expect(find.text(s), findsOneWidget);
    }
    await tester.tap(find.text('Detail'));
    await tester.pump();
    expect(find.text('Sharpen'), findsOneWidget);
    expect(find.text('Vignette'), findsOneWidget);
    await tester.tap(find.text('Curves'));
    await tester.pump();
    expect(find.byType(CurveEditor), findsOneWidget);
    expect(find.text('RGB'), findsOneWidget);
  });

  testWidgets('IMG-009 sharpen goes from zero up only', (tester) async {
    await open(tester, FakeEditor());
    await tester.tap(find.text('Detail'));
    await tester.pump();
    final slider = tester.widget<Slider>(find.byType(Slider).first);
    expect(slider.min, 0);
    final vignette = tester.widget<Slider>(find.byType(Slider).last);
    expect(vignette.min, -1);
  });

  testWidgets('IMG-009 a point added to the curve changes the picture', (
    tester,
  ) async {
    await open(tester, FakeEditor());
    await tester.tap(find.text('Curves'));
    await tester.pump();
    final box = tester.getRect(find.byType(CurveEditor));
    await tester.tapAt(box.center - const Offset(0, 40));
    await settle(tester);
    final master = editor.lastRendered.curves.master;
    expect(master, hasLength(3));
    expect(master[1].$2, greaterThan(0.5));
    await tester.tap(find.text('Reset curve'));
    await settle(tester);
    expect(editor.lastRendered.curves.master, isEmpty);
  });

  testWidgets(
    'IMG-009 a curve point drags and can be dragged out to remove it',
    (tester) async {
      final semantics = tester.ensureSemantics();
      await open(tester, FakeEditor());
      await tester.tap(find.text('Curves'));
      await tester.pump();
      final box = tester.getRect(find.byType(CurveEditor));
      await tester.tapAt(box.center);
      await settle(tester);
      expect(editor.lastRendered.curves.master, hasLength(3));
      // Drag the new point upwards: the middle of the curve is lifted.
      final handle = find.bySemanticsLabel('Curve point 2');
      final g = await tester.startGesture(tester.getCenter(handle));
      for (var i = 0; i < 6; i++) {
        await g.moveBy(const Offset(0, -10));
      }
      await g.up();
      await settle(tester);
      expect(editor.lastRendered.curves.master[1].$2, greaterThan(0.52));
      // Out of the box: gone.
      final g2 = await tester.startGesture(tester.getCenter(handle));
      for (var i = 0; i < 30; i++) {
        await g2.moveBy(const Offset(0, -12));
      }
      await g2.up();
      await settle(tester);
      expect(editor.lastRendered.curves.master, hasLength(2));
      semantics.dispose();
    },
  );

  testWidgets('IMG-009 curve points work as sliders for screen readers', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await open(tester, FakeEditor());
    await tester.tap(find.text('Curves'));
    await tester.pump();
    expect(find.bySemanticsLabel('Curve point 1'), findsOneWidget);
    expect(find.bySemanticsLabel('Curve point 2'), findsOneWidget);
    tester.semantics.increase(find.semantics.byLabel('Curve point 1'));
    await settle(tester);
    expect(editor.lastRendered.curves.master.first.$2, closeTo(0.05, 1e-9));
    handle.dispose();
  });

  group('IMG-009 crop and turn', () {
    testWidgets('IMG-009 the crop box and ratios appear in the crop tool', (
      tester,
    ) async {
      await open(tester, FakeEditor());
      await tester.tap(find.text('Crop'));
      await settle(tester);
      expect(find.byType(CropOverlay), findsOneWidget);
      for (final r in [
        'Free',
        'Original',
        '1:1',
        '4:3',
        '3:2',
        '16:9',
        '3:4',
        '2:3',
        '9:16',
      ]) {
        expect(find.text(r), findsOneWidget, reason: r);
      }
    });

    testWidgets('IMG-009 a ratio sets the box, shown cropped after leaving', (
      tester,
    ) async {
      await open(tester, FakeEditor());
      await tester.tap(find.text('Crop'));
      await settle(tester);
      await tester.tap(find.text('1:1'));
      await settle(tester);
      // While cropping the whole picture is shown.
      expect(editor.lastRendered.crop.isFull, isTrue);
      await tester.tap(find.text('Light'));
      await settle(tester);
      final c = editor.lastRendered.crop;
      expect(c.isFull, isFalse);
      expect(c.width * 64 / (c.height * 48), closeTo(1, 0.05));
    });

    testWidgets('IMG-009 dragging a corner resizes the crop', (tester) async {
      await open(tester, FakeEditor());
      await tester.tap(find.text('Crop'));
      await settle(tester);
      final area = tester.getRect(find.byType(RawImage));
      await tester.dragFrom(
        area.topLeft + const Offset(2, 2),
        const Offset(60, 40),
      );
      await settle(tester);
      await tester.tap(find.text('Light'));
      await settle(tester);
      final c = editor.lastRendered.crop;
      expect(c.left, greaterThan(0.1));
      expect(c.top, greaterThan(0.05));
      expect(c.right, closeTo(1, 1e-6));
    });

    testWidgets('IMG-009 turn and flip buttons change the geometry', (
      tester,
    ) async {
      await open(tester, FakeEditor());
      await tester.tap(find.text('Crop'));
      await settle(tester);
      await tester.tap(find.byTooltip('Turn right'));
      await settle(tester);
      expect(editor.lastRendered.turns, 1);
      await tester.tap(find.byTooltip('Turn left'));
      await settle(tester);
      expect(editor.lastRendered.turns, 0);
      await tester.tap(find.byTooltip('Flip horizontally'));
      await settle(tester);
      expect(editor.lastRendered.flipHorizontal, isTrue);
      await tester.tap(find.byTooltip('Flip vertically'));
      await settle(tester);
      expect(editor.lastRendered.flipVertical, isTrue);
    });

    testWidgets('IMG-009 the straighten slider tilts the picture', (
      tester,
    ) async {
      await open(tester, FakeEditor());
      await tester.tap(find.text('Crop'));
      await settle(tester);
      await tester.drag(find.byType(Slider).last, const Offset(60, 0));
      await settle(tester);
      expect(editor.lastRendered.straighten, greaterThan(1));
      expect(find.textContaining('°'), findsOneWidget);
    });

    testWidgets('IMG-009 reset crop restores the whole picture', (
      tester,
    ) async {
      await open(
        tester,
        FakeEditor(saved: const EditRecipe(crop: NormRect(0.1, 0.1, 0.5, 0.5))),
      );
      await tester.tap(find.text('Crop'));
      await settle(tester);
      await tester.tap(find.text('Reset crop'));
      await settle(tester);
      await tester.tap(find.text('Light'));
      await settle(tester);
      expect(editor.lastRendered.crop.isFull, isTrue);
    });
  });

  group('IMG-009 drawing', () {
    testWidgets('IMG-009 dragging with the pen leaves a stroke in the recipe', (
      tester,
    ) async {
      await open(tester, FakeEditor());
      await tester.tap(find.text('Draw'));
      await settle(tester);
      expect(find.byType(DrawLayer), findsOneWidget);
      final area = tester.getRect(find.byType(RawImage));
      await tester.dragFrom(area.center, const Offset(60, 20));
      await settle(tester);
      expect(editor.lastRendered.strokes, hasLength(1));
      expect(editor.lastRendered.strokes.single.colorArgb, 0xFFE53935);
      expect(editor.lastRendered.strokes.single.points.length, greaterThan(1));
    });

    testWidgets('IMG-009 colour and width are chosen before drawing', (
      tester,
    ) async {
      await open(tester, FakeEditor());
      await tester.tap(find.text('Draw'));
      await settle(tester);
      await tester.tap(find.bySemanticsLabel('Blue'));
      await tester.tap(find.text('Thick'));
      await tester.pump();
      final area = tester.getRect(find.byType(RawImage));
      await tester.dragFrom(area.center, const Offset(50, 0));
      await settle(tester);
      final s = editor.lastRendered.strokes.single;
      expect(s.colorArgb, 0xFF1E88E5);
      expect(s.width, 0.016);
    });

    testWidgets('IMG-009 line, arrow and box make their shapes', (
      tester,
    ) async {
      await open(tester, FakeEditor());
      await tester.tap(find.text('Draw'));
      await settle(tester);
      final area = tester.getRect(find.byType(RawImage));
      await tester.tap(find.text('Line'));
      await tester.pump();
      await tester.dragFrom(
        area.center - const Offset(40, 0),
        const Offset(80, 10),
      );
      await settle(tester);
      expect(editor.lastRendered.strokes.last.points, hasLength(2));
      await tester.tap(find.text('Arrow'));
      await tester.pump();
      await tester.dragFrom(
        area.center - const Offset(40, 20),
        const Offset(80, 10),
      );
      await settle(tester);
      expect(editor.lastRendered.strokes.last.points, hasLength(5));
      await tester.tap(find.text('Box'));
      await tester.pump();
      await tester.dragFrom(
        area.center - const Offset(30, 30),
        const Offset(60, 40),
      );
      await settle(tester);
      final box = editor.lastRendered.strokes.last.points;
      expect(box, hasLength(5));
      expect(box.first, box.last);
      expect(editor.lastRendered.strokes, hasLength(3));
    });

    testWidgets('IMG-009 the blur tool marks an area to blur', (tester) async {
      await open(tester, FakeEditor());
      await tester.tap(find.text('Draw'));
      await settle(tester);
      await tester.tap(find.text('Blur'));
      await tester.pump();
      expect(find.bySemanticsLabel('Red'), findsNothing);
      final area = tester.getRect(find.byType(RawImage));
      await tester.dragFrom(
        area.center - const Offset(30, 20),
        const Offset(60, 40),
      );
      await settle(tester);
      expect(editor.lastRendered.blurs, hasLength(1));
      expect(editor.lastRendered.strokes, isEmpty);
    });

    testWidgets('IMG-009 drawings can be removed and undone', (tester) async {
      await open(tester, FakeEditor());
      await tester.tap(find.text('Draw'));
      await settle(tester);
      final area = tester.getRect(find.byType(RawImage));
      await tester.dragFrom(area.center, const Offset(60, 20));
      await settle(tester);
      await tester.tap(find.text('Remove drawings and blurs'));
      await settle(tester);
      expect(editor.lastRendered.strokes, isEmpty);
      await tester.tap(find.byTooltip('Undo'));
      await settle(tester);
      expect(editor.lastRendered.strokes, hasLength(1));
    });
  });

  group('IMG-009 saving', () {
    Future<void> menu(WidgetTester tester, String item) async {
      await tester.tap(find.byTooltip('More'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(item));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
    }

    testWidgets('IMG-009 save a copy writes the recipe and says where', (
      tester,
    ) async {
      await open(tester, FakeEditor());
      await tester.drag(find.byType(Slider).first, const Offset(60, 0));
      await settle(tester);
      await menu(tester, 'Save a copy');
      await tester.pumpAndSettle();
      expect(editor.copies, hasLength(1));
      expect(editor.copies.single.amount(AdjustKind.exposure), greaterThan(0));
      expect(
        find.text(
          '${entry.name}_edited.jpg'.isEmpty
              ? ''
              : 'Saved as ${entry.name}_edited.jpg.',
        ),
        findsOneWidget,
      );
      // The editor stays open to carry on.
      expect(find.byType(EditorScreen), findsOneWidget);
    });

    testWidgets('IMG-009 a failed save says so and loses nothing', (
      tester,
    ) async {
      await open(tester, FakeEditor()..failSave = true);
      await menu(tester, 'Save a copy');
      await tester.pumpAndSettle();
      expect(find.textContaining("Couldn't save"), findsOneWidget);
      expect(find.byType(EditorScreen), findsOneWidget);
    });

    testWidgets('IMG-009 replacing the original asks first', (tester) async {
      await open(tester, FakeEditor());
      await menu(tester, 'Replace the original');
      await tester.pumpAndSettle();
      expect(find.text('Replace the original?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(editor.replaced, isEmpty);
      await menu(tester, 'Replace the original');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Replace'));
      await tester.pumpAndSettle();
      expect(editor.replaced, hasLength(1));
      expect(find.byType(EditorScreen), findsNothing);
    });

    testWidgets('IMG-009 formats that cannot be replaced only offer copies', (
      tester,
    ) async {
      await open(tester, FakeEditor(replaceable: false));
      await tester.tap(find.byTooltip('More'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Replace the original'), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(find.text('Replace the original?'), findsNothing);
      expect(editor.replaced, isEmpty);
    });

    testWidgets('IMG-009 closing keeps the edit for next time', (tester) async {
      await open(tester, FakeEditor());
      await tester.drag(find.byType(Slider).first, const Offset(60, 0));
      await settle(tester);
      await tester.tap(find.byTooltip('Close editor'));
      await tester.pumpAndSettle();
      expect(find.byType(EditorScreen), findsNothing);
      expect(editor.stored.single.amount(AdjustKind.exposure), greaterThan(0));
    });

    testWidgets('IMG-009 reset all returns to the untouched photo', (
      tester,
    ) async {
      await open(
        tester,
        FakeEditor(saved: const EditRecipe(adjust: {AdjustKind.exposure: 0.4})),
      );
      await menu(tester, 'Reset all edits');
      await settle(tester);
      expect(editor.lastRendered.isIdentity, isTrue);
      await tester.tap(find.byTooltip('Undo'));
      await settle(tester);
      expect(editor.lastRendered.amount(AdjustKind.exposure), 0.4);
    });

    testWidgets('IMG-009 the look can be copied, geometry stays behind', (
      tester,
    ) async {
      final container = await open(
        tester,
        FakeEditor(
          saved: const EditRecipe(
            turns: 1,
            adjust: {AdjustKind.saturation: 0.4},
          ),
        ),
      );
      await menu(tester, 'Copy this look');
      await tester.pumpAndSettle();
      final look = container.read(copiedLookProvider)!;
      expect(look.amount(AdjustKind.saturation), 0.4);
      expect(look.hasGeometry, isFalse);
      expect(find.textContaining('Look copied'), findsOneWidget);
    });
  });

  testWidgets('IMG-009 a photo that cannot be opened says so', (tester) async {
    await open(tester, FakeEditor()..failLoad = true);
    expect(
      find.text("This photo can't be opened for editing."),
      findsOneWidget,
    );
  });

  group('IMG-009 apply a look to other photos', () {
    testWidgets(
      'IMG-009 the dialog offers copies and, where possible, replacing',
      (tester) async {
        final e = FakeEditor();
        final photos = fakeEntries(days: 1, perDay: 2, firstId: 1);
        late WidgetRef ref0;
        late BuildContext ctx;
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              photoEditorProvider.overrideWithValue(e),
              copiedLookProvider.overrideWith(
                () => _FixedLook(
                  const EditRecipe(adjust: {AdjustKind.exposure: 0.2}),
                ),
              ),
            ],
            child: MaterialApp(
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: Consumer(
                builder: (c, ref, _) {
                  ref0 = ref;
                  ctx = c;
                  return Scaffold(
                    body: TextButton(
                      onPressed: () => applyCopiedLookFlow(ctx, ref0, photos),
                      child: const Text('go'),
                    ),
                  );
                },
              ),
            ),
          ),
        );
        await tester.tap(find.text('go'));
        await tester.pumpAndSettle();
        expect(find.text('Apply the copied look?'), findsOneWidget);
        expect(find.textContaining('these 2 photos'), findsOneWidget);
        await tester.tap(find.text('Save copies'));
        await tester.pumpAndSettle();
        expect(e.copies, hasLength(2));
        expect(find.text('2 photos saved.'), findsOneWidget);
      },
    );

    testWidgets('IMG-009 replacing originals goes through the editor', (
      tester,
    ) async {
      final e = FakeEditor();
      final photos = fakeEntries(days: 1, perDay: 3, firstId: 1);
      late BuildContext ctx;
      late WidgetRef ref0;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            photoEditorProvider.overrideWithValue(e),
            copiedLookProvider.overrideWith(
              () => _FixedLook(
                const EditRecipe(adjust: {AdjustKind.exposure: 0.2}),
              ),
            ),
          ],
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Consumer(
              builder: (c, ref, _) {
                ref0 = ref;
                ctx = c;
                return Scaffold(
                  body: TextButton(
                    onPressed: () => applyCopiedLookFlow(ctx, ref0, photos),
                    child: const Text('go'),
                  ),
                );
              },
            ),
          ),
        ),
      );
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Replace originals'));
      await tester.pumpAndSettle();
      expect(e.replaced, hasLength(3));
      expect(e.copies, isEmpty);
    });
  });
}

class _FixedLook extends CopiedLook {
  _FixedLook(this.look);

  final EditRecipe look;

  @override
  EditRecipe? build() => look;
}
