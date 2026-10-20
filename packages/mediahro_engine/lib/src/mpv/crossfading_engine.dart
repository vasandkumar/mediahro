import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:mediahro_engine/src/api/media_source.dart';
import 'package:mediahro_engine/src/api/models.dart';
import 'package:mediahro_engine/src/api/playback_engine.dart';
import 'package:mediahro_engine/src/api/video_target.dart';

/// Music-role engine with crossfades (AUD-003) over two cores.
///
/// Gapless transitions (no crossfade configured, or consecutive tracks of a
/// gapless album unless [TransitionConfig.crossfadeGaplessAlbums]) stay on
/// the active core's sample-accurate gapless path (AUD-002). Crossfades
/// preload the next item paused on the standby core, start it at the fade
/// point and ramp both with an equal-power curve, then swap cores.
final class CrossfadingEngine implements PlaybackEngine {
  CrossfadingEngine(
    PlaybackEngine Function() create, {
    this.fadeStep = const Duration(milliseconds: 40),
  }) : _a = create(),
       _create = create;

  final PlaybackEngine Function() _create;
  final Duration fadeStep;

  PlaybackEngine _a;
  PlaybackEngine? _b;
  PlaybackEngine get _standby => _b ??= _create();

  final _controller = StreamController<PlaybackState>.broadcast();
  StreamSubscription<PlaybackState>? _sub;
  PlaybackState _state = const PlaybackState();
  TransitionConfig _transition = const TransitionConfig();
  double _volume = 1;
  // Audio-focus ducking (AUD-045), applied to both cores.
  double _duck = 1;
  MediaSource? _next;
  var _sameAlbum = false;
  var _standbyReady = false;
  var _fading = false;
  var _item = 0;
  var _disposed = false;

  @override
  EngineRole get role => EngineRole.music;

  /// True while a crossfade runs (tests, UI).
  bool get fading => _fading;

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

  @override
  int? get textureId => null;

  bool get _crossfadeNext =>
      _next != null &&
      !(_sameAlbum && !_transition.crossfadeGaplessAlbums) &&
      (_transition.naturalEnd > Duration.zero ||
          _transition.manualSkip > Duration.zero);

  void _follow(PlaybackEngine e) {
    unawaited(_sub?.cancel());
    var lastItem = e.current.item;
    _sub = e.state.listen((s) {
      if (s.item != lastItem) {
        lastItem = s.item;
        // A native gapless advance on the active core (not an open()).
        if (!_fading && _next != null && !_standbyReady) {
          _item++;
          _next = null;
        }
      }
      // The outgoing core ends or stops during a fade; listeners keep
      // seeing one continuous, playing stream.
      _publish(
        _fading && identical(e, _a)
            ? s.copyWith(status: PlaybackStatus.playing)
            : s,
      );
      _maybeStartNaturalFade(s);
    });
  }

  void _publish(PlaybackState s) {
    _state = s.copyWith(
      item: _item,
      volume: _volume,
      ducked: _duck < 1,
      nextPrepared: _next != null && (_standbyReady || s.nextPrepared),
    );
    if (!_controller.isClosed) _controller.add(_state);
  }

  void _maybeStartNaturalFade(PlaybackState s) {
    if (_fading || !_crossfadeNext || !_standbyReady) return;
    final d = s.duration;
    if (d == null || _transition.naturalEnd <= Duration.zero) return;
    // A fade never takes more than half of the outgoing track.
    final fade = _transition.naturalEnd < d ~/ 2
        ? _transition.naturalEnd
        : d ~/ 2;
    if (s.status == PlaybackStatus.playing && s.position >= d - fade) {
      unawaited(_crossfade(fade));
    }
  }

  Future<void> _crossfade(Duration length) async {
    if (_fading) return;
    _fading = true;
    final from = _a;
    final to = _standby;
    try {
      await to.setVolume(0);
      await to.play();
      // Time-based so the fade lasts [length] however long each volume
      // update takes.
      final clock = Stopwatch()..start();
      while (!_disposed) {
        final x = math.min(
          1,
          clock.elapsedMicroseconds / math.max(1, length.inMicroseconds),
        );
        // Equal-power curve keeps perceived loudness constant.
        await from.setVolume(_volume * math.cos(x * math.pi / 2));
        await to.setVolume(_volume * math.sin(x * math.pi / 2));
        if (x >= 1) break;
        await Future<void>.delayed(fadeStep);
      }
      await from.stop();
      await from.setVolume(_volume);
      _a = to;
      _b = from;
      _standbyReady = false;
      _next = null;
      _item++;
      _follow(_a);
      _publish(_a.current);
    } finally {
      _fading = false;
    }
  }

  Future<void> _ensure() async {
    if (_disposed) throw StateError('CrossfadingEngine used after dispose');
    if (_sub == null) _follow(_a);
  }

  @override
  Future<void> open(MediaSource src, {OpenOptions? opts}) async {
    await _ensure();
    _next = null;
    _standbyReady = false;
    if (_b != null) await _b!.stop();
    _item++;
    await _a.open(src, opts: opts);
  }

  @override
  Future<void> setNext(MediaSource? next, {bool sameAlbum = false}) async {
    await _ensure();
    _next = next;
    _sameAlbum = sameAlbum;
    _standbyReady = false;
    if (next == null) {
      await _a.setNext(null);
      if (_b != null) await _b!.stop();
    } else if (_crossfadeNext) {
      await _a.setNext(null);
      await _standby.setDucking(_duck);
      await _standby.open(next, opts: const OpenOptions(autoplay: false));
      _standbyReady = true;
    } else {
      await _a.setNext(next, sameAlbum: sameAlbum);
    }
    _publish(_a.current);
  }

