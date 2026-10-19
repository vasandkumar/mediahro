import 'package:meta/meta.dart';

/// Audio routing, exclusivity and focus (AUD-040…045, VID-004):
/// setPreferredMixerAttributes / AAudio (A), AVAudioSession / CoreAudio hog
/// mode (I M), WASAPI exclusive / ASIO (W).
abstract interface class AudioOutputFacade {
  Future<List<AudioDevice>> devices();
  Stream<List<AudioDevice>> get deviceChanges;

  /// Requests a bit-perfect path; the grant reports what the OS gave.
  Future<AudioPathGrant> requestBitPerfect(
    String deviceId, {
    required int sampleRate,
    int? bitDepth,
  });
  Future<void> releaseBitPerfect();

  /// Calls, notifications, other apps, headphone unplug (AUD-045).
  Stream<AudioInterruption> get interruptions;
  Future<bool> requestFocus({bool duckOthers = false});
  Future<void> abandonFocus();
}

enum AudioDeviceKind {
  builtIn,
  wired,
  usb,
  bluetooth,
  hdmi,
  spdif,
  airplay,
  cast,
  other,
}

@immutable
final class AudioDevice {
  const AudioDevice({
    required this.id,
    required this.name,
    required this.kind,
    this.sampleRates = const [],
    this.supportsExclusive = false,
    this.encodedFormats = const [],
    this.bluetoothCodec,
  });

  final String id;
  final String name;
  final AudioDeviceKind kind;
  final List<int> sampleRates;
  final bool supportsExclusive;

  /// Passthrough-capable formats: ac3, eac3, dts, dtshd, truehd.
  final List<String> encodedFormats;

  /// Shown in the output picker (AUD-044).
  final String? bluetoothCodec;
}

@immutable
final class AudioPathGrant {
  const AudioPathGrant({
    required this.bitPerfect,
    this.sampleRate,
    this.bitDepth,
  });

  final bool bitPerfect;
  final int? sampleRate;
  final int? bitDepth;
}

enum AudioInterruptionKind {
  began,
  endedShouldResume,
  endedNoResume,
  duck,
  unduck,
  becomingNoisy,
}

@immutable
final class AudioInterruption {
  const AudioInterruption(this.kind);
  final AudioInterruptionKind kind;
}
