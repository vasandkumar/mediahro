import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:mediahro_engine/src/api/media_source.dart';
import 'package:mediahro_engine/src/api/models.dart';
import 'package:mediahro_engine/src/api/playback_engine.dart';
import 'package:mediahro_engine/src/bridge/audio_bridge.dart';
import 'package:mediahro_engine/src/bridge/render_bridge.dart';
import 'package:mediahro_engine/src/mpv/audio_dsp.dart';
import 'package:mediahro_engine/src/mpv/mpv_client.dart';
import 'package:mediahro_engine/src/mpv/mpv_node.dart';
import 'package:mediahro_engine/src/mpv/mpv_options.dart';
import 'package:mediahro_engine/src/mpv/playlist_files.dart';
import 'package:mediahro_engine/src/mpv/render_mapping.dart';
import 'package:mediahro_engine/src/mpv/software_renderer.dart';
import 'package:mediahro_engine/src/mpv/state_mapping.dart';
import 'package:mediahro_engine/src/mpv/stream_protocol.dart';
import 'package:mediahro_engine/src/mpv/subtitle_convert.dart';
import 'package:mediahro_ffi/mediahro_ffi.dart';
// The mpv bindings are an engine-private part of mediahro_ffi (lane B1).
// ignore: implementation_imports
import 'package:mediahro_ffi/src/mpv/mpv.dart' show Libmpv;
import 'package:meta/meta.dart';

/// Construction-time settings for [MpvEngine].
@immutable
final class MpvEngineConfig {
  const MpvEngineConfig({
    this.platform,
    this.video,
    this.nullAudio = false,
    this.renderBridge,
    this.allowSoftwareHevc,
    this.extraOptions = const {},
    this.logLevel = 'warn',
    this.onLog,
    this.softwareSize = (320, 180),
    this.libmpvPath,
    this.audioBridge,
  });

  /// Defaults to the running platform.
  final EnginePlatform? platform;

  /// Defaults to [VideoOutputMode.none] for the music role and to the
  /// platform's on-screen mode for the video role.
  final VideoOutputMode? video;

  /// `ao=null`, for headless harnesses and CI runners without audio devices.
  final bool nullAudio;

  /// Native render bridge; null in headless use.
  final RenderBridge? renderBridge;

  /// Software HEVC decode when no hardware/OS decoder exists (docs/09 §4).
  /// Defaults to off on Windows and on elsewhere.
  final bool? allowSoftwareHevc;

  /// Options applied after the defaults (tests, harness).
  final Map<String, String> extraOptions;

  /// mpv log level forwarded to [onLog] (`no`, `fatal`, `error`, `warn`,
  /// `info`, `v`, `debug`).
  final String logLevel;
  final void Function(MpvLogMessage message)? onLog;

  /// Frame size of the software renderer ([VideoOutputMode.software]).
  final (int, int) softwareSize;

  /// libmpv file to load first (harnesses); see `Libmpv.open`.
  final String? libmpvPath;

  /// OS bit-perfect / rate-matching requests (AUD-040, AUD-041); null in
  /// headless use.
  final AudioBridge? audioBridge;
}

/// [PlaybackEngine] over libmpv (docs/05 §4, ADR-004).
///
/// The core is created lazily on first use so construction never blocks or
/// throws; a missing libmpv surfaces as [EngineErrorCode.libraryMissing] in
/// [current] (CORE-011). Every libmpv call is asynchronous; events are read
/// on a separate isolate.
final class MpvEngine implements PlaybackEngine {
  MpvEngine(this.role, {this.config = const MpvEngineConfig()})
    : platform = config.platform ?? EnginePlatform.current;

  /// Whether libmpv can be loaded in this process (feature detection).
  static bool get isAvailable => Libmpv.isAvailable();

  @override
  final EngineRole role;
  final MpvEngineConfig config;
  final EnginePlatform platform;

  final _controller = StreamController<PlaybackState>.broadcast();
  PlaybackState _state = const PlaybackState();
  Future<MpvClient?>? _ready;
  MpvClient? _client;
  RenderSurface? _surface;
  StreamSubscription<(int, int?)>? _surfaceSub;
  MpvStreamProtocol? _protocol;
  SoftwareRenderer? _software;
  var _disposed = false;
  var _shuttingDown = false;

