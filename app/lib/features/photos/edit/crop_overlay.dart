import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mediahro/app/l10n/gen/app_localizations.dart';
import 'package:mediahro/features/photos/edit/edit_geometry.dart';
import 'package:mediahro/images/edit/edit_recipe.dart';

/// The crop box over the picture: drag a corner or an edge to resize, the
/// inside to move, arrow keys to nudge (shift resizes). [ratio] holds the
/// pixel aspect (null = free).
class CropOverlay extends StatefulWidget {
  const CropOverlay({
    required this.imageRect,
    required this.crop,
    required this.imageAspect,
    required this.onChanged,
    required this.onStart,
    required this.onEnd,
    this.ratio,
    super.key,
  });

  /// Where the picture is drawn, in this widget's coordinates.
  final Rect imageRect;
  final NormRect crop;
  final double imageAspect;
  final double? ratio;
  final ValueChanged<NormRect> onChanged;
  final VoidCallback onStart;
  final VoidCallback onEnd;

  @override
  State<CropOverlay> createState() => _CropOverlayState();
}

class _CropOverlayState extends State<CropOverlay> {
  CropHandle? _handle;
  NormRect _start = NormRect.full;
  Offset _total = Offset.zero;

  Rect get _box {
    final r = widget.imageRect;
    final c = widget.crop;
    return Rect.fromLTWH(
      r.left + c.left * r.width,
      r.top + c.top * r.height,
      c.width * r.width,
      c.height * r.height,
    );
  }

  void _down(DragStartDetails d) {
    _handle = hitCropHandle(_box, d.localPosition);
    if (_handle == null) return;
    _start = widget.crop;
    _total = Offset.zero;
    widget.onStart();
  }

  void _update(DragUpdateDetails d) {
    final h = _handle;
    if (h == null) return;
    _total += d.delta;
    final r = widget.imageRect;
    widget.onChanged(
      dragCrop(
        _start,
        h,
        Offset(_total.dx / r.width, _total.dy / r.height),
        ratio: widget.ratio,
        imageAspect: widget.imageAspect,
      ),
    );
  }

  void _end() {
    if (_handle != null) widget.onEnd();
    _handle = null;
  }

  KeyEventResult _key(FocusNode node, KeyEvent e) {
    if (e is KeyUpEvent) return KeyEventResult.ignored;
    const step = 0.01;
    final k = e.logicalKey;
    final dx = k == LogicalKeyboardKey.arrowLeft
        ? -step
        : k == LogicalKeyboardKey.arrowRight
        ? step
        : 0.0;
    final dy = k == LogicalKeyboardKey.arrowUp
        ? -step
        : k == LogicalKeyboardKey.arrowDown
        ? step
        : 0.0;
    if (dx == 0 && dy == 0) return KeyEventResult.ignored;
    final resize = HardwareKeyboard.instance.isShiftPressed;
    widget.onStart();
    widget.onChanged(
      dragCrop(
        widget.crop,
        resize ? CropHandle.bottomRight : CropHandle.move,
        Offset(dx, dy),
        ratio: widget.ratio,
        imageAspect: widget.imageAspect,
      ),
    );
    widget.onEnd();
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final c = widget.crop;
    return Focus(
      onKeyEvent: _key,
      child: Semantics(
        label: l10n.photosCropArea,
        value: l10n.photosCropAreaValue(
          (c.width * 100).round(),
          (c.height * 100).round(),
        ),
        hint: l10n.photosCropAreaHint,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanStart: _down,
          onPanUpdate: _update,
          onPanEnd: (_) => _end(),
          onPanCancel: _end,
          child: CustomPaint(
            painter: _CropPainter(widget.imageRect, _box),
            child: const SizedBox.expand(),
          ),
        ),
      ),
    );
  }
}

class _CropPainter extends CustomPainter {
  _CropPainter(this.image, this.box);

  final Rect image;
  final Rect box;

  @override
  void paint(Canvas canvas, Size size) {
    final dim = Path()
      ..addRect(image)
      ..addRect(box)
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(dim, Paint()..color = const Color(0x99000000));
    final line = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawRect(box, line);
    final grid = Paint()
      ..color = const Color(0x88FFFFFF)
      ..strokeWidth = 0.8;
    for (var i = 1; i < 3; i++) {
      final x = box.left + box.width * i / 3;
      final y = box.top + box.height * i / 3;
      canvas
        ..drawLine(Offset(x, box.top), Offset(x, box.bottom), grid)
        ..drawLine(Offset(box.left, y), Offset(box.right, y), grid);
    }
    final handle = Paint()
      ..color = Colors.white
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.square;
    const arm = 18.0;
    for (final (corner, dx, dy) in [
      (box.topLeft, 1.0, 1.0),
      (box.topRight, -1.0, 1.0),
      (box.bottomLeft, 1.0, -1.0),
      (box.bottomRight, -1.0, -1.0),
    ]) {
      canvas
        ..drawLine(corner, corner + Offset(dx * arm, 0), handle)
        ..drawLine(corner, corner + Offset(0, dy * arm), handle);
    }
  }

  @override
  bool shouldRepaint(_CropPainter old) => old.image != image || old.box != box;
}
