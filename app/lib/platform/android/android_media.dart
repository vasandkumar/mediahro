import 'dart:async';

import 'package:mediahro/platform/android/gen/media_api.pigeon.dart';
import 'package:mediahro/platform/audio_output.dart';
import 'package:mediahro/platform/media_session.dart';

/// [MediaSessionFacade] on Android (SYS-001/002/006): a Media3
/// `MediaLibraryService` mirrors the engine's state for the notification,
/// lock screen, Bluetooth and car, and sends their commands back
/// (`MediaSessionModule.kt`).
final class AndroidMediaSession implements MediaSessionFacade {
  AndroidMediaSession({
    MediaSessionHostApi? api,
    Stream<RemoteCommandMsg> Function()? events,
  }) : _api = api ?? MediaSessionHostApi(),
       _events = events ?? remoteCommands;

  final MediaSessionHostApi _api;
  final Stream<RemoteCommandMsg> Function() _events;

  @override
  Future<void> activate(MediaSessionKind kind) =>
      _api.activate(MediaSessionKindMsg.values[kind.index]);

  @override
  Future<void> setNowPlaying(NowPlaying item) => _api.setNowPlaying(
    NowPlayingMsg(
      title: item.title,
      artist: item.artist,
      album: item.album,
      durationMs: item.duration?.inMilliseconds,
      artwork: item.artwork,
      isLive: item.isLive,
    ),
  );

  @override
  Future<void> setPlaybackStatus(SessionPlaybackStatus status) =>
      _api.setPlaybackStatus(
        PlaybackStatusMsg(
          state: SessionStateMsg.values[status.state.index],
          positionMs: status.position.inMilliseconds,
          rate: status.rate,
          canSkipNext: status.canSkipNext,
          canSkipPrevious: status.canSkipPrevious,
        ),
      );

  @override
  late final Stream<RemoteCommand> commands = _events().map(_command);

  @override
  Future<void> deactivate() => _api.deactivate();

  static RemoteCommand _command(RemoteCommandMsg m) {
    final ms = Duration(milliseconds: m.positionMs ?? 0);
    return switch (m.kind) {
      RemoteCommandKindMsg.play => const PlayCommand(),
      RemoteCommandKindMsg.pause => const PauseCommand(),
      RemoteCommandKindMsg.togglePlayPause => const TogglePlayPauseCommand(),
      RemoteCommandKindMsg.next => const NextCommand(),
      RemoteCommandKindMsg.previous => const PreviousCommand(),
      RemoteCommandKindMsg.stop => const StopCommand(),
      RemoteCommandKindMsg.seekTo => SeekToCommand(ms),
      RemoteCommandKindMsg.skipBy => SkipByCommand(ms),
      RemoteCommandKindMsg.setRate => SetRateCommand(m.rate ?? 1),
    };
  }
}

/// [AudioOutputFacade] on Android (AUD-040, AUD-043/044/045): devices,
/// the Android 14 bit-perfect mixer for USB DACs, audio focus with
/// app-side ducking and headphone unplug (`AudioOutputModule.kt`).
final class AndroidAudioOutput implements AudioOutputFacade {
  AndroidAudioOutput({
    AudioOutputHostApi? api,
    Stream<AudioDeviceListMsg> Function()? deviceEvents,
    Stream<AudioInterruptionMsg> Function()? interruptionEvents,
  }) : _api = api ?? AudioOutputHostApi(),
       _deviceEvents = deviceEvents ?? audioDeviceChanges,
       _interruptionEvents = interruptionEvents ?? audioInterruptions;

  final AudioOutputHostApi _api;
  final Stream<AudioDeviceListMsg> Function() _deviceEvents;
  final Stream<AudioInterruptionMsg> Function() _interruptionEvents;

  @override
  Future<List<AudioDevice>> devices() async =>
      (await _api.devices()).map(_device).toList();

  @override
  late final Stream<List<AudioDevice>> deviceChanges = _deviceEvents().map(
    (l) => l.devices.map(_device).toList(),
  );

  @override
  Future<AudioPathGrant> requestBitPerfect(
    String deviceId, {
    required int sampleRate,
    int? bitDepth,
  }) async {
    final g = await _api.requestBitPerfect(deviceId, sampleRate, bitDepth);
    return AudioPathGrant(
      bitPerfect: g.bitPerfect,
      sampleRate: g.sampleRate,
      bitDepth: g.bitDepth,
    );
  }

  @override
  Future<void> releaseBitPerfect() => _api.releaseBitPerfect();

  @override
  late final Stream<AudioInterruption> interruptions = _interruptionEvents()
      .map(
        (m) => AudioInterruption(AudioInterruptionKind.values[m.kind.index]),
      );

  @override
  Future<bool> requestFocus({bool duckOthers = false}) =>
      _api.requestFocus(duckOthers);

  @override
  Future<void> abandonFocus() => _api.abandonFocus();

  static AudioDevice _device(AudioDeviceMsg d) => AudioDevice(
    id: d.id,
    name: d.name,
    kind: AudioDeviceKind.values[d.kind.index],
    sampleRates: d.sampleRates,
    supportsExclusive: d.supportsExclusive,
    encodedFormats: d.encodedFormats,
    bluetoothCodec: d.bluetoothCodec,
  );
}
