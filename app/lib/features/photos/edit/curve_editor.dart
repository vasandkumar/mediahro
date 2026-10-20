import 'package:flutter/material.dart';
import 'package:mediahro/app/l10n/gen/app_localizations.dart';
import 'package:mediahro/images/edit/edit_engine.dart';

/// A square to shape one tone curve in (IMG-009): tap to add a point, drag a
/// point to move it, drag it out of the square to remove it. The first and
/// last points only move up and down. Every point is also a slider for
/// screen readers and the keyboard.
class CurveEditor extends StatefulWidget {
  const CurveEditor({
    required this.points,
    required this.color,
    required this.onStart,
    required this.onChanged,
    required this.onEnd,
    super.key,
  });

  /// Control points; fewer than two means the straight line.
  final List<(double, double)> points;
  final Color color;
  final VoidCallback onStart;
  final ValueChanged<List<(double, double)>> onChanged;
  final VoidCallback onEnd;

  static const List<(double, double)> straight = [(0, 0), (1, 1)];

  @override
  State<CurveEditor> createState() => _CurveEditorState();
}

class _CurveEditorState extends State<CurveEditor> {
  List<(double, double)> get _pts =>
      widget.points.length < 2 ? CurveEditor.straight : widget.points;

  /// Hit target of a point, logical pixels.
  static const double _target = 44;

  // Where a drag began and how far the finger has gone since, unclamped so
  // dragging out of the box can be told from stopping at its edge.
  Offset _origin = Offset.zero;
  Offset _travel = Offset.zero;

  // The dragged point was dragged out and removed; the rest of the drag
  // must not move whichever point took its place.
  bool _gone = false;

  void _move(int i, (double, double) to, {required bool remove}) {
    final pts = [..._pts];
    if (remove && i != 0 && i != pts.length - 1) {
      pts.removeAt(i);
    } else {
      final first = i == 0;
      final last = i == pts.length - 1;
      final lo = first ? 0.0 : pts[i - 1].$1 + 0.01;
      final hi = last ? 1.0 : pts[i + 1].$1 - 0.01;
      final x = first || last ? pts[i].$1 : to.$1.clamp(lo, hi);
      pts[i] = (x, to.$2.clamp(0.0, 1.0));
    }
    widget.onChanged(pts);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    return AspectRatio(
      aspectRatio: 1,
      child: LayoutBuilder(
        builder: (context, box) {
          final size = box.biggest;
          Offset toPx((double, double) p) =>
              Offset(p.$1 * size.width, (1 - p.$2) * size.height);
          (double, double) toNorm(Offset o) =>
              (o.dx / size.width, 1 - o.dy / size.height);
          final pts = _pts;
          return Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapUp: (d) {
                    final n = toNorm(d.localPosition);
                    final next = [...pts, (n.$1.clamp(0.02, 0.98), n.$2)]
                      ..sort((a, b) => a.$1.compareTo(b.$1));
                    widget.onStart();
                    widget.onChanged(next);
                    widget.onEnd();
                  },
                  child: CustomPaint(
                    painter: _CurvePainter(
                      pts,
                      widget.color,
                      scheme.outlineVariant,
                      scheme.surfaceContainerHighest,
                    ),
                  ),
                ),
              ),
              for (var i = 0; i < pts.length; i++)
                Positioned(
                  left: toPx(pts[i]).dx - _target / 2,
                  top: toPx(pts[i]).dy - _target / 2,
                  width: _target,
                  height: _target,
                  child: Semantics(
                    slider: true,
                    label: l10n.photosCurvePoint(i + 1),
                    value: l10n.photosCurvePointValue(
                      (pts[i].$1 * 100).round(),
                      (pts[i].$2 * 100).round(),
                    ),
                    increasedValue: l10n.photosCurvePointValue(
                      (pts[i].$1 * 100).round(),
                      ((pts[i].$2 + 0.05).clamp(0, 1) * 100).round(),
                    ),
                    decreasedValue: l10n.photosCurvePointValue(
                      (pts[i].$1 * 100).round(),
                      ((pts[i].$2 - 0.05).clamp(0, 1) * 100).round(),
                    ),
                    onIncrease: () {
                      widget.onStart();
                      _move(i, (pts[i].$1, pts[i].$2 + 0.05), remove: false);
                      widget.onEnd();
                    },
                    onDecrease: () {
                      widget.onStart();
                      _move(i, (pts[i].$1, pts[i].$2 - 0.05), remove: false);
                      widget.onEnd();
                    },
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onPanStart: (_) {
                        _origin = toPx(pts[i]);
                        _travel = Offset.zero;
                        _gone = false;
                        widget.onStart();
                      },
                      onPanUpdate: (d) {
                        if (_gone) return;
                        _travel += d.delta;
                        final at = toNorm(_origin + _travel);
                        final outside =
                            at.$1 < -0.12 ||
                            at.$1 > 1.12 ||
                            at.$2 < -0.12 ||
                            at.$2 > 1.12;
                        _gone = outside && i != 0 && i != pts.length - 1;
                        _move(i, at, remove: outside);
                      },
                      onPanEnd: (_) => widget.onEnd(),
                      child: Center(
                        child: Container(
                          width: 16,
                          height: 16,
                          decoration: BoxDecoration(
                            color: widget.color,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _CurvePainter extends CustomPainter {
  _CurvePainter(this.points, this.color, this.grid, this.background);

  final List<(double, double)> points;
  final Color color;
  final Color grid;
  final Color background;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = background);
    final g = Paint()
      ..color = grid
      ..strokeWidth = 1;
    for (var i = 1; i < 4; i++) {
      canvas
        ..drawLine(
          Offset(size.width * i / 4, 0),
          Offset(size.width * i / 4, size.height),
          g,
        )
        ..drawLine(
          Offset(0, size.height * i / 4),
          Offset(size.width, size.height * i / 4),
          g,
        );
    }
    canvas.drawLine(
      Offset(0, size.height),
      Offset(size.width, 0),
      g..color = grid.withValues(alpha: 0.6),
    );
    final t = curveTable(points);
    final path = Path();
    for (var i = 0; i < 256; i++) {
      final x = i / 255 * size.width;
      final y = (1 - t[i]) * size.height;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );
  }

  @override
  bool shouldRepaint(_CurvePainter old) =>
      old.points != points || old.color != color || old.grid != grid;
}
