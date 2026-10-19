import 'package:freezed_annotation/freezed_annotation.dart';

part 'models.freezed.dart';

/// Which pool instance an engine serves (docs/05 §4.4): one for video, one
/// for music, so a film can pause while a track plays.
enum EngineRole { video, music }

enum TrackType { video, audio, subtitle }

/// Primary or secondary subtitle (SUB-016 dual subtitles).
enum SubtitleSlot { primary, secondary }

enum SeekMode {
  /// Fast seek to the nearest keyframe.
  keyframe,

  /// Frame-accurate seek (VID-061 when paused).
  exact,

  /// Seek relative to the current position.
  relative,
}

enum PlaybackStatus { idle, opening, buffering, playing, paused, ended, error }

/// Dynamic range of the current video (VID-031…035). Display copy never
/// uses Dolby trademarks (docs/09 §4); `dolbyVisionProfile` is technical.
enum HdrType { sdr, hdr10, hdr10Plus, hlg, dolbyVision }

/// Hardware decode path reported in the info overlay (VID-072).
enum HwdecPath {
  none,
  mediacodec,
  videotoolbox,
  d3d11va,
  d3d12va,
  vulkan,
  other,
}

/// Audio output truthfulness indicator (AUD-006).
enum AudioOutputPath { bitPerfect, resampled, mixed, passthrough, unknown }

enum ScreenshotFormat { png, jpegXl, webp, jpeg }

/// Informational notes surfaced once per item; mapped to copy by the UI.
enum EngineNotice {
  /// Dolby Vision profile 7: base layer played, enhancement layer ignored
  /// (VID-035).
  enhancementLayerIgnored,

  /// Hardware decode was unavailable and software decode took over (VID-002).
  softwareDecodeFallback,

  /// Passthrough was refused by the device; audio is decoded (VID-004).
  passthroughFallback,

  /// HEVC has no hardware or OS decoder on this Windows device and software
  /// HEVC is off by default (docs/09 §4).
  hevcSoftwareDecodeOff,

  /// Encrypted disc structure detected; only unencrypted discs play (VID-007).
  encryptedDisc,
}

/// Error categories mapped to user-facing copy (docs/06 §8).
enum EngineErrorCode {
  unsupportedFormat,
  decodeFailed,
  sourceUnavailable,
  networkTimeout,
  engineCrashed,
  libraryMissing,
  invalidArgument,
  unknown,
}

@freezed
abstract class EngineError with _$EngineError {
  const factory EngineError({
    required EngineErrorCode code,

    /// Technical detail for the info sheet ("Copy details"), never primary copy.
    String? detail,
  }) = _EngineError;
}

final class EngineException implements Exception {
  const EngineException(this.error);

  final EngineError error;

  @override
  String toString() =>
      'EngineException(${error.code.name}${error.detail == null ? '' : ': ${error.detail}'})';
}

@freezed
abstract class Track with _$Track {
  const factory Track({
    required int id,
    required TrackType type,
    String? title,

    /// BCP 47 language tag when known.
    String? language,
    String? codec,
    int? channels,
    int? sampleRate,
    int? width,
    int? height,
    double? fps,
    @Default(false) bool isDefault,
    @Default(false) bool isForced,
    @Default(false) bool isExternal,
    @Default(false) bool isAudioDescription,
    @Default(false) bool isHearingImpaired,

    /// Technical Dolby Vision profile of a video track (5, 7, 8); UI copy
    /// never uses the trademark (docs/09 §4).
    int? dolbyVisionProfile,

    /// ReplayGain tags read by the demuxer (AUD-004).
    double? replayGainTrackDb,
    double? replayGainAlbumDb,
  }) = _Track;
}

@freezed
abstract class Chapter with _$Chapter {
  const factory Chapter({required Duration start, String? title}) = _Chapter;
}

/// Stats overlay content (VID-072).
@freezed
abstract class VideoStats with _$VideoStats {
  const factory VideoStats({
    String? container,
    String? videoCodec,
    @Default(HwdecPath.none) HwdecPath hwdec,
    int? width,
    int? height,
    double? fps,
    @Default(0) int droppedFrames,
    int? bitrate,
    @Default(HdrType.sdr) HdrType hdr,

    /// e.g. 5, 7, 8 — profile string only, shown as "HDR (dynamic metadata, profile 8)".
    int? dolbyVisionProfile,
    String? subtitleRenderer,

    /// Mastering display peak (cd/m²) and MaxCLL from HDR10 metadata.
    double? peakNits,
    double? maxCll,
  }) = _VideoStats;
}

