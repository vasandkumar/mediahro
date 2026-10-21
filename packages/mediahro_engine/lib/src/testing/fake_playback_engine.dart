import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:mediahro_engine/src/api/audio_tap.dart';
import 'package:mediahro_engine/src/api/media_source.dart';
import 'package:mediahro_engine/src/api/models.dart';
import 'package:mediahro_engine/src/api/playback_engine.dart';
import 'package:mediahro_engine/src/api/subtitle_image.dart';
import 'package:mediahro_engine/src/api/video_target.dart';

/// Deterministic in-memory [PlaybackEngine] for widget and integration tests
/// of feature lanes before (and alongside) `MpvEngine`.
///
/// Time does not advance on its own; call [advance] to move the clock.
final class FakePlaybackEngine implements PlaybackEngine {
  FakePlaybackEngine({
    this.role = EngineRole.video,
    this.mediaDuration = const Duration(minutes: 90),
    this.mediaTracks = const [
      Track(
        id: 1,
        type: TrackType.video,
        codec: 'hevc',
        width: 3840,
        height: 2160,
        fps: 23.976,
      ),
      Track(
        id: 1,
        type: TrackType.audio,
        codec: 'aac',
        channels: 2,
        language: 'en',
        isDefault: true,
      ),
      Track(id: 1, type: TrackType.subtitle, codec: 'ass', language: 'en'),
    ],
  });

  @override
  final EngineRole role;
  final Duration mediaDuration;
  final List<Track> mediaTracks;

  /// Every call in order, for assertions: `['open', 'seek', ...]`.
  final List<String> calls = [];
  MediaSource? openedSource;
  VideoFilterChain filters = const VideoFilterChain();
  ShaderPreset shaderPreset = ShaderPreset.none;
  AudioDspChain dsp = const AudioDspChain();
  AudioOutputConfig output = const AudioOutputConfig();
  (Duration?, Duration?, int?) abLoop = (null, null, null);
  double subSpeed = 1;
  MediaSource? nextSource;
  TransitionConfig transition = const TransitionConfig();

  final _controller = StreamController<PlaybackState>.broadcast();
  PlaybackState _state = const PlaybackState();
  bool _disposed = false;

  @override
  PlaybackState get current => _state;

  @override
  Stream<PlaybackState> get state => Stream.multi((listener) {
    // Replays the current snapshot and forwards later ones without a gap
    // between listen and the first event.
    listener.add(_state);
    final sub = _controller.stream.listen(
      listener.add,
      onError: listener.addError,
      onDone: listener.close,
    );
    listener.onCancel = sub.cancel;
  });

  void _emit(PlaybackState s) {
    _state = s;
    if (!_controller.isClosed) _controller.add(s);
  }

  void _check(String call) {
    if (_disposed) throw StateError('FakePlaybackEngine used after dispose');
    calls.add(call);
  }

  /// Advances playback time when playing; ends at [mediaDuration].
  void advance(Duration by) {
    if (_state.status != PlaybackStatus.playing) return;
    final next = _state.position + by * _state.rate;
    if (next >= mediaDuration) {
      _emit(
        _state.copyWith(position: mediaDuration, status: PlaybackStatus.ended),
      );
    } else {
      _emit(_state.copyWith(position: next));
    }
  }

  /// Simulates an engine fault (CORE-011 isolation tests).
  void fail(EngineErrorCode code) => _emit(
    _state.copyWith(
      status: PlaybackStatus.error,
      error: EngineError(code: code),
    ),
  );

  @override
  Future<void> open(MediaSource src, {OpenOptions? opts}) async {
    _check('open');
    final o = opts ?? const OpenOptions();
    openedSource = src;
    final tracks = o.audioOnly
        ? mediaTracks.where((t) => t.type != TrackType.video).toList()
        : mediaTracks;
    int? first(TrackType t) =>
        tracks.where((x) => x.type == t).map((x) => x.id).firstOrNull;
    _emit(
      PlaybackState(
        status: o.autoplay ? PlaybackStatus.playing : PlaybackStatus.paused,
        position: o.start ?? Duration.zero,
        duration: mediaDuration,
        tracks: tracks,
        videoTrackId: first(TrackType.video),
        audioTrackId: first(TrackType.audio),
        volume: _state.volume,
        muted: _state.muted,
        ducked: _state.ducked,
      ),
    );
  }

