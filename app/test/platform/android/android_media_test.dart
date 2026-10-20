import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mediahro/platform/android/android_media.dart';
import 'package:mediahro/platform/android/gen/media_api.pigeon.dart';
import 'package:mediahro/platform/audio_output.dart';
import 'package:mediahro/platform/media_session.dart';

/// The Dart half of lane C4a's media session and audio output: message
/// mapping over fake Pigeon APIs.
final class _FakeSession extends MediaSessionHostApi {
  final calls = <Object>[];

  @override
  Future<void> activate(MediaSessionKindMsg kind) async => calls.add(kind);

  @override
  Future<void> setNowPlaying(NowPlayingMsg item) async => calls.add(item);

  @override
  Future<void> setPlaybackStatus(PlaybackStatusMsg status) async =>
      calls.add(status);
}

final class _FakeAudio extends AudioOutputHostApi {
  @override
  Future<List<AudioDeviceMsg>> devices() async => [
    AudioDeviceMsg(
      id: '7',
      name: 'USB DAC',
      kind: AudioDeviceKindMsg.usb,
      sampleRates: [44100, 96000],
      supportsExclusive: true,
      encodedFormats: [],
    ),
  ];

  @override
  Future<AudioPathGrantMsg> requestBitPerfect(
    String deviceId,
    int sampleRate,
    int? bitDepth,
  ) async => AudioPathGrantMsg(
    bitPerfect: true,
    sampleRate: sampleRate,
    bitDepth: bitDepth,
  );
}

void main() {
  test('SYS-001 now playing and status cross as messages', () async {
    final api = _FakeSession();
    final s = AndroidMediaSession(api: api, events: Stream.empty);
    await s.activate(MediaSessionKind.podcast);
    await s.setNowPlaying(
      const NowPlaying(title: 'T', duration: Duration(seconds: 90)),
    );
    await s.setPlaybackStatus(
      const SessionPlaybackStatus(
        state: SessionPlaybackState.buffering,
        position: Duration(milliseconds: 1500),
        rate: 1.25,
        canSkipPrevious: true,
      ),
    );
    expect(api.calls[0], MediaSessionKindMsg.podcast);
    final item = api.calls[1] as NowPlayingMsg;
    expect(item.durationMs, 90000);
    expect(item.isLive, isFalse);
    final status = api.calls[2] as PlaybackStatusMsg;
    expect(status.state, SessionStateMsg.buffering);
    expect(status.positionMs, 1500);
    expect(status.rate, 1.25);
    expect(status.canSkipPrevious, isTrue);
  });

  test('SYS-001 remote commands map to the facade types', () async {
    final events = StreamController<RemoteCommandMsg>();
    final s = AndroidMediaSession(
      api: _FakeSession(),
      events: () => events.stream,
    );
    final got = <RemoteCommand>[];
    final sub = s.commands.listen(got.add);
    events
      ..add(
        RemoteCommandMsg(kind: RemoteCommandKindMsg.seekTo, positionMs: 4200),
      )
      ..add(
        RemoteCommandMsg(kind: RemoteCommandKindMsg.skipBy, positionMs: -10000),
      )
      ..add(RemoteCommandMsg(kind: RemoteCommandKindMsg.setRate, rate: 2))
      ..add(RemoteCommandMsg(kind: RemoteCommandKindMsg.pause));
    await pumpEventQueue();
    await sub.cancel();
    expect(
      (got[0] as SeekToCommand).position,
      const Duration(milliseconds: 4200),
    );
    expect((got[1] as SkipByCommand).offset, const Duration(seconds: -10));
    expect((got[2] as SetRateCommand).rate, 2);
    expect(got[3], isA<PauseCommand>());
  });

  test('AUD-040 devices and bit-perfect grants map through', () async {
    final a = AndroidAudioOutput(
      api: _FakeAudio(),
      deviceEvents: Stream.empty,
      interruptionEvents: () => Stream.value(
        AudioInterruptionMsg(kind: AudioInterruptionKindMsg.becomingNoisy),
      ),
    );
    final d = (await a.devices()).single;
    expect(d.kind, AudioDeviceKind.usb);
    expect(d.sampleRates, [44100, 96000]);
    expect(d.supportsExclusive, isTrue);
    final g = await a.requestBitPerfect('7', sampleRate: 96000, bitDepth: 24);
    expect(g.bitPerfect, isTrue);
    expect(g.sampleRate, 96000);
    expect(g.bitDepth, 24);
    expect(
      (await a.interruptions.first).kind,
      AudioInterruptionKind.becomingNoisy,
    );
  });
}