@freezed
abstract class AudioOutputInfo with _$AudioOutputInfo {
  const factory AudioOutputInfo({
    String? device,
    String? format,
    int? sampleRate,
    int? bitDepth,
    int? channels,
    @Default(AudioOutputPath.unknown) AudioOutputPath path,

    /// Engine audio output in use (`wasapi`, `aaudio`, `coreaudio`, …).
    String? output,
  }) = _AudioOutputInfo;
}

/// Snapshot emitted by `PlaybackEngine.state`.
@freezed
abstract class PlaybackState with _$PlaybackState {
  const factory PlaybackState({
    @Default(PlaybackStatus.idle) PlaybackStatus status,
    @Default(Duration.zero) Duration position,
    Duration? duration,
    @Default(Duration.zero) Duration bufferedUntil,
    @Default(1.0) double rate,

    /// 0.0–3.0 (300 % boost with limiter, VID-066).
    @Default(1.0) double volume,
    @Default(false) bool muted,
    @Default(<Track>[]) List<Track> tracks,
    int? videoTrackId,
    int? audioTrackId,
    int? subtitleTrackId,
    int? secondarySubtitleTrackId,
    @Default(<Chapter>[]) List<Chapter> chapters,
    @Default(Duration.zero) Duration audioDelay,
    @Default(Duration.zero) Duration subtitleDelay,
    @Default(Duration.zero) Duration secondarySubtitleDelay,

    /// Current secondary subtitle line (SUB-016). The UI draws it with its own
    /// size and position; the engine does not burn it in.
    String? secondarySubtitleText,
    @Default(VideoStats()) VideoStats video,
    @Default(AudioOutputInfo()) AudioOutputInfo audio,
    EngineError? error,

    /// One-time informational notes for the current item (e.g. VID-035).
    @Default(<EngineNotice>{}) Set<EngineNotice> notices,

    /// True when the next item is preloaded for gapless or crossfade
    /// (AUD-002, AUD-003).
    @Default(false) bool nextPrepared,
  }) = _PlaybackState;
}

@freezed
abstract class OpenOptions with _$OpenOptions {
  const factory OpenOptions({
    Duration? start,
    @Default(true) bool autoplay,

    /// Music role and video audio-only mode (VID-068): `vid=no`.
    @Default(false) bool audioOnly,
    @Default(<String>[]) List<String> preferredAudioLanguages,
    @Default(<String>[]) List<String> preferredSubtitleLanguages,

    /// Read-ahead cache budget; null lets the engine size it by bitrate (VID-006).
    int? cacheBytes,
  }) = _OpenOptions;
}

enum ToneMapping { bt2390, spline, reinhard, hable, mobius, clip }

enum Scaler { bilinear, spline36, ewaLanczos }

enum Deinterlace { off, auto, yadif, bwdif }

/// Video rendering options (VID-031, VID-037, VID-039, VID-041).
@freezed
abstract class VideoFilterChain with _$VideoFilterChain {
  const factory VideoFilterChain({
    @Default(ToneMapping.bt2390) ToneMapping toneMapping,
    @Default(Scaler.spline36) Scaler scaler,
    @Default(false) bool deband,
    @Default(Deinterlace.auto) Deinterlace deinterlace,
    @Default(0) double sharpen,
    @Default(0) double brightness,
    @Default(0) double contrast,
    @Default(0) double saturation,
    @Default(0) double gamma,
    @Default(0) double hue,

    /// Clockwise degrees: 0, 90, 180, 270.
    @Default(0) int rotate,
    @Default(false) bool flipHorizontal,
    @Default(false) bool flipVertical,

    /// e.g. 16/9; null keeps the container aspect.
    double? aspectOverride,
    @Default(0) double zoom,
    @Default(0) double panX,
    @Default(0) double panY,
    @Default(false) bool interpolation,
  }) = _VideoFilterChain;
}

/// Built-in user-shader presets and custom GLSL (VID-038).
@freezed
abstract class ShaderPreset with _$ShaderPreset {
  const factory ShaderPreset({
    required String id,
    @Default(<Uri>[]) List<Uri> shaders,
  }) = _ShaderPreset;

