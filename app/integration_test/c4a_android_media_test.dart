import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mediahro/platform/android/android_media.dart';
import 'package:mediahro/platform/platform_bindings.dart';
import 'package:mediahro/platform/platform_facades.dart';

/// Lane C4a: MediaSessionFacade and AudioOutputFacade on the Android
/// emulator. A debug-only hook (`mediahro.test/session`) drives the Media3
/// session through its own MediaController, the way a headset, the
/// notification or a car does, reads back what controllers see, and takes
/// audio focus with a second client the way another app does.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final android = Platform.isAndroid;

  const hook = BasicMessageChannel<Object?>(
    'mediahro.test/session',
    StandardMessageCodec(),
  );
  Future<Object?> op(String name, [Object? arg]) => hook.send([name, arg]);
  Future<Map<Object?, Object?>> state() async =>
      (await op('state'))! as Map<Object?, Object?>;

  /// Polls [check] until it holds (session updates cross a binder hop).
  Future<void> eventually(
    Future<bool> Function() check, {
    String reason = '',
  }) async {
    final deadline = DateTime.now().add(const Duration(seconds: 10));
    while (!await check()) {
      if (DateTime.now().isAfter(deadline)) fail('timed out: $reason');
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  }

  // A 1×1 PNG.
  final png = Uint8List.fromList(const [
    0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, //
    0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
    0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
    0x0D, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0xF8, 0xCF, 0xC0, 0xF0,
    0x1F, 0x00, 0x05, 0x00, 0x01, 0xFF, 0x89, 0x99, 0x3D, 0x1D, 0x00, 0x00,
    0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
  ]);

  late AndroidMediaSession session;
  late AndroidAudioOutput audio;
  setUp(() {
    if (!android) return;
    session = AndroidMediaSession();
    audio = AndroidAudioOutput();
  });

  Future<void> startPlaying() async {
    await session.activate(MediaSessionKind.music);
    await session.setNowPlaying(
      NowPlaying(
        title: 'Blue in Green',
        artist: 'Miles Davis',
        album: 'Kind of Blue',
        duration: const Duration(minutes: 5, seconds: 37),
        artwork: png,
      ),
    );
    await session.setPlaybackStatus(
      const SessionPlaybackStatus(
        state: SessionPlaybackState.playing,
        position: Duration(seconds: 30),
        canSkipNext: true,
      ),
    );
  }

  tearDown(() async {
    if (!android) return;
    await op('release');
    await session.deactivate();
    await audio.abandonFocus();
    await op('returnFocus');
  });

  testWidgets('SYS-001 Android bindings provide MediaSession and AudioOutput', (
    tester,
  ) async {
    final c = ProviderContainer(overrides: platformOverrides());
    addTearDown(c.dispose);
    expect(c.read(mediaSessionProvider), isA<AndroidMediaSession>());
    expect(c.read(audioOutputProvider), isA<AndroidAudioOutput>());
  }, skip: !android);

  testWidgets(
    'SYS-001 controllers see now-playing metadata, artwork and status',
    (tester) async {
      await startPlaying();
      await eventually(
        () async => (await state())['title'] == 'Blue in Green',
        reason: 'metadata reaches the session',
      );
      final s = await state();
      expect(s['artist'], 'Miles Davis');
      expect(s['album'], 'Kind of Blue');
      expect(s['hasArtwork'], isTrue);
      expect(s['durationMs'], 337000);
      expect(s['playWhenReady'], isTrue);
      expect(s['playbackState'], 3, reason: 'Player.STATE_READY');
      expect(s['canNext'], isTrue);
      expect(s['canPrevious'], isFalse);
      expect(s['mediaType'], 1, reason: 'MediaMetadata.MEDIA_TYPE_MUSIC');
      expect(s['positionMs']! as int, greaterThanOrEqualTo(30000));
    },
    skip: !android,
  );

  testWidgets('SYS-001 headset, notification and car commands reach Dart', (
    tester,
  ) async {
    await startPlaying();
    await eventually(
      () async => (await state())['playWhenReady'] == true,
      reason: 'session playing',
    );
    final got = <RemoteCommand>[];
    final sub = session.commands.listen(got.add);
    addTearDown(sub.cancel);
    Future<T> next<T extends RemoteCommand>(String name, [Object? arg]) async {
      final before = got.length;
      await op(name, arg);
      await eventually(() async => got.length > before, reason: name);
      return got.last as T;
    }

    expect(await next<PauseCommand>('pause'), isA<PauseCommand>());
    expect(await next<PlayCommand>('play'), isA<PlayCommand>());
    expect(
      (await next<SeekToCommand>('seekTo', 42000)).position,
      const Duration(seconds: 42),
    );
    expect(
      (await next<SkipByCommand>('seekForward')).offset,
      const Duration(seconds: 10),
    );
    expect(
      (await next<SkipByCommand>('seekBack')).offset,
      const Duration(seconds: -10),
    );
    expect(await next<NextCommand>('next'), isA<NextCommand>());
    expect((await next<SetRateCommand>('speed', 1.5)).rate, 1.5);
    expect(await next<StopCommand>('stop'), isA<StopCommand>());
  }, skip: !android);

  testWidgets(
    'SYS-002 media notification and SYS-006 foreground service ends on stop',
    (tester) async {
      await startPlaying();
      await eventually(
        () async => await op('foreground') == true,
        reason: 'mediaPlayback foreground service while playing',
      );
      expect(await op('notification'), isTrue);
      // Paused: the notification keeps its controls (Media3 also keeps the
      // service in the foreground for a grace period so a resume from the
      // notification is allowed on Android 12+).
      await session.setPlaybackStatus(
        const SessionPlaybackStatus(
          state: SessionPlaybackState.paused,
          position: Duration(seconds: 31),
        ),
      );
      await tester.pump(const Duration(milliseconds: 500));
      expect(await op('notification'), isTrue);
      // Stopped: out of the foreground at once, nothing keeps running.
      await session.setPlaybackStatus(
        const SessionPlaybackStatus(
          state: SessionPlaybackState.stopped,
          position: Duration(seconds: 31),
        ),
      );
      await eventually(
        () async => await op('foreground') == false,
        reason: 'stopped: out of the foreground',
      );
      await eventually(
        () async => await op('notification') == false,
        reason: 'stopped: notification removed',
      );
      await session.deactivate();
      await eventually(
        () async => await op('service') == false,
        reason: 'deactivate stops the service',
      );
    },
    skip: !android,
  );

  testWidgets(
    'AUD-045 focus loss, ducking and regain reach Dart as interruptions',
    (tester) async {
      final got = <AudioInterruptionKind>[];
      final sub = audio.interruptions.listen((i) => got.add(i.kind));
      addTearDown(sub.cancel);
      Future<void> expectKinds(List<AudioInterruptionKind> kinds) =>
          eventually(
            () async => got.length >= kinds.length,
            reason: '$kinds, got $got',
          ).then((_) {
            expect(got, kinds);
            got.clear();
          });

      expect(await audio.requestFocus(), isTrue);
      expect(await op('stealFocus', 'transient'), isTrue);
      await expectKinds([AudioInterruptionKind.began]);
      await op('returnFocus');
      await expectKinds([AudioInterruptionKind.endedShouldResume]);

      expect(await op('stealFocus', 'duck'), isTrue);
      await expectKinds([AudioInterruptionKind.duck]);
      await op('returnFocus');
      await expectKinds([AudioInterruptionKind.unduck]);

      expect(await op('stealFocus', 'full'), isTrue);
      await expectKinds([
        AudioInterruptionKind.began,
        AudioInterruptionKind.endedNoResume,
      ]);
    },
    skip: !android,
  );

  testWidgets('AUD-045 headphone unplug is reported as becoming noisy', (
    tester,
  ) async {
    final got = <AudioInterruptionKind>[];
    final sub = audio.interruptions.listen((i) => got.add(i.kind));
    addTearDown(sub.cancel);
    expect(await audio.requestFocus(), isTrue);
    await op('noisy');
    await eventually(() async => got.isNotEmpty, reason: 'noisy');
    expect(got, [AudioInterruptionKind.becomingNoisy]);
  }, skip: !android);

  testWidgets(
    'AUD-044 outputs list kinds, rates and formats; bit-perfect is honest',
    (tester) async {
      final devices = await audio.devices();
      expect(devices, isNotEmpty);
      final speaker = devices.firstWhere(
        (d) => d.kind == AudioDeviceKind.builtIn,
      );
      expect(speaker.name, isNotEmpty);
      expect(speaker.bluetoothCodec, isNull);
      expect(speaker.encodedFormats, isNot(contains('pcm')));
      // The built-in speaker has no bit-perfect mixer: the grant says so.
      final grant = await audio.requestBitPerfect(
        speaker.id,
        sampleRate: 48000,
        bitDepth: 24,
      );
      expect(grant.bitPerfect, speaker.supportsExclusive);
      await audio.releaseBitPerfect();
      await expectLater(
        audio.requestBitPerfect('no-such-device', sampleRate: 44100),
        throwsA(isA<PlatformException>()),
      );
    },
    skip: !android,
  );
}
