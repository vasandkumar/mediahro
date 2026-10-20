import 'package:flutter_test/flutter_test.dart';
import 'package:mediahro/features/settings/settings_store.dart';
import 'package:mediahro/features/video/player/play_request.dart';
import 'package:mediahro/features/video/player/sleep_timer.dart';
import 'package:mediahro/features/video/player/video_memory.dart';
import 'package:mediahro/features/video/player/video_player_controller.dart';
import 'package:mediahro/features/video/video_settings.dart';
import 'package:mediahro_engine/mediahro_engine.dart';

import '../../../integration_test/support/c1_engine.dart';
import '../../helpers.dart';

PlayRequest _req(String name, {List<PlayRequest> next = const []}) =>
    PlayRequest.uri(Uri.parse('file:///v/$name.mkv'), next: next);

/// Builds the controller inside the test so its timers run on fake time.
Future<(RecordingEngine, VideoPlayerController, VideoMemory, SettingsStore)>
_setUp(WidgetTester tester) async {
  final engine = RecordingEngine(mediaDuration: const Duration(minutes: 2));
  final memory = (await tester.runAsync(
    () => VideoMemory.open(MemoryVideoMemoryPersistence()),
  ))!;
  final settings = (await tester.runAsync(memoryStore))!;
  final c = VideoPlayerController(
    engine: engine,
    memory: memory,
    settings: settings,
  );
  addTearDown(() async {
    c.dispose();
    await engine.dispose();
  });
  return (engine, c, memory, settings);
}

PlaybackState _onDevice(PlaybackState s, String device) =>
    s.copyWith(audio: AudioOutputInfo(device: device));

void main() {
  group('VID-066 audio volume', () {
    testWidgets('VID-066 volume boosts to 300 % at most; mute toggles', (
      tester,
    ) async {
      final (engine, c, _, _) = await _setUp(tester);
      await c.open(_req('a'));
      await c.setVolume(5);
      expect(engine.volumes.last, 3.0);
      await c.setVolume(-1);
      expect(engine.volumes.last, 0.0);
      await c.toggleMute();
      await tester.pump();
      expect(c.state.muted, isTrue);
      await c.toggleMute();
      await tester.pump();
      expect(c.state.muted, isFalse);
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('VID-066 each output device keeps its own volume', (
      tester,
    ) async {
      final (engine, c, memory, _) = await _setUp(tester);
      await c.open(_req('a'));
      engine.emit(_onDevice(c.state, 'speaker'));
      await tester.pump();
      await c.setVolume(0.5);
      engine.emit(_onDevice(c.state, 'headphones'));
      await tester.pump();
      await c.setVolume(1.4);
      engine.emit(_onDevice(c.state, 'speaker'));
      await tester.pump();
      expect(engine.volumes.last, 0.5);
      engine.emit(_onDevice(c.state, 'headphones'));
      await tester.pump();
      expect(engine.volumes.last, 1.4);
      expect(memory.deviceVolume('speaker'), 0.5);
      await tester.pump(const Duration(seconds: 1));
    });
  });

  group('VID-069 sleep timer', () {
    testWidgets('VID-069 after a time: fades out, pauses, restores volume', (
      tester,
    ) async {
      final (engine, c, _, _) = await _setUp(tester);
      await c.open(_req('a'));
      final timer = SleepTimer(c)
        ..set(const SleepAfterTime(Duration(seconds: 40)));
      addTearDown(timer.dispose);
      await tester.pump(const Duration(seconds: 5));
      expect(timer.remaining, const Duration(seconds: 35));
      expect(engine.volumes, isEmpty, reason: 'no fade before the last 30 s');
      await tester.pump(const Duration(seconds: 20));
      expect(engine.volumes.last, lessThan(1.0));
      await tester.pump(const Duration(seconds: 16));
      expect(c.state.status, PlaybackStatus.paused);
      expect(engine.volumes.last, 1.0, reason: 'volume restored');
      expect(timer.active, isFalse);
    });

    testWidgets('VID-069 the countdown waits while paused', (tester) async {
      final (engine, c, _, _) = await _setUp(tester);
      await c.open(_req('a'));
      final timer = SleepTimer(c)
        ..set(const SleepAfterTime(Duration(minutes: 15)));
      addTearDown(timer.dispose);
      await engine.pause();
      await tester.pump(const Duration(minutes: 1));
      expect(timer.remaining, const Duration(minutes: 15));
      timer.set(const SleepOff());
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('VID-069 end of item stops there instead of playing next', (
      tester,
    ) async {
      final (engine, c, _, settings) = await _setUp(tester);
      settings.set(VideoSettings.nextCountdown, 0);
      await c.open(_req('a', next: [_req('b')]));
      final timer = SleepTimer(c)..set(const SleepAtEndOfItem());
      addTearDown(timer.dispose);
      engine.fake.advance(const Duration(seconds: 100));
      await tester.pump(const Duration(seconds: 1));
      expect(engine.volumes.last, lessThan(1.0), reason: 'fading');
      engine.fake.advance(const Duration(seconds: 30));
      await tester.pump(const Duration(seconds: 1));
      expect(c.state.status, PlaybackStatus.ended);
      expect(c.request!.title, 'a.mkv');
      expect(c.nextUp, isNull);
      expect(engine.volumes.last, 1.0);
      expect(timer.active, isFalse);
    });

    testWidgets('VID-069 end of queue plays on, then stops after the last', (
      tester,
    ) async {
      final (engine, c, _, settings) = await _setUp(tester);
      settings.set(VideoSettings.nextCountdown, 0);
      await c.open(_req('a', next: [_req('b')]));
      final timer = SleepTimer(c)..set(const SleepAtEndOfQueue());
      addTearDown(timer.dispose);
      expect(timer.remaining, isNull, reason: 'b is still queued');
      engine.fake.advance(const Duration(minutes: 3));
      await tester.pump(const Duration(seconds: 1));
      expect(c.request!.title, 'b.mkv');
      expect(timer.active, isTrue);
      engine.fake.advance(const Duration(minutes: 3));
      await tester.pump(const Duration(seconds: 1));
      expect(c.state.status, PlaybackStatus.ended);
      expect(timer.active, isFalse);
    });

    testWidgets('VID-069 turning it off cancels and restores', (tester) async {
      final (engine, c, _, _) = await _setUp(tester);
      await c.open(_req('a'));
      final timer = SleepTimer(c)
        ..set(const SleepAfterTime(Duration(seconds: 20)));
      addTearDown(timer.dispose);
      await tester.pump(const Duration(seconds: 5));
      expect(engine.volumes.last, lessThan(1.0));
      timer.set(const SleepOff());
      await tester.pump();
      expect(engine.volumes.last, 1.0);
      await tester.pump(const Duration(minutes: 1));
      expect(c.state.status, PlaybackStatus.playing);
    });
  });
}
