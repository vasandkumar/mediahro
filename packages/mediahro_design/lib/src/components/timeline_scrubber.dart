import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mediahro_design/src/components/focus.dart';
import 'package:mediahro_design/src/theme.dart';
import 'package:mediahro_design/src/tokens.dart';

/// A labelled position on the timeline (a year or month).
@immutable
final class KTimelineMark {
  const KTimelineMark({required this.label, required this.fraction});

  final String label;

  /// Scroll position of this mark, 0 = top, 1 = bottom.
  final double fraction;
}

/// Year/month scrubber on the edge of the photos timeline (docs/06 §3.3).
///
/// Drag the thumb to scroll; a bubble shows the nearest mark. Screen readers
/// and the keyboard (↑/↓, Page Up/Down) step from mark to mark. Sits on the
/// trailing edge, which is the left edge in RTL locales.
class KTimelineScrubber extends StatefulWidget {
  const KTimelineScrubber({
    required this.marks,
    required this.fraction,
    required this.onChanged,
    required this.label,
    this.onScrubStart,
    this.onScrubEnd,
    super.key,
  });

  final List<KTimelineMark> marks;

  /// Current scroll fraction.
  final double fraction;
  final ValueChanged<double> onChanged;

  /// Accessibility name ("Timeline").
  final String label;
  final VoidCallback? onScrubStart;
  final VoidCallback? onScrubEnd;

  @override
  State<KTimelineScrubber> createState() => _KTimelineScrubberState();
}

class _KTimelineScrubberState extends State<KTimelineScrubber> {
  bool _dragging = false;
  bool _focused = false;

  int _nearest(double f) {
    if (widget.marks.isEmpty) return -1;
    var best = 0;
    for (var i = 0; i < widget.marks.length; i++) {
      if (widget.marks[i].fraction <= f + 1e-9) best = i;
    }
    return best;
  }

  String? _labelAt(double f) {
    final i = _nearest(f);
    return i < 0 ? null : widget.marks[i].label;
  }

  void _stepMark(int delta) {
    if (widget.marks.isEmpty) return;
    final i = (_nearest(widget.fraction) + delta).clamp(
      0,
      widget.marks.length - 1,
    );
    widget.onChanged(widget.marks[i].fraction);
  }

  void _dragTo(double dy, double height) =>
      widget.onChanged((dy / height).clamp(0.0, 1.0));

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final min = theme.mediahroShape.minTarget;
    final current = _labelAt(widget.fraction);
    final i = _nearest(widget.fraction);
    final next = i >= 0 && i + 1 < widget.marks.length
        ? widget.marks[i + 1].label
        : null;
    final prev = i > 0 ? widget.marks[i - 1].label : null;

    return FocusableActionDetector(
      onShowFocusHighlight: (v) => setState(() => _focused = v),
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.arrowDown): _MarkIntent(1),
        SingleActivator(LogicalKeyboardKey.arrowUp): _MarkIntent(-1),
        SingleActivator(LogicalKeyboardKey.pageDown): _MarkIntent(5),
        SingleActivator(LogicalKeyboardKey.pageUp): _MarkIntent(-5),
      },
      actions: {
        _MarkIntent: CallbackAction<_MarkIntent>(
          onInvoke: (m) => _stepMark(m.delta),
        ),
      },
      child: Semantics(
        slider: true,
        label: widget.label,
        value: current,
        increasedValue: next,
        decreasedValue: prev,
        onIncrease: next == null ? null : () => _stepMark(1),
        onDecrease: prev == null ? null : () => _stepMark(-1),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final h = constraints.maxHeight;
            const thumbH = 48.0;
            final top = (widget.fraction * (h - thumbH)).clamp(0.0, h - thumbH);
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onVerticalDragStart: (d) {
                setState(() => _dragging = true);
                widget.onScrubStart?.call();
                _dragTo(d.localPosition.dy, h);
              },
              onVerticalDragUpdate: (d) => _dragTo(d.localPosition.dy, h),
              onVerticalDragEnd: (_) {
                setState(() => _dragging = false);
                widget.onScrubEnd?.call();
              },
              child: SizedBox(
                width: min,
                height: h,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    PositionedDirectional(
                      top: top,
                      end: 4,
                      child: KFocusRing(
                        focused: _focused,
                        radius: 12,
                        child: Container(
                          width: 28,
                          height: thumbH,
                          decoration: BoxDecoration(
                            color: scheme.secondaryContainer,
                            borderRadius: BorderRadius.circular(14),
                            boxShadow: const [
                              BoxShadow(blurRadius: 2, color: Colors.black26),
                            ],
                          ),
                          child: Icon(
                            Icons.unfold_more,
                            size: 18,
                            color: scheme.onSecondaryContainer,
                          ),
                        ),
                      ),
                    ),
                    if (_dragging && current != null)
                      PositionedDirectional(
                        top: top + 8,
                        end: min + 4,
                        child: ExcludeSemantics(
                          child: Material(
                            color: scheme.inverseSurface,
                            borderRadius: BorderRadius.circular(KRadius.pill),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: KSpacing.s12,
                                vertical: KSpacing.s8,
                              ),
                              child: Text(
                                current,
                                style: theme.textTheme.labelLarge?.copyWith(
                                  color: scheme.onInverseSurface,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _MarkIntent extends Intent {
  const _MarkIntent(this.delta);

  final int delta;
}
