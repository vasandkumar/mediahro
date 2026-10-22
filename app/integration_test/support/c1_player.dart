import 'dart:async';
import 'dart:convert';

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
import 'package:mediahro/features/video/player/video_render.dart';
import 'package:mediahro/features/video/subtitles/audio_sync.dart';
import 'package:mediahro/features/video/subtitles/subtitle_sources.dart';
import 'package:mediahro/features/video/subtitles/subtitle_style.dart';
import 'package:mediahro/features/video/video_open.dart';
import 'package:mediahro/features/video/video_settings.dart';
import 'package:mediahro/platform/platform_facades.dart';
import 'package:mediahro_design/mediahro_design.dart';
import 'package:mediahro_engine/mediahro_engine.dart';

import 'c1_audio.dart';
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
  SettingsStore? settings,
}) async {
  tester.view
    ..physicalSize = size * tester.view.devicePixelRatio
    ..devicePixelRatio = tester.view.devicePixelRatio;
  addTearDown(tester.view.resetPhysicalSize);
  final engine = RecordingEngine(tracks: _tracks);
  final store =
      settings ??
      (await tester.runAsync(
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

/// Scrolls [f] into view (sheets are taller than a landscape phone) and
/// taps it.
Future<void> tapVisible(WidgetTester tester, Finder f) async {
  await tester.ensureVisible(f);
  await tester.pumpAndSettle();
  await tester.tap(f);
}

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
    await tapVisible(tester, find.widgetWithText(RadioListTile<int>, 'Off'));
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
    await tapVisible(tester, find.text('Sound only'));
    await tester.pumpAndSettle();
    expect(engine.selections.last, (
      TrackType.video,
      null,
      SubtitleSlot.primary,
    ));
    await tapVisible(tester, find.text('Keep playing in the background'));
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

  playerTest('VID-070 the More sheet lets the player rotate with the phone', (
    tester,
  ) async {
    final display = FakeDisplay();
    final (_, store) = await pumpPlayer(
      tester,
      overrides: [displayProvider.overrideWithValue(display)],
    );
    expect(store.get(VideoSettings.orientation), VideoOrientation.followVideo);
    await tester.tap(iconButton('More'));
    await tester.pumpAndSettle();

    await tapVisible(tester, find.text('Rotate with the phone'));
    await tester.pumpAndSettle();

    expect(store.get(VideoSettings.orientation), VideoOrientation.auto);
    expect(display.locks.last, OrientationLock.auto);
    await tapVisible(tester, find.text('Rotate with the phone'));
    await tester.pumpAndSettle();
    expect(store.get(VideoSettings.orientation), VideoOrientation.followVideo);
    expect(display.locks.last, OrientationLock.landscape);
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

  playerTest('VID-066 the audio sheet sets volume up to 300 % and mutes', (
    tester,
  ) async {
    final (engine, _) = await pumpPlayer(tester);
    await tester.tap(find.text('Audio'));
    await tester.pumpAndSettle();
    expect(find.text('100 %'), findsWidgets);
    final slider = tester.widget<Slider>(find.byType(Slider));
    expect(slider.max, 3);
    slider.onChanged!(2.5);
    await tester.pumpAndSettle();
    expect(engine.volumes.last, 2.5);
    expect(find.text('250 %'), findsWidgets);
    await tester.tap(find.byTooltip('Mute'));
    await tester.pumpAndSettle();
    expect(engine.current.muted, isTrue);
  });

  playerTest('VID-069 sleep timer from the More sheet shows a countdown', (
    tester,
  ) async {
    await pumpPlayer(tester);
    await tester.tap(iconButton('More'));
    await tester.pumpAndSettle();
    await tapVisible(tester, find.text('Sleep timer'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('15 minutes'));
    await tester.pumpAndSettle();
    expect(find.text('Sleep timer'), findsNothing, reason: 'sheets closed');
    final chip = find.widgetWithText(KChip, 'Pauses in 15:00');
    expect(chip, findsOneWidget);
    await tester.tap(chip);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Off'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(KChip, 'Pauses in 15:00'), findsNothing);
  });

  playerTest('SUB-013 the subtitle sheet forces a character set', (
    tester,
  ) async {
    final (engine, _) = await pumpPlayer(tester);
    await tester.tap(find.text('Subtitles'));
    await tester.pumpAndSettle();
    expect(find.text('Detect automatically'), findsOneWidget);
    await tapVisible(tester, find.text('Character encoding'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Cyrillic (Windows-1251)'),
      100,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.text('Cyrillic (Windows-1251)'));
    await tester.pumpAndSettle();
    expect(engine.fake.subtitleCodepage, 'cp1251');
  });

  playerTest('SUB-012 a picked subtitle file is added and shown', (
    tester,
  ) async {
    final (engine, _) = await pumpPlayer(
      tester,
      overrides: [
        subtitleFilePickerProvider.overrideWithValue(
          () async => PickedSubtitle(
            'Extra.fr.srt',
            Uint8List.fromList(
              utf8.encode('1\n00:00:01,000 --> 00:00:02,000\nSalut\n'),
            ),
          ),
        ),
      ],
    );
    await tester.tap(find.text('Subtitles'));
    await tester.pumpAndSettle();
    await tapVisible(tester, find.text('Add a subtitle file'));
    // The file is written to the cache with real I/O: alternate real time
    // and frames until the track arrives.
    for (var i = 0; i < 20 && engine.externalTracks.isEmpty; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
    }
    await tester.pumpAndSettle();
    expect(engine.externalTracks.single.$2.pathSegments.last, 'Extra.fr.srt');
    expect(
      engine.current.subtitleTrackId,
      engine.current.tracks.lastWhere((t) => t.type == TrackType.subtitle).id,
    );
  });

  playerTest('SUB-014 changing a subtitle setting restyles at once', (
    tester,
  ) async {
    final (engine, store) = await pumpPlayer(tester);
    store.set(SubtitleSettings.size, SubSize.huge);
    await tester.pumpAndSettle();
    expect(engine.styles.last.$1.scale, 2);
    store.set(SubtitleSettings.background, SubBackground.box);
    await tester.pumpAndSettle();
    expect(
      engine.styles.last.$1.borderStyle,
      SubtitleBorderStyle.backgroundBox,
    );
  });

  playerTest('SUB-015 the subtitle speed converts frame rates', (tester) async {
    final (engine, _) = await pumpPlayer(tester);
    await tester.tap(find.text('Subtitles'));
    await tester.pumpAndSettle();
    await tapVisible(tester, find.text('Subtitle speed'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('From 23.976 to 25 fps'));
    await tester.pumpAndSettle();
    expect(engine.fake.subSpeed, closeTo(25 / 23.976, 1e-9));
  });

  playerTest('SUB-016 second subtitles: chosen in the sheet, drawn by the '
      'player', (tester) async {
    final (engine, _) = await pumpPlayer(tester);
    await tester.tap(find.text('Subtitles'));
    await tester.pumpAndSettle();
    await tapVisible(tester, find.text('Second subtitles'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('日本語'));
    await tester.pumpAndSettle();
    expect(engine.selections.last, (
      TrackType.subtitle,
      2,
      SubtitleSlot.secondary,
    ));
    engine.emit(engine.current.copyWith(secondarySubtitleText: 'こんにちは'));
    await tester.pumpAndSettle();
    expect(find.text('こんにちは'), findsOneWidget);
  });

  playerTest('SUB-030 Edit subtitles opens the editor on a subtitle file', (
    tester,
  ) async {
    await pumpPlayer(
      tester,
      overrides: [
        subtitleFilePickerProvider.overrideWithValue(
          () async => PickedSubtitle(
            'Edit.srt',
            Uint8List.fromList(
              utf8.encode('1\n00:00:01,000 --> 00:00:02,000\nTo edit\n'),
            ),
          ),
        ),
      ],
    );
    await tester.tap(find.text('Subtitles'));
    await tester.pumpAndSettle();
    await tapVisible(tester, find.text('Edit subtitles'));
    // File I/O and the parse isolate run in real time.
    for (var i = 0; i < 40 && find.text('To edit').evaluate().isEmpty; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
    }
    await tester.pumpAndSettle();
    expect(find.text('To edit'), findsOneWidget);
    expect(find.text('Shift all'), findsOneWidget);
  });

  /// Adds a picked English subtitle file through the Subtitles sheet and
  /// waits for the real file I/O.
  Future<RecordingEngine> withSubtitleFile(
    WidgetTester tester, {
    List<Override> overrides = const [],
    String srt = '1\n00:00:01,000 --> 00:00:02,000\nHello\n',
  }) async {
    final (engine, _) = await pumpPlayer(
      tester,
      overrides: [
        subtitleFilePickerProvider.overrideWithValue(
          () async => PickedSubtitle(
            'Film.en.srt',
            Uint8List.fromList(utf8.encode(srt)),
          ),
        ),
        ...overrides,
      ],
    );
    await tester.tap(find.text('Subtitles'));
    await tester.pumpAndSettle();
    await tapVisible(tester, find.text('Add a subtitle file'));
    for (var i = 0; i < 20 && engine.externalTracks.isEmpty; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
    }
    await tester.pumpAndSettle();
    return engine;
  }

  playerTest('SUB-040 read aloud is switched on in the Subtitles sheet', (
    tester,
  ) async {
    final speech = FakeSpeech();
    await withSubtitleFile(
      tester,
      overrides: [speechSynthesisProvider.overrideWithValue(speech)],
    );
    await tester.tap(find.text('Subtitles'));
    await tester.pumpAndSettle();
    await tapVisible(tester, find.text('Read subtitles aloud'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<SwitchListTile>(
            find.widgetWithText(SwitchListTile, 'Read subtitles aloud'),
          )
          .value,
      isTrue,
    );
  });

  playerTest('SUB-053 translate: target, consent to download, new track', (
    tester,
  ) async {
    final translation = FakeTranslation();
    final engine = await withSubtitleFile(
      tester,
      overrides: [translationProvider.overrideWithValue(translation)],
    );
    await tester.tap(find.text('Subtitles'));
    await tester.pumpAndSettle();
    await tapVisible(tester, find.text('Translate subtitles'));
    for (var i = 0; i < 20 && find.text('Deutsch').evaluate().isEmpty; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
    }
    await tester.tap(find.text('Deutsch'));
    await tester.pumpAndSettle();
    expect(find.text('Download a language pack?'), findsOneWidget);
    await tester.tap(find.text('Download'));
    for (var i = 0; i < 20 && engine.externalTracks.length < 2; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
    }
    await tester.pumpAndSettle();
    expect(translation.prepared, [('en', 'de')]);
    final added = engine.current.tracks.lastWhere(
      (t) => t.type == TrackType.subtitle,
    );
    expect(added.title, 'Deutsch (translated)');
    expect(added.language, 'de');
    expect(engine.current.subtitleTrackId, added.id);
  });

  playerTest('SUB-050 sync to the audio previews the fix with undo', (
    tester,
  ) async {
    const seconds = 60;
    final turns = speechTurns(seconds, seed: 5);
    final engine = await withSubtitleFile(
      tester,
      srt: turnsSrt(turns, shift: 1.8),
      overrides: [
        pcmSourceProvider.overrideWithValue(fakePcm(turns, seconds: seconds)),
      ],
    );
    await tester.tap(find.text('Subtitles'));
    await tester.pumpAndSettle();
    await tapVisible(tester, find.text('Sync to the audio'));
    for (var i = 0; i < 100 && engine.subDelays.isEmpty; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
    }
    await tester.pump();
    expect(engine.subDelays.last.$1.inMilliseconds, closeTo(-1800, 50));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.textContaining('Subtitles synced'), findsOneWidget);
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(engine.subDelays.last.$1, Duration.zero);
  });
  playerTest('VID-037 Picture sheet: rotate, mirror and aspect for this '
      'video; colour for every video', (tester) async {
    final (engine, store) = await pumpPlayer(tester);
    await tester.tap(iconButton('Picture'));
    await tester.pumpAndSettle();
    await tapVisible(tester, find.text('Rotate'));
    await tester.pumpAndSettle();
    expect(engine.filterChains.last.rotate, 90);
    expect(find.text('Rotated 90°'), findsOneWidget);
    await tapVisible(tester, find.text('Mirror'));
    await tester.pumpAndSettle();
    expect(engine.filterChains.last.flipHorizontal, isTrue);
    await tapVisible(tester, find.text('4:3'));
    await tester.pumpAndSettle();
    expect(engine.filterChains.last.aspectOverride, closeTo(4 / 3, 1e-9));
    store.set<double>(RenderSettings.brightness, 40);
    await tester.pumpAndSettle();
    expect(engine.filterChains.last.brightness, 40);
    expect(engine.filterChains.last.rotate, 90, reason: 'view is kept');
    await tapVisible(tester, find.text('Reset').last);
    await tester.pumpAndSettle();
    expect(store.get(RenderSettings.brightness), 0);
    expect(engine.filterChains.last.brightness, 0);
    await tapVisible(tester, find.text('Reset').first);
    await tester.pumpAndSettle();
    expect(engine.filterChains.last.rotate, 0);
    expect(engine.filterChains.last.aspectOverride, isNull);
  });

  playerTest('VID-038 Picture sheet: a shader from the folder is applied '
      'and restored for the next video', (tester) async {
    final shader = ShaderChoice('custom:sharp.glsl', 'sharp.glsl', [
      Uri.parse('file:///s/sharp.glsl'),
    ]);
    final folders = <String>[];
    final overrides = [
      shaderLibraryProvider.overrideWithValue((folder) async {
        folders.add(folder);
        return folder.isEmpty ? const <ShaderChoice>[] : [shader];
      }),
      storageProvider.overrideWithValue(
        FakeFolderPicker(
          FolderGrant(id: 'g', uri: Uri.parse('file:///s/'), displayName: 's'),
        ),
      ),
    ];
    final (engine, store) = await pumpPlayer(tester, overrides: overrides);
    await tester.tap(iconButton('Picture'));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Put .glsl shader files in a folder and choose it here to '
        'use them.',
      ),
      findsOneWidget,
    );
    await tapVisible(tester, find.text('Choose a shader folder'));
    await tester.pumpAndSettle();
    expect(store.get(RenderSettings.shaderFolder), 'file:///s/');
    await tapVisible(tester, find.text('sharp.glsl'));
    await tester.pumpAndSettle();
    expect(engine.shaderPresets.last, shader.preset);
    expect(store.get(RenderSettings.shaderPreset), 'custom:sharp.glsl');
    await tapVisible(tester, find.text('None'));
    await tester.pumpAndSettle();
    expect(engine.shaderPresets.last, ShaderPreset.none);
    store.set(RenderSettings.shaderPreset, 'custom:sharp.glsl');
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
    final (next, _) = await pumpPlayer(
      tester,
      overrides: overrides,
      settings: store,
    );
    for (var i = 0; i < 20 && next.shaderPresets.isEmpty; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    expect(next.shaderPresets.single, shader.preset);
  });

  playerTest('VID-038 built-in presets are listed by name and applied', (
    tester,
  ) async {
    final fsr = ShaderChoice('builtin:fsr', 'fsr', [
      Uri.parse('file:///data/shaders/FSR.glsl'),
    ], builtIn: true);
    final (engine, _) = await pumpPlayer(
      tester,
      overrides: [
        shaderLibraryProvider.overrideWithValue((_) async => [fsr]),
      ],
    );
    await tester.tap(iconButton('Picture'));
    await tester.pumpAndSettle();
    await tapVisible(tester, find.text('FSR: sharp upscaling for any video'));
    await tester.pumpAndSettle();
    expect(engine.shaderPresets.last, fsr.preset);
  });

  playerTest('VID-038 a folder without a file path is refused', (tester) async {
    final (_, store) = await pumpPlayer(
      tester,
      overrides: [
        storageProvider.overrideWithValue(
          FakeFolderPicker(
            FolderGrant(
              id: 'g',
              uri: Uri.parse('content://com.android.externalstorage/tree/x'),
              displayName: 'x',
            ),
          ),
        ),
      ],
    );
    await tester.tap(iconButton('Picture'));
    await tester.pumpAndSettle();
    await tapVisible(tester, find.text('Choose a shader folder'));
    await tester.pumpAndSettle();
    expect(store.get(RenderSettings.shaderFolder), isEmpty);
    expect(
      find.text(
        "Shaders can only be read from a folder on this device's "
        'own storage.',
      ),
      findsOneWidget,
    );
  });

  playerTest('VID-037 stretch modes and pan', (tester) async {
    final (engine, _) = await pumpPlayer(tester);
    BoxFit fit() => tester
        .widget<FittedBox>(
          find.ancestor(
            of: find.byType(Texture),
            matching: find.byType(FittedBox),
          ),
        )
        .fit;
    expect(fit(), BoxFit.contain);
    await tester.tap(iconButton('Picture'));
    await tester.pumpAndSettle();
    expect(find.text('Left and right'), findsNothing);
    await tapVisible(tester, find.text('Stretch'));
    await tester.pumpAndSettle();
    expect(fit(), BoxFit.fill);
    await tapVisible(tester, find.text('Fill screen'));
    await tester.pumpAndSettle();
    expect(fit(), BoxFit.cover);
    final pan = find.ancestor(
      of: find.text('Left and right'),
      matching: find.byType(Row),
    );
    await tester.ensureVisible(pan);
    await tester.pumpAndSettle();
    final slider = tester.getRect(
      find.descendant(of: pan, matching: find.byType(Slider)),
    );
    await tester.tapAt(slider.centerRight - const Offset(8, 0));
    await tester.pumpAndSettle();
    expect(engine.filterChains.last.panX, greaterThan(0.3));
  });

  playerTest('VID-038 VID-039 a hot device pauses shaders and smooth motion', (
    tester,
  ) async {
    final power = FakePowerStatus();
    final shader = ShaderChoice('custom:sharp.glsl', 'sharp.glsl', [
      Uri.parse('file:///s/sharp.glsl'),
    ]);
    final (engine, store) = await pumpPlayer(
      tester,
      overrides: [
        powerStatusProvider.overrideWithValue(power),
        shaderLibraryProvider.overrideWithValue((_) async => [shader]),
      ],
    );
    await tester.tap(iconButton('Picture'));
    await tester.pumpAndSettle();
    await tapVisible(tester, find.text('sharp.glsl'));
    await tester.pumpAndSettle();
    expect(engine.shaderPresets.last, shader.preset);
    power.set(
      const PowerStatus(thermal: ThermalLevel.serious, batterySaver: false),
    );
    await tester.pumpAndSettle();
    expect(engine.shaderPresets.last, ShaderPreset.none);
    const cooling =
        'Shaders and smooth motion are paused while the device is hot or '
        'saving battery.';
    expect(find.text(cooling), findsWidgets);
    power.set(
      const PowerStatus(thermal: ThermalLevel.fair, batterySaver: false),
    );
    await tester.pumpAndSettle();
    expect(engine.shaderPresets.last, shader.preset);
    expect(store.get(RenderSettings.shaderPreset), 'custom:sharp.glsl');
  });

  if (gestures) {
    playerTest('VID-039 smooth motion on a phone asks about battery first', (
      tester,
    ) async {
      final (engine, store) = await pumpPlayer(tester);
      await tester.tap(iconButton('Picture'));
      await tester.pumpAndSettle();
      await tapVisible(tester, find.text('Smooth motion'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(store.get(RenderSettings.interpolation), isFalse);
      await tapVisible(tester, find.text('Smooth motion'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Turn on'));
      await tester.pumpAndSettle();
      expect(store.get(RenderSettings.interpolation), isTrue);
      expect(engine.filterChains.last.interpolation, isTrue);
    }, variant: touchVariant);
  } else {
    playerTest('VID-039 smooth motion on a computer switches on at once', (
      tester,
    ) async {
      final (engine, store) = await pumpPlayer(tester);
      await tester.tap(iconButton('Picture'));
      await tester.pumpAndSettle();
      await tapVisible(tester, find.text('Smooth motion'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(store.get(RenderSettings.interpolation), isTrue);
      expect(engine.filterChains.last.interpolation, isTrue);
    });
  }
}
