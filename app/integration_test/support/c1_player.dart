import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:mediahro/app/app.dart';
import 'package:mediahro/app/router.dart';
import 'package:mediahro/engine/engine_pool.dart';
import 'package:mediahro/features/settings/settings_providers.dart';
import 'package:mediahro/features/settings/settings_store.dart';
import 'package:mediahro/features/video/player/play_request.dart';
import 'package:mediahro/features/video/player/video_memory.dart';
import 'package:mediahro/features/video/player/video_player_screen.dart';
import 'package:mediahro/features/video/video_open.dart';
import 'package:mediahro/features/video/video_settings.dart';
import 'package:mediahro/platform/platform_facades.dart';
import 'package:mediahro_design/mediahro_design.dart';
import 'package:mediahro_engine/mediahro_engine.dart';

import 'c1_engine.dart';
import 'c1_platform.dart';

// Lane C1's player acceptance suite. The widget tests run it on the CI
// host; integration_test/c1_video_player_test.dart runs it inside the app
// on Android, iOS, macOS and Windows.

const _tracks = [
  Track(
    id: 1,
    type: TrackType.video,
    codec: 'hevc',
    width: 3840,
    height: 2160,
    fps: 23.976,
  ),
  Track(
    id: 1,
    type: TrackType.audio,
    codec: 'aac',
    channels: 2,
    language: 'eng',
    isDefault: true,
  ),
  Track(
    id: 2,
    type: TrackType.audio,
    codec: 'ac3',
    channels: 6,
    language: 'ger',
  ),
  Track(id: 1, type: TrackType.subtitle, codec: 'subrip', language: 'en'),
  Track(id: 2, type: TrackType.subtitle, codec: 'ass', language: 'ja'),
];

final _request = PlayRequest(
  source: UriSource(Uri.parse('file:///v/film.mkv')),
  title: 'Film',
  memoryKey: 'film',
  chapters: const [
    Chapter(start: Duration.zero, title: 'Opening'),
    Chapter(start: Duration(minutes: 30), title: 'Middle'),
  ],
);

/// Opens the player for [_request] in the real app shell.
Future<(RecordingEngine, SettingsStore)> pumpPlayer(
  WidgetTester tester, {
  Size size = const Size(800, 400),
  List<Override> overrides = const [],
}) async {
  tester.view
    ..physicalSize = size * tester.view.devicePixelRatio
    ..devicePixelRatio = tester.view.devicePixelRatio;
  addTearDown(tester.view.resetPhysicalSize);
  final engine = RecordingEngine(tracks: _tracks);
  final store = (await tester.runAsync(
    () => SettingsStore.open(MemorySettingsPersistence(), null),
  ))!;
  final memory = (await tester.runAsync(
    () => VideoMemory.open(MemoryVideoMemoryPersistence()),
  ))!;
  final router = buildRouter(fullScreenRoutes: videoRoutes);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        settingsStoreProvider.overrideWithValue(store),
        playbackEngineFactoryProvider.overrideWithValue((_) => engine),
        videoMemoryProvider.overrideWith((ref) async => memory),
        appRoutesProvider.overrideWithValue(videoRoutes),
        ...overrides,
      ],
      child: MediahroApp(router: router),
    ),
  );
  await tester.pumpAndSettle();
  unawaited(router.push(VideoRoutes.play, extra: _request));
  await tester.pumpAndSettle();
  return (engine, store);
}

Finder iconButton(String label) =>
    find.byWidgetPredicate((w) => w is KIconButton && w.label == label);

Future<void> doubleTapAt(WidgetTester tester, Offset at) async {
  await tester.tapAt(at);
  await tester.pump(const Duration(milliseconds: 60));
  await tester.tapAt(at);
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump();
}

/// [testWidgets] that unmounts the player and lets its timers (chrome
/// auto-hide, coalesced memory writes) run out before the test ends.
void playerTest(
  String description,
  WidgetTesterCallback body, {
  TestVariant<Object?> variant = const DefaultTestVariant(),
}) => testWidgets(description, (tester) async {
  await body(tester);
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 5));
}, variant: variant);

