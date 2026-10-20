import 'dart:async';
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderException;
import 'package:go_router/go_router.dart';
import 'package:mediahro/app/l10n/gen/app_localizations.dart';
import 'package:mediahro/app/shortcuts/shortcut_catalog.dart';
import 'package:mediahro/app/shortcuts/shortcut_scope.dart';
import 'package:mediahro/core/library/progress.dart';
import 'package:mediahro/engine/engine_pool.dart';
import 'package:mediahro/features/settings/settings_providers.dart';
import 'package:mediahro/features/video/player/info_overlay.dart';
import 'package:mediahro/features/video/player/play_request.dart';
import 'package:mediahro/features/video/player/player_gestures.dart';
import 'package:mediahro/features/video/player/player_platform.dart';
import 'package:mediahro/features/video/player/player_sheets.dart';
import 'package:mediahro/features/video/player/video_memory.dart';
import 'package:mediahro/features/video/player/video_player_controller.dart';
import 'package:mediahro/features/video/video_settings.dart';
import 'package:mediahro/platform/platform_facades.dart';
import 'package:mediahro_design/mediahro_design.dart';
import 'package:mediahro_engine/mediahro_engine.dart';

T? _optional<T>(T Function() read) {
  try {
    return read();
  } on PlatformCapabilityUnavailable {
    return null;
  } on ProviderException catch (e) {
    if (e.exception is PlatformCapabilityUnavailable) return null;
    rethrow;
  }
}

/// Library progress for indexed items (LIB-010); null without a library.
/// `videoOverrides` points it at `progressRepositoryProvider`.
final videoProgressProvider = Provider<ProgressRepository?>((ref) => null);

/// The video player (docs/06 §3.1): video on black under
/// [KPlayerChrome], the touch gesture layer (VID-060), the seek bar with
/// chapters and A-B markers (VID-061), speed (VID-062), chapters and
/// bookmarks (VID-063), resume and post-playback (VID-064), track chooser
/// (VID-065), delays (VID-066) and the info overlay (VID-072).
class VideoPlayerScreen extends ConsumerStatefulWidget {
  const VideoPlayerScreen({required this.request, super.key});

  final PlayRequest request;

  @override
  ConsumerState<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends ConsumerState<VideoPlayerScreen> {
  VideoPlayerController? _c;
  PlayerPlatform? _platform;
  bool _chrome = true;
  bool _locked = false;
  bool _info = false;
  bool _fill = false;
  bool _remaining = false;
  bool _deleteShown = false;
  Duration? _scrub;
  Timer? _hide;
  bool _phone = true;

  @override
  void initState() {
    super.initState();
    unawaited(
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky),
    );
    unawaited(_start());
  }

  Future<void> _start() async {
    final memory = await ref.read(videoMemoryProvider.future);
    if (!mounted) return;
    final engine = ref.read(playbackEngineProvider(EngineRole.video));
    final c = VideoPlayerController(
      engine: engine,
      memory: memory,
      settings: ref.read(settingsStoreProvider),
      progress: ref.read(videoProgressProvider),
      onClose: _close,
      systemLanguages: [
        for (final l in PlatformDispatcher.instance.locales) l.languageCode,
      ],
    )..addListener(_onChange);
    final music = playbackEngineProvider(EngineRole.music);
    final platform = PlayerPlatform(
      controller: c,
      settings: ref.read(settingsStoreProvider),
      display: _optional(() => ref.read(displayProvider)),
      pip: _optional(() => ref.read(pipProvider)),
      session: _optional(() => ref.read(mediaSessionProvider)),
      otherAudio: ref.exists(music) ? ref.read(music) : null,
      isPhone: () => _phone,
    );
    platform.inPip.addListener(_onPip);
    setState(() {
      _c = c;
      _platform = platform;
    });
    _scheduleHide();
    await platform.start();
    await c.open(widget.request);
  }