  @override
  Future<void> skipToNext() async {
    await _ensure();
    if (_next == null) return;
    if (_standbyReady) {
      final fade = _transition.manualSkip;
      if (fade > Duration.zero) {
        await _crossfade(fade);
      } else {
        await _crossfade(fadeStep);
      }
    } else {
      await _a.skipToNext();
    }
  }

  @override
  Future<void> setTransition(TransitionConfig config) async {
    await _ensure();
    TransitionConfig clamp12(TransitionConfig c) {
      Duration cap(Duration d) => d > const Duration(seconds: 12)
          ? const Duration(seconds: 12)
          : (d < Duration.zero ? Duration.zero : d);
      return c.copyWith(
        naturalEnd: cap(c.naturalEnd),
        manualSkip: cap(c.manualSkip),
      );
    }

    _transition = clamp12(config);
    final next = _next;
    if (next != null) await setNext(next, sameAlbum: _sameAlbum);
  }

  /// Applies [f] to both cores so the standby matches the active one.
  Future<void> _both(Future<void> Function(PlaybackEngine e) f) async {
    await _ensure();
    await f(_a);
    final b = _b;
    if (b != null) await f(b);
  }

  @override
  Future<void> play() async {
    await _ensure();
    await _a.play();
  }

  @override
  Future<void> pause() async {
    await _ensure();
    await _a.pause();
    if (_fading) await _b?.pause();
  }

  @override
  Future<void> stop() async {
    await _ensure();
    _next = null;
    _standbyReady = false;
    await _a.stop();
    await _b?.stop();
  }

  @override
  Future<void> seek(
    Duration position, {
    SeekMode mode = SeekMode.keyframe,
  }) async {
    await _ensure();
    await _a.seek(position, mode: mode);
  }

  @override
  Future<void> frameStep({bool backwards = false}) async {
    await _ensure();
    await _a.frameStep(backwards: backwards);
  }

  @override
  Future<void> setRate(double rate) => _both((e) => e.setRate(rate));

  @override
  Future<void> setVolume(double volume) async {
    _volume = volume.clamp(0, 3);
    await _ensure();
    if (!_fading) await _a.setVolume(_volume);
    _publish(_a.current);
  }

  @override
  Future<void> setMuted({required bool muted}) =>
      _both((e) => e.setMuted(muted: muted));

  @override
  Future<void> setAudioDelay(Duration delay) =>
      _both((e) => e.setAudioDelay(delay));

  @override
  Future<void> setSubDelay(
    Duration delay, {
    SubtitleSlot slot = SubtitleSlot.primary,
  }) => _both((e) => e.setSubDelay(delay, slot: slot));

  @override
  Future<void> setSubSpeed(double speed) => _both((e) => e.setSubSpeed(speed));

  @override
  Future<void> setSubtitleCodepage(String? codepage) =>
      _both((e) => e.setSubtitleCodepage(codepage));

  @override
  Future<void> selectTrack(
    TrackType type,
    int? id, {
    SubtitleSlot slot = SubtitleSlot.primary,
  }) async {
    await _ensure();
    await _a.selectTrack(type, id, slot: slot);
  }

  @override
  Future<void> addExternalTrack(
    TrackType type,
    Uri uri, {
    String? title,
    String? language,
  }) async {
    await _ensure();
    await _a.addExternalTrack(type, uri, title: title, language: language);
  }

  @override
  Future<void> setVideoFilters(VideoFilterChain chain) =>
      _both((e) => e.setVideoFilters(chain));

  @override
  Future<void> setShaderPreset(ShaderPreset preset) =>
      _both((e) => e.setShaderPreset(preset));

  @override
  Future<void> setAudioDsp(AudioDspChain chain) =>
      _both((e) => e.setAudioDsp(chain));

  @override
  Future<void> setAudioOutput(AudioOutputConfig config) =>
      _both((e) => e.setAudioOutput(config));

  @override
  Future<void> setSubtitleStyle(
    SubtitleStyle style, {
    SubtitleSlot slot = SubtitleSlot.primary,
  }) => _both((e) => e.setSubtitleStyle(style, slot: slot));

  @override
  Future<void> setAbLoop(Duration? a, Duration? b, {int? count}) async {
    await _ensure();
    await _a.setAbLoop(a, b, count: count);
  }

  @override
  Future<Uint8List> screenshot({
    bool subtitles = true,
    ScreenshotFormat format = ScreenshotFormat.png,
  }) async {
    await _ensure();
    return await _a.screenshot(subtitles: subtitles, format: format);
  }

  @override
  Future<void> export(
    Duration start,
    Duration end,
    ExportFormat format,
    Uri out, {
    bool subtitles = false,
  }) async {
    await _ensure();
    await _a.export(start, end, format, out, subtitles: subtitles);
  }

  @override
  Future<void> setVideoTarget(VideoTarget target) async {
    await _ensure();
    await _a.setVideoTarget(target);
  }

  @override
  Future<void> setDucking(double gain) async {
    _duck = gain.clamp(0, 1);
    await _both((e) => e.setDucking(_duck));
    _publish(_a.current);
  }

  @override
  Future<List<EngineAudioDevice>> audioDevices() async {
    await _ensure();
    return await _a.audioDevices();
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _sub?.cancel();
    await _a.dispose();
    await _b?.dispose();
    await _controller.close();
  }
}
