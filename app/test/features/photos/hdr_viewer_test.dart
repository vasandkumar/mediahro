import 'package:flutter/material.dart' hide ImageInfo;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediahro/features/photos/timeline/timeline_model.dart';
import 'package:mediahro/features/photos/viewer/hdr_surface.dart';
import 'package:mediahro_design/mediahro_design.dart';

import 'photos_harness.dart';

final class _Opener implements HdrOpener {
  _Opener({this.display = true, this.refuse = false});

  final bool display;
  final bool refuse;
  final List<int> opened = [];
  final List<int> closed = [];

  @override
  Future<bool> available() async => display;

  @override
  Future<HdrHandle?> open(PhotoEntry entry) async {
    if (refuse) return null;
    opened.add(entry.id);
    return HdrHandle(
      viewType: 'test/hdr',
      uri: Uri.parse('file:///x/${entry.name}'),
      onClose: () async => closed.add(entry.id),
    );
  }
}

void main() {
  const surface = ValueKey('hdr-surface');

  Future<(PhotosHarness, _Opener)> open(
    WidgetTester tester, {
    _Opener? opener,
    Set<int> hdr = const {0, 1},
  }) async {
    final o = opener ?? _Opener();
    final h = await PhotosHarness.create(tester);
    await h.pump(
      tester,
      entries: fakeEntries(days: 1, hdr: hdr),
      extra: [
        hdrOpenerProvider.overrideWithValue(o),
        hdrPlatformViewProvider.overrideWithValue(
          (context, handle) =>
              SizedBox.expand(key: surface, child: Text(handle.viewType)),
        ),
      ],
    );
    await tester.tap(find.byType(KGridTile).first);
    await tester.pumpAndSettle();
    return (h, o);
  }

  testWidgets('IMG-002 an HDR photo at rest is shown by the system HDR view', (
    tester,
  ) async {
    final (_, o) = await open(tester);
    expect(find.byKey(surface), findsOneWidget);
    expect(o.opened, [0]);
  });

  testWidgets('IMG-002 an ordinary photo is not covered', (tester) async {
    final (_, o) = await open(tester, hdr: const {3});
    expect(find.byKey(surface), findsNothing);
    expect(find.byTooltip('Show without HDR'), findsNothing);
    expect(o.opened, isEmpty);
  });

  testWidgets('IMG-002 on an SDR display nothing changes', (tester) async {
    final (_, o) = await open(tester, opener: _Opener(display: false));
    expect(find.byKey(surface), findsNothing);
    expect(find.byTooltip('Show without HDR'), findsNothing);
    expect(o.opened, isEmpty);
  });

  testWidgets('IMG-002 the HDR toggle switches between HDR and tone-mapped', (
    tester,
  ) async {
    final (_, o) = await open(tester);
    await tester.tap(find.byTooltip('Show without HDR'));
    await tester.pumpAndSettle();
    expect(find.byKey(surface), findsNothing);
    expect(o.closed, [0]);
    await tester.tap(find.byTooltip('Show in HDR'));
    await tester.pumpAndSettle();
    expect(find.byKey(surface), findsOneWidget);
  });

  testWidgets('IMG-002 zooming in falls back to the zoomable picture', (
    tester,
  ) async {
    await open(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.equal);
    await tester.pumpAndSettle();
    expect(find.byKey(surface), findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.digit0);
    await tester.pumpAndSettle();
    expect(find.byKey(surface), findsOneWidget);
  });

  testWidgets('IMG-002 turning or filling the photo hides the HDR view', (
    tester,
  ) async {
    await open(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyR);
    await tester.pumpAndSettle();
    expect(find.byKey(surface), findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyR);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyR);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyR);
    await tester.pumpAndSettle();
    expect(find.byKey(surface), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
    await tester.pumpAndSettle();
    expect(find.byKey(surface), findsNothing);
  });

  testWidgets('IMG-002 the HDR view follows the photo when swiping', (
    tester,
  ) async {
    final (_, o) = await open(tester);
    await tester.drag(find.byType(PageView), const Offset(-380, 0));
    await tester.pumpAndSettle();
    expect(o.opened, [0, 1]);
    expect(o.closed, contains(0));
    expect(find.byKey(surface), findsOneWidget);
    await tester.drag(find.byType(PageView), const Offset(-380, 0));
    await tester.pumpAndSettle();
    // The third photo is not HDR.
    expect(find.byKey(surface), findsNothing);
  });

  testWidgets(
    'IMG-002 a view that cannot be opened leaves the normal picture',
    (tester) async {
      await open(tester, opener: _Opener(refuse: true));
      expect(find.byKey(surface), findsNothing);
      expect(find.byType(RawImage), findsWidgets);
    },
  );
}
