import 'dart:typed_data';

import 'package:mediahro_engine/src/api/media_source.dart';
import 'package:mediahro_engine/src/api/models.dart';

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

  /// A-B loop (VID-063); both null clears it.
  Future<void> setAbLoop(Duration? a, Duration? b, {int? count});

  /// Encoded still of the current frame (VID-042).
  Future<Uint8List> screenshot({
    bool subtitles = true,
    ScreenshotFormat format = ScreenshotFormat.png,
  });

  /// Flutter external texture id for the video surface; null for the music
  /// role or before the first frame.
  int? get textureId;

  Future<void> dispose();
}

/// Creates engines for the app's engine pool and the SDK.
typedef PlaybackEngineFactory = PlaybackEngine Function(EngineRole role);
