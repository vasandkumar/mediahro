import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediahro/app/app.dart';
import 'package:mediahro/app/router.dart';
import 'package:mediahro/engine/engine_pool.dart';
import 'package:mediahro/features/photos/photos_providers.dart';
import 'package:mediahro/features/photos/timeline/timeline_model.dart';
import 'package:mediahro/features/photos/viewer/photo_clips.dart';
import 'package:mediahro/features/photos/viewer/photo_viewer.dart';
import 'package:mediahro/features/settings/settings_providers.dart';
import 'package:mediahro_design/mediahro_design.dart';
import 'package:mediahro_engine/mediahro_engine.dart';
import 'package:mediahro_engine/testing.dart';
import 'package:mediahro_ffi/mediahro_ffi.dart';

import '../../helpers.dart';
import 'photos_harness.dart';

/// A clip that notes when it is closed.
final class _Clip implements VirtualFile {
  bool closed = false;

  @override
  Uri get uri => Uri.parse('file:///clip.mp4');

  @override
  Future<int?> length() async => 10;

  @override
  Future<Uint8List> read(int offset, int length) async => Uint8List(0);

  @override
  bool get isSeekable => true;

  @override
  Future<void> close() async => closed = true;
}

final class _Clips implements PhotoClips {
  _Clips({this.missing = false});

  final bool missing;
  final List<_Clip> made = [];
  final List<int> asked = [];

  @override
  Future<PhotoClip?> open(PhotoEntry entry) async {
    asked.add(entry.id);
    if (missing) return null;
    final c = _Clip();
    made.add(c);
    return PhotoClip(c, motion: entry.motionPhoto);
  }
}

void main() {
  late FakePlaybackEngine engine;
  late _Clips clips;

  Future<void> open(
    WidgetTester tester, {
    Set<int> live = const {0},
    Set<int> motion = const {},
    bool missing = false,
  }) async {
    engine = FakePlaybackEngine(mediaDuration: const Duration(seconds: 3));
    clips = _Clips(missing: missing);
    final h = await PhotosHarness.create(tester);
    final entries = fakeEntries(days: 1, live: live, motion: motion);
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
          photoClipsProvider.overrideWithValue(clips),
          playbackEngineFactoryProvider.overrideWithValue((role) => engine),
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
  }

  testWidgets('IMG-001 a Live Photo and a Motion Photo offer to play', (
    tester,
  ) async {
    await open(tester, live: {0}, motion: {1});
    expect(find.byTooltip('Play Live Photo'), findsOneWidget);
    expect(find.byTooltip('Play Motion Photo'), findsNothing);
    await tester.drag(find.byType(PageView), const Offset(-380, 0));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Play Motion Photo'), findsOneWidget);
    await tester.drag(find.byType(PageView), const Offset(-380, 0));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Play Live Photo'), findsNothing);
    expect(find.byTooltip('Play Motion Photo'), findsNothing);
  });

  testWidgets('IMG-001 playing opens the clip in the player until it ends', (
    tester,
  ) async {
    await open(tester);
    await tester.tap(find.byTooltip('Play Live Photo'));
    await tester.pump();
    await tester.pump();
    await tester.pump();
    expect(find.byTooltip('Stop playing'), findsOneWidget);
    final source = engine.openedSource;
    expect(source, isA<VirtualFileSource>());
    expect((source! as VirtualFileSource).file, same(clips.made.single));
    expect(find.byType(Texture), findsOneWidget);
    engine.advance(const Duration(seconds: 5));
    await tester.pump();
    await tester.pumpAndSettle();
    expect(find.byTooltip('Play Live Photo'), findsOneWidget);
    expect(find.byType(Texture), findsNothing);
    expect(clips.made.single.closed, isTrue);
    expect(engine.calls, contains('stop'));
  });

  testWidgets('IMG-001 the stop button ends it early and closes the clip', (
    tester,
  ) async {
    await open(tester);
    await tester.tap(find.byTooltip('Play Live Photo'));
    await tester.pump();
    await tester.pump();
    await tester.tap(find.byTooltip('Stop playing'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Play Live Photo'), findsOneWidget);
    expect(clips.made.single.closed, isTrue);
    expect(engine.calls.last, 'stop');
  });

  testWidgets(
    'IMG-001 a clip that cannot be found just goes back to the still',
    (tester) async {
      await open(tester, missing: true);
      await tester.tap(find.byTooltip('Play Live Photo'));
      await tester.pumpAndSettle();
      expect(clips.asked, [0]);
      expect(find.byTooltip('Play Live Photo'), findsOneWidget);
      expect(engine.openedSource, isNull);
    },
  );

  testWidgets('IMG-001 swiping to another photo stops the clip', (
    tester,
  ) async {
    await open(tester);
    await tester.tap(find.byTooltip('Play Live Photo'));
    await tester.pump();
    await tester.pump();
    await tester.drag(find.byType(PageView), const Offset(-380, 0));
    await tester.pumpAndSettle();
    expect(clips.made.single.closed, isTrue);
    await tester.drag(find.byType(PageView), const Offset(380, 0));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Play Live Photo'), findsOneWidget);
  });
}