  void _close() {
    if (!mounted) return;
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/video');
    }
  }

  void _onPip() {
    if (mounted) setState(() {});
  }

  void _onChange() {
    final c = _c!;
    final s = c.state;
    final playing = s.status == PlaybackStatus.playing;
    if (c.deletePending && !_deleteShown) {
      _deleteShown = true;
      unawaited(_confirmDelete());
    }
    if (!playing && !_chrome) setState(() => _chrome = true);
    if (mounted) setState(() {});
  }

  Future<void> _confirmDelete() async {
    final l = AppLocalizations.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l.videoDeleteTitle),
        content: Text(l.videoDeleteBody(_c!.request?.title ?? '')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l.videoCancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l.videoDeleteConfirm),
          ),
        ],
      ),
    );
    _deleteShown = false;
    if (ok ?? false) {
      await _c?.confirmDelete();
    } else {
      _c?.cancelDelete();
    }
  }

  void _scheduleHide() {
    _hide?.cancel();
    _hide = Timer(const Duration(seconds: 3), () {
      final c = _c;
      if (!mounted || c == null || !c.isPlaying || _scrub != null) return;
      if (!KPlayerChrome.shouldAutoHide(context)) return;
      setState(() => _chrome = false);
    });
  }

  void _toggleChrome() {
    setState(() => _chrome = !_chrome);
    if (_chrome) _scheduleHide();
  }

  /// Any control use keeps the chrome up for another 3 s.
  void _poke() {
    if (!_chrome) setState(() => _chrome = true);
    _scheduleHide();
  }

  @override
  void dispose() {
    _hide?.cancel();
    final c = _c;
    final platform = _platform;
    if (platform != null) {
      platform.inPip.removeListener(_onPip);
      // Its synchronous part detaches from the controller before that is
      // disposed below.
      unawaited(platform.dispose());
    }
    if (c != null) {
      c
        ..removeListener(_onChange)
        ..dispose();
      unawaited(c.engine.stop());
    }
    unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge));
    super.dispose();
  }

  // ------------------------------------------------------------- shortcuts

  Map<String, VoidCallback> _handlers(VideoPlayerController c) {
    void run(Future<void> Function() f) {
      _poke();
      unawaited(f());
    }

    Duration s(int n) => Duration(seconds: n);
    const subStep = Duration(milliseconds: 50);
    const audioStep = Duration(milliseconds: 10);
    return {
      'player.playPause': () => run(c.togglePlay),
      'player.seekBack5': () => run(() => c.seekBy(-s(5))),
      'player.seekForward5': () => run(() => c.seekBy(s(5))),
      'player.seekBack1': () => run(() => c.seekBy(-s(1))),
      'player.seekForward1': () => run(() => c.seekBy(s(1))),
      'player.seekBack60': () => run(() => c.seekBy(-s(60))),
      'player.seekForward60': () => run(() => c.seekBy(s(60))),
      'player.seekBack10': () => run(() => c.seekBy(-s(10))),
      'player.seekForward10': () => run(() => c.seekBy(s(10))),
      for (var i = 1; i <= 9; i++)
        'player.jump${i}0': () => run(() => c.jumpToPercent(i * 10)),
      'player.frameBack': () => run(() => c.frameStep(backwards: true)),
      'player.frameForward': () => run(c.frameStep),
      'player.abLoopSet': () => run(c.markLoopPoint),
      'player.abLoopClear': () => run(c.clearLoop),
      'player.speedDown': () => run(() => c.nudgeRate(up: false)),
      'player.speedUp': () => run(() => c.nudgeRate(up: true)),
      'player.speedReset': () => run(c.resetRate),
      'player.volumeUp': () => run(() => c.setVolume(c.volume + 0.05)),
      'player.volumeDown': () => run(() => c.setVolume(c.volume - 0.05)),
      'player.mute': () => run(c.toggleMute),
      'player.audioCycle': () => run(c.cycleAudio),
      'player.subtitleCycle': () => run(c.cycleSubtitle),
      'player.subtitleToggle': () => run(
        () => c.state.subtitleTrackId == null
            ? c.cycleSubtitle()
            : c.selectSubtitle(null),
      ),
      'player.subtitleDelayMinus': () =>
          run(() => c.setSubtitleDelay(c.subtitleDelay - subStep)),
      'player.subtitleDelayPlus': () =>
          run(() => c.setSubtitleDelay(c.subtitleDelay + subStep)),
      'player.audioDelayMinus': () =>
          run(() => c.setAudioDelay(c.audioDelay - audioStep)),
      'player.audioDelayPlus': () =>
          run(() => c.setAudioDelay(c.audioDelay + audioStep)),
      'player.info': () => setState(() => _info = !_info),
      'player.pip': () => unawaited(_platform?.enterPip()),
      'player.exitFullscreen': _close,
    };
  }

  // ---------------------------------------------------------------- build

  GestureConfig _gestures(WidgetRef ref) {
    final g = ref.watch(settingsProvider);
    return GestureConfig(
      seek: g.get(VideoSettings.gestureSeek),
      brightness: g.get(VideoSettings.gestureBrightness),
      volume: g.get(VideoSettings.gestureVolume),
      doubleTap: g.get(VideoSettings.gestureDoubleTap),
      longPress: g.get(VideoSettings.gestureLongPress),
      pinch: g.get(VideoSettings.gesturePinch),
      subtitleDelay: g.get(VideoSettings.gestureSubtitleDelay),
      doubleTapStep: Duration(seconds: g.get(VideoSettings.doubleTapSeconds)),
      longPressRate: g.get(VideoSettings.longPressSpeed),
      sensitivity: g.get(VideoSettings.gestureSensitivity),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final c = _c;
    if (c == null) {
      return const ColoredBox(color: Colors.black, child: SizedBox.expand());
    }
    _phone = MediaQuery.sizeOf(context).shortestSide < 600;
    final s = c.state;
    final dur = s.duration ?? Duration.zero;
    final shown = _scrub ?? s.position;
    String t(Duration d) => formatMediaDuration(d, reference: dur);
    final playing = s.status == PlaybackStatus.playing;
    final touch = switch (Theme.of(context).platform) {
      TargetPlatform.android || TargetPlatform.iOS => true,
      _ => false,
    };

    final video = _VideoSurface(
      textureId: c.engine.textureId,
      size: PlayerPlatform.videoSize(s),
      fill: _fill,
    );

    final platform = _platform!;
    // In picture-in-picture only the video shows (VID-067).
    if (platform.inPip.value) {
      return ColoredBox(color: Colors.black, child: video);
    }

    final error = s.error;
    final overlay = Stack(
      fit: StackFit.expand,
      children: [
        if (_info)
          Positioned(
            top: 72,
            left: KSpacing.s16,
            child: SafeArea(child: VideoInfoOverlay(state: s)),
          ),
        if (s.status == PlaybackStatus.buffering ||
            s.status == PlaybackStatus.opening)
          const Center(child: CircularProgressIndicator(color: Colors.white)),
        if (error != null)
          Center(
            child: _ErrorCard(error: error, onBack: _close),
          ),
        if (c.resumedFrom case final from? when error == null)
          Positioned(
            left: KSpacing.s16,
            bottom: 140,
            child: SafeArea(
              child: _Banner(
                text: l.videoResumedAt(t(from)),
                action: l.videoStartOver,
                onAction: () => unawaited(c.startOver()),
                onDismiss: c.dismissResumed,
              ),
            ),
          ),
        if (c.nextUp case final next?)
          Positioned(
            right: KSpacing.s16,
            bottom: 140,
            child: SafeArea(
              child: _Banner(
                text: l.videoNextUp(next.request.title, next.remaining),
                action: l.videoPlayNow,
                onAction: () => unawaited(c.playNextNow()),
                onDismiss: c.cancelNextUp,
              ),
            ),
          ),
        if (_locked && _chrome)
          Center(
            child: KIconButton(
              icon: KIcon.lock,
              label: l.videoUnlock,
              color: Colors.white,
              size: 32,
              onPressed: () => setState(() => _locked = false),
            ),
          ),
      ],
    );

    final seekBar = Stack(
      clipBehavior: Clip.none,
      children: [
        KSeekBar(
          position: shown,
          duration: dur,
          buffered: s.bufferedUntil,
          chapters: [for (final ch in c.chapters) ch.start],
          onDark: true,
          onScrubStart: () => setState(() => _scrub = s.position),
          onScrubUpdate: (d) => setState(() => _scrub = d),
          onScrubEnd: () {
            setState(() => _scrub = null);
            _scheduleHide();
          },
          onSeek: (d) {
            _poke();
            unawaited(c.seekTo(d));
          },
          previewBuilder: (context, at) =>
              _SeekPreview(label: t(at), chapter: _chapterAt(c, at)),
        ),
        if (dur > Duration.zero)
          Positioned.fill(
            child: IgnorePointer(
              child: _LoopMarkers(a: c.abA, b: c.abB, duration: dur),
            ),
          ),
      ],
    );

    final chrome = KPlayerChrome(
      video: video,
      visible: _chrome && !_locked,
      title: c.request?.title ?? widget.request.title,
      subtitle: c.request?.subtitle,
      sourceBadge: c.request?.sourceBadge,
      onBack: _close,
      overlay: overlay,
      topActions: [
        KIconButton(
          icon: KIcon.info,
          label: l.videoInfoToggle,
          selected: _info,
          color: Colors.white,
          onPressed: () => setState(() => _info = !_info),
        ),
        if (platform.pipSupported)
          KIconButton(
            icon: KIcon.pip,
            label: l.videoPip,
            color: Colors.white,
            onPressed: () => unawaited(platform.enterPip()),
          ),
        KIconButton(
          icon: KIcon.more,
          label: l.videoMoreTitle,
          color: Colors.white,
          onPressed: () => unawaited(showMoreSheet(context, c, platform)),
        ),
      ],
      seekBar: seekBar,
      elapsed: Text(t(shown)),
      remaining: GestureDetector(
        onTap: () => setState(() => _remaining = !_remaining),
        child: Semantics(
          button: true,
          label: _remaining ? l.videoShowDuration : l.videoShowRemaining,
          child: Text(
            _remaining
                ? l.videoRemaining(
                    t(
                      dur - shown < Duration.zero ? Duration.zero : dur - shown,
                    ),
                  )
                : t(dur),
          ),
        ),
      ),
      transport: [
        KIconButton(
          icon: KIcon.seekBack,
          label: l.videoSeekBack(10),
          color: Colors.white,
          onPressed: () {
            _poke();
            unawaited(c.seekBy(const Duration(seconds: -10)));
          },
        ),
        KIconButton(
          icon: playing ? KIcon.pause : KIcon.play,
          label: playing ? l.videoPause : l.videoPlay,
          color: Colors.white,
          size: 40,
          onPressed: () {
            _poke();
            unawaited(c.togglePlay());
          },
        ),
        KIconButton(
          icon: KIcon.seekForward,
          label: l.videoSeekForward(10),
          color: Colors.white,
          onPressed: () {
            _poke();
            unawaited(c.seekBy(const Duration(seconds: 10)));
          },
        ),
      ],
      chips: [
        KChip(
          label: l.videoSpeedValue(s.rate),
          semanticLabel: l.videoSpeedChip(l.videoSpeedValue(s.rate)),
          onDark: true,
          onPressed: () => unawaited(showSpeedSheet(context, c)),
        ),
        KChip(
          label: l.videoSubtitlesTitle,
          icon: KIcon.subtitles,
          selected: s.subtitleTrackId != null,
          semanticLabel: s.subtitleTrackId == null
              ? l.videoSubtitlesChipOff
              : l.videoSubtitlesChipOn,
          onDark: true,
          onPressed: () => unawaited(showSubtitleSheet(context, c)),
        ),
        KChip(
          label: l.videoAudioTitle,
          icon: KIcon.audioTrack,
          onDark: true,
          onPressed: () => unawaited(showAudioSheet(context, c)),
        ),
      ],
      trailingActions: [
        if (touch)
          KIconButton(
            icon: KIcon.lock,
            label: l.videoLock,
            color: Colors.white,
            onPressed: () => setState(() {
              _locked = true;
              _chrome = false;
            }),
          ),
      ],
    );

    final surface = touch
        ? PlayerGestureLayer(
            controller: c,
            config: _gestures(ref),
            locked: _locked,
            onToggleChrome: _toggleChrome,
            onFill: (v) => setState(() => _fill = v),
            setBrightness: switch (platform.display) {
              final d? => d.setWindowBrightness,
              null => null,
            },
            child: chrome,
          )
        // Desktop: a click on the video plays or pauses; buttons keep their
        // own clicks, and moving the mouse shows the chrome.
        : GestureDetector(
            onTap: () => unawaited(c.togglePlay()),
            child: MouseRegion(onHover: (_) => _poke(), child: chrome),
          );

    return Scaffold(
      backgroundColor: Colors.black,
      body: ShortcutScopeWidget(
        scope: ShortcutScope.player,
        handlers: _handlers(c),
        child: Focus(autofocus: true, child: surface),
      ),
    );
  }

  static String? _chapterAt(VideoPlayerController c, Duration at) {
    final cs = c.chapters;
    for (var i = cs.length - 1; i >= 0; i--) {
      if (at >= cs[i].start) return cs[i].title;
    }
    return null;
  }
}