  // Flags that derive the status (see [_deriveStatus]).
  var _paused = false;
  var _idle = true;
  var _eof = false;
  var _pausedForCache = false;
  var _seeking = false;
  var _loading = false;
  int _frameDrops = 0;
  int _decoderDrops = 0;
  Map<String, Object?>? _audioParams;
  Map<String, Object?>? _audioOutParams;
  String? _ao;
  String? _audioDevice;
  var _exclusive = false;
  AudioDspChain _dsp = const AudioDspChain();
  AudioOutputConfig _output = const AudioOutputConfig();
  MediaSource? _source;
  var _isNetwork = false;
  var _hevcChecked = false;
  int _generation = 0;
  Completer<void>? _opened;
  var _emitScheduled = false;
  var _videoWidth = 0;
  var _videoHeight = 0;
  MediaSource? _next;
  List<Chapter> _externalChapters = const [];
  int _itemSerial = 0;
  Directory? _tempDir;

  VideoOutputMode get _videoMode =>
      config.video ??
      (role == EngineRole.music
          ? VideoOutputMode.none
          : config.renderBridge == null
          ? VideoOutputMode.software
          : platform == EnginePlatform.android
          ? VideoOutputMode.androidSurface
          : VideoOutputMode.renderApi);

  bool get _allowSoftwareHevc =>
      config.allowSoftwareHevc ?? platform != EnginePlatform.windows;

  /// The underlying client once created (tests and the corpus harness).
  @visibleForTesting
  MpvClient? get client => _client;

  /// Software renderer in [VideoOutputMode.software] (harnesses, tests).
  SoftwareRenderer? get softwareRenderer => _software;

  /// Options the core rejected (unknown in the loaded libmpv build).
  Map<String, int> get rejectedOptions => _client?.rejectedOptions ?? const {};

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
  int? get textureId => _surface?.textureId;

  /// Render path of the current surface (stats overlay, VID-072).
  String? get renderBackend => _surface?.backend;

  // ---------------------------------------------------------------- core --

  Future<MpvClient?> _core() => _ready ??= _create();

  Future<MpvClient?> _create() async {
    if (_disposed) return null;
    try {
      final options = {
        ...defaultMpvOptions(
          platform: platform,
          role: role,
          video: _videoMode,
          nullAudio: config.nullAudio,
        ),
        ...config.extraOptions,
      };
      final client = await MpvClient.create(
        options: options,
        logLevel: config.logLevel,
        library: Libmpv.open(path: config.libmpvPath),
      );
      _client = client;
      client.events.listen(_onEvent);
      for (final MapEntry(:key, :value) in observedProperties.entries) {
        try {
          client.observe(key, value);
        } on MpvException {
          // Property unknown to this libmpv build; the field stays default.
        }
      }
      _protocol = MpvStreamProtocol.register(client);
      if (role == EngineRole.video && _videoMode == VideoOutputMode.software) {
        _software = SoftwareRenderer.create(
          client,
          width: config.softwareSize.$1,
          height: config.softwareSize.$2,
        );
      }
      await _attachSurface(client);
      return client;
    } on NativeLibraryUnavailable catch (e) {
      _fail(EngineErrorCode.libraryMissing, '$e');
    } on MpvException catch (e) {
      _fail(EngineErrorCode.engineCrashed, '$e');
    }
    return null;
  }

  Future<void> _attachSurface(MpvClient client) async {
    final bridge = config.renderBridge;
    if (bridge == null || role != EngineRole.video) return;
    if (_videoMode != VideoOutputMode.renderApi &&
        _videoMode != VideoOutputMode.androidSurface) {
      return;
    }
    try {
      final surface = await bridge.create(
        mpvHandle: client.handleAddress,
        libmpvPath: client.library.path,
      );
      _surface = surface;
      if (surface.androidSurface != null) {
        await _setWid(client, surface.androidSurface!);
      }
      _surfaceSub = bridge.surfaceChanges.listen((change) async {
        if (change.$1 != _surface?.textureId) return;
        final c = _client;
        if (c == null || c.isDestroyed) return;
        await _setWid(c, change.$2 ?? 0);
      });
    } on Object catch (e) {
      // No surface: playback continues (audio, screenshots) and the UI shows
      // the decode-failed copy for the video area.
      _state = _state.copyWith(
        video: _state.video.copyWith(subtitleRenderer: 'no surface: $e'),
      );
    }
  }