  @override
  Future<void> play() async {
    _check('play');
    if (_state.status case PlaybackStatus.paused || PlaybackStatus.ended) {
      _emit(_state.copyWith(status: PlaybackStatus.playing));
    }
  }

  @override
  Future<void> pause() async {
    _check('pause');
    if (_state.status == PlaybackStatus.playing) {
      _emit(_state.copyWith(status: PlaybackStatus.paused));
    }
  }

  @override
  Future<void> stop() async {
    _check('stop');
    openedSource = null;
    _emit(
      PlaybackState(
        volume: _state.volume,
        muted: _state.muted,
        ducked: _state.ducked,
      ),
    );
  }

  @override
  Future<void> seek(
    Duration position, {
    SeekMode mode = SeekMode.keyframe,
  }) async {
    _check('seek');
    final target = mode == SeekMode.relative
        ? _state.position + position
        : position;
    final clamped = target < Duration.zero
        ? Duration.zero
        : (target > mediaDuration ? mediaDuration : target);
    _emit(_state.copyWith(position: clamped));
  }

  @override
  Future<void> frameStep({bool backwards = false}) async {
    _check('frameStep');
    final fps =
        _state.tracks
            .where((t) => t.type == TrackType.video)
            .firstOrNull
            ?.fps ??
        24;
    final frame = Duration(microseconds: (1e6 / fps).round());
    _emit(
      _state.copyWith(
        status: PlaybackStatus.paused,
        position: backwards ? _state.position - frame : _state.position + frame,
      ),
    );
  }

  @override
  Future<void> setRate(double rate) async {
    _check('setRate');
    if (rate < 0.25 || rate > 4.0) {
      throw const EngineException(
        EngineError(
          code: EngineErrorCode.invalidArgument,
          detail: 'rate out of 0.25–4.0',
        ),
      );
    }
    _emit(_state.copyWith(rate: rate));
  }

  @override
  Future<void> setVolume(double volume) async {
    _check('setVolume');
    _emit(_state.copyWith(volume: volume.clamp(0, 3)));
  }

  @override
  Future<void> setMuted({required bool muted}) async {
    _check('setMuted');
    _emit(_state.copyWith(muted: muted));
  }

  @override
  Future<void> setAudioDelay(Duration delay) async {
    _check('setAudioDelay');
    _emit(_state.copyWith(audioDelay: delay));
  }

  @override
  Future<void> setSubDelay(
    Duration delay, {
    SubtitleSlot slot = SubtitleSlot.primary,
  }) async {
    _check('setSubDelay');
    _emit(_state.copyWith(subtitleDelay: delay));
  }

  @override
  Future<void> selectTrack(
    TrackType type,
    int? id, {
    SubtitleSlot slot = SubtitleSlot.primary,
  }) async {
    _check('selectTrack');
    _emit(switch (type) {
      TrackType.video => _state.copyWith(videoTrackId: id),
      TrackType.audio => _state.copyWith(audioTrackId: id),
      TrackType.subtitle when slot == SubtitleSlot.secondary => _state.copyWith(
        secondarySubtitleTrackId: id,
      ),
      TrackType.subtitle => _state.copyWith(subtitleTrackId: id),
    });
  }

  @override
  Future<void> addExternalTrack(
    TrackType type,
    Uri uri, {
    String? title,
    String? language,
  }) async {
    _check('addExternalTrack');
    final id = _state.tracks.where((t) => t.type == type).length + 1;
    _emit(
      _state.copyWith(
        tracks: [
          ..._state.tracks,
          Track(
            id: id,
            type: type,
            title: title,
            language: language,
            isExternal: true,
          ),
        ],
      ),
    );
  }

