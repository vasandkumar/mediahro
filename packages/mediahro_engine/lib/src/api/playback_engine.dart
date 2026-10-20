import 'dart:typed_data';

import 'package:mediahro_engine/src/api/audio_tap.dart';
import 'package:mediahro_engine/src/api/media_source.dart';
import 'package:mediahro_engine/src/api/models.dart';
import 'package:mediahro_engine/src/api/video_target.dart';

/// The playback contract (docs/05 §4.2). Implemented by `MpvEngine` on every
/// platform; `NativeAppleEngine` is the specified fallback (ADR-001). This
/// interface is also the public surface of the Mediahro Engine SDK (B2B-004)
/// and is frozen at the end of Phase B; changes need an ADR (docs/05 §12).
///
/// All methods are asynchronous and safe to call from the UI isolate; the
/// implementation keeps decoding and rendering off it. Engine faults surface
/// as [PlaybackState.error] and never crash the app (CORE-011).
abstract interface class PlaybackEngine {
  EngineRole get role;

  /// Opens [src], replacing the current item.
  Future<void> open(MediaSource src, {OpenOptions? opts});

  /// Broadcast stream of state snapshots. Emits the current state on listen.
  Stream<PlaybackState> get state;

  /// Latest snapshot (same value the stream last emitted).
  PlaybackState get current;

  Future<void> play();
  Future<void> pause();
  Future<void> stop();
  Future<void> seek(Duration position, {SeekMode mode = SeekMode.keyframe});

  /// Single-frame step (VID-063).
  Future<void> frameStep({bool backwards = false});

  /// 0.25–4.0 with pitch correction (VID-062).
  Future<void> setRate(double rate);

  /// 0.0–3.0 (VID-066).
  Future<void> setVolume(double volume);
  Future<void> setMuted({required bool muted});
  Future<void> setAudioDelay(Duration delay);
  Future<void> setSubDelay(
    Duration delay, {
    SubtitleSlot slot = SubtitleSlot.primary,
  });

  /// Selects a track; `id == null` disables that track type (or slot).
  Future<void> selectTrack(
    TrackType type,
    int? id, {
    SubtitleSlot slot = SubtitleSlot.primary,
  });
  Future<void> addExternalTrack(
    TrackType type,
    Uri uri, {
    String? title,
    String? language,
  });

  Future<void> setVideoFilters(VideoFilterChain chain);
  Future<void> setShaderPreset(ShaderPreset preset);
  Future<void> setAudioDsp(AudioDspChain chain);
  Future<void> setAudioOutput(AudioOutputConfig config);
  Future<void> setSubtitleStyle(
    SubtitleStyle style, {
    SubtitleSlot slot = SubtitleSlot.primary,
  });

  /// Subtitle character set (SUB-013): null for automatic detection
  /// (uchardet), otherwise an iconv name such as `cp1251` forced for the
  /// loaded external subtitles, which are reloaded.
  Future<void> setSubtitleCodepage(String? codepage);

  /// Subtitle speed factor, e.g. 25 / 23.976 for frame-rate conversion
  /// (SUB-015). Applies to text subtitles.
  Future<void> setSubSpeed(double speed);

  /// Preloads [next] so it starts sample-accurately when the current item
  /// ends (gapless, AUD-002) or crossfades per [setTransition] (AUD-003).
  /// `null` clears it. [sameAlbum] marks consecutive tracks of one album for
  /// the gapless-album rule.
  Future<void> setNext(MediaSource? next, {bool sameAlbum = false});

  /// Starts the prepared next item now, crossfading per the manual-skip rule.
  Future<void> skipToNext();

  /// Crossfade rules for natural ends and manual skips (AUD-003).
  Future<void> setTransition(TransitionConfig config);

  /// A-B loop (VID-063); both null clears it.
  Future<void> setAbLoop(Duration? a, Duration? b, {int? count});

  /// Encoded still of the current frame (VID-042).
  Future<Uint8List> screenshot({
    bool subtitles = true,
    ScreenshotFormat format = ScreenshotFormat.png,
  });

  /// Exports [start]…[end] of the current item to [out] (a `file:` URI)
  /// (VID-042): an animated GIF or WebP, re-encoded, with burnt-in
  /// subtitles when [subtitles] is true, or [ExportFormat.clipCopy], a
  /// lossless stream copy of the range (container from [out]'s extension;
  /// [subtitles] keeps the subtitle tracks). Throws [EngineException] when
  /// nothing is open or the range is empty.
  Future<void> export(
    Duration start,
    Duration end,
    ExportFormat format,
    Uri out, {
    bool subtitles = false,
  });

  /// Writes embedded text subtitle track [trackId] of the current item to
  /// [out], a `file:` URI whose extension picks the format: `.srt`,
  /// `.ass`/`.ssa` (ASS tracks keep their styles) or `.vtt` (ADR-031:
  /// SUB-030, SUB-050 and SUB-053 on embedded tracks). Works without
  /// disturbing playback. Throws [EngineException]: `notSupported` for
  /// bitmap tracks, `invalidArgument` for an unknown track, another
  /// extension or nothing open.
  Future<void> extractSubtitles(int trackId, Uri out);

  /// Draws video into [target] (VID-031, ADR-022); [VideoTarget.texture] by
  /// default. Throws [EngineException] for an unregistered platform-view
  /// handle (`invalidArgument`) or where the platform has no such path yet
  /// (`notSupported`).
  Future<void> setVideoTarget(VideoTarget target);

  /// Lowers the output by [gain] (0…1) while another app holds audio focus
  /// (AUD-045); 1 restores it. Never changes [PlaybackState.volume], the
  /// user's volume; [PlaybackState.ducked] reports the state.
  Future<void> setDucking(double gain);

  /// Output devices for [AudioOutputConfig.deviceId] (AUD-040…042, VID-004).
  Future<List<EngineAudioDevice>> audioDevices();

  /// Analysis of the audio being played for visualisers (AUD-046, ADR-027):
  /// a broadcast stream of [AudioTapFrame]s over windows of [frames]
  /// samples, about 30 per second while playing. Costs nothing until the
  /// first listener and stops when the last one cancels.
  Stream<AudioTapFrame> audioTap({int frames = 1024});

  /// Decodes the audio of [source] for analysis without playing it
  /// (ADR-032: SUB-050 auto-sync, SUB-052 auto-captions, MUS-010
  /// fingerprints), as fast as the device allows and independent of what is
  /// playing. Float32 PCM at [sampleRate], mono or interleaved stereo, in
  /// contiguous chunks of about half a second from [start] (default: the
  /// beginning) to [end] (default: the end). [trackId] picks the audio track
  /// (default: the default track). Network sources are read once.
  ///
  /// Pausing the subscription pauses decoding; cancelling it stops it.
  /// Failures arrive as [EngineException] (e.g. `decodeFailed`,
  /// `unsupportedFormat` for a source without audio).
  Stream<Float32List> decodeAudio(
    MediaSource source, {
    int? trackId,
    int sampleRate = 16000,
    bool mono = true,
    Duration? start,
    Duration? end,
  });

  /// Flutter external texture id for the video surface; null for the music
  /// role or before the first frame.
  int? get textureId;

  Future<void> dispose();
}

/// Creates engines for the app's engine pool and the SDK.
typedef PlaybackEngineFactory = PlaybackEngine Function(EngineRole role);
