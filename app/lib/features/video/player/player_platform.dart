import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:mediahro/features/settings/settings_store.dart';
import 'package:mediahro/features/video/player/video_player_controller.dart';
import 'package:mediahro/features/video/video_settings.dart';
import 'package:mediahro/platform/platform_facades.dart';
import 'package:mediahro_engine/mediahro_engine.dart';

/// The video player's side of the shared media-session owner (ADR-029,
/// `mediaSessionOwnerProvider`).
abstract interface class SessionOwnership {
  bool get ownedByVideo;
  void claim();
  void release();
}

/// Rotation without a display facade (desktop has none to do; iOS until
/// C4b's lands): Flutter's own orientation request.
abstract interface class OrientationRequests {
  Future<void> lock(OrientationLock lock);
}

final class SystemChromeOrientation implements OrientationRequests {
  const SystemChromeOrientation();

  @override
  Future<void> lock(OrientationLock lock) =>
      SystemChrome.setPreferredOrientations(switch (lock) {
        OrientationLock.landscape => const [
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ],
        OrientationLock.portrait => const [DeviceOrientation.portraitUp],
        OrientationLock.auto || OrientationLock.followVideo => const [],
      });
}

/// What the player asks of the platform while it is open, through C4's
/// facades only:
///
/// - screen on while playing, window brightness, rotation that follows the
///   video or the user's lock, given back on exit (VID-070, `DisplayFacade`);
/// - picture-in-picture on demand and, when the user opts in, on leaving
///   the app (VID-067, `PipFacade`);
/// - playing on in the background, with the video track off to save power
///   (VID-068), and the OS media session for the lock screen, notification,
///   headset and media keys (VID-068, VID-074, `MediaSessionFacade`).
///
/// Every facade is optional: where a platform has none the feature quietly
/// does nothing, or falls back (rotation through [OrientationRequests]).
final class PlayerPlatform with WidgetsBindingObserver {
  PlayerPlatform({
    required this.controller,
    required this.settings,
    this.display,
    this.pip,
    this.session,
    this.otherAudio,
    this.orientation = const SystemChromeOrientation(),
    this.sessionOwner,
    this.isPhone = _always,
  });

  static bool _always() => true;

  final VideoPlayerController controller;
  final SettingsStore settings;
  final DisplayFacade? display;
  final PipFacade? pip;
  final MediaSessionFacade? session;

  /// The music engine, paused when a video starts so two sources never play
  /// over each other.
  final PlaybackEngine? otherAudio;
  final OrientationRequests orientation;

  /// The shared session owner (ADR-029); null where there is no session.
  final SessionOwnership? sessionOwner;

  /// Phones get portrait back after a landscape video (VID-070).
  final bool Function() isPhone;

  /// True while the system picture-in-picture window shows the video.
  final ValueNotifier<bool> inPip = ValueNotifier(false);

  /// "Keep playing in the background" for this session only (VID-068).
  final ValueNotifier<bool> backgroundThisSession = ValueNotifier(false);

  bool _pipSupported = false;
  bool get pipSupported => _pipSupported;

  StreamSubscription<bool>? _pipSub;
  StreamSubscription<RemoteCommand>? _commands;
  bool _keepOn = false;
  // Auto-enter starts off on the platform side.
  bool _autoPip = false;
  OrientationLock? _lock;
  bool _offForBackground = false;
  bool _sessionActive = false;
  int? _shownItem;
  String? _shownTitle;
  SessionPlaybackState? _shownState;
  Duration _shownPosition = Duration.zero;
  double _shownRate = 1;
  bool _started = false;
  bool _disposed = false;

  Future<void> start() async {
    if (_started) return;
    _started = true;
    WidgetsBinding.instance.addObserver(this);
    controller.addListener(_onChange);
    _commands = session?.commands.listen((c) => unawaited(_onCommand(c)));
    final p = pip;
    if (p != null) {
      _pipSub = p.isActive.listen((a) => inPip.value = a);
      try {
        _pipSupported = await p.isSupported();
      } on PlatformCapabilityUnavailable {
        _pipSupported = false;
      }
    }
    _onChange();
  }

  // ------------------------------------------------------------------ PiP

