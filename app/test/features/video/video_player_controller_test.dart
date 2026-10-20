import 'package:flutter_test/flutter_test.dart';
import 'package:mediahro/features/settings/settings_store.dart';
import 'package:mediahro/features/video/player/play_request.dart';
import 'package:mediahro/features/video/player/speed.dart';
import 'package:mediahro/features/video/player/video_memory.dart';
import 'package:mediahro/features/video/player/video_player_controller.dart';
import 'package:mediahro/features/video/video_settings.dart';
import 'package:mediahro_engine/mediahro_engine.dart';

import '../../../integration_test/support/c1_engine.dart';
import '../../helpers.dart';

void main() {
  late RecordingEngine engine;
  late VideoMemory memory;
  late SettingsStore settings;
  late VideoPlayerController c;
  var closed = 0;

  PlayRequest req(String name, {List<PlayRequest> next = const []}) =>
      PlayRequest.uri(Uri.parse('file:///v/$name.mkv'), next: next);

  Future<void> settle() => Future<void>.delayed(Duration.zero);

  setUp(() async {
    engine = RecordingEngine(mediaDuration: const Duration(minutes: 10));
    memory = await VideoMemory.open(MemoryVideoMemoryPersistence());
    settings = await memoryStore();
    closed = 0;
    c = VideoPlayerController(
      engine: engine,
      memory: memory,
      settings: settings,
      onClose: () => closed++,
    );
  });

  tearDown(() async {
    c.dispose();
    await engine.dispose();
  });

  group('VID-061 seek bar', () {
    test('VID-061 seeks are frame-accurate, playing or paused', () async {
      await c.open(req('a'));
      await settle();
      await c.seekTo(const Duration(minutes: 2));
      expect(engine.seeks.last.$2, SeekMode.exact);
      await engine.pause();
      await settle();
      await c.seekTo(const Duration(minutes: 3));
      expect(engine.seeks.last, (const Duration(minutes: 3), SeekMode.exact));
    });

    test('VID-061 seeks clamp to the item and jump to percentages', () async {
      await c.open(req('a'));
      await settle();
      await c.seekBy(const Duration(hours: 1));
      expect(engine.seeks.last.$1, const Duration(minutes: 10));
      await c.seekBy(-const Duration(hours: 2));
      expect(engine.seeks.last.$1, Duration.zero);
      await c.jumpToPercent(30);
      expect(engine.seeks.last.$1, const Duration(minutes: 3));
    });
  });

  group('VID-062 speed', () {
    test('VID-062 speed snaps to 0.05 steps within 0.25–4.0', () {
      expect(PlaybackSpeed.normalize(1.07), 1.05);
      expect(PlaybackSpeed.normalize(1.13), 1.15);
      expect(PlaybackSpeed.normalize(0.1), 0.25);
      expect(PlaybackSpeed.normalize(9), 4.0);
      expect(PlaybackSpeed.presets, containsAll(<double>[0.5, 1, 1.5, 2]));
    });

    test('VID-062 speed presets persist per item', () async {
      await c.open(req('a'));
      await c.setRate(1.5);
      await c.open(req('b'));
      await settle();
      expect(engine.rates.last, 1.5, reason: 'a was set');
      expect(c.state.rate, 1.0, reason: 'b starts at 1x per item');
      await c.open(req('a'));
      await settle();
      expect(engine.rates.last, 1.5);
      expect(c.state.rate, 1.5);
    });

    test('VID-062 global memory applies the last speed everywhere', () async {
      settings.set(VideoSettings.speedMemory, SpeedMemory.global);
      await c.open(req('a'));
      await c.setRate(1.25);
      await c.open(req('b'));
      await settle();
      expect(c.state.rate, 1.25);
    });

    test('VID-062 keyboard nudges by 0.1 and resets', () async {
      await c.open(req('a'));
      await settle();
      await c.nudgeRate(up: true);
      await settle();
      expect(c.state.rate, 1.1);
      await c.nudgeRate(up: false);
      await c.nudgeRate(up: false);
      await settle();
      expect(c.state.rate, 0.9);
      await c.resetRate();
      await settle();
      expect(c.state.rate, 1.0);
    });

    test('VID-062 memory survives a reload from disk', () async {
      final p = MemoryVideoMemoryPersistence();
      final m1 = await VideoMemory.open(p)
        ..updateItem('k', (m) => m.copyWith(rate: () => 1.75))
        ..globalRate = 1.75;
      await m1.flush();
      final m2 = await VideoMemory.open(p);
      expect(m2.item('k').rate, 1.75);
      expect(m2.globalRate, 1.75);
    });
  });

  group('VID-063 frame step, A-B loop, chapters, bookmarks', () {
    test('VID-063 frame step forward and back pauses on a frame', () async {
      await c.open(req('a'));
      await settle();
      await c.frameStep();
      await settle();
      expect(c.state.status, PlaybackStatus.paused);
      final p = c.state.position;
      await c.frameStep(backwards: true);
      await settle();
      expect(c.state.position, lessThan(p));
    });

    test('VID-063 A-B loop: set A, set B, count, clear', () async {
      await c.open(req('a'));
      await engine.seek(const Duration(seconds: 10));
      await settle();
      await c.markLoopPoint();
      expect(c.abA, const Duration(seconds: 10));
      expect(engine.fake.abLoop.$1, isNull, reason: 'loop starts with B');
      await engine.seek(const Duration(seconds: 20));
      await settle();
      await c.setLoopCount(3);
      await c.markLoopPoint();
      expect(engine.fake.abLoop, (
        const Duration(seconds: 10),
        const Duration(seconds: 20),
        3,
      ));
      await c.clearLoop();
      expect(engine.fake.abLoop, (null, null, null));
      expect(c.abA, isNull);
    });

    test('VID-063 chapters from the request; next/previous', () async {
      await c.open(
        PlayRequest(
          source: UriSource(Uri.parse('file:///v/c.mkv')),
          title: 'c',
          memoryKey: 'c',
          chapters: const [
            Chapter(start: Duration.zero, title: 'Intro'),
            Chapter(start: Duration(minutes: 2), title: 'Part 1'),
            Chapter(start: Duration(minutes: 5), title: 'Part 2'),
          ],
        ),
      );
      await settle();
      expect(engine.opens.last!.chapters, hasLength(3));
      await c.nextChapter();
      await settle();
      expect(c.state.position, const Duration(minutes: 2));
      await c.nextChapter();
      await settle();
      expect(c.currentChapter, 2);
      await c.previousChapter();
      await settle();
      expect(c.state.position, const Duration(minutes: 2));
    });

    test('VID-063 bookmarks with notes are kept per item, sorted', () async {
      await c.open(req('a'));
      await engine.seek(const Duration(minutes: 4));
      await settle();
      final b = c.addBookmark(note: 'Great shot')!;
      await engine.seek(const Duration(minutes: 1));
      await settle();
      c.addBookmark();
      expect(c.bookmarks.map((x) => x.position), [
        const Duration(minutes: 1),
        const Duration(minutes: 4),
      ]);
      c.editBookmark(b, 'Even better');
      expect(c.bookmarks.last.note, 'Even better');
      await c.open(req('b'));
      expect(c.bookmarks, isEmpty);
      await c.open(req('a'));
      expect(c.bookmarks, hasLength(2));
      c.removeBookmark(c.bookmarks.first);
      expect(c.bookmarks, hasLength(1));
    });
  });

  group('VID-064 resume and post-playback', () {
    test('VID-064 resumes where it stopped and offers start over', () async {
      await c.open(req('a'));
      await engine.seek(const Duration(minutes: 3));
      await engine.pause();
      await settle();
      await c.open(req('b'));
      await c.open(req('a'));
      expect(engine.opens.last!.start, const Duration(minutes: 3));
      expect(c.resumedFrom, const Duration(minutes: 3));
      await c.startOver();
      expect(engine.seeks.last, (Duration.zero, SeekMode.exact));
      expect(c.resumedFrom, isNull);
    });

    test('VID-064 resume per server: same file, two keys', () async {
      PlayRequest server(String id) => PlayRequest(
        source: UriSource(Uri.parse('https://h/$id/f.mkv')),
        title: 'f',
        memoryKey: 'server:$id:42',
      );
      await c.open(server('s1'));
      await engine.seek(const Duration(minutes: 5));
      await engine.pause();
      await settle();
      await c.open(server('s2'));
      expect(engine.opens.last!.start, isNull);
      await engine.seek(const Duration(minutes: 7));
      await engine.pause();
      await settle();
      await c.open(server('s1'));
      expect(engine.opens.last!.start, const Duration(minutes: 5));
    });

    test(
      'VID-064 never resumes when resume is off; short plays not kept',
      () async {
        await c.open(req('a'));
        await engine.seek(const Duration(seconds: 10));
        await engine.pause();
        await settle();
        expect(memory.item(c.request!.memoryKey).position, isNull);
        await engine.play();
        await engine.seek(const Duration(minutes: 2));
        await engine.pause();
        await settle();
        settings.set(VideoSettings.resume, ResumeMode.never);
        await c.open(req('a'));
        expect(engine.opens.last!.start, isNull);
      },
    );

    testWidgets('VID-064 next in folder after a cancellable countdown', (
      tester,
    ) async {
      // Subscriptions must live in the test's fake-time zone.
      c.dispose();
      c = VideoPlayerController(
        engine: engine,
        memory: memory,
        settings: settings,
      );
      await c.open(req('a', next: [req('b'), req('c')]));
      engine.fake.advance(const Duration(minutes: 11));
      await tester.pump();
      expect(c.nextUp?.request.title, 'b.mkv');
      expect(c.nextUp?.remaining, 10);
      expect(memory.item(req('a').memoryKey).position, isNull);
      await tester.pump(const Duration(seconds: 3));
      expect(c.nextUp?.remaining, 7);
      c.cancelNextUp();
      await tester.pump(const Duration(seconds: 20));
      expect(c.request!.title, 'a.mkv');
      await c.playNextNow();
      expect(c.request!.title, 'b.mkv');
      expect(c.request!.next.single.title, 'c.mkv');
      engine.fake.advance(const Duration(minutes: 11));
      await tester.pump();
      await tester.pump(const Duration(seconds: 10));
      await tester.pump();
      expect(c.request!.title, 'c.mkv');
      // Let the coalesced memory write fire.
      await tester.pump(const Duration(seconds: 1));
    });

    test('VID-064 repeat, stop and close', () async {
      settings.set(VideoSettings.afterPlayback, PostPlayback.repeat);
      await c.open(req('a'));
      engine.fake.advance(const Duration(minutes: 11));
      await settle();
      await settle();
      expect(c.state.status, PlaybackStatus.playing);
      expect(c.state.position, Duration.zero);

      settings.set(VideoSettings.afterPlayback, PostPlayback.stop);
      engine.fake.advance(const Duration(minutes: 11));
      await settle();
      expect(c.state.status, PlaybackStatus.ended);
      expect(closed, 0);

      settings.set(VideoSettings.afterPlayback, PostPlayback.close);
      await c.togglePlay();
      engine.fake.advance(const Duration(minutes: 11));
      await settle();
      await settle();
      expect(closed, 1);
    });

    test('VID-064 delete asks first, then deletes and moves on', () async {
      settings.set(VideoSettings.afterPlayback, PostPlayback.delete);
      var deleted = 0;
      final a = PlayRequest(
        source: UriSource(Uri.parse('file:///v/a.mkv')),
        title: 'a',
        memoryKey: 'a',
        onDelete: () async => deleted++,
        next: [req('b')],
      );
      await c.open(a);
      engine.fake.advance(const Duration(minutes: 11));
      await settle();
      await settle();
      expect(c.deletePending, isTrue);
      expect(deleted, 0);
      await c.confirmDelete();
      expect(deleted, 1);
      expect(c.request!.title, 'b.mkv');
    });
  });
}