  @override
  Future<void> setVideoFilters(VideoFilterChain chain) async {
    _check('setVideoFilters');
    filters = chain;
  }

  @override
  Future<void> setShaderPreset(ShaderPreset preset) async {
    _check('setShaderPreset');
    shaderPreset = preset;
  }

  @override
  Future<void> setAudioDsp(AudioDspChain chain) async {
    _check('setAudioDsp');
    dsp = chain;
  }

  @override
  Future<void> setAudioOutput(AudioOutputConfig config) async {
    _check('setAudioOutput');
    output = config;
  }

  @override
  Future<void> setSubtitleStyle(
    SubtitleStyle style, {
    SubtitleSlot slot = SubtitleSlot.primary,
  }) async {
    _check('setSubtitleStyle');
  }

  String? subtitleCodepage;

  @override
  Future<void> setSubtitleCodepage(String? codepage) async {
    _check('setSubtitleCodepage');
    subtitleCodepage = codepage;
  }

  @override
  Future<void> setSubSpeed(double speed) async {
    _check('setSubSpeed');
    subSpeed = speed;
  }

  @override
  Future<void> setNext(MediaSource? next, {bool sameAlbum = false}) async {
    _check('setNext');
    nextSource = next;
    _emit(_state.copyWith(nextPrepared: next != null));
  }

  @override
  Future<void> skipToNext() async {
    _check('skipToNext');
    final next = nextSource;
    if (next == null) return;
    nextSource = null;
    await open(next);
    calls.removeLast();
  }

  @override
  Future<void> setTransition(TransitionConfig config) async {
    _check('setTransition');
    transition = config;
  }

  @override
  Future<void> setAbLoop(Duration? a, Duration? b, {int? count}) async {
    _check('setAbLoop');
    abLoop = (a, b, count);
  }

  @override
  Future<Uint8List> screenshot({
    bool subtitles = true,
    ScreenshotFormat format = ScreenshotFormat.png,
  }) async {
    _check('screenshot');
    // Smallest valid PNG signature + IHDR is not needed by callers; return a marker.
    return Uint8List.fromList(const [0x89, 0x50, 0x4E, 0x47]);
  }

  /// Last target passed to [setVideoTarget].
  VideoTarget videoTarget = const VideoTarget.texture();

  /// Audio devices [audioDevices] returns (tests set them).
  List<EngineAudioDevice> devices = const [
    EngineAudioDevice(id: 'auto', name: 'Default', isDefault: true),
  ];

  /// Exports requested through [export], as (start, end, format, out).
  final List<(Duration, Duration, ExportFormat, Uri)> exports = [];

  @override
  Future<void> export(
    Duration start,
    Duration end,
    ExportFormat format,
    Uri out, {
    bool subtitles = false,
  }) async {
    _check('export');
    if (openedSource == null || end <= start) {
      throw const EngineException(
        EngineError(code: EngineErrorCode.invalidArgument),
      );
    }
    exports.add((start, end, format, out));
  }

  @override
  Future<void> setVideoTarget(VideoTarget target) async {
    _check('setVideoTarget');
    videoTarget = target;
  }

  @override
  Future<void> setDucking(double gain) async {
    _check('setDucking');
    _emit(_state.copyWith(ducked: gain < 1));
  }

  @override
  Future<void> audioRouteChanged() async {
    _check('audioRouteChanged');
  }

  final _tap = StreamController<AudioTapFrame>.broadcast();

  /// Emits [frame] to [audioTap] listeners (tests drive visualisers).
  void emitTap(AudioTapFrame frame) => _tap.add(frame);

  /// Whether anything listens to [audioTap].
  bool get tapListened => _tap.hasListener;

  @override
  Stream<AudioTapFrame> audioTap({int frames = 1024}) => _tap.stream;

  /// What [decodeAudio] was asked for, in order.
  final List<
    ({
      MediaSource source,
      int? trackId,
      int sampleRate,
      bool mono,
      Duration? start,
      Duration? end,
    })
  >
  decodeRequests = [];

