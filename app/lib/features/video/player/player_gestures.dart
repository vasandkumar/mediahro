import 'dart:async';

import 'package:flutter/gestures.dart' show kDoubleTapTimeout;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mediahro/app/l10n/gen/app_localizations.dart';
import 'package:mediahro/features/video/player/video_player_controller.dart';
import 'package:mediahro_design/mediahro_design.dart';

/// Which touch gestures are on and how they behave (VID-060).
@immutable
final class GestureConfig {
  const GestureConfig({
    this.seek = true,
    this.brightness = true,
    this.volume = true,
    this.doubleTap = true,
    this.longPress = true,
    this.pinch = true,
    this.subtitleDelay = true,
    this.doubleTapStep = const Duration(seconds: 10),
    this.longPressRate = 2,
    this.sensitivity = 1,
  });

  final bool seek;
  final bool brightness;
  final bool volume;
  final bool doubleTap;
  final bool longPress;
  final bool pinch;
  final bool subtitleDelay;
  final Duration doubleTapStep;
  final double longPressRate;

  /// Multiplies every swipe's effect.
  final double sensitivity;
}

/// Transient feedback near the gesture: a thin bar or a short label, never a
/// centred popup (docs/06 §3.1).
@immutable
final class GestureFeedback {
  const GestureFeedback({
    required this.icon,
    required this.label,
    this.fraction,
    this.alignment = Alignment.center,
  });

  final IconData icon;
  final String label;

  /// 0…1 for a level bar (brightness, volume); null for a label only.
  final double? fraction;
  final Alignment alignment;
}

enum _Drag { none, seek, brightness, volume, subDelay, pinch }

/// The touch layer over the video (VID-060, docs/06 §6.1): tap toggles the
/// chrome, double-tap sides skip, double-tap centre plays/pauses,
/// horizontal swipe seeks, vertical swipes set brightness (left) and volume
/// (right), long-press plays faster while held, pinch toggles fit/fill and a
/// two-finger horizontal swipe shifts the subtitles. Every gesture can be
/// turned off; the touch lock ignores all of them.
class PlayerGestureLayer extends StatefulWidget {
  const PlayerGestureLayer({
    required this.controller,
    required this.config,
    required this.onToggleChrome,
    required this.onFill,
    required this.child,
    this.locked = false,
    this.setBrightness,
    this.initialBrightness = 0.5,
    super.key,
  });

  final VideoPlayerController controller;
  final GestureConfig config;
  final VoidCallback onToggleChrome;

  /// true = fill the screen (crop), false = fit.
  final ValueChanged<bool> onFill;

  /// The player chrome. The layer wraps it so it sees touches over the
  /// video even while the chrome is shown; the chrome's own buttons win
  /// their taps.
  final Widget child;
  final bool locked;

  /// Window brightness through `DisplayFacade` (A I); null hides the
  /// gesture where the platform has none.
  final Future<void> Function(double value)? setBrightness;
  final double initialBrightness;

  @override
  State<PlayerGestureLayer> createState() => _PlayerGestureLayerState();
}

class _PlayerGestureLayerState extends State<PlayerGestureLayer> {
  GestureFeedback? _feedback;
  Timer? _hide;
  _Drag _drag = _Drag.none;
  Offset _start = Offset.zero;
  Duration _seekFrom = Duration.zero;
  Duration _seekTo = Duration.zero;
  double _level = 0;
  late double _brightness = widget.initialBrightness;
  Duration _subFrom = Duration.zero;
  Duration _subTo = Duration.zero;
  bool _hitBoundary = false;
  Offset? _tapAt;
  Timer? _singleTap;

  VideoPlayerController get _c => widget.controller;
  GestureConfig get _cfg => widget.config;

  @override
  void dispose() {
    _hide?.cancel();
    _singleTap?.cancel();
    super.dispose();
  }

  void _show(GestureFeedback f, {bool sticky = false}) {
    _hide?.cancel();
    setState(() => _feedback = f);
    if (!sticky) {
      _hide = Timer(const Duration(milliseconds: 700), () {
        if (mounted) setState(() => _feedback = null);
      });
    }
  }

  void _boundary(bool at) {
    if (at && !_hitBoundary) unawaited(HapticFeedback.selectionClick());
    _hitBoundary = at;
  }

  String _time(Duration d) =>
      formatMediaDuration(d, reference: _c.state.duration ?? d);

