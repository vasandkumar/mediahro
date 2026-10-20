import 'dart:async';
import 'dart:typed_data';

import 'package:mediahro_engine/mediahro_engine.dart';
import 'package:mediahro_engine/testing.dart';

/// [FakePlaybackEngine] plus the arguments lane C1 asserts on (seek modes,
/// rates, open options). Shared by C1's widget and integration tests.
final class RecordingEngine implements PlaybackEngine {
  RecordingEngine({
    Duration mediaDuration = const Duration(minutes: 90),
    List<Track>? tracks,
  }) : fake = tracks == null
           ? FakePlaybackEngine(mediaDuration: mediaDuration)
           : FakePlaybackEngine(
               mediaDuration: mediaDuration,
               mediaTracks: tracks,
             );

  final FakePlaybackEngine fake;
  final List<(Duration, SeekMode)> seeks = [];
  final List<double> rates = [];
  final List<OpenOptions?> opens = [];
  final List<(TrackType, int?, SubtitleSlot)> selections = [];
  final List<Duration> audioDelays = [];
  final List<(Duration, SubtitleSlot)> subDelays = [];
  final List<double> volumes = [];
  final List<VideoFilterChain> filterChains = [];
  final List<ShaderPreset> shaderPresets = [];
  final List<(SubtitleStyle, SubtitleSlot)> styles = [];
  final List<(TrackType, Uri)> externalTracks = [];

  PlaybackState? _injected;
  final _extra = StreamController<PlaybackState>.broadcast();

  /// Emits [s] as the engine state (chapters, tracks, stats, errors) until
  /// the fake emits again.
  void emit(PlaybackState s) {
    _injected = s;
    _extra.add(s);
  }

  List<String> get calls => fake.calls;

  @override
  EngineRole get role => fake.role;

  @override
  PlaybackState get current => _injected ?? fake.current;

  @override
  Stream<PlaybackState> get state => Stream.multi((l) {
    final a = fake.state.listen((s) {
      _injected = null;
      l.add(s);
    });
    final b = _extra.stream.listen(l.add);
    l.onCancel = () async {
      await a.cancel();
      await b.cancel();
    };
  });

  @override
  int? get textureId => fake.textureId;

  @override
  Future<void> open(MediaSource src, {OpenOptions? opts}) {
    opens.add(opts);
    return fake.open(src, opts: opts);
  }

  @override
  Future<void> play() => fake.play();

  @override
  Future<void> pause() => fake.pause();

  @override
  Future<void> stop() => fake.stop();

  @override
  Future<void> seek(Duration position, {SeekMode mode = SeekMode.keyframe}) {
    seeks.add((position, mode));
    return fake.seek(position, mode: mode);
  }

  @override
  Future<void> frameStep({bool backwards = false}) =>
      fake.frameStep(backwards: backwards);

  @override
  Future<void> setRate(double rate) {
    rates.add(rate);
    return fake.setRate(rate);
  }

  @override
  Future<void> setVolume(double volume) {
    volumes.add(volume);
    return fake.setVolume(volume);
  }

  @override
  Future<void> setMuted({required bool muted}) => fake.setMuted(muted: muted);

  @override
  Future<void> setAudioDelay(Duration delay) {
    audioDelays.add(delay);
    return fake.setAudioDelay(delay);
  }

  @override
  Future<void> setSubDelay(
    Duration delay, {
    SubtitleSlot slot = SubtitleSlot.primary,
  }) {
    subDelays.add((delay, slot));
    return fake.setSubDelay(delay, slot: slot);
  }

  @override
  Future<void> selectTrack(
    TrackType type,
    int? id, {
    SubtitleSlot slot = SubtitleSlot.primary,
  }) {
    selections.add((type, id, slot));
    return fake.selectTrack(type, id, slot: slot);
  }

  @override
  Future<void> addExternalTrack(
    TrackType type,
    Uri uri, {
    String? title,
    String? language,
  }) {
    externalTracks.add((type, uri));
    return fake.addExternalTrack(type, uri, title: title, language: language);
  }

  @override
  Future<void> setVideoFilters(VideoFilterChain chain) {
    filterChains.add(chain);
    return fake.setVideoFilters(chain);
  }

  @override
  Future<void> setShaderPreset(ShaderPreset preset) {
    shaderPresets.add(preset);
    return fake.setShaderPreset(preset);
  }

  @override
  Future<void> setAudioDsp(AudioDspChain chain) => fake.setAudioDsp(chain);

  @override
  Future<void> setAudioOutput(AudioOutputConfig config) =>
      fake.setAudioOutput(config);

  @override
  Future<void> setSubtitleStyle(
    SubtitleStyle style, {
    SubtitleSlot slot = SubtitleSlot.primary,
  }) {
    styles.add((style, slot));
    return fake.setSubtitleStyle(style, slot: slot);
  }

  @override
  Future<void> setSubtitleCodepage(String? codepage) =>
      fake.setSubtitleCodepage(codepage);

  @override
  Future<void> setSubSpeed(double speed) => fake.setSubSpeed(speed);

  @override
  Future<void> setNext(MediaSource? next, {bool sameAlbum = false}) =>
      fake.setNext(next, sameAlbum: sameAlbum);

  @override
  Future<void> skipToNext() => fake.skipToNext();

  @override
  Future<void> setTransition(TransitionConfig config) =>
      fake.setTransition(config);

  @override
  Future<void> setAbLoop(Duration? a, Duration? b, {int? count}) =>
      fake.setAbLoop(a, b, count: count);

  @override
  Future<Uint8List> screenshot({
    bool subtitles = true,
    ScreenshotFormat format = ScreenshotFormat.png,
  }) => fake.screenshot(subtitles: subtitles, format: format);

  @override
  Future<void> export(
    Duration start,
    Duration end,
    ExportFormat format,
    Uri out, {
    bool subtitles = false,
  }) => fake.export(start, end, format, out, subtitles: subtitles);

  @override
  Future<void> setVideoTarget(VideoTarget target) =>
      fake.setVideoTarget(target);

  @override
  Future<void> setDucking(double gain) => fake.setDucking(gain);

  @override
  Future<List<EngineAudioDevice>> audioDevices() => fake.audioDevices();

  @override
  Stream<AudioTapFrame> audioTap({int frames = 1024}) =>
      fake.audioTap(frames: frames);

  @override
  Stream<Float32List> decodeAudio(
    MediaSource source, {
    int? trackId,
    int sampleRate = 16000,
    bool mono = true,
    Duration? start,
    Duration? end,
  }) => fake.decodeAudio(
    source,
    trackId: trackId,
    sampleRate: sampleRate,
    mono: mono,
    start: start,
    end: end,
  );

  @override
  Future<void> dispose() async {
    await _extra.close();
    await fake.dispose();
  }
}