/// The player acceptance tests (VID-060…065, VID-072). [gestures] runs
/// the touch-gesture tests (VID-060, A I only), under [touchVariant].
void videoPlayerSuite({
  required bool gestures,
  TestVariant<Object?> touchVariant = const DefaultTestVariant(),
}) {
  playerTest('VID-061 seek bar with chapters; precise seek when paused', (
    tester,
  ) async {
    final (engine, _) = await pumpPlayer(tester);
    expect(find.bySemanticsLabel('Seek'), findsOneWidget);
    expect(engine.opens.single!.chapters, hasLength(2));
    await engine.pause();
    await tester.pumpAndSettle();
    final bar = tester.getRect(find.bySemanticsLabel('Seek'));
    await tester.tapAt(bar.center);
    await tester.pumpAndSettle();
    expect(engine.seeks.last.$2, SeekMode.exact);
    expect(
      engine.seeks.last.$1.inMinutes,
      inInclusiveRange(40, 50),
      reason: 'middle of a 90 min item',
    );
  });

  if (gestures) {
    playerTest('VID-060 double-tap sides skip, centre plays/pauses', (
      tester,
    ) async {
      final (engine, _) = await pumpPlayer(tester);
      await engine.seek(const Duration(minutes: 5));
      await tester.pump();
      engine.seeks.clear();
      await doubleTapAt(tester, const Offset(700, 200));
      expect(engine.seeks.single.$1, const Duration(minutes: 5, seconds: 10));
      await doubleTapAt(tester, const Offset(100, 200));
      expect(engine.seeks.last.$1, const Duration(minutes: 5));
      await doubleTapAt(tester, const Offset(400, 200));
      expect(engine.current.status, PlaybackStatus.paused);
      await tester.pumpAndSettle();
    }, variant: touchVariant);

    playerTest('VID-060 double-tap step is configurable (5–60 s)', (
      tester,
    ) async {
      final (engine, store) = await pumpPlayer(tester);
      store.set(VideoSettings.doubleTapSeconds, 30);
      await tester.pump();
      await doubleTapAt(tester, const Offset(700, 200));
      expect(engine.seeks.last.$1, const Duration(seconds: 30));
      await tester.pumpAndSettle();
    }, variant: touchVariant);

    playerTest(
      'VID-060 horizontal swipe seeks; vertical right swipe sets volume',
      (tester) async {
        final (engine, _) = await pumpPlayer(tester);
        await tester.dragFrom(const Offset(200, 200), const Offset(300, 0));
        await tester.pumpAndSettle();
        expect(engine.seeks.last.$1, greaterThan(Duration.zero));
        await tester.dragFrom(const Offset(700, 300), const Offset(0, -150));
        await tester.pumpAndSettle();
        expect(engine.volumes, isNotEmpty);
      },
      variant: touchVariant,
    );

    playerTest('VID-060 long-press plays at 2x while held, then restores', (
      tester,
    ) async {
      final (engine, _) = await pumpPlayer(tester);
      final g = await tester.startGesture(const Offset(400, 200));
      await tester.pump(const Duration(milliseconds: 700));
      expect(engine.rates.last, 2.0);
      await g.up();
      await tester.pumpAndSettle();
      expect(engine.rates.last, 1.0);
    }, variant: touchVariant);

    playerTest('VID-060 gestures can be turned off; touch lock ignores them', (
      tester,
    ) async {
      final (engine, store) = await pumpPlayer(tester);
      store.set(VideoSettings.gestureDoubleTap, false);
      await tester.pump();
      engine.seeks.clear();
      await doubleTapAt(tester, const Offset(700, 200));
      expect(engine.seeks, isEmpty);
      store.set(VideoSettings.gestureDoubleTap, true);
      await tester.pumpAndSettle();
      await tester.tap(iconButton('Lock touch controls'));
      await tester.pumpAndSettle();
      await tester.dragFrom(const Offset(200, 200), const Offset(300, 0));
      await doubleTapAt(tester, const Offset(700, 200));
      await tester.pumpAndSettle();
      expect(engine.seeks, isEmpty);
    }, variant: touchVariant);
  }

  playerTest('VID-062 speed sheet presets', (tester) async {
    final (engine, _) = await pumpPlayer(tester);
    await tester.tap(find.bySemanticsLabel('Speed: 1×'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('1.5×'));
    await tester.pumpAndSettle();
    expect(engine.rates.last, 1.5);
  });

  playerTest('VID-065 audio chooser shows language, codec and channels', (
    tester,
  ) async {
    final (engine, _) = await pumpPlayer(tester);
    await tester.tap(find.text('Audio'));
    await tester.pumpAndSettle();
    expect(find.text('English'), findsOneWidget);
    expect(find.text('Deutsch'), findsOneWidget);
    expect(find.textContaining('AC3 · 5.1'), findsOneWidget);
    await tester.tap(find.text('Deutsch'));
    await tester.pumpAndSettle();
    expect(engine.selections.last, (TrackType.audio, 2, SubtitleSlot.primary));
  });

  playerTest('VID-065 subtitle chooser selects a track or off', (tester) async {
    final (engine, _) = await pumpPlayer(tester);
    await tester.tap(find.text('Subtitles'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('日本語'));
    await tester.pumpAndSettle();
    expect(engine.selections.last.$2, 2);
    await tester.tap(find.text('Off'));
    await tester.pumpAndSettle();
    expect(engine.selections.last.$2, isNull);
  });

  playerTest('VID-072 info overlay shows codec, resolution and frame rate', (
    tester,
  ) async {
    await pumpPlayer(tester);
    await tester.tap(iconButton('Playback information'));
    await tester.pumpAndSettle();
    expect(find.text('hevc'), findsOneWidget);
    expect(find.text('3840 × 2160'), findsOneWidget);
    expect(find.text('23.976 fps'), findsOneWidget);
    expect(find.text('SDR'), findsOneWidget);
  });

  playerTest('VID-061 VID-063 keyboard: L seeks, B sets A-B, . steps', (
    tester,
  ) async {
    final (engine, _) = await pumpPlayer(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyL);
    await tester.pumpAndSettle();
    expect(engine.seeks.last.$1, const Duration(seconds: 10));
    await tester.sendKeyEvent(LogicalKeyboardKey.keyB);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyL);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.keyB);
    await tester.pumpAndSettle();
    expect(engine.fake.abLoop.$1, const Duration(seconds: 10));
    expect(engine.fake.abLoop.$2, const Duration(seconds: 20));
    await tester.sendKeyEvent(LogicalKeyboardKey.period);
    await tester.pumpAndSettle();
    expect(engine.calls, contains('frameStep'));
    await tester.sendKeyEvent(LogicalKeyboardKey.bracketRight);
    await tester.sendKeyEvent(LogicalKeyboardKey.bracketRight);
    await tester.pumpAndSettle();
    expect(engine.rates.last, 1.2);
  });

  playerTest('VID-064 back leaves the player and saves the position', (
    tester,
  ) async {
    final (engine, _) = await pumpPlayer(tester);
    await engine.seek(const Duration(minutes: 12));
    await tester.pump();
    await tester.tap(iconButton('Back'));
    await tester.pumpAndSettle();
    expect(find.byType(VideoPlayerScreen), findsNothing);
    expect(engine.calls, contains('stop'));
  });

  playerTest('VID-067 the PiP button enters picture-in-picture; the window '
      'shows only the video', (tester) async {
    final pip = FakePip();
    await pumpPlayer(tester, overrides: [pipProvider.overrideWithValue(pip)]);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(iconButton('Picture in picture'));
    await tester.pumpAndSettle();
    expect(pip.entered.single, closeTo(16 / 9, 0.001));
    expect(find.byType(KPlayerChrome), findsNothing);
    pip.setActive(active: false);
    await tester.pumpAndSettle();
    expect(find.byType(KPlayerChrome), findsOneWidget);
  });

  playerTest('VID-068 sound only and background play from the More sheet', (
    tester,
  ) async {
    final (engine, _) = await pumpPlayer(tester);
    await tester.tap(iconButton('More'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sound only'));
    await tester.pumpAndSettle();
    expect(engine.selections.last, (
      TrackType.video,
      null,
      SubtitleSlot.primary,
    ));
    await tester.tap(find.text('Keep playing in the background'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<SwitchListTile>(
            find.widgetWithText(
              SwitchListTile,
              'Keep playing in the background',
            ),
          )
          .value,
      isTrue,
    );
  });

  playerTest('VID-070 the screen stays on while playing; leaving restores '
      'brightness and rotation', (tester) async {
    final display = FakeDisplay();
    await pumpPlayer(
      tester,
      overrides: [displayProvider.overrideWithValue(display)],
    );
    expect(display.keepOn.last, isTrue);
    expect(display.locks.last, OrientationLock.landscape);
    await tester.tap(iconButton('Back'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 1));
    expect(display.keepOn.last, isFalse);
    expect(display.brightness.last, isNull);
    expect(display.locks.last, OrientationLock.auto);
  });
}