  String _signed(AppLocalizations l, Duration d) => d.isNegative
      ? l.videoGestureSeekBack(_time(-d))
      : l.videoGestureSeekForward(_time(d));

  // ---------------------------------------------------------- double tap

  /// Taps are told apart with a timer instead of a double-tap recognizer:
  /// a recognizer here would hold the gesture arena and delay every chrome
  /// button by the double-tap timeout.
  void _onTapUp(TapUpDetails d, Size size) {
    final first = _tapAt;
    if (_cfg.doubleTap &&
        (_singleTap?.isActive ?? false) &&
        first != null &&
        (d.localPosition - first).distance < 80) {
      _singleTap!.cancel();
      _tapAt = null;
      _onDoubleTap(d.localPosition, size);
      return;
    }
    if (!_cfg.doubleTap) {
      widget.onToggleChrome();
      return;
    }
    _tapAt = d.localPosition;
    _singleTap?.cancel();
    _singleTap = Timer(kDoubleTapTimeout, widget.onToggleChrome);
  }

  void _onDoubleTap(Offset at, Size size) {
    final l = AppLocalizations.of(context);
    final third = size.width / 3;
    if (at.dx > third && at.dx < 2 * third) {
      unawaited(_c.togglePlay());
      return;
    }
    final back = at.dx <= third;
    final step = _cfg.doubleTapStep;
    unawaited(_c.seekBy(back ? -step : step));
    _show(
      GestureFeedback(
        icon: back ? Icons.fast_rewind_rounded : Icons.fast_forward_rounded,
        label: back
            ? l.videoGestureSkipBack(step.inSeconds)
            : l.videoGestureSkipForward(step.inSeconds),
        alignment: back ? Alignment.centerLeft : Alignment.centerRight,
      ),
    );
  }

  // ---------------------------------------------------------------- drags

  void _onScaleStart(ScaleStartDetails d) {
    _start = d.localFocalPoint;
    _drag = _Drag.none;
    _hitBoundary = false;
    if (d.pointerCount >= 2) {
      _subFrom = _c.subtitleDelay;
      _subTo = _subFrom;
    }
  }

  void _onScaleUpdate(ScaleUpdateDetails d, Size size) {
    final l = AppLocalizations.of(context);
    final delta = d.localFocalPoint - _start;
    if (_drag == _Drag.none) {
      if (d.pointerCount >= 2) {
        if (_cfg.pinch && (d.scale - 1).abs() > 0.12) {
          _drag = _Drag.pinch;
        } else if (_cfg.subtitleDelay && delta.dx.abs() > 24) {
          _drag = _Drag.subDelay;
        }
      } else if (delta.distance > 18) {
        final horizontal = delta.dx.abs() > delta.dy.abs();
        if (horizontal && _cfg.seek) {
          _drag = _Drag.seek;
          _seekFrom = _c.state.position;
          _seekTo = _seekFrom;
        } else if (!horizontal) {
          final left = _start.dx < size.width / 2;
          if (left && _cfg.brightness && widget.setBrightness != null) {
            _drag = _Drag.brightness;
            _level = _brightness;
          } else if (!left && _cfg.volume) {
            _drag = _Drag.volume;
            _level = _c.volume.clamp(0, 1);
          }
        }
      }
    }
    switch (_drag) {
      case _Drag.none:
        break;
      case _Drag.seek:
        // A full-width swipe covers up to 2 minutes (× sensitivity).
        final total = _c.state.duration ?? Duration.zero;
        final span = total < const Duration(minutes: 2)
            ? total
            : const Duration(minutes: 2);
        final offset = span * (delta.dx / size.width * _cfg.sensitivity);
        var to = _seekFrom + offset;
        if (to < Duration.zero) to = Duration.zero;
        if (total > Duration.zero && to > total) to = total;
        _boundary(to == Duration.zero || to == total);
        _seekTo = to;
        _show(
          GestureFeedback(
            icon: Icons.swap_horiz_rounded,
            label: l.videoGestureSeekTo(_signed(l, to - _seekFrom), _time(to)),
          ),
          sticky: true,
        );
      case _Drag.brightness || _Drag.volume:
        final v = (_level - delta.dy / (size.height * 0.8) * _cfg.sensitivity)
            .clamp(0.0, 1.0);
        _boundary(v == 0 || v == 1);
        final percent = (v * 100).round();
        if (_drag == _Drag.brightness) {
          _brightness = v;
          unawaited(widget.setBrightness!(v));
          _show(
            GestureFeedback(
              icon: Icons.brightness_6_rounded,
              label: l.videoGestureBrightness(percent),
              fraction: v,
              alignment: Alignment.centerLeft,
            ),
            sticky: true,
          );
        } else {
          unawaited(_c.setVolume(v));
          _show(
            GestureFeedback(
              icon: v == 0 ? Icons.volume_off_rounded : Icons.volume_up_rounded,
              label: l.videoGestureVolume(percent),
              fraction: v,
              alignment: Alignment.centerRight,
            ),
            sticky: true,
          );
        }
      case _Drag.subDelay:
        // A full-width two-finger swipe shifts subtitles by 5 s.
        final ms =
            (delta.dx / size.width * 5000 * _cfg.sensitivity / 50).round() * 50;
        _subTo = _subFrom + Duration(milliseconds: ms);
        _show(
          GestureFeedback(
            icon: Icons.subtitles_rounded,
            label: l.videoSubtitleDelayValue(_subTo.inMilliseconds),
          ),
          sticky: true,
        );
      case _Drag.pinch:
        break;
    }
  }

