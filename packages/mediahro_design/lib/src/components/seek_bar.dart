import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:mediahro_design/src/components/focus.dart';
import 'package:mediahro_design/src/foundation/format.dart';
import 'package:mediahro_design/src/foundation/strings.dart';
import 'package:mediahro_design/src/theme.dart';

/// Media seek bar (docs/06 §3.1, §7).
///
/// - Chapter ticks, buffered range, thumbnail preview while scrubbing.
/// - Screen readers: adjustable with 1 % steps, plus "+10 %" / "−10 %"
///   custom actions; the value reads "1:23 of 45:00".
/// - Keyboard: ←/→ 1 %, Page Up/Down 10 %, Home/End.
/// - Always laid out left-to-right: media timelines are not mirrored in RTL
///   locales (Material bidirectionality guidance).
class KSeekBar extends StatefulWidget {
  const KSeekBar({
    required this.position,
    required this.duration,
    this.buffered,
    this.chapters = const [],
    this.onSeek,
    this.onScrubStart,
    this.onScrubUpdate,
    this.onScrubEnd,
    this.previewBuilder,
    this.onDark = false,
    this.focusNode,
    super.key,
  });

  final Duration position;
  final Duration duration;
  final Duration? buffered;

  /// Chapter start times, drawn as gaps in the track.
  final List<Duration> chapters;

  /// Final seek (tap, drag end, keyboard, accessibility action).
  final ValueChanged<Duration>? onSeek;
  final VoidCallback? onScrubStart;

  /// Live position while dragging (for preview frames).
  final ValueChanged<Duration>? onScrubUpdate;
  final VoidCallback? onScrubEnd;

  /// Thumbnail preview above the thumb while scrubbing.
  final Widget Function(BuildContext context, Duration at)? previewBuilder;

  /// White track on the player scrim.
  final bool onDark;
  final FocusNode? focusNode;

  @override
  State<KSeekBar> createState() => _KSeekBarState();
}

class _KSeekBarState extends State<KSeekBar> {
  Duration? _drag;
  bool _focused = false;

  int get _totalMs => math.max(widget.duration.inMilliseconds, 1);

  Duration get _shown => _drag ?? widget.position;

  double _fractionOf(Duration d) =>
      (d.inMilliseconds / _totalMs).clamp(0.0, 1.0);

  Duration _at(double fraction) =>
      Duration(milliseconds: (fraction.clamp(0.0, 1.0) * _totalMs).round());

  Duration _step(double percent) =>
      Duration(milliseconds: (_totalMs * percent / 100).round());

  void _seekBy(Duration delta) {
    final next = _shown + delta;
    final clamped = next < Duration.zero
        ? Duration.zero
        : (next > widget.duration ? widget.duration : next);
    widget.onSeek?.call(clamped);
  }

  double _fractionAt(Offset local, double width) => local.dx / width;

  void _start(Offset local, double width) {
    widget.onScrubStart?.call();
    setState(() => _drag = _at(_fractionAt(local, width)));
    widget.onScrubUpdate?.call(_drag!);
  }

  void _update(Offset local, double width) {
    setState(() => _drag = _at(_fractionAt(local, width)));
    widget.onScrubUpdate?.call(_drag!);
  }

