import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mediahro/platform/android/android_display.dart';
import 'package:mediahro/platform/platform_bindings.dart';
import 'package:mediahro/platform/platform_facades.dart';

/// Lane C4a: external-display presentations on an Android device (ADR-044
/// amendment 1). The phone has no second screen, so a debug-only hook
/// (`mediahro.test/vdisplay`) makes a virtual presentation display drawn into
/// an ImageReader; the test shows frames on it and reads the middle pixel back.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final android = Platform.isAndroid;

  const hook = BasicMessageChannel<Object?>(
    'mediahro.test/vdisplay',
    StandardMessageCodec(),
  );
  Future<String> createDisplay() async =>
      (await hook.send(['create']))! as String;
  Future<int?> pixel() async => (await hook.send(['pixel'])) as int?;

  Future<Uint8List> solid(WidgetTester tester, ui.Color color) async {
    final bytes = await tester.runAsync(() async {
      final rec = ui.PictureRecorder();
      ui.Canvas(rec).drawRect(
        const ui.Rect.fromLTWH(0, 0, 64, 36),
        ui.Paint()..color = color,
      );
      final image = await rec.endRecording().toImage(64, 36);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      return data!.buffer.asUint8List();
    });
    return bytes!;
  }

  /// The middle pixel as (r, g, b) once [test] holds, within [seconds].
  Future<(int, int, int)> pixelWhere(
    WidgetTester tester,
    bool Function(int r, int g, int b) test, {
    int seconds = 20,
  }) async {
    (int, int, int)? last;
    final end = DateTime.now().add(Duration(seconds: seconds));
    while (DateTime.now().isBefore(end)) {
      final p = await tester.runAsync(pixel);
      if (p != null) {
        last = ((p >> 16) & 0xff, (p >> 8) & 0xff, p & 0xff);
        if (test(last.$1, last.$2, last.$3)) return last;
      }
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 250)),
      );
    }
    fail('the display never showed the expected colour; last pixel: $last');
  }

  testWidgets('ADR-044 Android bindings provide the display facade', (
    tester,
  ) async {
    final c = ProviderContainer(overrides: platformOverrides());
    addTearDown(c.dispose);
    expect(c.read(displayProvider), isA<AndroidDisplay>());
  }, skip: !android);

  testWidgets('ADR-044 the built-in screen cannot present', (tester) async {
    expect(await AndroidDisplay().openPresentation('0'), isNull);
    expect(await AndroidDisplay().openPresentation('not-a-display'), isNull);
  }, skip: !android);

  testWidgets(
    'IMG-012 frames appear on the external display, a clear goes black, and removal closes it',
    (tester) async {
      final display = AndroidDisplay();
      final id = await tester.runAsync(createDisplay);
      addTearDown(() => hook.send(['release']));
      expect(id, isNotNull);
      final listed = await tester.runAsync(display.displays);
      expect(listed!.where((d) => d.id == id && d.isExternal), hasLength(1));

      final handle = await tester.runAsync(() => display.openPresentation(id!));
      expect(handle, isNotNull);
      expect(handle!.displayId, id);

      // Red, then green with a crossfade, then clear (black).
      final red = await solid(tester, const ui.Color(0xFFFF0000));
      final green = await solid(tester, const ui.Color(0xFF00FF00));
      await tester.runAsync(
        () => display.present(
          handle,
          PresentationFrame(image: red, fit: BoxFit.fill),
        ),
      );
      await pixelWhere(tester, (r, g, b) => r > 200 && g < 60 && b < 60);

      await tester.runAsync(
        () => display.present(
          handle,
          PresentationFrame(
            image: green,
            fit: BoxFit.fill,
            transition: PresentationTransition.crossfade,
            transitionDuration: const Duration(milliseconds: 300),
          ),
        ),
      );
      await pixelWhere(tester, (r, g, b) => g > 200 && r < 60 && b < 60);

      await tester.runAsync(
        () => display.present(handle, PresentationFrame.clear),
      );
      await pixelWhere(tester, (r, g, b) => r < 30 && g < 30 && b < 30);

      // The display goes away: the presentation closes by itself.
      await tester.runAsync(() => hook.send(['release']));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(seconds: 1)),
      );
      await tester.runAsync(
        () => display.present(handle, PresentationFrame(image: red)),
      );
      await tester.runAsync(() => display.closePresentation(handle));
      expect(
        await tester.runAsync(() => display.openPresentation(id!)),
        isNull,
      );
    },
    skip: !android,
  );

  testWidgets('IMG-012 a caption and a pan-and-zoom frame are accepted', (
    tester,
  ) async {
    final display = AndroidDisplay();
    final id = await tester.runAsync(createDisplay);
    addTearDown(() => hook.send(['release']));
    final handle = await tester.runAsync(() => display.openPresentation(id!));
    expect(handle, isNotNull);
    final blue = await solid(tester, const ui.Color(0xFF0000FF));
    await tester.runAsync(
      () => display.present(
        handle!,
        PresentationFrame(
          image: blue,
          fit: BoxFit.cover,
          caption: 'Test',
          motion: const PresentationMotion(
            from: ui.Rect.fromLTRB(0, 0, 1, 1),
            to: ui.Rect.fromLTRB(0.25, 0.25, 0.75, 0.75),
            duration: Duration(seconds: 4),
          ),
        ),
      ),
    );
    await pixelWhere(tester, (r, g, b) => b > 150 && r < 100 && g < 100);
    await tester.runAsync(() => display.closePresentation(handle!));
  }, skip: !android);
}