  static const none = ShaderPreset(id: 'none');
}

enum EqBandType { peaking, lowShelf, highShelf, lowPass, highPass, notch }

@freezed
abstract class EqBand with _$EqBand {
  const factory EqBand({
    required EqBandType type,
    required double frequencyHz,
    required double gainDb,
    @Default(0.707) double q,
  }) = _EqBand;
}

enum LoudnessMode { off, replayGainTrack, replayGainAlbum, ebuR128 }

/// Audio DSP chain (AUD-004, AUD-005, POD-001 skip silence).
@freezed
abstract class AudioDspChain with _$AudioDspChain {
  const factory AudioDspChain({
    /// 10-band graphic EQ gains in dB (31 Hz … 16 kHz), empty when off.
    @Default(<double>[]) List<double> graphicEq,

    /// Up to 32 parametric biquads.
    @Default(<EqBand>[]) List<EqBand> parametricEq,
    @Default(0) double preampDb,
    @Default(LoudnessMode.off) LoudnessMode loudness,
    @Default(-18) double r128TargetLufs,
    @Default(true) bool clippingPrevention,
    @Default(false) bool limiter,
    @Default(0) double balance,
    @Default(false) bool mono,
    @Default(false) bool crossfeed,
    @Default(0) double bassDb,
    @Default(0) double trebleDb,
    @Default(1) double pitch,
    @Default(false) bool skipSilence,

    /// Channel mixer: one row per output channel, one gain per input channel
    /// (AUD-005). Empty keeps the layout.
    @Default(<List<double>>[]) List<List<double>> channelMatrix,
  }) = _AudioDspChain;
}

/// Post-conversion low-pass for DSD played as PCM (AUD-043).
enum DsdFilter {
  /// 24 kHz cutoff, the common DAC default.
  standard,

  /// 20 kHz steep cutoff.
  sharp,

  /// 30 kHz gentle cutoff for high-rate PCM.
  slow,
}

/// Output device selection and exclusivity (VID-004, AUD-040…043).
@freezed
abstract class AudioOutputConfig with _$AudioOutputConfig {
  const factory AudioOutputConfig({
    /// Engine device id; null = system default.
    String? deviceId,
    @Default(false) bool exclusive,
    @Default(<String>[]) List<String> passthroughCodecs,
    @Default(false) bool nativeDsd,

    /// Low-pass applied after DSD→PCM conversion (AUD-043).
    @Default(DsdFilter.standard) DsdFilter dsdFilter,

    /// Switch the device to the source sample rate when exclusive
    /// (AUD-040…042).
    @Default(true) bool matchSampleRate,

    /// Extra output latency compensation, e.g. Bluetooth A/V sync (AUD-044).
    @Default(Duration.zero) Duration latencyOffset,
  }) = _AudioOutputConfig;
}

/// Subtitle rendering style (SUB-014). Null fields follow the system caption
/// preferences.
@freezed
abstract class SubtitleStyle with _$SubtitleStyle {
  const factory SubtitleStyle({
    String? font,
    double? scale,
    int? colorArgb,
    int? outlineColorArgb,
    double? outlineWidth,
    double? shadowOffset,
    int? backgroundArgb,

    /// 0 = bottom, 100 = top.
    double? verticalPosition,
    @Default(false) bool overrideAssStyles,

    /// Horizontal alignment and margins (SUB-014).
    SubtitleAlignX? alignX,
    double? marginX,
    double? marginY,
    @Default(SubtitleBorderStyle.outlineAndShadow)
    SubtitleBorderStyle borderStyle,
  }) = _SubtitleStyle;
}

enum SubtitleAlignX { left, center, right }

enum SubtitleBorderStyle { outlineAndShadow, opaqueBox, backgroundBox }

/// Track transition rules for the music role (AUD-002, AUD-003).
@freezed
abstract class TransitionConfig with _$TransitionConfig {
  const factory TransitionConfig({
    /// Crossfade on natural track end, 0–12 s; zero means gapless.
    @Default(Duration.zero) Duration naturalEnd,

    /// Crossfade on a manual skip, 0–12 s.
    @Default(Duration.zero) Duration manualSkip,

    /// Crossfade even between consecutive tracks of a gapless album (opt-in).
    @Default(false) bool crossfadeGaplessAlbums,
  }) = _TransitionConfig;
}