class _VideoSurface extends StatelessWidget {
  const _VideoSurface({
    required this.textureId,
    required this.size,
    required this.fill,
  });

  final int? textureId;
  final (int, int)? size;
  final bool fill;

  @override
  Widget build(BuildContext context) {
    final id = textureId;
    if (id == null) return const ColoredBox(color: Colors.black);
    final (w, h) = size ?? (16, 9);
    return ColoredBox(
      color: Colors.black,
      child: ClipRect(
        child: FittedBox(
          fit: fill ? BoxFit.cover : BoxFit.contain,
          child: SizedBox(
            width: w.toDouble(),
            height: h.toDouble(),
            child: Texture(textureId: id, filterQuality: FilterQuality.medium),
          ),
        ),
      ),
    );
  }
}

class _SeekPreview extends StatelessWidget {
  const _SeekPreview({required this.label, this.chapter});

  final String label;
  final String? chapter;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelLarge!
        .copyWith(color: Colors.white);
    return Center(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.75),
          borderRadius: BorderRadius.circular(KRadius.sm),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: KSpacing.s8,
            vertical: KSpacing.s4,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (chapter != null)
                Text(
                  chapter!,
                  style: style.copyWith(color: Colors.white70),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              Text(label, style: style),
            ],
          ),
        ),
      ),
    );
  }
}