  Future<void> _setWid(MpvClient c, int surface) async {
    await _quiet(c.setProperty('wid', '$surface'));
    // Re-create the VO on the new surface (or drop it when detached).
    await _quiet(c.setProperty('vo', surface == 0 ? 'null' : 'gpu-next'));
  }

  Future<void> _quiet(Future<Object?> f) async {
    try {
      await f;
    } on MpvException {
      // Commands that do not apply in the current state (e.g. seek while
      // idle) are not errors for the user.
    }
  }

  void _fail(EngineErrorCode code, String detail) {
    _loading = false;
    _state = _state.copyWith(
      status: PlaybackStatus.error,
      error: EngineError(code: code, detail: detail),
    );
    _emitNow();
    final o = _opened;
    if (o != null && !o.isCompleted) o.complete();
  }

  // -------------------------------------------------------------- events --

  void _onEvent(MpvEvent e) {
    switch (e) {
      case MpvPropertyChange(:final name, :final value):
        _onProperty(name, value);
      case MpvStartFile():
        _itemSerial++;
        if (_next != null) {
          // Gapless advance (AUD-002): the queued entry starts while audio
          // keeps flowing; drop the finished entry and keep the status.
          _source = _next;
          _next = null;
          _state = _state.copyWith(nextPrepared: false, item: _itemSerial);
          final c = _client;
          if (c != null) unawaited(_quiet(c.command(['playlist-remove', '0'])));
        } else {
          _loading = true;
          _state = _state.copyWith(item: _itemSerial);
        }
      case MpvFileLoaded():
        _loading = false;
        _eof = false;
        final o = _opened;
        if (o != null && !o.isCompleted) o.complete();
      case MpvEndFile(:final reason, :final error):
        if (reason == MpvEndReason.error) {
          _fail(
            mapEndFileError(error, isNetwork: _isNetwork),
            'end-file error $error',
          );
          return;
        }
        if (reason == MpvEndReason.eof && _next == null) _eof = true;
      case MpvPlaybackRestart():
        _seeking = false;
        unawaited(_afterRestart());
        if (_seekedSinceRestart) {
          _seekedSinceRestart = false;
          unawaited(_refreshExternalBitmapSubs());
        }
      case MpvSeekStarted():
        _seeking = true;
      case MpvShutdown():
        if (!_shuttingDown) {
          // The core went away without us asking: isolate the fault to this
          // player session and rebuild the core on the next open().
          _client = null;
          _ready = null;
          _fail(EngineErrorCode.engineCrashed, 'mpv core shut down');
        }
      case MpvLogMessage():
        config.onLog?.call(e);
      default:
        break;
    }
    _scheduleEmit();
  }

  void _onProperty(String name, Object? value) {
    switch (name) {
      case 'pause':
        _paused = value == true;
      case 'idle-active':
        _idle = value == true;
      case 'eof-reached':
        _eof = value == true;
      case 'paused-for-cache':
        _pausedForCache = value == true;
      case 'seeking':
        _seeking = value == true;
      case 'frame-drop-count':
        _frameDrops = value is int ? value : 0;
      case 'decoder-frame-drop-count':
        _decoderDrops = value is int ? value : 0;
      case 'audio-params':
        _audioParams = value is Map<String, Object?> ? value : null;
        unawaited(_syncOutputPreference());
      case 'audio-out-params':
        _audioOutParams = value is Map<String, Object?> ? value : null;
      case 'current-ao':
        _ao = value is String ? value : null;
      case 'audio-device':
        _audioDevice = value is String ? value : null;
      case 'audio-exclusive':
        _exclusive = value == true;
      case 'track-list':
        _state = applyProperty(_state, name, value);
        _onTracks();
        return;
      case 'chapter-list':
        _state = applyProperty(_state, name, value);
        if (_state.chapters.isEmpty && _externalChapters.isNotEmpty) {
          _state = _state.copyWith(chapters: _externalChapters);
        }
        return;
      case 'video-params':
        _state = applyProperty(_state, name, value);
        _onVideoSize();
        return;
      default:
        _state = applyProperty(_state, name, value);
        return;
    }
    if (name.startsWith('audio') || name == 'current-ao') {
      _refreshAudioInfo();
    }
    if (name.endsWith('drop-count')) {
      _state = _state.copyWith(
        video: _state.video.copyWith(
          droppedFrames: _frameDrops + _decoderDrops,
        ),
      );
    }
  }

