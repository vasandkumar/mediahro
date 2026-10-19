import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:mediahro_design/src/foundation/strings.dart';
import 'package:mediahro_design/src/tokens.dart';

enum KCompareMode {
  /// 2-up or 4-up panels with synchronised pan and zoom.
  sideBySide,

  /// The second image revealed by a draggable divider.
  swipe,

  /// The second image blended over the first.
  overlay,

  /// Absolute pixel difference of the first two images.
  difference,
}

/// Photo compare view (docs/06 §3.3, IMG compare). Pan and zoom are shared
/// by every panel through one [TransformationController]. Images are never
/// mirrored in RTL.
class KCompareView extends StatefulWidget {
  const KCompareView({
    required this.children,
    this.mode = KCompareMode.sideBySide,
    this.controller,
    this.initialSplit = 0.5,
    super.key,
  }) : assert(children.length >= 2 && children.length <= 4, '2–4 images');

  final List<Widget> children;
  final KCompareMode mode;
  final TransformationController? controller;

  /// Divider position (swipe) or opacity (overlay), 0–1.
  final double initialSplit;

  @override
  State<KCompareView> createState() => _KCompareViewState();
}

class _KCompareViewState extends State<KCompareView> {
  late final TransformationController _own = TransformationController();
  late double _split = widget.initialSplit;

  TransformationController get _controller => widget.controller ?? _own;

  @override
  void dispose() {
    _own.dispose();
    super.dispose();
  }

  Widget _panel(int i, {bool interactive = true}) {
    final strings = KStrings.of(context);
    final child = Semantics(
      image: true,
      label: strings.compareItem(i + 1, widget.children.length),
      child: widget.children[i],
    );
    if (!interactive) return child;
    return InteractiveViewer(
      transformationController: _controller,
      maxScale: 16,
      child: child,
    );
  }

  void _nudge(double delta) =>
      setState(() => _split = (_split + delta).clamp(0.0, 1.0));

  @override
  Widget build(BuildContext context) {
    final strings = KStrings.of(context);
    return Directionality(
      textDirection: TextDirection.ltr,
      child: switch (widget.mode) {
        KCompareMode.sideBySide => _sideBySide(),
        KCompareMode.swipe => _swipe(strings),
        KCompareMode.overlay => _overlay(strings),
        KCompareMode.difference => InteractiveViewer(
          transformationController: _controller,
          maxScale: 16,
          child: Stack(
            fit: StackFit.expand,
            children: [
              _panel(0, interactive: false),
              _BlendLayer(
                mode: BlendMode.difference,
                child: _panel(1, interactive: false),
              ),
            ],
          ),
        ),
      },
    );
  }

  Widget _sideBySide() {
    final n = widget.children.length;
    if (n == 2) {
      return LayoutBuilder(
        builder: (context, c) {
          final panels = [
            Expanded(child: _panel(0)),
            const SizedBox(width: 2, height: 2),
            Expanded(child: _panel(1)),
          ];
          return c.maxWidth >= c.maxHeight
              ? Row(children: panels)
              : Column(children: panels);
        },
      );
    }
    Widget cell(int i) =>
        Expanded(child: i < n ? _panel(i) : const SizedBox.shrink());
    return Column(
      children: [
        Expanded(
          child: Row(children: [cell(0), const SizedBox(width: 2), cell(1)]),
        ),
        const SizedBox(height: 2),
        Expanded(
          child: Row(children: [cell(2), const SizedBox(width: 2), cell(3)]),
        ),
      ],
    );
  }

  Widget _adjustable({required String label, required Widget child}) {
    final strings = KStrings.of(context);
    String pct(double v) => strings.percent((v * 100).round());
    return FocusableActionDetector(
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.arrowRight): _SplitIntent(0.05),
        SingleActivator(LogicalKeyboardKey.arrowLeft): _SplitIntent(-0.05),
      },
      actions: {
        _SplitIntent: CallbackAction<_SplitIntent>(
          onInvoke: (i) => _nudge(i.delta),
        ),
      },
      child: Semantics(
        slider: true,
        label: label,
        value: pct(_split),
        increasedValue: pct((_split + 0.05).clamp(0, 1)),
        decreasedValue: pct((_split - 0.05).clamp(0, 1)),
        onIncrease: () => _nudge(0.05),
        onDecrease: () => _nudge(-0.05),
        child: child,
      ),
    );
  }

  Widget _swipe(KStrings strings) => LayoutBuilder(
    builder: (context, c) {
      final x = c.maxWidth * _split;
      return Stack(
        fit: StackFit.expand,
        children: [
          _panel(0),
          ClipRect(
            clipper: _FromLeft(x),
            child: IgnorePointer(child: _panel(1)),
          ),
          Positioned(
            left: x - 22,
            top: 0,
            bottom: 0,
            width: 44,
            child: _adjustable(
              label: strings.compareDivider,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onHorizontalDragUpdate: (d) => setState(
                  () =>
                      _split = ((x + d.delta.dx) / c.maxWidth).clamp(0.0, 1.0),
                ),
                child: Center(
                  child: Container(
                    width: 3,
                    color: Colors.white,
                    child: const OverflowBox(
                      maxWidth: 32,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          boxShadow: [BoxShadow(blurRadius: 4)],
                        ),
                        child: SizedBox.square(
                          dimension: 32,
                          child: Icon(
                            Icons.compare_arrows,
                            color: Colors.black,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    },
  );

  Widget _overlay(KStrings strings) => Column(
    children: [
      Expanded(
        child: Stack(
          fit: StackFit.expand,
          children: [
            _panel(0),
            IgnorePointer(
              child: Opacity(opacity: _split, child: _panel(1)),
            ),
          ],
        ),
      ),
      _adjustable(
        label: strings.compareDivider,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: KSpacing.s16),
          child: ExcludeSemantics(
            child: Slider(
              value: _split,
              onChanged: (v) => setState(() => _split = v),
            ),
          ),
        ),
      ),
    ],
  );
}

class _SplitIntent extends Intent {
  const _SplitIntent(this.delta);

  final double delta;
}

class _FromLeft extends CustomClipper<Rect> {
  _FromLeft(this.x);

  final double x;

  @override
  Rect getClip(Size size) => Rect.fromLTRB(x, 0, size.width, size.height);

  @override
  bool shouldReclip(_FromLeft old) => old.x != x;
}

/// Composites its child onto what is below with [mode].
class _BlendLayer extends SingleChildRenderObjectWidget {
  const _BlendLayer({required this.mode, super.child});

  final BlendMode mode;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderBlend(mode);

  @override
  void updateRenderObject(BuildContext context, _RenderBlend renderObject) =>
      renderObject.mode = mode;
}

class _RenderBlend extends RenderProxyBox {
  _RenderBlend(this._mode);

  BlendMode _mode;
  BlendMode get mode => _mode;
  set mode(BlendMode m) {
    if (m == _mode) return;
    _mode = m;
    markNeedsPaint();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (child == null) return;
    context.canvas.saveLayer(offset & size, Paint()..blendMode = _mode);
    super.paint(context, offset);
    context.canvas.restore();
  }
}