/// A and B markers over the seek bar (VID-061).
class _LoopMarkers extends StatelessWidget {
  const _LoopMarkers({
    required this.a,
    required this.b,
    required this.duration,
  });

  final Duration? a;
  final Duration? b;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    if (a == null) return const SizedBox.shrink();
    final accent = Theme.of(context).colorScheme.primary;
    return LayoutBuilder(
      builder: (context, c) {
        double x(Duration d) =>
            c.maxWidth *
            (d.inMilliseconds / duration.inMilliseconds).clamp(0, 1);
        return Stack(
          children: [
            if (b != null)
              Positioned(
                left: x(a!),
                width: (x(b!) - x(a!)).clamp(0, c.maxWidth),
                top: c.maxHeight / 2 - 2,
                height: 4,
                child: ColoredBox(color: accent.withValues(alpha: 0.6)),
              ),
            for (final m in [a!, ?b])
              Positioned(
                left: x(m) - 1.5,
                top: c.maxHeight / 2 - 9,
                width: 3,
                height: 18,
                child: ColoredBox(color: accent),
              ),
          ],
        );
      },
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({
    required this.text,
    required this.action,
    required this.onAction,
    required this.onDismiss,
  });

  final String text;
  final String action;
  final VoidCallback onAction;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Semantics(
      liveRegion: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.75),
          borderRadius: BorderRadius.circular(KRadius.md),
        ),
        child: Padding(
          padding: const EdgeInsets.only(left: KSpacing.s12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(text, style: const TextStyle(color: Colors.white)),
              TextButton(onPressed: onAction, child: Text(action)),
              KIconButton(
                icon: KIcon.close,
                label: l.videoDismiss,
                color: Colors.white,
                onPressed: onDismiss,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Engine errors as user copy (docs/06 §8), detail behind "Copy details".
class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.error, required this.onBack});

  final EngineError error;
  final VoidCallback onBack;

  static String message(AppLocalizations l, EngineErrorCode code) =>
      switch (code) {
        EngineErrorCode.unsupportedFormat => l.videoErrorUnsupported,
        EngineErrorCode.decodeFailed => l.videoErrorDecode,
        EngineErrorCode.sourceUnavailable => l.videoErrorSource,
        EngineErrorCode.networkTimeout => l.videoErrorNetwork,
        EngineErrorCode.libraryMissing => l.videoErrorEngineMissing,
        EngineErrorCode.engineCrashed ||
        EngineErrorCode.invalidArgument ||
        EngineErrorCode.notSupported ||
        EngineErrorCode.unknown => l.videoErrorGeneric,
      };

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.all(KSpacing.s24),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.8),
          borderRadius: BorderRadius.circular(KRadius.md),
        ),
        child: Padding(
          padding: const EdgeInsets.all(KSpacing.s16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                message(l, error.code),
                style: const TextStyle(color: Colors.white),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: KSpacing.s12),
              Wrap(
                spacing: KSpacing.s8,
                children: [
                  if (error.detail != null)
                    KButton(
                      label: l.videoCopyDetails,
                      icon: KIcon.copy,
                      onPressed: () => unawaited(
                        Clipboard.setData(ClipboardData(text: error.detail!)),
                      ),
                    ),
                  KButton(
                    label: l.videoChooseAnother,
                    variant: KButtonVariant.primary,
                    onPressed: onBack,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
