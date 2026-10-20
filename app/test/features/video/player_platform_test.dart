import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediahro/features/settings/settings_store.dart';
import 'package:mediahro/features/video/player/play_request.dart';
import 'package:mediahro/features/video/player/player_platform.dart';
import 'package:mediahro/features/video/player/video_memory.dart';
import 'package:mediahro/features/video/player/video_player_controller.dart';
import 'package:mediahro/features/video/video_settings.dart';
import 'package:mediahro/platform/platform_facades.dart';
import 'package:mediahro_engine/mediahro_engine.dart';
import 'package:mediahro_engine/testing.dart';

import '../../../integration_test/support/c1_engine.dart';
import '../../../integration_test/support/c1_platform.dart';
import '../../helpers.dart';

const _portrait = [
  Track(id: 1, type: TrackType.video, width: 1080, height: 1920, fps: 30),
  Track(id: 1, type: TrackType.audio, codec: 'aac', channels: 2),
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late RecordingEngine engine;
  late VideoMemory memory;
  late SettingsStore settings;
  late VideoPlayerController c;
  late FakeDisplay display;
  late FakePip pip;
  late FakeMediaSession session;
  late FakePlaybackEngine music;
  late PlayerPlatform p;
  var phone = true;

  Future<void> settle() async {
    for (var i = 0; i < 5; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  PlayRequest req(String name, {List<PlayRequest> next = const []}) =>
      PlayRequest.uri(Uri.parse('file:///v/$name.mkv'), next: next);

  _Owner? owner;

  Future<void> build({List<Track>? tracks}) async {
    engine = RecordingEngine(
      mediaDuration: const Duration(minutes: 10),
      tracks: tracks,
    );
    c = VideoPlayerController(
      engine: engine,
      memory: memory,
      settings: settings,
    );
    p = PlayerPlatform(
      controller: c,
      settings: settings,
      display: display,
      pip: pip,
      session: session,
      otherAudio: music,
      isPhone: () => phone,
      sessionOwner: owner,
    );
    await p.start();
  }

  setUp(() async {
    memory = await VideoMemory.open(MemoryVideoMemoryPersistence());
    settings = await memoryStore();
    display = FakeDisplay();
    pip = FakePip();
    session = FakeMediaSession();
    music = FakePlaybackEngine(role: EngineRole.music);
    phone = true;
    owner = null;
  });

  tearDown(() async {
    await p.dispose();
    c.dispose();
    await engine.dispose();
  });

  group('VID-070 orientation and display', () {
    test('VID-070 keeps the screen awake only while playing', () async {
      await build();
      await c.open(req('a'));
      await settle();
      expect(display.keepOn.last, isTrue);
      await engine.pause();
      await settle();
      expect(display.keepOn.last, isFalse);
    });

    test(
      'VID-070 rotation follows the video: landscape and portrait',
      () async {
        await build();
        await c.open(req('wide'));
        await settle();
        expect(display.locks.last, OrientationLock.landscape);
        await p.dispose();
        c.dispose();
        await engine.dispose();
        display = FakeDisplay();
        await build(tracks: _portrait);
        await c.open(req('tall'));
        await settle();
        expect(display.locks.last, OrientationLock.portrait);
      },
    );

    test(
      'VID-070 a fixed rotation setting wins over the video shape',
      () async {
        settings.set(VideoSettings.orientation, VideoOrientation.portrait);
        await build();
        await c.open(req('wide'));
        await settle();
        expect(display.locks, [OrientationLock.portrait]);
      },
    );

    test('VID-070 leaving gives rotation back, portrait first on phones; '
        'brightness and screen-on restored', () async {
      await build();
      await c.open(req('wide'));
      await settle();
      await p.dispose();
      expect(display.locks, [
        OrientationLock.landscape,
        OrientationLock.portrait,
        OrientationLock.auto,
      ]);
      expect(display.brightness.last, isNull);
      expect(display.keepOn.last, isFalse);
    });

    test('VID-070 tablets go straight back to the system rotation', () async {
      phone = false;
      await build();
      await c.open(req('wide'));
      await settle();
      await p.dispose();
      expect(display.locks, [OrientationLock.landscape, OrientationLock.auto]);
    });

    test('VID-070 without a display facade Flutter rotates instead', () async {
      final rotation = FakeOrientation();
      engine = RecordingEngine();
      c = VideoPlayerController(
        engine: engine,
        memory: memory,
        settings: settings,
      );
      p = PlayerPlatform(
        controller: c,
        settings: settings,
        orientation: rotation,
      );
      await p.start();
      await c.open(req('wide'));
      await settle();
      expect(rotation.locks.last, OrientationLock.landscape);
    });
  });

  group('VID-067 picture-in-picture', () {
    test(
      'VID-067 enters with the video shape, clamped to what PiP accepts',
      () async {
        await build();
        await c.open(req('a'));
        await settle();
        expect(p.pipSupported, isTrue);
        expect(await p.enterPip(), isTrue);
        expect(pip.entered.single, closeTo(16 / 9, 0.001));
        await settle();
        expect(p.inPip.value, isTrue);
        expect(
          PlayerPlatform.aspectRatio(
            const PlaybackState(video: VideoStats(width: 4000, height: 1000)),
          ),
          2.39,
        );
      },
    );

    test(
      'VID-067 auto-PiP on leave is opt-in and only while playing',
      () async {
        await build();
        await c.open(req('a'));
        await settle();
        expect(pip.autoEnter, isEmpty, reason: 'off by default');
        settings.set(VideoSettings.autoPip, true);
        await engine.pause();
        await engine.play();
        await settle();
        expect(pip.autoEnter.last, isTrue);
        await engine.pause();
        await settle();
        expect(pip.autoEnter.last, isFalse);
      },
    );

    test('VID-067 the video shape reaches PiP on every size change '
        '(ADR-028)', () async {
      await build();
      await c.open(req('a'));
      await settle();
      expect(pip.aspectRatios, [closeTo(16 / 9, 0.001)]);
      engine.emit(
        c.state.copyWith(video: const VideoStats(width: 1440, height: 1080)),
      );
      await settle();
      expect(pip.aspectRatios.last, closeTo(4 / 3, 0.001));
      engine.emit(
        c.state.copyWith(video: const VideoStats(width: 1440, height: 1080)),
      );
      await settle();
      expect(pip.aspectRatios, hasLength(2), reason: 'only on changes');
    });

    test('VID-067 unsupported devices offer no PiP', () async {
      pip = FakePip(supported: false);
      await build();
      await c.open(req('a'));
      expect(p.pipSupported, isFalse);
      expect(await p.enterPip(), isFalse);
      expect(pip.entered, isEmpty);
    });
  });

  group('VID-068 background and audio-only playback', () {
    test('VID-068 by default the video pauses when the app leaves', () async {
      await build();
      await c.open(req('a'));
      await settle();
      p.didChangeAppLifecycleState(AppLifecycleState.paused);
      await settle();
      expect(c.state.status, PlaybackStatus.paused);
    });

    test('VID-068 opted in for the session: sound plays on, picture off, '
        'picture back on return', () async {
      await build();
      await c.open(req('a'));
      await settle();
      p.backgroundThisSession.value = true;
      p.didChangeAppLifecycleState(AppLifecycleState.paused);
      await settle();
      expect(c.state.status, PlaybackStatus.playing);
      expect(engine.selections.last, (
        TrackType.video,
        null,
        SubtitleSlot.primary,
      ));
      p.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await settle();
      expect(engine.selections.last, (
        TrackType.video,
        1,
        SubtitleSlot.primary,
      ));
    });

    test(
      'VID-068 "always" setting keeps playing; picture can stay on',
      () async {
        settings
          ..set(VideoSettings.backgroundPlay, BackgroundPlay.always)
          ..set(VideoSettings.backgroundVideoOff, false);
        await build();
        await c.open(req('a'));
        await settle();
        p.didChangeAppLifecycleState(AppLifecycleState.paused);
        await settle();
        expect(c.state.status, PlaybackStatus.playing);
        expect(engine.selections, isEmpty);
      },
    );

    test(
      'VID-068 in picture-in-picture leaving the app changes nothing',
      () async {
        await build();
        await c.open(req('a'));
        await settle();
        await p.enterPip();
        await settle();
        p.didChangeAppLifecycleState(AppLifecycleState.paused);
        await settle();
        expect(c.state.status, PlaybackStatus.playing);
      },
    );

    test('VID-068 sound only turns the video track off and back on', () async {
      await build();
      await c.open(req('a'));
      await settle();
      await c.setVideoOff(off: true);
      expect(c.videoOff, isTrue);
      expect(engine.selections.last.$2, isNull);
      await c.setVideoOff(off: false);
      expect(c.videoOff, isFalse);
      expect(engine.selections.last.$2, 1);
    });

    test('VID-068 a video starting pauses the music', () async {
      await music.open(UriSource(Uri.parse('file:///m/song.flac')));
      expect(music.current.status, PlaybackStatus.playing);
      await build();
      await c.open(req('a'));
      await settle();
      expect(music.current.status, PlaybackStatus.paused);
    });
  });

  group('VID-074 media session (lock screen, notification, media keys)', () {
    test('VID-074 the session shows the video and follows its state', () async {
      await build();
      await c.open(req('film', next: [req('next')]));
      await settle();
      expect(session.activated, [MediaSessionKind.video]);
      expect(session.nowPlaying.last.title, 'film.mkv');
      expect(session.statuses.last.state, SessionPlaybackState.playing);
      expect(session.statuses.last.canSkipNext, isTrue);
      await engine.pause();
      await settle();
      expect(session.statuses.last.state, SessionPlaybackState.paused);
    });

    test('VID-074 remote commands drive the player', () async {
      await build();
      await c.open(req('film', next: [req('next')]));
      await settle();
      session.send(const PauseCommand());
      await settle();
      expect(c.state.status, PlaybackStatus.paused);
      session.send(const TogglePlayPauseCommand());
      await settle();
      expect(c.state.status, PlaybackStatus.playing);
      session.send(const SeekToCommand(Duration(minutes: 4)));
      await settle();
      expect(c.state.position, const Duration(minutes: 4));
      session.send(const SkipByCommand(Duration(seconds: -30)));
      await settle();
      expect(c.state.position, const Duration(minutes: 3, seconds: 30));
      session.send(const SetRateCommand(1.5));
      await settle();
      expect(c.state.rate, 1.5);
      session.send(const NextCommand());
      await settle();
      expect(c.request!.title, 'next.mkv');
    });

    test('VID-074 leaving the player releases the session', () async {
      await build();
      await c.open(req('film'));
      await settle();
      await p.dispose();
      expect(session.deactivations, 1);
    });
  });

  group('ADR-029 one owner for the media session', () {
    test('ADR-029 the video claims the session when it plays', () async {
      owner = _Owner();
      await build();
      await c.open(req('film'));
      await settle();
      expect(owner!.kind, 'video');
      expect(session.activated, [MediaSessionKind.video]);
    });

    test(
      'ADR-029 while music owns it, video ignores remote commands',
      () async {
        owner = _Owner();
        await build();
        await c.open(req('film'));
        await settle();
        owner!.kind = 'music';
        session.send(const PauseCommand());
        await settle();
        expect(c.state.status, PlaybackStatus.playing);
      },
    );

    test('ADR-029 playing again takes the session back and re-shows the '
        'video', () async {
      owner = _Owner();
      await build();
      await c.open(req('film'));
      await settle();
      owner!.kind = 'music';
      await engine.pause();
      await settle();
      await engine.play();
      await settle();
      expect(owner!.kind, 'video');
      expect(session.activated, hasLength(2));
      expect(session.nowPlaying, hasLength(2));
      session.send(const PauseCommand());
      await settle();
      expect(c.state.status, PlaybackStatus.paused);
    });

    test('ADR-029 closing the video after music took the session leaves '
        "music's session alone", () async {
      owner = _Owner();
      await build();
      await c.open(req('film'));
      await settle();
      owner!.kind = 'music';
      session.send(const PauseCommand());
      await settle();
      expect(c.state.status, PlaybackStatus.playing);
      await p.dispose();
      expect(owner!.kind, 'music');
      expect(session.deactivations, 0);
    });

    test('ADR-029 leaving releases only its own ownership', () async {
      owner = _Owner();
      await build();
      await c.open(req('film'));
      await settle();
      await p.dispose();
      expect(owner!.kind, isNull);
      expect(owner!.releases, 1);
    });
  });
}

final class _Owner implements SessionOwnership {
  String? kind;
  int releases = 0;

  @override
  bool get ownedByVideo => kind == 'video';

  @override
  void claim() => kind = 'video';

  @override
  void release() {
    releases++;
    if (kind == 'video') kind = null;
  }
}