  void _onScaleEnd(ScaleEndDetails d) {
    switch (_drag) {
      case _Drag.seek:
        unawaited(_c.seekTo(_seekTo));
      case _Drag.subDelay:
        unawaited(_c.setSubtitleDelay(_subTo));
      case _Drag.none || _Drag.brightness || _Drag.volume || _Drag.pinch:
        break;
    }
    _drag = _Drag.none;
    _hide?.cancel();
    _hide = Timer(const Duration(milliseconds: 500), () {
      if (mounted) setState(() => _feedback = null);
    });
  }

  void _onScaleUpdateWithPinch(ScaleUpdateDetails d, Size size) {
    _onScaleUpdate(d, size);
    if (_drag == _Drag.pinch) {
      final fill = d.scale > 1;
      widget.onFill(fill);
      final l = AppLocalizations.of(context);
      _show(
        GestureFeedback(
          icon: fill ? Icons.zoom_out_map_rounded : Icons.fit_screen_rounded,
          label: fill ? l.videoZoomFill : l.videoZoomFit,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final f = _feedback;
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        final layer = widget.locked
            ? GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: widget.onToggleChrome,
                child: widget.child,
              )
            : GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapUp: (d) => _onTapUp(d, size),
                onLongPressStart: _cfg.longPress
                    ? (_) {
                        unawaited(_c.holdRate(_cfg.longPressRate));
                        _show(
                          GestureFeedback(
                            icon: Icons.fast_forward_rounded,
                            label: AppLocalizations.of(context)
                                .videoSpeedValue(_cfg.longPressRate),
                            alignment: Alignment.topCenter,
                          ),
                          sticky: true,
                        );
                      }
                    : null,
                onLongPressEnd: _cfg.longPress
                    ? (_) {
                        unawaited(_c.releaseRate());
                        setState(() => _feedback = null);
                      }
                    : null,
                onScaleStart: _onScaleStart,
                onScaleUpdate: (d) => _onScaleUpdateWithPinch(d, size),
                onScaleEnd: _onScaleEnd,
                child: widget.child,
              );
        return Stack(
          fit: StackFit.expand,
          children: [
            layer,
            if (f != null)
              IgnorePointer(
                child: Align(
                  alignment: f.alignment,
                  child: Padding(
                    padding: const EdgeInsets.all(KSpacing.s32),
                    child: _FeedbackPill(feedback: f),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _FeedbackPill extends StatelessWidget {
  const _FeedbackPill({required this.feedback});

  final GestureFeedback feedback;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.titleSmall!
        .copyWith(color: Colors.white);
    return Semantics(
      liveRegion: true,
      label: feedback.label,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(KRadius.md),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: KSpacing.s12,
            vertical: KSpacing.s8,
          ),
          child: ExcludeSemantics(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(feedback.icon, color: Colors.white, size: 20),
                    const SizedBox(width: KSpacing.s8),
                    Text(feedback.label, style: style),
                  ],
                ),
                if (feedback.fraction != null) ...[
                  const SizedBox(height: KSpacing.s8),
                  SizedBox(
                    width: 120,
                    child: LinearProgressIndicator(
                      value: feedback.fraction,
                      minHeight: 3,
                      color: Colors.white,
                      backgroundColor: Colors.white24,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
