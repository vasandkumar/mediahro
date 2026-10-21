import 'dart:collection';
import 'dart:typed_data';

import 'package:flutter/material.dart' hide ImageInfo;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediahro/app/l10n/gen/app_localizations.dart';
import 'package:mediahro/features/photos/viewer/external_image_viewer.dart';
import 'package:mediahro/features/photos/viewer/viewer_image.dart';
import 'package:mediahro/features/photos/viewer/viewer_surface.dart';
import 'package:mediahro/images/image_pipeline.dart'
    show DecodedImage, ImageInfo;

Future<ViewerImage> _image() async {
  final pixels = Uint8List(64 * 48 * 4)..fillRange(0, 64 * 48 * 4, 120);
  final img = await uiImageFrom(
    DecodedImage(width: 64, height: 48, pixels: pixels),
  );
  return ViewerImage(
    base: img,
    fullSize: const Size(640, 480),
    info: const ImageInfo(width: 640, height: 480, format: 'jpeg'),
  );
}

void main() {
  final a = ExternalImage(Uri.parse('content://media/1'), 'a.jpg');
  final b = ExternalImage(Uri.parse('content://media/2'), 'b.png');

  /// Pumps the viewer on [images]; the loader hands out pictures prepared up
  /// front (dart:ui needs the real event loop) and records what it opened.
  Future<List<Uri>> pump(
    WidgetTester tester,
    List<ExternalImage> images, {
    bool failing = false,
    int index = 0,
  }) async {
    final opened = <Uri>[];
    final ready = Queue<ViewerImage>();
    await tester.runAsync(() async {
      for (var i = 0; i < images.length; i++) {
        ready.add(await _image());
      }
    });
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          externalImageLoaderProvider.overrideWithValue((uri) async {
            opened.add(uri);
            if (failing) throw StateError('gone');
            return ready.removeFirst();
          }),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: ExternalImageViewer(args: ExternalImageArgs(images, index)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return opened;
  }

  testWidgets('IMG-004 an external picture opens in the zoom surface', (
    tester,
  ) async {
    await pump(tester, [a]);
    expect(find.text('a.jpg'), findsOneWidget);
    expect(find.byType(ViewerSurface), findsOneWidget);
  });

  testWidgets('SYS-004 several pictures show a count and swipe', (
    tester,
  ) async {
    await pump(tester, [a, b]);
    expect(find.text('a.jpg (1/2)'), findsOneWidget);

    await tester.fling(find.byType(PageView), const Offset(-600, 0), 2000);
    await tester.pumpAndSettle();

    expect(find.text('b.png (2/2)'), findsOneWidget);
  });

  testWidgets('SYS-004 the set can start on a later picture', (tester) async {
    await pump(tester, [a, b], index: 1);
    expect(find.text('b.png (2/2)'), findsOneWidget);
  });

  testWidgets('IMG-004 a picture that cannot be read says so', (tester) async {
    await pump(tester, [a], failing: true);
    expect(find.textContaining('It may be corrupt'), findsOneWidget);
    expect(find.byType(ViewerSurface), findsNothing);
  });

  testWidgets('IMG-004 only the picture on screen is read', (tester) async {
    final opened = await pump(tester, [a, b]);
    expect(opened, [a.uri]);
  });
}