  OutputPreference? _osOutput;
  int? _preferredRate;

  void _refreshAudioInfo() {
    final os = _osOutput;
    _state = _state.copyWith(
      audio: audioOutputInfo(
        decoded: _audioParams,
        output: _audioOutParams,
        exclusive: _exclusive || (os?.bitPerfect ?? false),
        dspActive: dspFilters(_dsp).isNotEmpty || _state.rate != 1,
        device: os?.device ?? _audioDevice,
        ao: _ao,
      ),
    );
  }

  /// Asks the OS for a bit-perfect output at the current source rate
  /// (automatic rate switching, AUD-040/041); released when exclusive is off.
  Future<void> _syncOutputPreference() async {
    final bridge = config.audioBridge;
    if (bridge == null) return;
    final rate = _audioParams?['samplerate'] as int?;
    if (!_output.exclusive) {
      if (_osOutput?.applied ?? false) await bridge.prefer(bitPerfect: false);
      _osOutput = null;
      _preferredRate = null;
      return;
    }
    if (rate == null || rate == _preferredRate) return;
    _preferredRate = rate;
    _osOutput = await bridge.prefer(
      bitPerfect: true,
      sampleRate: rate,
      channels: _audioParams?['channel-count'] as int?,
      bitDepth: sampleFormatBits(_audioParams?['format'] as String?),
    );
    _refreshAudioInfo();
    _scheduleEmit();
  }

  void _onTracks() {
    final dv = _state.tracks
        .where((t) => t.type == TrackType.video)
        .map((t) => t.dolbyVisionProfile)
        .nonNulls
        .firstOrNull;
    if (dv == 7 &&
        !_state.notices.contains(EngineNotice.enhancementLayerIgnored)) {
      _state = _state.copyWith(
        notices: {..._state.notices, EngineNotice.enhancementLayerIgnored},
      );
    }
  }

  void _onVideoSize() {
    final w = _state.video.width ?? 0;
    final h = _state.video.height ?? 0;
    final surface = _surface;
    if (surface == null || w <= 0 || h <= 0) return;
    if (w == _videoWidth && h == _videoHeight) return;
    _videoWidth = w;
    _videoHeight = h;
    unawaited(
      config.renderBridge
          ?.resize(surface.textureId, w, h)
          .catchError((Object _) {}),
    );
  }

  var _seekedSinceRestart = false;

  /// External PGS (.sup) files are demuxed one segment per packet, so a seek
  /// can land inside a display set and the caption on screen stays blank
  /// until the next set. Re-selecting the track makes mpv decode the set
  /// from its start (SUB-011).
  Future<void> _refreshExternalBitmapSubs() async {
    final c = _client;
    if (c == null) return;
    for (final (prop, id) in [
      ('sid', _state.subtitleTrackId),
      ('secondary-sid', _state.secondarySubtitleTrackId),
    ]) {
      if (id == null) continue;
      final t = _state.tracks
          .where((t) => t.type == TrackType.subtitle && t.id == id)
          .firstOrNull;
      if (t == null || !t.isExternal || t.codec != 'hdmv_pgs_subtitle') {
        continue;
      }
      await _quiet(c.setProperty(prop, 'no'));
      await _quiet(c.setProperty(prop, '$id'));
    }
  }

  Future<void> _afterRestart() async {
    final c = _client;
    if (c == null || _hevcChecked || _allowSoftwareHevc) return;
    final codec = _state.video.videoCodec ?? '';
    if (!codec.toLowerCase().contains('hevc')) return;
    _hevcChecked = true;
    if (_state.video.hwdec != HwdecPath.none) return;
    // No hardware/OS HEVC decoder: software HEVC is off by default on
    // Windows (docs/09 §4). Audio keeps playing; the UI offers the toggle.
    await _quiet(c.setProperty('vid', 'no'));
    _state = _state.copyWith(
      notices: {..._state.notices, EngineNotice.hevcSoftwareDecodeOff},
    );
    _scheduleEmit();
  }

  PlaybackStatus _deriveStatus() {
    if (_state.error != null) return PlaybackStatus.error;
    if (_loading) return PlaybackStatus.opening;
    if (_idle) return PlaybackStatus.idle;
    if (_eof) return PlaybackStatus.ended;
    if (_pausedForCache || (_seeking && !_paused)) {
      return PlaybackStatus.buffering;
    }
    return _paused ? PlaybackStatus.paused : PlaybackStatus.playing;
  }