  /// Enters picture-in-picture with the video's shape (VID-067).
  Future<bool> enterPip() async {
    final p = pip;
    if (p == null || !_pipSupported) return false;
    return await p.enter(aspectRatio: aspectRatio(controller.state));
  }

  /// Width / height of the video, 16:9 until it is known; clamped to the
  /// range Android accepts for picture-in-picture (1:2.39 … 2.39:1).
  static double aspectRatio(PlaybackState s) {
    final size = videoSize(s);
    final r = size == null ? 16 / 9 : size.$1 / size.$2;
    return r.clamp(1 / 2.39, 2.39);
  }

  static (int, int)? videoSize(PlaybackState s) {
    final v = s.tracks
        .where((t) => t.type == TrackType.video && t.id == s.videoTrackId)
        .firstOrNull;
    final w = s.video.width ?? v?.width;
    final h = s.video.height ?? v?.height;
    return w == null || h == null || w == 0 || h == 0 ? null : (w, h);
  }

  // --------------------------------------------------------- state sync

  void _onChange() {
    if (_disposed) return;
    final s = controller.state;
    final playing = s.status == PlaybackStatus.playing;
    if (playing != _keepOn) {
      _keepOn = playing;
      unawaited(display?.keepScreenOn(on: playing));
      if (playing) unawaited(_pauseOtherAudio());
    }
    final wantAuto =
        _pipSupported && playing && settings.get(VideoSettings.autoPip);
    if (wantAuto != _autoPip && pip != null && _pipSupported) {
      _autoPip = wantAuto;
      unawaited(pip!.setAutoEnter(enabled: wantAuto));
    }
    _syncAspect(s);
    _applyOrientation(s);
    unawaited(_syncSession(s));
  }

  double? _aspect;

  /// Tells the platform the video's shape whenever it changes (ADR-028):
  /// auto-enter and an open PiP window use it.
  void _syncAspect(PlaybackState s) {
    final p = pip;
    if (p == null || videoSize(s) == null) return;
    final r = aspectRatio(s);
    if (r == _aspect) return;
    _aspect = r;
    unawaited(p.setAspectRatio(r));
  }

  Future<void> _pauseOtherAudio() async {
    final other = otherAudio;
    if (other != null && other.current.status == PlaybackStatus.playing) {
      await other.pause();
    }
  }

  /// The lock for the current setting and video shape (VID-070).
  static OrientationLock lockFor(VideoOrientation mode, (int, int)? size) =>
      switch (mode) {
        VideoOrientation.followVideo =>
          size == null
              ? OrientationLock.landscape
              : size.$1 >= size.$2
              ? OrientationLock.landscape
              : OrientationLock.portrait,
        VideoOrientation.landscape => OrientationLock.landscape,
        VideoOrientation.portrait => OrientationLock.portrait,
        VideoOrientation.auto => OrientationLock.auto,
      };

  void _applyOrientation(PlaybackState s) {
    final mode = settings.get(VideoSettings.orientation);
    final size = videoSize(s);
    // Follow the video only once its shape is known.
    if (mode == VideoOrientation.followVideo && size == null) return;
    final lock = lockFor(mode, size);
    if (lock == _lock) return;
    _lock = lock;
    unawaited(_requestLock(lock));
  }

  Future<void> _requestLock(OrientationLock lock) async {
    final d = display;
    if (d != null) {
      try {
        await d.setOrientationLock(lock);
        return;
      } on PlatformCapabilityUnavailable {
        // Fall through to Flutter's request.
      }
    }
    await orientation.lock(lock);
  }

