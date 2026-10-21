import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:mediahro_engine/src/api/audio_tap.dart';
import 'package:mediahro_engine/src/api/media_source.dart';
import 'package:mediahro_engine/src/api/models.dart';
import 'package:mediahro_engine/src/api/playback_engine.dart';
import 'package:mediahro_engine/src/api/subtitle_image.dart';
import 'package:mediahro_engine/src/api/video_target.dart';
import 'package:mediahro_engine/src/bridge/audio_bridge.dart';
import 'package:mediahro_engine/src/bridge/render_bridge.dart';
import 'package:mediahro_engine/src/disc/disc_reader.dart';
import 'package:mediahro_engine/src/mpv/audio_decoder.dart';
import 'package:mediahro_engine/src/mpv/audio_dsp.dart';
import 'package:mediahro_engine/src/mpv/audio_tapper.dart';
import 'package:mediahro_engine/src/mpv/display_icc.dart';
import 'package:mediahro_engine/src/mpv/dsd_dop.dart';
import 'package:mediahro_engine/src/mpv/exporter.dart';
import 'package:mediahro_engine/src/mpv/mp4_gapless.dart';
import 'package:mediahro_engine/src/mpv/mpv_client.dart';
import 'package:mediahro_engine/src/mpv/mpv_node.dart';
import 'package:mediahro_engine/src/mpv/mpv_options.dart';
import 'package:mediahro_engine/src/mpv/playlist_files.dart';
import 'package:mediahro_engine/src/mpv/render_mapping.dart';
import 'package:mediahro_engine/src/mpv/scratch.dart';
import 'package:mediahro_engine/src/mpv/software_renderer.dart';
import 'package:mediahro_engine/src/mpv/stall_guard.dart';
import 'package:mediahro_engine/src/mpv/state_mapping.dart';
import 'package:mediahro_engine/src/mpv/stream_protocol.dart';
import 'package:mediahro_engine/src/mpv/subtitle_convert.dart';
import 'package:mediahro_engine/src/mpv/subtitle_extract.dart';
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
    : platform = config.platform ?? EnginePlatform.current {
    // Leftovers of a crashed run (decoded PCM, subtitle dumps) go at start-up.
    unawaited(sweepOnce());
  }

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
  // Network source without a caller-chosen cache: resize once the bitrate
  // is known (VID-006).
  var _cacheByBitrate = false;
  // Local files the engine opened as VirtualFiles; closed on the next open.
  final _ownedFiles = <VirtualFile>[];

  // DSD played as DoP (AUD-043): the item in play, and the queued one.
  var _dop = false;
  DsdInfo? _dopInfo;
  var _skipDop = false;
  // Visualiser taps by window size (AUD-046), started on first listen.
  final _taps = <int, AnalysisTap>{};
  // Audio-focus ducking gain (AUD-045): mpv's volume-gain where it exists
  // (mpv >= 0.36); older builds scale mpv's `volume` instead while the state
  // keeps reporting the user's volume.
  double _duck = 1;
  var _duckViaVolume = false;
  double _userVolume = 1;
  // Bluetooth codec of the active output, from the AudioBridge (AUD-044).
  String? _bluetoothCodec;
  // Where video is drawn (VID-031): the texture or a platform view.
  VideoTarget _videoTarget = const VideoTarget.texture();
  // JNI reference to a platform view's Surface (Android), released on change.
  int? _viewRef;
  // Completed on the next playback-restart (end of a seek).
  final _restartWaiters = <Completer<void>>[];
  var _hevcChecked = false;
  // VID-002: a hardware decoder that froze is rebuilt in software, once per
  // item; mpv drops the file-local override when the item ends.
  final _stall = StallGuard();
  Timer? _stallTimer;
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

  /// Whether the render bridge runs on the iOS Simulator (VID-030 tests).
  bool get renderOnSimulator => _surface?.simulator ?? false;

  /// Why the render bridge gave no surface, if it failed (diagnostics).
  String? get surfaceError => _surfaceError;
  String? _surfaceError;

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
      _appliedFilterProps.clear();
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
      if (role == EngineRole.video) {
        _stallTimer = Timer.periodic(
          _stallTick,
          (_) => unawaited(_checkStall()),
        );
      }
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
      _surfaceError = '$e';
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

  /// VID-006: sizes the read-ahead cache to the file's average bitrate once
  /// its size and duration are known.
  Future<void> _sizeCacheToBitrate(int gen) async {
    final c = _client;
    if (c == null) return;
    try {
      final size = await c.getProperty('file-size');
      final duration = await c.getProperty('duration');
      if (gen != _generation || size is! int || duration is! double) return;
      if (size <= 0 || duration <= 0) return;
      final bytes = cacheBytes(
        platform: platform,
        isNetwork: true,
        bitrate: (size * 8 / duration).round(),
      );
      await c.setProperty('demuxer-max-bytes', '$bytes');
    } on MpvException {
      // Size or duration unknown (live streams): keep the default budget.
    }
  }

  /// AUD-002: MP4/M4A files with an iTunSMPB tag end exactly at their last
  /// real sample (mpv's per-file `end`), and the double-trimmed framing plays
  /// through [Mp4GaplessFile] (see [inspectSmpb]). Other files are returned
  /// unchanged and open directly.
  Future<(MediaSource, String?)> _oneGaplessTrim(MediaSource src) async {
    if (_protocol == null) return (src, null);
    final VirtualFile file;
    var owned = false;
    switch (src) {
      case UriSource(:final uri) when uri.scheme == 'file':
        file = LocalVirtualFile(File(uri.toFilePath()));
        owned = true;
      case VirtualFileSource(file: final f):
        file = f;
      default:
        return (src, null);
    }
    SmpbFix? fix;
    try {
      fix = await inspectSmpb(file);
    } on Object {
      fix = null;
    }
    final blankAt = fix?.blankAt;
    if (blankAt == null) {
      if (owned) await file.close();
      return (src, fix?.end);
    }
    if (owned) _ownedFiles.add(file);
    return (
      VirtualFileSource(Mp4GaplessFile(file, blankAt), title: src.title),
      fix!.end,
    );
  }

  /// Whether the output may be sent DoP at all (AUD-043, ADR-023). DoP played
  /// to a device that does not decode it is full-scale noise, so every
  /// condition must hold: native DSD is on, the output is exclusive (no
  /// mixer in between), and the app has listed `dop` among the selected
  /// device's passthrough formats, which it does only for a device that
  /// advertises DoP rates, and the device is named: DoP is pinned to that
  /// device, never to whatever the system default is. The rest is checked on
  /// the real output before anything is heard (see [_dopOutputOk]).
  bool get _dopAllowed =>
      _output.nativeDsd &&
      _output.exclusive &&
      _output.passthroughCodecs.contains('dop') &&
      (_output.deviceId ?? 'auto') != 'auto' &&
      _protocol != null;

  /// With DoP allowed, a DSF or DFF file (mono or stereo, DSD64 to DSD256,
  /// not DST) as its DoP stream and layout; null for anything else, which
  /// opens as usual (DSD→PCM with the selectable low-pass). With [keep]
  /// false the file is only inspected and released.
  Future<({MediaSource source, DsdInfo info})?> _dopSource(
    MediaSource src, {
    required bool keep,
  }) async {
    if (!_dopAllowed) return null;
    final VirtualFile file;
    var owned = false;
    switch (src) {
      case UriSource(:final uri) when uri.scheme == 'file':
        file = LocalVirtualFile(File(uri.toFilePath()));
        owned = true;
      case VirtualFileSource(file: final f):
        file = f;
      default:
        return null;
    }
    final info = await inspectDsd(file);
    if (info == null || !keep) {
      if (owned) await file.close();
      return info == null ? null : (source: src, info: info);
    }
    if (owned) _ownedFiles.add(file);
    return (
      source: VirtualFileSource(
        DopVirtualFile(file, info),
        title: src.title,
        sensitive: src.sensitive,
      ),
      info: info,
    );
  }

  /// Checks that the output really carries the DoP samples untouched: it is
  /// open, runs exclusively at the DoP rate with at least 24 bits, and on
  /// Android and iOS the OS granted the bit-perfect path at that rate. Reads
  /// the output as it is now, not what was last reported. With [wait], gives
  /// the output up to 3 s to open (mpv opens it while the item is paused).
  Future<bool> _dopOutputOk(
    MpvClient c,
    DsdInfo info, {
    bool wait = false,
  }) async {
    final mobile =
        platform == EnginePlatform.android || platform == EnginePlatform.ios;
    final deadline = DateTime.now().add(
      wait ? const Duration(seconds: 3) : const Duration(seconds: 2),
    );
    Future<Object?> read(String name) async {
      try {
        return await c.getProperty(name);
      } on MpvException {
        return null;
      }
    }

    while (true) {
      final raw = await read('audio-out-params');
      final out = raw is Map<String, Object?> ? raw : null;
      final os = _osOutput;
      if (out != null && (!mobile || os != null)) {
        final bits = sampleFormatBits(out['format'] as String?) ?? 0;
        final rateOk = (out['samplerate'] as int?) == info.dopRate;
        final osOk =
            !mobile ||
            (os!.applied &&
                os.bitPerfect &&
                (os.sampleRate == null || os.sampleRate == info.dopRate));
        // The output must be the real device that was chosen: not the null
        // output mpv falls back to when that device is gone, and not
        // another device.
        final ao = await read('current-ao');
        final device = await read('audio-device');
        return rateOk &&
            bits >= 24 &&
            await read('audio-exclusive') == true &&
            ao is String &&
            ao != 'null' &&
            device == _output.deviceId &&
            osOk;
      }
      if (!DateTime.now().isBefore(deadline)) return false;
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
  }

  // True while a DoP item is being opened or its output re-checked: the
  // output events of that work are not new route changes. A change reported
  // meanwhile is remembered and checked when the work ends.
  var _dopBusy = false;
  var _dopPending = false;
  OpenOptions _openOptions = const OpenOptions();

  void _dopIdle() {
    _dopBusy = false;
    if (_dopPending) {
      _dopPending = false;
      unawaited(_dopRecheck());
    }
  }

  /// A DoP item is playing and the output changed under it (a new config,
  /// another device, the OS moved the route, the output reopened): pause at
  /// once, check the output again, and only resume when it still carries the
  /// stream untouched. Otherwise the item continues as PCM from where it
  /// was.
  ///
  /// Changes the app makes ([setAudioOutput]) and routes the platform
  /// reports are caught before anything new is played. A change mpv makes on
  /// its own (the device vanishes, the output drops exclusive) is seen only
  /// after mpv has reacted, so the DoP item runs with the device pinned by
  /// name and `audio-fallback-to-null`: when that device is gone mpv opens
  /// its silent null output, not another device, and this check then finds
  /// the null output and plays the item as PCM instead.
  Future<void> _dopRecheck({bool? wasPlaying, bool refreshOs = false}) async {
    final c = _client;
    final info = _dopInfo;
    if (!_dop || c == null || info == null) return;
    if (_dopBusy && wasPlaying == null) {
      _dopPending = true;
      return;
    }
    _dopBusy = true;
    final gen = _generation;
    try {
      final resume = wasPlaying ?? !_paused;
      await _quiet(c.setProperty('pause', 'yes'));
      if (refreshOs) {
        _preferredRate = null;
        await _syncOutputPreference();
      }
      final ok = _dopAllowed && await _dopOutputOk(c, info);
      if (gen != _generation || !_dop) return;
      if (ok) {
        if (resume) await _quiet(c.setProperty('pause', 'no'));
        return;
      }
      // The same file as PCM from the current position.
      final at = _state.position;
      _skipDop = true;
      _dopBusy = false;
      final src = _source;
      if (src != null) {
        // On the output the user chose, not whatever mpv was left with.
        await _setAll(c, audioOutputProperties(_output, platform));
        await open(
          src,
          opts: _openOptions.copyWith(start: at, autoplay: resume),
        );
      }
    } finally {
      _dopIdle();
    }
  }

  /// Sets an mpv property as if mpv had changed it itself (tests of the
  /// observer path).
  @visibleForTesting
  Future<void> debugSetMpvProperty(String name, String value) async {
    final c = await _live();
    if (c != null) await c.setProperty(name, value);
  }

  /// The OS changed the audio route (a DAC unplugged, a new default device).
  /// Called by the platform module on such events; checked at once, not on
  /// the next sample.
  @override
  Future<void> audioRouteChanged() => _dopRecheck(refreshOs: true);

  /// Per-file mpv options that keep the DoP stream bit-exact: any gain,
  /// filter, speed change or pitch correction would corrupt the markers
  /// the DAC looks for. File-local, so the next item gets its own back.
  static const Map<String, String> _dopOptions = {
    'volume': '100',
    'af': '',
    'speed': '1',
    'replaygain': 'no',
    'audio-pitch-correction': 'no',
    // A delay pads or trims samples, which breaks the marker sequence.
    'audio-delay': '0',
    // If the pinned device vanishes mpv opens its null output, never another
    // device, which would play the DoP stream as noise.
    'audio-fallback-to-null': 'yes',
  };

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
    _dopBusy = false;
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
          _dop = false;
          _state = _state.copyWith(nextPrepared: false, item: _itemSerial);
          _refreshAudioInfo();
          final c = _client;
          if (c != null) unawaited(_quiet(c.command(['playlist-remove', '0'])));
        } else {
          _loading = true;
          _state = _state.copyWith(item: _itemSerial);
        }
      case MpvFileLoaded():
        _loading = false;
        _eof = false;
        if (_cacheByBitrate) unawaited(_sizeCacheToBitrate(_generation));
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
        for (final w in _restartWaiters) {
          if (!w.isCompleted) w.complete();
        }
        _restartWaiters.clear();
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
        unawaited(_refreshBluetoothCodec());
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
      case 'volume':
        // While ducking scales mpv's volume (no volume-gain), the state still
        // carries the user's volume, also between emits (AUD-045).
        _state = _duckViaVolume
            ? _state.copyWith(volume: _userVolume)
            : applyProperty(_state, name, value);
        return;
      default:
        _state = applyProperty(_state, name, value);
        return;
    }
    if (name.startsWith('audio') || name == 'current-ao') {
      _refreshAudioInfo();
      // The output changed under a playing DoP stream.
      if (_dop &&
          !_dopBusy &&
          const {
            'audio-out-params',
            'current-ao',
            'audio-device',
            'audio-exclusive',
          }.contains(name)) {
        unawaited(_dopRecheck());
      }
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

  Future<void> _refreshBluetoothCodec() async {
    final bridge = config.audioBridge;
    if (bridge == null) return;
    final codec = await bridge.bluetoothCodec();
    if (codec == _bluetoothCodec) return;
    _bluetoothCodec = codec;
    _scheduleEmit();
  }

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
        dop: _dop,
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
    final backend =
        _surface?.backend ?? (_software != null ? 'software' : null);
    final hdrOutput =
        _videoTarget is PlatformViewVideoTarget &&
            _state.video.hdr != HdrType.sdr
        ? HdrOutput.native
        : HdrOutput.sdrToneMapped;
    if (_state.video.renderBackend != backend ||
        _state.video.hdrOutput != hdrOutput) {
      _state = _state.copyWith(
        video: _state.video.copyWith(
          renderBackend: backend,
          hdrOutput: hdrOutput,
        ),
      );
    }
    if (_state.ducked != _duck < 1) {
      _state = _state.copyWith(ducked: _duck < 1);
    }
    // The state reports the user's volume, never the ducked output.
    if (_duckViaVolume && _state.volume != _userVolume) {
      _state = _state.copyWith(volume: _userVolume);
    }
    if (_state.audio.bluetoothCodec != _bluetoothCodec) {
      _state = _state.copyWith(
        audio: _state.audio.copyWith(bluetoothCodec: _bluetoothCodec),
      );
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
    final disc = await _discFor(src);
    if (disc != null) {
      final title = disc.mainTitle;
      if (disc.encrypted || title == null) {
        _state = _state.copyWith(
          notices: {if (disc.encrypted) EngineNotice.encryptedDisc},
        );
        _fail(
          EngineErrorCode.unsupportedFormat,
          disc.encrypted ? 'encrypted disc' : 'disc without titles',
        );
        return;
      }
      // VID-001/VID-007: a disc image or folder opens its main title.
      return await open(
        title.source,
        opts: title.openOptions(opts ?? const OpenOptions()),
      );
    }
    final o = opts ?? const OpenOptions();
    _openOptions = o;
    final gen = ++_generation;
    // An old DoP stream keeps playing until the new item loads, while this
    // open works out what to do (and the DoP guards are not looking at an
    // item that is on its way out): pause it first.
    if (_dop) await _quiet(c.setProperty('pause', 'yes'));
    _source = src;
    _next = null;
    _hevcChecked = false;
    _stall.reset();
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
    final stale = List.of(_ownedFiles);
    _ownedFiles.clear();
    // The previous item's files are released once the new one is loaded.
    unawaited(
      opened.future.whenComplete(() async {
        for (final f in stale) {
          await f.close();
        }
      }),
    );
    final dop = _skipDop ? null : await _dopSource(src, keep: true);
    _skipDop = false;
    final (played, gaplessEnd) = dop != null
        ? (dop.source, null)
        : await _oneGaplessTrim(src);
    if (gen != _generation) return;
    final newDop = dop != null;
    String url;
    var rest = const <String>[];
    switch (played) {
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
    _cacheByBitrate = _isNetwork && o.cacheBytes == null;
    final perFile = <String, String>{
      // A DoP item stays paused until its output has been checked.
      'pause': o.autoplay && !newDop ? 'no' : 'yes',
      if (o.start != null) 'start': secondsValue(o.start!),
      'end': ?gaplessEnd,
      if (newDop) ..._dopOptions,
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
    // From here the new item is the one in play.
    _dop = newDop;
    _dopBusy = newDop;
    _dopInfo = dop?.info;
    _refreshAudioInfo();
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
    final info = _dopInfo;
    if (_dop && info != null) {
      final ok = await _dopOutputOk(c, info, wait: true);
      if (gen != _generation) return;
      if (!ok) {
        // The device would not carry the stream untouched: play the DSD
        // as PCM instead, never as DoP.
        _dopBusy = false;
        _dopPending = false;
        _skipDop = true;
        await open(src, opts: o);
        return;
      }
      if (o.autoplay) await _quiet(c.setProperty('pause', 'no'));
      _dopIdle();
    }
    _scheduleEmit();
  }

  /// Disc images (`.iso`) and VIDEO_TS/BDMV folders, read as discs.
  Future<DiscInfo?> _discFor(MediaSource src) async {
    try {
      switch (src) {
        case UriSource(:final uri) when uri.scheme == 'file':
          final path = uri.toFilePath();
          if (path.toLowerCase().endsWith('.iso')) {
            return await DiscReader.readImage(
              await const LocalFileSystem().open(uri),
            );
          }
          if (FileSystemEntity.isDirectorySync(path) &&
              DiscReader.isDiscFolder(Directory(path))) {
            return await DiscReader.read(Directory(path));
          }
        case VirtualFileSource(:final file)
            when file.uri.path.toLowerCase().endsWith('.iso'):
          return await DiscReader.readImage(file);
        default:
          break;
      }
    } on Object {
      // Not a readable disc: let mpv try the file as it is.
    }
    return null;
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
    if (_seeking || _seekedSinceRestart) {
      // mpv drops a frame step issued while a seek is still settling.
      final settled = Completer<void>();
      _restartWaiters.add(settled);
      await settled.future.timeout(
        const Duration(seconds: 2),
        onTimeout: () {},
      );
    }
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
    // A DoP stream plays at its own speed only.
    if (_dop) return;
    await _quiet(c.setProperty('speed', '$rate'));
  }

  @override
  Future<void> setVolume(double volume) async {
    final c = await _live();
    if (c == null) return;
    _userVolume = volume.clamp(0.0, 3.0);
    await _applyVolume(c);
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
    if (c == null || _dop) return;
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
    // The converted copy would be plaintext on disk.
    if (kind == null || isSensitiveSource(_source)) return null;
    final dir = _tempDir ??= await createScratch('subs');
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
  Future<void> setVideoFilters(VideoFilterChain chain) {
    _wantedFilters = chain;
    // Head moves in 360° video arrive many times a second (VID-041): a
    // running update finishes with the latest chain instead of queueing.
    return _filtersRunning ??= _applyFilters().whenComplete(
      () => _filtersRunning = null,
    );
  }

  VideoFilterChain _wantedFilters = const VideoFilterChain();
  Future<void>? _filtersRunning;
  // What mpv has, so an update sets only what changed (a new `vf` rebuilds
  // the filter chain).
  final _appliedFilterProps = <String, String>{};
  String? _displayIcc;

  Future<void> _applyFilters() async {
    VideoFilterChain? applied;
    while (applied != _wantedFilters) {
      final chain = _wantedFilters;
      final c = await _live();
      if (c == null) return;
      if (chain.iccAuto && chain.iccProfile == null) {
        _displayIcc ??= displayIccProfilePath();
      }
      final props = videoFilterProperties(chain, iccProfilePath: _displayIcc);
      final changed = {
        for (final MapEntry(:key, :value) in props.entries)
          if (_appliedFilterProps[key] != value) key: value,
      };
      await _setAll(c, changed);
      _appliedFilterProps.addAll(changed);
      applied = chain;
    }
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
    // The chain applies from the next item when a DoP stream is playing.
    if (_dop) return;
    await _applyAudioFilters(c);
    await _setAll(c, dspProperties(chain));
  }

  Future<void> _applyAudioFilters(MpvClient c) async {
    if (_dop) return;
    final codec = _state.tracks
        .where((t) => t.type == TrackType.audio && t.id == _state.audioTrackId)
        .firstOrNull
        ?.codec;
    await _quiet(
      c.setProperty(
        'af',
        audioFilterValue(_dsp, sourceCodec: codec, dsd: _output.dsdFilter),
      ),
    );
  }

  @override
  Future<void> setDucking(double gain) async {
    final c = await _live();
    if (c == null) return;
    _duck = gain.clamp(0.0, 1.0);
    if (!_duckViaVolume) {
      try {
        await c.setProperty('volume-gain', duckingGainDb(_duck));
      } on MpvException {
        // No volume-gain in this libmpv: duck through `volume` instead.
        _duckViaVolume = true;
      }
    }
    if (_duckViaVolume) await _applyVolume(c);
    _scheduleEmit();
  }

  /// mpv `volume`: the user's volume, times the ducking gain when ducking
  /// cannot use `volume-gain` (AUD-045).
  Future<void> _applyVolume(MpvClient c) async {
    // Any gain would alter the DoP samples; the device's volume applies.
    if (_dop) return;
    final v = _userVolume * (_duckViaVolume ? _duck : 1) * 100;
    await _quiet(c.setProperty('volume', v.toStringAsFixed(2)));
  }

  @override
  Stream<AudioTapFrame> audioTap({int frames = 1024}) {
    final n = frames.clamp(64, 16384);
    return (_taps[n] ??= AnalysisTap(
      frames: n,
      source: () => _source,
      item: () => _itemSerial,
      position: () => _state.position,
      playing: () => _state.status == PlaybackStatus.playing,
      isLocal: () => switch (_source) {
        UriSource(:final uri) => uri.scheme == 'file',
        _ => false,
      },
      dumpCache: (a, b, path) async {
        final c = _client;
        if (c == null) return false;
        try {
          await c.command([
            'dump-cache',
            secondsValue(a),
            secondsValue(b),
            path,
          ]);
          return true;
        } on MpvException {
          return false;
        }
      },
      libmpvPath: config.libmpvPath,
    )).stream;
  }

  @override
  Stream<Float32List> decodeAudio(
    MediaSource source, {
    int? trackId,
    int sampleRate = 16000,
    bool mono = true,
    Duration? start,
    Duration? end,
  }) {
    if (sampleRate < 8000 || sampleRate > 192000) {
      return Stream.error(
        const EngineException(
          EngineError(
            code: EngineErrorCode.invalidArgument,
            detail: 'sampleRate out of 8000–192000',
          ),
        ),
      );
    }
    return AudioDecoder(
      source,
      trackId: trackId,
      sampleRate: sampleRate,
      mono: mono,
      start: start,
      end: end,
      libmpvPath: config.libmpvPath,
    ).stream;
  }

  static const _stallTick = Duration(milliseconds: 500);

  Future<void> _checkStall() async {
    final rebuild = _stall.check(
      elapsed: _stallTick,
      position: _state.position,
      playing: _deriveStatus() == PlaybackStatus.playing,
      hardwareVideo:
          _state.videoTrackId != null && _state.video.hwdec != HwdecPath.none,
    );
    if (rebuild) await recoverStalledDecoder();
  }

  /// Rebuilds the video decoder in software for the rest of the item, from
  /// the last shown frame (VID-002 stall recovery; tests call it directly).
  @visibleForTesting
  Future<void> recoverStalledDecoder() async {
    final c = _client;
    if (c == null) return;
    config.onLog?.call(
      const MpvLogMessage(
        'mediahro',
        'warn',
        'video decoder stalled; continuing in software',
      ),
    );
    // mpv rebuilds the decoder and seeks back to the last shown frame; the
    // file-local value ends with the item, so the next one starts on the
    // configured decoder.
    await _quiet(c.setProperty('file-local-options/hwdec', 'no'));
    _state = _state.copyWith(
      notices: {..._state.notices, EngineNotice.softwareDecodeFallback},
    );
    _scheduleEmit();
  }

  /// Whether a visualiser tap's analysis core is running (tests).
  @visibleForTesting
  bool get audioTapActive => _taps.values.any((t) => t.active);

  /// PCM bytes the visualiser taps have written (tests: write rate).
  @visibleForTesting
  int get audioTapBytes => _taps.values.fold(0, (n, t) => n + t.bytesWritten);

  @override
  Future<List<EngineAudioDevice>> audioDevices() async {
    final c = await _live();
    if (c == null) return const [];
    try {
      return parseAudioDevices(await c.getProperty('audio-device-list'));
    } on MpvException {
      return const [];
    }
  }

  @override
  Future<void> setVideoTarget(VideoTarget target) async {
    final c = await _live();
    if (c == null) return;
    if (target == _videoTarget) return;
    final bridge = config.renderBridge;
    switch (target) {
      case TextureVideoTarget():
        await _releaseView();
        final surface = _surface;
        if (surface?.androidSurface != null) {
          await _setWid(c, surface!.androidSurface!);
        } else {
          await _quiet(c.setProperty('wid', '0'));
          await _quiet(
            c.setProperty('vo', _surface == null ? 'null' : 'libmpv'),
          );
        }
        await _quiet(c.setProperty('target-colorspace-hint', 'no'));
      case PlatformViewVideoTarget(:final handle):
        if (bridge == null || role != EngineRole.video) {
          throw const EngineException(
            EngineError(
              code: EngineErrorCode.notSupported,
              detail: 'no render bridge for a platform view',
            ),
          );
        }
        if (!bridge.supportsViews) {
          throw const EngineException(
            EngineError(
              code: EngineErrorCode.notSupported,
              detail: 'no native video view on this platform yet (ADR-022)',
            ),
          );
        }
        final native = await bridge.viewSurface(handle);
        if (native == null) {
          throw EngineException(
            EngineError(
              code: EngineErrorCode.invalidArgument,
              detail: 'platform view $handle is not registered',
            ),
          );
        }
        await _releaseView();
        if (platform == EnginePlatform.android) _viewRef = native;
        // Native HDR on HDR displays: mpv signals the content's colour space
        // to the swapchain instead of tone mapping to SDR.
        await _quiet(c.setProperty('target-colorspace-hint', 'yes'));
        await _setWid(c, native);
    }
    _videoTarget = target;
    _scheduleEmit();
  }

  Future<void> _releaseView() async {
    final ref = _viewRef;
    _viewRef = null;
    if (ref != null) await config.renderBridge?.releaseViewSurface(ref);
  }

  @override
  Future<void> export(
    Duration start,
    Duration end,
    ExportFormat format,
    Uri out, {
    bool subtitles = false,
  }) async {
    final src = _source;
    // The clip is a file written for the caller; protected media is not.
    if (isSensitiveSource(src)) throw sensitiveNeedsMemory;
    if (src == null || end <= start || out.scheme != 'file') {
      throw EngineException(
        EngineError(
          code: EngineErrorCode.invalidArgument,
          detail: src == null
              ? 'nothing open to export'
              : 'export needs a non-empty range and a file: URI',
        ),
      );
    }
    try {
      await exportRange(
        url: switch (src) {
          UriSource(:final uri) =>
            uri.scheme == 'file' ? uri.toFilePath() : uri.toString(),
          VirtualFileSource() => '',
        },
        virtualFile: src is VirtualFileSource ? src.file : null,
        start: start,
        end: end,
        format: format,
        out: File(out.toFilePath()),
        subtitles: subtitles,
        libmpvPath: config.libmpvPath,
      );
    } on MpvException catch (e) {
      throw EngineException(
        EngineError(code: EngineErrorCode.unsupportedFormat, detail: '$e'),
      );
    } on ExportException catch (e) {
      throw EngineException(
        EngineError(code: EngineErrorCode.unsupportedFormat, detail: '$e'),
      );
    }
  }

  // The open source and its embedded subtitle track [trackId].
  (MediaSource, Track) _embeddedSubtitle(int trackId) {
    final src = _source;
    // The dump is a disk file; protected media never goes to disk.
    if (isSensitiveSource(src)) throw sensitiveNeedsMemory;
    final track = _state.tracks
        .where((t) => t.type == TrackType.subtitle && t.id == trackId)
        .firstOrNull;
    if (src == null || track == null || track.isExternal) {
      throw EngineException(
        EngineError(
          code: EngineErrorCode.invalidArgument,
          detail: src == null
              ? 'nothing open'
              : 'no embedded subtitle track $trackId',
        ),
      );
    }
    return (src, track);
  }

  @override
  Stream<SubtitleImage> extractSubtitleImages(int trackId) async* {
    final (src, track) = _embeddedSubtitle(trackId);
    yield* extractSubtitleImageTrack(
      url: switch (src) {
        UriSource(:final uri) =>
          uri.scheme == 'file' ? uri.toFilePath() : uri.toString(),
        VirtualFileSource() => '',
      },
      virtualFile: src is VirtualFileSource ? src.file : null,
      headers: src is UriSource ? src.headers : const {},
      trackId: trackId,
      codec: track.codec ?? '',
      audioTracks: _state.tracks
          .where((t) => t.type == TrackType.audio && !t.isExternal)
          .length,
      libmpvPath: config.libmpvPath,
    );
  }

  @override
  Future<void> extractSubtitles(int trackId, Uri out) async {
    final (src, track) = _embeddedSubtitle(trackId);
    if (out.scheme != 'file') {
      throw const EngineException(
        EngineError(
          code: EngineErrorCode.invalidArgument,
          detail: 'subtitles are written to a file: URI',
        ),
      );
    }
    await extractSubtitleTrack(
      url: switch (src) {
        UriSource(:final uri) =>
          uri.scheme == 'file' ? uri.toFilePath() : uri.toString(),
        VirtualFileSource() => '',
      },
      virtualFile: src is VirtualFileSource ? src.file : null,
      headers: src is UriSource ? src.headers : const {},
      trackId: trackId,
      codec: track.codec ?? '',
      audioTracks: _state.tracks
          .where((t) => t.type == TrackType.audio && !t.isExternal)
          .length,
      out: File(out.toFilePath()),
      libmpvPath: config.libmpvPath,
    );
  }

  @override
  Future<void> setAudioOutput(AudioOutputConfig config) async {
    final c = await _live();
    if (c == null) return;
    // A DoP stream on the old output must not reach the new one unchecked:
    // pause first, apply, check the new output, then resume or play PCM.
    final recheck = _dop && _dopInfo != null && !_dopBusy;
    final wasPlaying = !_paused;
    if (recheck) {
      _dopBusy = true;
      await _quiet(c.setProperty('pause', 'yes'));
    }
    final latencyChanged = config.latencyOffset != _output.latencyOffset;
    _output = config;
    await _setAll(c, audioOutputProperties(config, platform));
    await _applyAudioFilters(c);
    if (latencyChanged) await setAudioDelay(_state.audioDelay);
    _preferredRate = null;
    await _syncOutputPreference();
    if (recheck) {
      // Close the output and open it again on the new device: a paused item
      // opens its output once decoding restarts, which a seek to where it is
      // does.
      await _quiet(c.command(['ao-reload']));
      await _quiet(
        c.command(['seek', secondsValue(_state.position), 'absolute+exact']),
      );
      _dopBusy = false;
      _dopPending = false;
      await _dopRecheck(wasPlaying: wasPlaying);
    }
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
    _next = null;
    // A DoP item is never joined gaplessly: its output is checked when it is
    // opened, so the app opens it itself when the current one ends.
    if (next != null && await _dopSource(next, keep: false) != null) {
      _state = _state.copyWith(nextPrepared: false);
      _scheduleEmit();
      return;
    }
    _next = next;
    if (next != null) {
      final (played, gaplessEnd) = await _oneGaplessTrim(next);
      final url = switch (played) {
        UriSource(:final uri) =>
          uri.scheme == 'file' ? uri.toFilePath() : uri.toString(),
        VirtualFileSource(:final file) => _protocol!.urlFor(file),
      };
      await _quiet(
        c.loadfile(
          url,
          flags: 'append',
          options: gaplessEnd == null
              ? null
              : encodeOptions({'end': gaplessEnd}),
        ),
      );
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
    _dop = false;
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
    // mpv writes the frame to a file first; protected media never is.
    if (isSensitiveSource(_source)) throw sensitiveNeedsMemory;
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
    final dir = await createScratch('shot');
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
      await deleteScratch(dir);
    }
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _shuttingDown = true;
    _stallTimer?.cancel();
    final client = await (_ready ?? Future<MpvClient?>.value());
    await _surfaceSub?.cancel();
    final surface = _surface;
    if (surface != null) {
      await config.renderBridge
          ?.dispose(surface.textureId)
          .catchError((Object _) {});
    }
    for (final t in _taps.values) {
      await t.close();
    }
    _taps.clear();
    _protocol?.shutdown();
    for (final f in _ownedFiles) {
      await f.close();
    }
    _ownedFiles.clear();
    _software?.dispose();
    await client?.destroy();
    await _protocol?.dispose();
    final subs = _tempDir;
    if (subs != null) await deleteScratch(subs);
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
  // 'dop' is not an mpv passthrough format: it tells the engine the device
  // takes DSD over PCM (AUD-043).
  'audio-spdif': config.passthroughCodecs.where((c) => c != 'dop').join(','),
  // 0 = open the device at the source rate; in exclusive mode the device
  // switches rate per track (automatic rate switching).
  'audio-samplerate': '0',
  // AUD-044: keep the output fed with silence and wait before the first
  // sample, so a waking Bluetooth link does not cut the start.
  'audio-stream-silence': config.preRoll > Duration.zero ? 'yes' : 'no',
  'audio-wait-open': secondsValue(config.preRoll),
};

/// mpv `volume-gain` in dB for an audio-focus ducking [gain] (0…1, AUD-045).
String duckingGainDb(double gain) {
  if (gain >= 1) return '0';
  if (gain <= 0) return '-96';
  final db = 20 * math.log(gain) / math.ln10;
  return (db < -96 ? -96.0 : db).toStringAsFixed(2);
}

/// mpv's `audio-device-list` as [EngineAudioDevice]s (AUD-040…042).
List<EngineAudioDevice> parseAudioDevices(Object? list) => [
  if (list is List)
    for (final d in list)
      if (d is Map && d['name'] is String)
        EngineAudioDevice(
          id: d['name']! as String,
          name: (d['description'] as String?)?.isNotEmpty ?? false
              ? d['description']! as String
              : d['name']! as String,
          isDefault: d['name'] == 'auto',
        ),
];

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