  void _scheduleEmit() {
    if (_emitScheduled) return;
    _emitScheduled = true;
    scheduleMicrotask(_emitNow);
  }

  void _emitNow() {
    _emitScheduled = false;
    if (_state.error == null) {
      _state = _state.copyWith(status: _deriveStatus());
    }
    if (!_controller.isClosed) _controller.add(_state);
  }

  // ----------------------------------------------------------------- API --

  Future<MpvClient?> _live() {
    if (_disposed) throw StateError('MpvEngine used after dispose');
    return _core();
  }

  @override
  Future<void> open(MediaSource src, {OpenOptions? opts}) async {
    final c = await _live();
    if (c == null) return;
    final o = opts ?? const OpenOptions();
    final gen = ++_generation;
    _source = src;
    _next = null;
    _hevcChecked = false;
    _externalChapters = o.chapters;
    _loading = true;
    _eof = false;
    _idle = false;
    _state = PlaybackState(
      status: PlaybackStatus.opening,
      volume: _state.volume,
      muted: _state.muted,
      rate: _state.rate,
      item: _itemSerial,
      chapters: o.chapters,
    );
    _emitNow();
    final opened = _opened = Completer<void>();
    String url;
    var rest = const <String>[];
    switch (src) {
      case UriSource(:final uri):
        _isNetwork = isNetworkUri(uri);
        url = uri.scheme == 'file' ? uri.toFilePath() : uri.toString();
        if (uri.scheme == 'file' && needsPlaylistExpansion(url)) {
          final entries = await _expandPlaylist(uri);
          if (entries.isEmpty) {
            _fail(EngineErrorCode.unsupportedFormat, 'empty playlist');
            return;
          }
          url = entries.first;
          rest = entries.sublist(1);
        }
      case VirtualFileSource(:final file):
        _isNetwork = isNetworkUri(file.uri);
        final protocol = _protocol;
        if (protocol == null) {
          _fail(EngineErrorCode.sourceUnavailable, 'stream shim missing');
          return;
        }
        url = protocol.urlFor(file);
    }
    final perFile = <String, String>{
      'pause': o.autoplay ? 'no' : 'yes',
      if (o.start != null) 'start': secondsValue(o.start!),
      if (o.audioOnly || role == EngineRole.music) 'vid': 'no',
      if (o.preferredAudioLanguages.isNotEmpty)
        'alang': o.preferredAudioLanguages.join(','),
      if (o.preferredSubtitleLanguages.isNotEmpty)
        'slang': o.preferredSubtitleLanguages.join(','),
      'demuxer-max-bytes':
          '${o.cacheBytes ?? cacheBytes(platform: platform, isNetwork: _isNetwork)}',
      if (src case UriSource(:final headers) when headers.isNotEmpty)
        'http-header-fields': headers.entries
            .map((e) => '${e.key}: ${e.value}')
            .join(','),
      if (src case UriSource(:final userAgent?)) 'user-agent': userAgent,
      if (o.loudnessGainDb != null && _dsp.loudness != LoudnessMode.off)
        'replaygain-fallback': dspProperties(
          _dsp,
          scannedGainDb: o.loudnessGainDb,
        )['replaygain-fallback']!,
    };
    try {
      await c.loadfile(url, options: encodeOptions(perFile));
      for (final entry in rest) {
        await c.loadfile(entry, flags: 'append');
      }
    } on MpvException catch (e) {
      _fail(EngineErrorCode.invalidArgument, '$e');
      return;
    }
    await opened.future;
    if (gen != _generation) return;
    _scheduleEmit();
  }

  Future<List<String>> _expandPlaylist(Uri uri) async {
    try {
      final text = await File.fromUri(uri).readAsString();
      return [
        for (final e in parseXspf(text, uri))
          if (e.scheme == 'file') e.toFilePath() else e.toString(),
      ];
    } on FileSystemException {
      return const [];
    } on FormatException {
      return const [];
    }
  }

  @override
  Future<void> play() async {
    final c = await _live();
    if (c == null) return;
    if (_eof) {
      _eof = false;
      await _quiet(c.command(['seek', '0', 'absolute']));
    }
    await _quiet(c.setProperty('pause', 'no'));
  }

  @override
  Future<void> pause() async {
    final c = await _live();
    if (c == null) return;
    await _quiet(c.setProperty('pause', 'yes'));
  }