  void _end() {
    final target = _drag;
    setState(() => _drag = null);
    widget.onScrubEnd?.call();
    if (target != null) widget.onSeek?.call(target);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final strings = KStrings.of(context);
    final scheme = theme.colorScheme;
    final enabled = widget.onSeek != null;
    final minTarget = theme.mediahroShape.minTarget;
    final active = widget.onDark ? Colors.white : scheme.primary;
    final inactive = widget.onDark
        ? Colors.white.withValues(alpha: 0.3)
        : scheme.onSurface.withValues(alpha: 0.2);
    final buffered = widget.onDark
        ? Colors.white.withValues(alpha: 0.55)
        : scheme.onSurface.withValues(alpha: 0.4);

    String spoken(Duration d) => strings.seekValue(
      formatMediaDuration(d, reference: widget.duration),
      formatMediaDuration(widget.duration),
    );
    final small = _step(1);
    final large = _step(10);

    final bar = LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final preview = _drag != null && widget.previewBuilder != null;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: enabled
              ? (d) => widget.onSeek!(_at(_fractionAt(d.localPosition, width)))
              : null,
          onHorizontalDragStart: enabled
              ? (d) => _start(d.localPosition, width)
              : null,
          onHorizontalDragUpdate: enabled
              ? (d) => _update(d.localPosition, width)
              : null,
          onHorizontalDragEnd: enabled ? (_) => _end() : null,
          onHorizontalDragCancel: enabled ? _end : null,
          dragStartBehavior: DragStartBehavior.down,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              SizedBox(
                height: minTarget,
                width: width,
                child: CustomPaint(
                  painter: _SeekPainter(
                    position: _fractionOf(_shown),
                    buffered: widget.buffered == null
                        ? null
                        : _fractionOf(widget.buffered!),
                    chapters: [for (final c in widget.chapters) _fractionOf(c)],
                    active: active,
                    inactive: inactive,
                    bufferedColor: buffered,
                    gap: widget.onDark ? Colors.black : scheme.surface,
                    thick: _drag != null || _focused,
                  ),
                ),
              ),
              if (preview)
                Positioned(
                  bottom: minTarget,
                  left: (_fractionOf(_drag!) * width - 80).clamp(
                    0,
                    math.max(0, width - 160),
                  ),
                  width: 160,
                  child: ExcludeSemantics(
                    child: widget.previewBuilder!(context, _drag!),
                  ),
                ),
            ],
          ),
        );
      },
    );

    return Directionality(
      textDirection: TextDirection.ltr,
      child: FocusableActionDetector(
        focusNode: widget.focusNode,
        enabled: enabled,
        onShowFocusHighlight: (v) => setState(() => _focused = v),
        shortcuts: const {
          SingleActivator(LogicalKeyboardKey.arrowRight): _SeekIntent(1),
          SingleActivator(LogicalKeyboardKey.arrowLeft): _SeekIntent(-1),
          SingleActivator(LogicalKeyboardKey.pageUp): _SeekIntent(10),
          SingleActivator(LogicalKeyboardKey.pageDown): _SeekIntent(-10),
          SingleActivator(LogicalKeyboardKey.home): _SeekIntent(-100),
          SingleActivator(LogicalKeyboardKey.end): _SeekIntent(100),
        },
        actions: {
          _SeekIntent: CallbackAction<_SeekIntent>(
            onInvoke: (i) => _seekBy(_step(i.percent.toDouble())),
          ),
        },
        child: Semantics(
          slider: true,
          label: strings.seekBar,
          value: spoken(_shown),
          increasedValue: spoken(_clamp(_shown + small)),
          decreasedValue: spoken(_clamp(_shown - small)),
          onIncrease: enabled ? () => _seekBy(small) : null,
          onDecrease: enabled ? () => _seekBy(-small) : null,
          customSemanticsActions: enabled
              ? {
                  CustomSemanticsAction(label: strings.seekForwardLarge): () =>
                      _seekBy(large),
                  CustomSemanticsAction(label: strings.seekBackLarge): () =>
                      _seekBy(-large),
                }
              : null,
          child: KFocusRing(focused: _focused, radius: 8, child: bar),
        ),
      ),
    );
  }

  Duration _clamp(Duration d) => d < Duration.zero
      ? Duration.zero
      : (d > widget.duration ? widget.duration : d);
}

class _SeekIntent extends Intent {
  const _SeekIntent(this.percent);

  final int percent;
}

class _SeekPainter extends CustomPainter {
  _SeekPainter({
    required this.position,
    required this.buffered,
    required this.chapters,
    required this.active,
    required this.inactive,
    required this.bufferedColor,
    required this.gap,
    required this.thick,
  });

  final double position;
  final double? buffered;
  final List<double> chapters;
  final Color active;
  final Color inactive;
  final Color bufferedColor;
  final Color gap;
  final bool thick;

  @override
  void paint(Canvas canvas, Size size) {
    final h = thick ? 6.0 : 4.0;
    final y = size.height / 2;
    final track = RRect.fromLTRBR(
      0,
      y - h / 2,
      size.width,
      y + h / 2,
      Radius.circular(h / 2),
    );
    canvas
      ..save()
      ..clipRRect(track)
      ..drawRect(track.outerRect, Paint()..color = inactive);
    if (buffered != null) {
      canvas.drawRect(
        Rect.fromLTRB(0, y - h / 2, size.width * buffered!, y + h / 2),
        Paint()..color = bufferedColor,
      );
    }
    canvas.drawRect(
      Rect.fromLTRB(0, y - h / 2, size.width * position, y + h / 2),
      Paint()..color = active,
    );
    final gapPaint = Paint()..color = gap;
    for (final c in chapters) {
      if (c <= 0 || c >= 1) continue;
      final x = size.width * c;
      canvas.drawRect(Rect.fromLTRB(x - 1, y - h, x + 1, y + h), gapPaint);
    }
    canvas
      ..restore()
      ..drawCircle(
        Offset(size.width * position, y),
        thick ? 9 : 7,
        Paint()..color = active,
      );
  }

  @override
  bool shouldRepaint(_SeekPainter old) =>
      old.position != position ||
      old.buffered != buffered ||
      old.thick != thick ||
      old.active != active ||
      old.inactive != inactive ||
      old.chapters.length != chapters.length;
}