  // --------------------------------------------------------- background

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.hidden || AppLifecycleState.paused:
        unawaited(_toBackground());
      case AppLifecycleState.resumed:
        unawaited(_toForeground());
      case AppLifecycleState.inactive || AppLifecycleState.detached:
        break;
    }
  }

  bool get backgroundAllowed =>
      backgroundThisSession.value ||
      settings.get(VideoSettings.backgroundPlay) == BackgroundPlay.always;

  Future<void> _toBackground() async {
    if (inPip.value) return;
    if (controller.state.status != PlaybackStatus.playing) return;
    if (!backgroundAllowed) {
      await controller.engine.pause();
      return;
    }
    if (settings.get(VideoSettings.backgroundVideoOff) &&
        !controller.videoOff) {
      _offForBackground = true;
      await controller.setVideoOff(off: true);
    }
  }

  Future<void> _toForeground() async {
    if (!_offForBackground) return;
    _offForBackground = false;
    await controller.setVideoOff(off: false);
  }

  // ------------------------------------------------------- media session

  Future<void> _syncSession(PlaybackState s) async {
    final ses = session;
    final r = controller.request;
    if (ses == null || r == null) return;
    final owner = sessionOwner;
    if (_sessionActive && owner != null && !owner.ownedByVideo) {
      // Music took the session: let go until the video plays again.
      _sessionActive = false;
      _shownItem = null;
      _shownState = null;
    }
    if (!_sessionActive) {
      if (s.status != PlaybackStatus.playing) return;
      _sessionActive = true;
      owner?.claim();
      await ses.activate(MediaSessionKind.video);
    }
    if (_shownItem != s.item || _shownTitle != r.title) {
      _shownItem = s.item;
      _shownTitle = r.title;
      await ses.setNowPlaying(
        NowPlaying(title: r.title, artist: r.subtitle, duration: s.duration),
      );
    }
    final state = switch (s.status) {
      PlaybackStatus.playing => SessionPlaybackState.playing,
      PlaybackStatus.buffering ||
      PlaybackStatus.opening => SessionPlaybackState.buffering,
      PlaybackStatus.paused => SessionPlaybackState.paused,
      _ => SessionPlaybackState.stopped,
    };
    // Positions only on changes and jumps; the OS extrapolates.
    final expected = _shownPosition;
    final jumped = (s.position - expected).abs() > const Duration(seconds: 2);
    _shownPosition = s.position;
    if (state == _shownState && !jumped && s.rate == _shownRate) return;
    _shownState = state;
    _shownRate = s.rate;
    await ses.setPlaybackStatus(
      SessionPlaybackStatus(
        state: state,
        position: s.position,
        rate: s.rate,
        canSkipNext: r.next.isNotEmpty,
        canSkipPrevious: true,
      ),
    );
  }

  Future<void> _onCommand(RemoteCommand c) async {
    // The music player shares the session; act only while video owns it
    // (ADR-029).
    if (!_sessionActive) return;
    if (sessionOwner case final o? when !o.ownedByVideo) return;
    final ctl = controller;
    switch (c) {
      case PlayCommand():
        await ctl.engine.play();
      case PauseCommand():
        await ctl.engine.pause();
      case TogglePlayPauseCommand():
        await ctl.togglePlay();
      case NextCommand():
        await ctl.playNextNow();
      case PreviousCommand():
        await ctl.seekTo(Duration.zero);
      case StopCommand():
        await ctl.engine.pause();
      case SeekToCommand(:final position):
        await ctl.seekTo(position);
      case SkipByCommand(:final offset):
        await ctl.seekBy(offset);
      case SetRateCommand(:final rate):
        await ctl.setRate(rate);
    }
  }

  /// Leaves the platform as the player found it.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    controller.removeListener(_onChange);
    await _pipSub?.cancel();
    await _commands?.cancel();
    final d = display;
    await d?.keepScreenOn(on: false);
    await d?.setWindowBrightness(null);
    if (_autoPip) await pip?.setAutoEnter(enabled: false);
    if (_sessionActive) {
      // If music took the session meanwhile it is music's now: leave it
      // active (ADR-029).
      final ours = sessionOwner?.ownedByVideo ?? true;
      sessionOwner?.release();
      if (ours) await session?.deactivate();
    }
    // After a landscape video a phone with auto-rotate off would stay in
    // landscape: ask for portrait first, then hand rotation back.
    if (_lock == OrientationLock.landscape && isPhone()) {
      await _requestLock(OrientationLock.portrait);
      await Future<void>.delayed(const Duration(milliseconds: 400));
    }
    if (_lock != null) await _requestLock(OrientationLock.auto);
    inPip.dispose();
    backgroundThisSession.dispose();
  }
}