  @override
  Future<void> stop() async {
    final c = await _live();
    if (c == null) return;
    ++_generation;
    _source = null;
    await _quiet(c.command(['stop']));
    _state = PlaybackState(volume: _state.volume, muted: _state.muted);
    _idle = true;
    _loading = false;
    _eof = false;
    _emitNow();
  }

  @override
  Future<void> seek(
    Duration position, {
    SeekMode mode = SeekMode.keyframe,
  }) async {
    final c = await _live();
    if (c == null) return;
    _eof = false;
    _seekedSinceRestart = true;
    await _quiet(
      c.command([
        'seek',
        secondsValue(position),
        switch (mode) {
          SeekMode.keyframe => 'absolute+keyframes',
          SeekMode.exact => 'absolute+exact',
          SeekMode.relative => 'relative',
        },
      ]),
    );
  }

  @override
  Future<void> frameStep({bool backwards = false}) async {
    final c = await _live();
    if (c == null) return;
    await _quiet(
      c.command([if (backwards) 'frame-back-step' else 'frame-step']),
    );
  }

  @override
  Future<void> setRate(double rate) async {
    if (rate < 0.25 || rate > 4.0) {
      throw const EngineException(
        EngineError(
          code: EngineErrorCode.invalidArgument,
          detail: 'rate out of 0.25–4.0',
        ),
      );
    }
    final c = await _live();
    if (c == null) return;
    await _quiet(c.setProperty('speed', '$rate'));
  }

  @override
  Future<void> setVolume(double volume) async {
    final c = await _live();
    if (c == null) return;
    final v = volume.clamp(0.0, 3.0) * 100;
    await _quiet(c.setProperty('volume', v.toStringAsFixed(2)));
  }

  @override
  Future<void> setMuted({required bool muted}) async {
    final c = await _live();
    if (c == null) return;
    await _quiet(c.setProperty('mute', muted ? 'yes' : 'no'));
  }

  @override
  Future<void> setAudioDelay(Duration delay) async {
    final c = await _live();
    if (c == null) return;
    await _quiet(
      c.setProperty('audio-delay', secondsValue(delay + _output.latencyOffset)),
    );
  }

  @override
  Future<void> setSubDelay(
    Duration delay, {
    SubtitleSlot slot = SubtitleSlot.primary,
  }) async {
    final c = await _live();
    if (c == null) return;
    await _quiet(
      c.setProperty(
        slot == SubtitleSlot.primary ? 'sub-delay' : 'secondary-sub-delay',
        secondsValue(snapSubtitleDelay(delay)),
      ),
    );
  }

  @override
  Future<void> setSubSpeed(double speed) async {
    final c = await _live();
    if (c == null) return;
    await _quiet(c.setProperty('sub-speed', '${speed.clamp(0.1, 10.0)}'));
  }

  @override
  Future<void> selectTrack(
    TrackType type,
    int? id, {
    SubtitleSlot slot = SubtitleSlot.primary,
  }) async {
    final c = await _live();
    if (c == null) return;
    final prop = switch (type) {
      TrackType.video => 'vid',
      TrackType.audio => 'aid',
      TrackType.subtitle when slot == SubtitleSlot.secondary => 'secondary-sid',
      TrackType.subtitle => 'sid',
    };
    await _quiet(c.setProperty(prop, id == null ? 'no' : '$id'));
  }

  @override
  Future<void> addExternalTrack(
    TrackType type,
    Uri uri, {
    String? title,
    String? language,
  }) async {
    final c = await _live();
    if (c == null) return;
    final cmd = switch (type) {
      TrackType.video => 'video-add',
      TrackType.audio => 'audio-add',
      TrackType.subtitle => 'sub-add',
    };
    var path = uri.scheme == 'file' ? uri.toFilePath() : uri.toString();
    var trackTitle = title ?? '';
    if (type == TrackType.subtitle && uri.scheme == 'file') {
      final converted = await _convertSubtitle(path);
      if (converted != null) {
        trackTitle = title ?? uri.pathSegments.last;
        path = converted;
      }
    }
    try {
      await c.command([cmd, path, 'select', trackTitle, language ?? '']);
    } on MpvException catch (e) {
      throw EngineException(
        EngineError(code: EngineErrorCode.unsupportedFormat, detail: '$e'),
      );
    }
  }

