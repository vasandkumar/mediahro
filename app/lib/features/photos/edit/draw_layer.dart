import 'package:flutter/material.dart';
import 'package:mediahro/features/photos/edit/edit_geometry.dart';
import 'package:mediahro/features/photos/edit/editor_controller.dart';
import 'package:mediahro/images/edit/edit_recipe.dart';

/// Catches a finger or mouse drag over the picture and turns it into a
/// stroke, a shape or a blurred area (IMG-009 draw / annotate / blur). The
/// result is in 0–1 coordinates of the picture, so it lands in the same
/// place at full size.
class DrawLayer extends StatefulWidget {
  const DrawLayer({
    required this.imageRect,
    required this.imageAspect,
    required this.shape,
    required this.colorArgb,
    required this.width,
    required this.onStroke,
    required this.onBlur,
    super.key,
  });

  final Rect imageRect;
  final double imageAspect;
  final DrawShape shape;
  final int colorArgb;

  /// Fraction of the picture's shorter side.
  final double width;
  final ValueChanged<StrokeSpec> onStroke;
  final ValueChanged<BlurSpec> onBlur;

  @override
  State<DrawLayer> createState() => _DrawLayerState();
}

class _DrawLayerState extends State<DrawLayer> {
  final List<(double, double)> _pts = [];

  (double, double) _norm(Offset local) {
    final r = widget.imageRect;
    return (
      ((local.dx - r.left) / r.width).clamp(0.0, 1.0),
      ((local.dy - r.top) / r.height).clamp(0.0, 1.0),
    );
  }

  void _start(DragStartDetails d) {
    _pts
      ..clear()
      ..add(_norm(d.localPosition));
    setState(() {});
  }

  void _update(DragUpdateDetails d) {
    final p = _norm(d.localPosition);
    setState(() {
      if (widget.shape == DrawShape.pen) {
        _pts.add(p);
      } else {
        if (_pts.length > 1) _pts.removeLast();
        _pts.add(p);
      }
    });
  }

  /// What the gesture stands for, as polyline points of a stroke.
  List<(double, double)> _shapePoints() {
    if (_pts.isEmpty) return const [];
    final a = _pts.first;
    final b = _pts.last;
    return switch (widget.shape) {
      DrawShape.pen || DrawShape.line => List.of(
        _pts.length > 1 && widget.shape == DrawShape.line ? [a, b] : _pts,
      ),
      DrawShape.arrow => arrowPoints(a, b, aspect: widget.imageAspect),
      DrawShape.box => boxPoints(a, b),
      DrawShape.blur => const [],
    };
  }

  void _end() {
    if (_pts.isEmpty) return;
    if (widget.shape == DrawShape.blur) {
      final box = rectBetween(_pts.first, _pts.last);
      if (box.width > 0.01 && box.height > 0.01) {
        widget.onBlur(BlurSpec(box));
      }
    } else {
      final pts = _shapePoints();
      if (pts.isNotEmpty) {
        widget.onStroke(
          StrokeSpec(pts, colorArgb: widget.colorArgb, width: widget.width),
        );
      }
    }
    setState(_pts.clear);
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onPanStart: _start,
    onPanUpdate: _update,
    onPanEnd: (_) => _end(),
    onPanCancel: () => setState(_pts.clear),
    child: CustomPaint(
      painter: _LivePainter(
        widget.imageRect,
        widget.shape,
        _shapePoints(),
        _pts.length > 1 ? rectBetween(_pts.first, _pts.last) : null,
        Color(widget.colorArgb),
        widget.width,
      ),
      child: const SizedBox.expand(),
    ),
  );
}

/// The stroke being drawn, before it becomes part of the recipe.
class _LivePainter extends CustomPainter {
  _LivePainter(
    this.image,
    this.shape,
    this.points,
    this.blur,
    this.color,
    this.width,
  );

  final Rect image;
  final DrawShape shape;
  final List<(double, double)> points;
  final NormRect? blur;
  final Color color;
  final double width;

  @override
  void paint(Canvas canvas, Size size) {
    if (shape == DrawShape.blur) {
      final b = blur;
      if (b == null) return;
      final r = Rect.fromLTWH(
        image.left + b.left * image.width,
        image.top + b.top * image.height,
        b.width * image.width,
        b.height * image.height,
      );
      canvas
        ..drawRect(r, Paint()..color = const Color(0x33FFFFFF))
        ..drawRect(
          r,
          Paint()
            ..color = Colors.white
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5,
        );
      return;
    }
    if (points.isEmpty) return;
    final strokeWidth =
        (width * (image.width < image.height ? image.width : image.height))
            .clamp(1.0, 200.0);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    Offset at((double, double) p) => Offset(
      image.left + p.$1 * image.width,
      image.top + p.$2 * image.height,
    );
    if (points.length == 1) {
      canvas.drawCircle(
        at(points.first),
        strokeWidth / 2,
        paint..style = PaintingStyle.fill,
      );
      return;
    }
    final path = Path()..moveTo(at(points.first).dx, at(points.first).dy);
    for (final p in points.skip(1)) {
      path.lineTo(at(p).dx, at(p).dy);
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_LivePainter old) => true;
}