  /// When set, [decodeAudio] fails with it (e.g. an [EngineException]).
  Exception? decodeAudioError;

  /// The PCM [decodeAudio] returns, in the rate and layout the test
  /// will request; `start` and `end` cut it (ADR-032).
  Float32List decodedAudio = Float32List(0);

  /// What [extractSubtitleImages] streams (ADR-031 part 2).
  List<SubtitleImage> extractedSubtitleImages = [];

  @override
  Stream<SubtitleImage> extractSubtitleImages(int trackId) async* {
    _check('extractSubtitleImages');
    final track = _state.tracks
        .where((t) => t.type == TrackType.subtitle && t.id == trackId)
        .firstOrNull;
    if (openedSource == null || track == null) {
      throw const EngineException(
        EngineError(code: EngineErrorCode.invalidArgument),
      );
    }
    if (!const {
      'hdmv_pgs_subtitle',
      'dvd_subtitle',
      'dvb_subtitle',
    }.contains(track.codec)) {
      throw const EngineException(
        EngineError(code: EngineErrorCode.notSupported),
      );
    }
    yield* Stream.fromIterable(extractedSubtitleImages);
  }

  /// What [extractSubtitles] writes (ADR-031); tests set the file content.
  String extractedSubtitles = '1\n00:00:01,000 --> 00:00:02,000\nHello\n';

  @override
  Future<void> extractSubtitles(int trackId, Uri out) async {
    _check('extractSubtitles');
    final track = _state.tracks
        .where((t) => t.type == TrackType.subtitle && t.id == trackId)
        .firstOrNull;
    if (openedSource == null || track == null) {
      throw const EngineException(
        EngineError(code: EngineErrorCode.invalidArgument),
      );
    }
    if (const {
      'hdmv_pgs_subtitle',
      'dvd_subtitle',
      'dvb_subtitle',
    }.contains(track.codec)) {
      throw const EngineException(
        EngineError(code: EngineErrorCode.notSupported),
      );
    }
    await File(out.toFilePath()).writeAsString(extractedSubtitles);
  }

  /// Sets what [PlaybackState.subtitleText] reports, as a cue change would
  /// (ADR-031).
  void setSubtitleText(String? text) =>
      _emit(_state.copyWith(subtitleText: text));

  @override
  Stream<Float32List> decodeAudio(
    MediaSource source, {
    int? trackId,
    int sampleRate = 16000,
    bool mono = true,
    Duration? start,
    Duration? end,
  }) async* {
    _check('decodeAudio');
    decodeRequests.add((
      source: source,
      trackId: trackId,
      sampleRate: sampleRate,
      mono: mono,
      start: start,
      end: end,
    ));
    final error = decodeAudioError;
    if (error != null) throw error;
    final channels = mono ? 1 : 2;
    int at(Duration? d, int fallback) => d == null
        ? fallback
        : (d.inMicroseconds * sampleRate ~/ 1000000 * channels).clamp(
            0,
            decodedAudio.length,
          );
    final from = at(start, 0);
    final to = at(end, decodedAudio.length);
    final chunk = sampleRate ~/ 2 * channels;
    for (var i = from; i < to; i += chunk) {
      yield Float32List.fromList(
        decodedAudio.sublist(i, i + chunk < to ? i + chunk : to),
      );
    }
  }

  /// Sets what [PlaybackState.mediaTitle] / [PlaybackState.mediaMetadata]
  /// report, as an ICY or HLS ID3 update would (MUS-014).
  void setMediaMetadata(String? title, Map<String, String> metadata) =>
      _emit(_state.copyWith(mediaTitle: title, mediaMetadata: metadata));

  @override
  Future<List<EngineAudioDevice>> audioDevices() async {
    _check('audioDevices');
    return devices;
  }

  @override
  int? get textureId =>
      role == EngineRole.video && openedSource != null ? 1 : null;

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    calls.add('dispose');
    _disposed = true;
    await _controller.close();
    await _tap.close();
  }
}
