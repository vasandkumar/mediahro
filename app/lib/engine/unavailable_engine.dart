import 'dart:async';
import 'dart:typed_data';

import 'package:mediahro_engine/mediahro_engine.dart';

/// [PlaybackEngine] used when the native engine is not linked. Every call
/// resolves and the state reports [EngineErrorCode.libraryMissing], so the
/// UI shows actionable copy instead of crashing (CORE-011).
final class UnavailableEngine implements PlaybackEngine {
  UnavailableEngine(this.role);

  @override
  final EngineRole role;

  static const _missing = PlaybackState(
    status: PlaybackStatus.error,
    error: EngineError(
      code: EngineErrorCode.libraryMissing,
      detail: 'libmpv not bundled in this build',
    ),
  );

  @override
  PlaybackState get current => _missing;

  @override
  Stream<PlaybackState> get state => Stream.value(_missing);

  @override
  int? get textureId => null;

  @override
  Future<void> open(MediaSource src, {OpenOptions? opts}) async {}
  @override
  Future<void> play() async {}
  @override
  Future<void> pause() async {}
  @override
  Future<void> stop() async {}
  @override
  Future<void> seek(
    Duration position, {
    SeekMode mode = SeekMode.keyframe,
  }) async {}
  @override
  Future<void> frameStep({bool backwards = false}) async {}
  @override
  Future<void> setRate(double rate) async {}
  @override
  Future<void> setVolume(double volume) async {}
  @override
  Future<void> setMuted({required bool muted}) async {}
  @override
  Future<void> setAudioDelay(Duration delay) async {}
  @override
  Future<void> setSubDelay(
    Duration delay, {
    SubtitleSlot slot = SubtitleSlot.primary,
  }) async {}
  @override
  Future<void> selectTrack(
    TrackType type,
    int? id, {
    SubtitleSlot slot = SubtitleSlot.primary,
  }) async {}
  @override
  Future<void> addExternalTrack(
    TrackType type,
    Uri uri, {
    String? title,
    String? language,
  }) async {}
  @override
  Future<void> setVideoFilters(VideoFilterChain chain) async {}
  @override
  Future<void> setShaderPreset(ShaderPreset preset) async {}
  @override
  Future<void> setAudioDsp(AudioDspChain chain) async {}
  @override
  Future<void> setAudioOutput(AudioOutputConfig config) async {}
  @override
  Future<void> setSubtitleStyle(
    SubtitleStyle style, {
    SubtitleSlot slot = SubtitleSlot.primary,
  }) async {}
  @override
  Future<void> setSubtitleCodepage(String? codepage) async {}
  @override
  Future<void> setSubSpeed(double speed) async {}
  @override
  Future<void> setNext(MediaSource? next, {bool sameAlbum = false}) async {}
  @override
  Future<void> skipToNext() async {}
  @override
  Future<void> setTransition(TransitionConfig config) async {}
  @override
  Future<void> setAbLoop(Duration? a, Duration? b, {int? count}) async {}
  @override
  Future<Uint8List> screenshot({
    bool subtitles = true,
    ScreenshotFormat format = ScreenshotFormat.png,
  }) => Future.error(
    const EngineException(EngineError(code: EngineErrorCode.libraryMissing)),
  );
  @override
  Future<void> export(
    Duration start,
    Duration end,
    ExportFormat format,
    Uri out, {
    bool subtitles = false,
  }) => Future.error(
    const EngineException(EngineError(code: EngineErrorCode.libraryMissing)),
  );
  @override
  Future<void> setVideoTarget(VideoTarget target) async {}
  @override
  Future<void> setDucking(double gain) async {}
  @override
  Future<List<EngineAudioDevice>> audioDevices() async => const [];
  @override
  Stream<AudioTapFrame> audioTap({int frames = 1024}) => const Stream.empty();
  @override
  Future<void> extractSubtitles(int trackId, Uri out) => Future.error(
    const EngineException(EngineError(code: EngineErrorCode.libraryMissing)),
  );
  @override
  Stream<Float32List> decodeAudio(
    MediaSource source, {
    int? trackId,
    int sampleRate = 16000,
    bool mono = true,
    Duration? start,
    Duration? end,
  }) => Stream.error(
    const EngineException(EngineError(code: EngineErrorCode.libraryMissing)),
  );
  @override
  Future<void> dispose() async {}
}
