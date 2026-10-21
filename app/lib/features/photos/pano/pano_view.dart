import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:mediahro/app/l10n/gen/app_localizations.dart';
import 'package:mediahro/features/photos/pano/pano_controller.dart';
import 'package:mediahro/features/photos/pano/pano_painter.dart';

/// The picture of a 360° photo and the ways to move around in it (IMG-001):
/// drag, pinch, mouse wheel, arrow keys and +/-, and the actions a screen
/// reader offers. With reduced motion a flick does not coast.
class PanoramaView extends StatefulWidget {
  const PanoramaView({
    required this.image,
    required this.controller,
    required this.program,
    this.reduceMotion = false,
    super.key,
  });

  final ui.Image image;
  final PanoController controller;

  /// The shader, or null to draw with the mesh.
  final ui.FragmentProgram? program;
  final bool reduceMotion;

  @override
  State<PanoramaView> createState() => _PanoramaViewState();
}

class _PanoramaViewState extends State<PanoramaView>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker(_onTick);
  Offset _focal = Offset.zero;
  double _scale = 1;
  double _height = 1;
  (double, double) _speed = (0, 0);
  Duration _last = Duration.zero;
  final FocusNode _focus = FocusNode(debugLabel: 'pano');

  @override
  void dispose() {
    _ticker.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onTick(Duration now) {
    final dt = (now - _last).inMicroseconds / 1e6;
    _last = now;
    if (dt <= 0) return;
    // A slow frame does not throw the view far.
    _speed = widget.controller.coastBy(_speed, math.min(dt, 0.1));
    if (_speed == (0.0, 0.0)) _ticker.stop();
  }

  void _stopCoast() {
    _speed = (0, 0);
    if (_ticker.isActive) _ticker.stop();
  }

  void _onStart(ScaleStartDetails d) {
    _stopCoast();
    _focal = d.localFocalPoint;
    _scale = 1;
    _focus.requestFocus();
  }

  void _onUpdate(ScaleUpdateDetails d) {
    widget.controller.drag(d.localFocalPoint - _focal, _height);
    _focal = d.localFocalPoint;
    if (d.pointerCount > 1 && d.scale != _scale) {
      widget.controller.zoom(d.scale / _scale);
      _scale = d.scale;
    }
  }

  void _onEnd(ScaleEndDetails d) {
    if (widget.reduceMotion || _height <= 0) return;
    final v = widget.controller.view;
    final perPixel = v.fov / _height;
    final vel = d.velocity.pixelsPerSecond;
    // The picture follows the finger, so the camera goes the other way.
    _speed = (-vel.dx * perPixel, vel.dy * perPixel);
    if (_speed == (0.0, 0.0)) return;
    _last = Duration.zero;
    _ticker.start();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is KeyUpEvent) return KeyEventResult.ignored;
    final c = widget.controller;
    final k = e.logicalKey;
    if (k == LogicalKeyboardKey.arrowLeft) {
      c.step(right: -1);
    } else if (k == LogicalKeyboardKey.arrowRight) {
      c.step(right: 1);
    } else if (k == LogicalKeyboardKey.arrowUp) {
      c.step(up: 1);
    } else if (k == LogicalKeyboardKey.arrowDown) {
      c.step(up: -1);
    } else if (k == LogicalKeyboardKey.equal ||
        k == LogicalKeyboardKey.add ||
        k == LogicalKeyboardKey.numpadAdd) {
      c.zoomStep(zoomIn: true);
    } else if (k == LogicalKeyboardKey.minus ||
        k == LogicalKeyboardKey.numpadSubtract) {
      c.zoomStep(zoomIn: false);
    } else if (k == LogicalKeyboardKey.digit0 || k == LogicalKeyboardKey.home) {
      c.reset();
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final c = widget.controller;
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        final (heading, tilt) = c.facing;
        return Focus(
          focusNode: _focus,
          onKeyEvent: _onKey,
          child: Semantics(
            container: true,
            image: true,
            label: l10n.photosPanoHint,
            value: l10n.photosPanoFacing(heading, tilt),
            customSemanticsActions: {
              CustomSemanticsAction(label: l10n.photosPanoLeft): () =>
                  c.step(right: -1),
              CustomSemanticsAction(label: l10n.photosPanoRight): () =>
                  c.step(right: 1),
              CustomSemanticsAction(label: l10n.photosPanoUp): () =>
                  c.step(up: 1),
              CustomSemanticsAction(label: l10n.photosPanoDown): () =>
                  c.step(up: -1),
              CustomSemanticsAction(label: l10n.photosPanoZoomIn): () =>
                  c.zoomStep(zoomIn: true),
              CustomSemanticsAction(label: l10n.photosPanoZoomOut): () =>
                  c.zoomStep(zoomIn: false),
              CustomSemanticsAction(label: l10n.photosPanoReset): c.reset,
            },
            child: Listener(
              onPointerSignal: (e) {
                if (e is PointerScrollEvent) {
                  c.zoom(math.exp(-e.scrollDelta.dy / 300));
                }
              },
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onScaleStart: _onStart,
                onScaleUpdate: _onUpdate,
                onScaleEnd: _onEnd,
                child: LayoutBuilder(
                  builder: (context, box) {
                    _height = box.maxHeight;
                    return ExcludeSemantics(
                      child: SizedBox.expand(
                        child: CustomPaint(
                          painter: PanoPainter(
                            image: widget.image,
                            controller: c,
                            program: widget.program,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