  /// Converts TTML/DFXP, LRC and timestamped TXT to SRT (SUB-010); returns
  /// the converted file or null when mpv reads [path] natively.
  Future<String?> _convertSubtitle(String path) async {
    final file = File(path);
    final ConvertedSubtitle? kind;
    final String text;
    try {
      final bytes = await file.readAsBytes();
      text = utf8.decode(bytes, allowMalformed: true);
      kind = conversionFor(
        path,
        head: text.substring(0, text.length < 512 ? text.length : 512),
      );
    } on FileSystemException {
      return null;
    }
    if (kind == null) return null;
    final dir = _tempDir ??= await Directory.systemTemp.createTemp('mh-subs');
    final out = File(
      '${dir.path}${Platform.pathSeparator}${dir.listSync().length}.srt',
    );
    await out.writeAsString(
      convertToSrt(kind, text, videoFps: _state.video.fps),
    );
    return out.path;
  }

  @override
  Future<void> setSubtitleCodepage(String? codepage) async {
    final c = await _live();
    if (c == null) return;
    await _quiet(
      c.setProperty('sub-codepage', codepage == null ? 'auto' : '+$codepage'),
    );
    // Reload external subtitles so the new charset applies.
    final ids = _state.tracks
        .where((t) => t.type == TrackType.subtitle && t.isExternal)
        .map((t) => t.id);
    for (final id in ids) {
      await _quiet(c.command(['sub-reload', '$id']));
    }
  }

  Future<void> _setAll(MpvClient c, Map<String, String> props) async {
    for (final MapEntry(:key, :value) in props.entries) {
      try {
        await c.setProperty(key, value);
      } on MpvException catch (e) {
        // Builds before mpv 0.38 know some options by older names.
        final legacy = legacyPropertyNames[key];
        if (legacy != null && e.code == MpvError.propertyNotFound) {
          await _quiet(c.setProperty(legacy, value));
        }
      }
    }
  }

  @override
  Future<void> setVideoFilters(VideoFilterChain chain) async {
    final c = await _live();
    if (c == null) return;
    await _setAll(c, videoFilterProperties(chain));
  }

  @override
  Future<void> setShaderPreset(ShaderPreset preset) async {
    final c = await _live();
    if (c == null) return;
    await _quiet(
      c.setProperty(
        'glsl-shaders',
        shaderListValue(preset, windows: platform == EnginePlatform.windows),
      ),
    );
  }

  @override
  Future<void> setAudioDsp(AudioDspChain chain) async {
    final c = await _live();
    if (c == null) return;
    _dsp = chain;
    await _applyAudioFilters(c);
    await _setAll(c, dspProperties(chain));
  }

  Future<void> _applyAudioFilters(MpvClient c) async {
    final codec = _state.tracks
        .where((t) => t.type == TrackType.audio && t.id == _state.audioTrackId)
        .firstOrNull
        ?.codec;
    await _quiet(
      c.setProperty(
        'af',
        audioFilterValue(
          _dsp,
          sourceCodec: codec,
          dsd: _output.nativeDsd ? null : _output.dsdFilter,
        ),
      ),
    );
  }

  @override
  Future<void> setAudioOutput(AudioOutputConfig config) async {
    final c = await _live();
    if (c == null) return;
    final latencyChanged = config.latencyOffset != _output.latencyOffset;
    _output = config;
    await _setAll(c, audioOutputProperties(config, platform));
    await _applyAudioFilters(c);
    if (latencyChanged) await setAudioDelay(_state.audioDelay);
    _preferredRate = null;
    await _syncOutputPreference();
  }

  @override
  Future<void> setSubtitleStyle(
    SubtitleStyle style, {
    SubtitleSlot slot = SubtitleSlot.primary,
  }) async {
    final c = await _live();
    if (c == null) return;
    await _setAll(c, subtitleStyleProperties(style, slot: slot));
  }

  @override
  Future<void> setAbLoop(Duration? a, Duration? b, {int? count}) async {
    final c = await _live();
    if (c == null) return;
    await _setAll(c, {
      'ab-loop-a': a == null ? 'no' : secondsValue(a),
      'ab-loop-b': b == null ? 'no' : secondsValue(b),
      'ab-loop-count': count == null ? 'inf' : '$count',
    });
  }

