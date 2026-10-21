import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediahro/app/l10n/gen/app_localizations.dart';
import 'package:mediahro/features/photos/pano/pano_controller.dart';
import 'package:mediahro/features/photos/pano/pano_math.dart';
import 'package:mediahro/features/photos/pano/pano_providers.dart';
import 'package:mediahro/features/photos/pano/pano_screen.dart';
import 'package:mediahro/features/photos/pano/pano_view.dart';
import 'package:mediahro/features/photos/timeline/timeline_model.dart';
import 'package:mediahro/images/metadata/pano_meta.dart';

import 'photos_harness.dart';

final class _Motion implements PanoMotionSource {
  final StreamController<PanoAttitude> controller =
      StreamController<PanoAttitude>.broadcast();

  @override
  Stream<PanoAttitude> get attitude => controller.stream;
}

Future<ui.Image> _sphere(WidgetTester tester) async {
  final made = await tester.runAsync(() {
    final rec = ui.PictureRecorder();
    final c = ui.Canvas(rec);
    for (var i = 0; i < 8; i++) {
      c.drawRect(
        ui.Rect.fromLTWH(i * 16, 0, 16, 32),
        ui.Paint()..color = Color(0xFF000000 | (i * 30 << 16) | (200 - i * 20)),
      );
    }
    return rec.endRecording().toImage(128, 64);
  });
  return made!;
}

