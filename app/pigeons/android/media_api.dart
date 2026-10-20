// Pigeon messages for MediaSessionFacade and AudioOutputFacade on Android
// (lane C4a, SYS-001/002/006, AUD-040/043/044/045).
//
//   dart run pigeon --input pigeons/android/media_api.dart   (from app/)
//
// Pigeon's schema is positional; named bool parameters do not map to Kotlin.
// ignore_for_file: avoid_positional_boolean_parameters

import 'package:pigeon/pigeon.dart';

@ConfigurePigeon(
  PigeonOptions(
    dartOut: 'lib/platform/android/gen/media_api.pigeon.dart',
    kotlinOut: 'android/app/src/main/kotlin/com/mediahro/mediahro/pigeon/MediaApi.g.kt',
    kotlinOptions: KotlinOptions(
      // Shares FlutterError and the event-channel classes of StorageApi.g.kt.
      package: 'com.mediahro.mediahro.pigeon',
      includeErrorClass: false,
    ),
    dartPackageName: 'mediahro',
  ),
)
enum MediaSessionKindMsg { video, music, podcast }

enum SessionStateMsg { playing, paused, buffering, stopped }

class NowPlayingMsg {
  NowPlayingMsg(
    this.title,
    this.artist,
    this.album,
    this.durationMs,
    this.artwork,
    this.isLive,
  );
  String title;
  String? artist;
  String? album;
  int? durationMs;
  Uint8List? artwork;
  bool isLive;
}

class PlaybackStatusMsg {
  PlaybackStatusMsg(
    this.state,
    this.positionMs,
    this.rate,
    this.canSkipNext,
    this.canSkipPrevious,
  );
  SessionStateMsg state;
  int positionMs;
  double rate;
  bool canSkipNext;
  bool canSkipPrevious;
}

enum RemoteCommandKindMsg {
  play,
  pause,
  togglePlayPause,
  next,
  previous,
  stop,
  seekTo,
  skipBy,
  setRate,
}

class RemoteCommandMsg {
  RemoteCommandMsg(this.kind, this.positionMs, this.rate);
  RemoteCommandKindMsg kind;

  /// seekTo: the target; skipBy: the signed offset.
  int? positionMs;
  double? rate;
}

enum AudioDeviceKindMsg {
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

class AudioDeviceMsg {
  AudioDeviceMsg(
    this.id,
    this.name,
    this.kind,
    this.sampleRates,
    this.supportsExclusive,
    this.encodedFormats,
    this.bluetoothCodec,
  );
  String id;
  String name;
  AudioDeviceKindMsg kind;
  List<int> sampleRates;
  bool supportsExclusive;
  List<String> encodedFormats;
  String? bluetoothCodec;
}

class AudioDeviceListMsg {
  AudioDeviceListMsg(this.devices);
  List<AudioDeviceMsg> devices;
}

class AudioPathGrantMsg {
  AudioPathGrantMsg(this.bitPerfect, this.sampleRate, this.bitDepth);
  bool bitPerfect;
  int? sampleRate;
  int? bitDepth;
}

enum AudioInterruptionKindMsg {
  began,
  endedShouldResume,
  endedNoResume,
  duck,
  unduck,
  becomingNoisy,
}

class AudioInterruptionMsg {
  AudioInterruptionMsg(this.kind);
  AudioInterruptionKindMsg kind;
}

@HostApi()
abstract class MediaSessionHostApi {
  @async
  void activate(MediaSessionKindMsg kind);

  void setNowPlaying(NowPlayingMsg item);
  void setPlaybackStatus(PlaybackStatusMsg status);

  @async
  void deactivate();
}

@HostApi()
abstract class AudioOutputHostApi {
  List<AudioDeviceMsg> devices();

  AudioPathGrantMsg requestBitPerfect(
    String deviceId,
    int sampleRate,
    int? bitDepth,
  );

  void releaseBitPerfect();

  bool requestFocus(bool duckOthers);
  void abandonFocus();
}

@EventChannelApi(
  kotlinOptions: KotlinEventChannelOptions(includeSharedClasses: false),
)
abstract class MediaEventsApi {
  RemoteCommandMsg remoteCommands();
  AudioDeviceListMsg audioDeviceChanges();
  AudioInterruptionMsg audioInterruptions();
}