  @override
  Future<void> setNext(MediaSource? next, {bool sameAlbum = false}) async {
    final c = await _live();
    if (c == null) return;
    // Drop a previously queued entry, then append the new one; mpv prefetches
    // it and joins the two sample-accurately (gapless-audio, AUD-002).
    if (_next != null) await _quiet(c.command(['playlist-clear']));
    _next = next;
    if (next != null) {
      final url = switch (next) {
        UriSource(:final uri) =>
          uri.scheme == 'file' ? uri.toFilePath() : uri.toString(),
        VirtualFileSource(:final file) => _protocol!.urlFor(file),
      };
      await _quiet(c.loadfile(url, flags: 'append'));
    }
    _state = _state.copyWith(nextPrepared: next != null);
    _scheduleEmit();
  }

  @override
  Future<void> skipToNext() async {
    final c = await _live();
    if (c == null || _next == null) return;
    _source = _next;
    _next = null;
    _state = _state.copyWith(nextPrepared: false);
    await _quiet(c.command(['playlist-next', 'force']));
  }

  @override
  Future<void> setTransition(TransitionConfig config) async {
    await _live();
    _transition = config;
  }

  TransitionConfig _transition = const TransitionConfig();

  /// Crossfade rules in effect (AUD-003).
  TransitionConfig get transition => _transition;

  @override
  Future<Uint8List> screenshot({
    bool subtitles = true,
    ScreenshotFormat format = ScreenshotFormat.png,
  }) async {
    final c = await _live();
    if (c == null || _source == null) {
      throw const EngineException(
        EngineError(
          code: EngineErrorCode.invalidArgument,
          detail: 'nothing is playing',
        ),
      );
    }
    final ext = switch (format) {
      ScreenshotFormat.png => 'png',
      ScreenshotFormat.jpegXl => 'jxl',
      ScreenshotFormat.webp => 'webp',
      ScreenshotFormat.jpeg => 'jpg',
    };
    final dir = await Directory.systemTemp.createTemp('mediahro-shot');
    final file = File('${dir.path}${Platform.pathSeparator}frame.$ext');
    try {
      await c.setProperty('screenshot-format', ext == 'jpg' ? 'jpeg' : ext);
      await c.command([
        'screenshot-to-file',
        file.path,
        if (subtitles) 'subtitles' else 'video',
      ]);
      return await file.readAsBytes();
    } on MpvException catch (e) {
      throw EngineException(
        EngineError(code: EngineErrorCode.unsupportedFormat, detail: '$e'),
      );
    } finally {
      await dir.delete(recursive: true).catchError((Object _) => dir);
    }
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _shuttingDown = true;
    final client = await (_ready ?? Future<MpvClient?>.value());
    await _surfaceSub?.cancel();
    final surface = _surface;
    if (surface != null) {
      await config.renderBridge
          ?.dispose(surface.textureId)
          .catchError((Object _) {});
    }
    _protocol?.shutdown();
    _software?.dispose();
    await client?.destroy();
    await _protocol?.dispose();
    await _tempDir?.delete(recursive: true).catchError((Object _) => _tempDir!);
    await _controller.close();
  }
}

/// mpv properties for [config] (VID-004, AUD-040…044).
Map<String, String> audioOutputProperties(
  AudioOutputConfig config,
  EnginePlatform platform,
) => {
  'audio-device': config.deviceId ?? 'auto',
  'audio-exclusive': config.exclusive ? 'yes' : 'no',
  'audio-spdif': config.passthroughCodecs.join(','),
  // 0 = open the device at the source rate; in exclusive mode the device
  // switches rate per track (automatic rate switching).
  'audio-samplerate': '0',
};

/// Encodes per-file options for `loadfile` using mpv's `%len%` quoting so
/// values may contain commas and equals signs.
String encodeOptions(Map<String, String> options) => options.entries
    .map((e) => '${e.key}=%${_utf8Length(e.value)}%${e.value}')
    .join(',');

int _utf8Length(String s) {
  var n = 0;
  for (final r in s.runes) {
    n += r < 0x80
        ? 1
        : r < 0x800
        ? 2
        : r < 0x10000
        ? 3
        : 4;
  }
  return n;
}

/// Option names renamed in mpv 0.38 → their earlier names, for older
/// libmpv builds (bootstrap prebuilts).
const Map<String, String> legacyPropertyNames = {
  'sub-outline-size': 'sub-border-size',
  'sub-outline-color': 'sub-border-color',
};