void main() {
  late PhotoEntry entry;
  late ui.Image image;

  PanoController controllerOf(WidgetTester t) =>
      t.widget<PanoramaView>(find.byType(PanoramaView)).controller;

  Future<void> open(
    WidgetTester tester, {
    PanoramaMeta? meta,
    PanoMotionSource? motion,
    bool reduceMotion = false,
    Future<PanoImage> Function()? load,
  }) async {
    entry = fakeEntries(days: 1).first;
    image = await _sphere(tester);
    tester.view
      ..physicalSize = const Size(400, 800)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    if (reduceMotion) {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
    }
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          panoImageLoaderProvider.overrideWithValue(
            (e) => load != null
                ? load()
                : Future.value(PanoImage(image: image.clone(), meta: meta)),
          ),
          panoMotionProvider.overrideWithValue(motion),
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

  group('IMG-001 360° look-around', () {
    testWidgets(
      'IMG-001 the photo opens in the look-around with its controls',
      (tester) async {
        await open(tester);
        expect(find.byType(PanoramaView), findsOneWidget);
        for (final tip in [
          'Look left',
          'Look right',
          'Look up',
          'Look down',
          'Zoom in',
          'Zoom out',
          'Reset the view',
        ]) {
          expect(find.byTooltip(tip), findsOneWidget, reason: tip);
        }
        // Without a sensor there is nothing to follow.
        expect(find.byTooltip('Look around by moving the phone'), findsNothing);
      },
    );

    testWidgets('IMG-001 the buttons turn and zoom the view', (tester) async {
      await open(tester);
      final c = controllerOf(tester);
      final start = c.view;
      await tester.tap(find.byTooltip('Look right'));
      await tester.pump();
      expect(c.view.yaw > start.yaw, isTrue);
      await tester.tap(find.byTooltip('Look up'));
      await tester.pump();
      expect(c.view.pitch > start.pitch, isTrue);
      final fov = c.view.fov;
      await tester.tap(find.byTooltip('Zoom in'));
      await tester.pump();
      expect(c.view.fov < fov, isTrue);
      await tester.tap(find.byTooltip('Reset the view'));
      await tester.pump();
      expect(c.view, start);
    });

    testWidgets('IMG-001 dragging turns the camera the other way', (
      tester,
    ) async {
      await open(tester);
      final c = controllerOf(tester);
      final start = c.view;
      await tester.dragFrom(const Offset(200, 300), const Offset(100, 0));
      await tester.pump();
      expect(c.view.yaw < start.yaw, isTrue);
    });

    testWidgets('IMG-001 a flick coasts, and with reduced motion it does not', (
      tester,
    ) async {
      await open(tester);
      var c = controllerOf(tester);
      await tester.fling(
        find.byType(PanoramaView),
        const Offset(-200, 0),
        1500,
      );
      final after = c.view.yaw;
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(c.view.yaw > after, isTrue, reason: 'it keeps going');
      await tester.pumpAndSettle(const Duration(seconds: 3));

      await tester.pageBack();
      await tester.pumpAndSettle();
      await open(tester, reduceMotion: true);
      c = controllerOf(tester);
      await tester.fling(
        find.byType(PanoramaView),
        const Offset(-200, 0),
        1500,
      );
      final stopped = c.view.yaw;
      await tester.pump(const Duration(milliseconds: 500));
      expect(c.view.yaw, stopped);
    });

    testWidgets('IMG-001 the keyboard moves around too', (tester) async {
      await open(tester);
      final c = controllerOf(tester);
      await tester.tap(find.byType(PanoramaView));
      await tester.pump();
      final start = c.view;
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      expect(c.view.yaw > start.yaw, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      expect(c.view.pitch < start.pitch, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.equal);
      expect(c.view.fov < start.fov, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.minus);
      await tester.sendKeyEvent(LogicalKeyboardKey.digit0);
      expect(c.view, start);
    });

    testWidgets(
      'IMG-001 a screen reader hears what it is and which way it faces',
      (tester) async {
        final handle = tester.ensureSemantics();
        await open(tester);
        expect(
          find.bySemanticsLabel(
            '360° photo. Drag to look around, pinch to zoom.',
          ),
          findsOneWidget,
        );
        final node = tester.getSemantics(
          find.bySemanticsLabel(
            '360° photo. Drag to look around, pinch to zoom.',
          ),
        );
        expect(node.value, startsWith('Facing '));
        final c = controllerOf(tester);
        final start = c.view;
        // The screen reader's own actions move the view as the buttons do.
        tester.semantics.performAction(
          find.semantics.byLabel(
            '360° photo. Drag to look around, pinch to zoom.',
          ),
          SemanticsAction.customAction,
          args: CustomSemanticsAction.getIdentifier(
            const CustomSemanticsAction(label: 'Look right'),
          ),
        );
        await tester.pump();
        expect(c.view.yaw > start.yaw, isTrue);
        handle.dispose();
      },
    );

    testWidgets('IMG-001 the buttons are at least 48 points', (tester) async {
      await open(tester);
      for (final tip in ['Look left', 'Zoom in', 'Reset the view']) {
        final size = tester.getSize(find.byTooltip(tip));
        expect(size.width >= 48 && size.height >= 48, isTrue, reason: tip);
      }
    });

    testWidgets('IMG-001 a photo that cannot be read says so', (tester) async {
      await open(tester, load: () => Future.error(StateError('gone')));
      expect(find.text("This 360° photo can't be opened."), findsOneWidget);
      expect(find.byType(PanoramaView), findsNothing);
    });

    testWidgets('IMG-001 a cropped panorama stays inside its window', (
      tester,
    ) async {
      await open(
        tester,
        meta: const PanoramaMeta(
          projection: 'equirectangular',
          fullWidth: 8000,
          fullHeight: 4000,
          croppedWidth: 2000,
          croppedHeight: 800,
          croppedLeft: 3000,
          croppedTop: 1600,
        ),
      );
      final c = controllerOf(tester);
      for (var i = 0; i < 30; i++) {
        await tester.tap(find.byTooltip('Look right'));
        await tester.tap(find.byTooltip('Look up'));
      }
      await tester.pump();
      final g = c.geometry;
      final v = c.view;
      expect(v.yaw <= g.lonMax, isTrue);
      expect(v.pitch <= g.latMax, isTrue);
      expect(v, c.camera.clamp(v));
    });
  });

  group('IMG-001 moving the phone to look around', () {
    testWidgets('IMG-001 where the phone has sensors the camera follows them', (
      tester,
    ) async {
      final motion = _Motion();
      addTearDown(motion.controller.close);
      await open(tester, motion: motion);
      expect(find.byTooltip('Stop following the phone'), findsOneWidget);
      expect(motion.controller.hasListener, isTrue);
      final c = controllerOf(tester);
      motion.controller.add(const PanoAttitude(yaw: 0, pitch: 0));
      await tester.pump();
      final start = c.view;
      for (var i = 0; i < 30; i++) {
        motion.controller.add(const PanoAttitude(yaw: 0.6, pitch: 0.1));
        await tester.pump();
      }
      expect(c.view.yaw > start.yaw + 0.3, isTrue);
    });

    testWidgets(
      'IMG-001 with reduced motion the phone is not followed to begin with',
      (tester) async {
        final motion = _Motion();
        addTearDown(motion.controller.close);
        await open(tester, motion: motion, reduceMotion: true);
        expect(motion.controller.hasListener, isFalse);
        expect(
          find.byTooltip('Look around by moving the phone'),
          findsOneWidget,
        );
        // It can still be asked for.
        await tester.tap(find.byTooltip('Look around by moving the phone'));
        await tester.pump();
        expect(motion.controller.hasListener, isTrue);
        await tester.tap(find.byTooltip('Stop following the phone'));
        await tester.pump();
        expect(motion.controller.hasListener, isFalse);
      },
    );

    testWidgets('IMG-001 the sensors are let go when the screen closes', (
      tester,
    ) async {
      final motion = _Motion();
      addTearDown(motion.controller.close);
      await open(tester, motion: motion);
      expect(motion.controller.hasListener, isTrue);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(motion.controller.hasListener, isFalse);
    });

    testWidgets('IMG-001 the sensors are let go while the app is away', (
      tester,
    ) async {
      final motion = _Motion();
      addTearDown(motion.controller.close);
      await open(tester, motion: motion);
      tester.binding
        ..handleAppLifecycleStateChanged(AppLifecycleState.inactive)
        ..handleAppLifecycleStateChanged(AppLifecycleState.hidden)
        ..handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      expect(motion.controller.hasListener, isFalse);
      tester.binding
        ..handleAppLifecycleStateChanged(AppLifecycleState.hidden)
        ..handleAppLifecycleStateChanged(AppLifecycleState.inactive)
        ..handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    });

    testWidgets(
      'IMG-001 a drag while following becomes the new starting point',
      (tester) async {
        final motion = _Motion();
        addTearDown(motion.controller.close);
        await open(tester, motion: motion);
        final c = controllerOf(tester);
        motion.controller.add(const PanoAttitude(yaw: 1, pitch: 0));
        await tester.pump();
        await tester.dragFrom(const Offset(200, 300), const Offset(100, 0));
        await tester.pump();
        final dragged = c.view.yaw;
        motion.controller.add(const PanoAttitude(yaw: 1, pitch: 0));
        await tester.pump();
        expect(c.view.yaw, closeTo(dragged, 0.05));
      },
    );
  });
}
