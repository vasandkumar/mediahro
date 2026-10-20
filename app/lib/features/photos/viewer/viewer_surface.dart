import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/scheduler.dart';
import 'package:mediahro/features/photos/viewer/tile_plan.dart';
import 'package:mediahro/features/photos/viewer/zoom_math.dart';
import 'package:mediahro_design/mediahro_design.dart';

/// Loads one tile of the full-resolution pyramid, or null when it cannot be
/// produced. The widget disposes the images it receives.
typedef TileLoader = Future<ui.Image?> Function(TileKey key);

/// Commands the viewer chrome and the keyboard send to a [ViewerSurface].
final class ViewerController extends ChangeNotifier {
  _ViewerSurfaceState? _state;

  ZoomState? get zoom => _state?._zoom.value;

  int? get percent {
    final s = _state;
    return s?._geometry.percent(s._zoom.value);
  }

  void zoomIn() => _state?._zoomBy(1.5);
  void zoomOut() => _state?._zoomBy(1 / 1.5);
  void reset() => _state?._animateTo(_state!._geometry.initial);
  void oneToOne() => _state?._animateToScale(_state!._geometry.oneToOne);

  void _changed() => notifyListeners();
}

/// The picture with pinch, scroll-wheel and double-tap zoom, pan with
/// inertia, and on-demand full-resolution tiles over a base picture
/// (IMG-004). [fullSize] is the size in source pixels after orientation;
/// [base] covers all of it at lower or equal resolution. Rotation by
/// [quarterTurns] is a display transform.
class ViewerSurface extends StatefulWidget {
  const ViewerSurface({
    required this.base,
    required this.fullSize,
    this.tileLoader,
    this.mode = FitMode.fit,
    this.quarterTurns = 0,
    this.controller,
    this.onZoomChanged,
    this.onAtFitChanged,
    this.onTap,
    super.key,
  });

  final ui.Image base;
  final ui.Size fullSize;
  final TileLoader? tileLoader;
  final FitMode mode;
  final int quarterTurns;
  final ViewerController? controller;

  /// The zoom changed; `percent` is the readout value.
  final void Function(ZoomState zoom, int percent)? onZoomChanged;

  /// The picture moved to or from the fit zoom (the page view may swipe
  /// only at fit).
  final ValueChanged<bool>? onAtFitChanged;
  final VoidCallback? onTap;

  @override
  State<ViewerSurface> createState() => _ViewerSurfaceState();
}

class _ViewerSurfaceState extends State<ViewerSurface>
    with SingleTickerProviderStateMixin {
  final ValueNotifier<ZoomState> _zoom = ValueNotifier(
    const ZoomState(1, ui.Offset.zero),
  );
  late ZoomGeometry _geometry;
  ui.Size _viewport = ui.Size.zero;
  double _dpr = 1;
  bool _atFit = true;
  bool _initialised = false;

  // Gesture state.
  late ZoomState _startZoom;
  ui.Offset _startFocal = ui.Offset.zero;
  ui.Offset _doubleTapAt = ui.Offset.zero;

  late final AnimationController _anim = AnimationController(vsync: this);
  Ticker? _fling;

  // Tiles.
  final LinkedHashMap<TileKey, ui.Image> _tiles = LinkedHashMap();
  final Set<TileKey> _loading = {};
  Timer? _tileTimer;
  int _tileGeneration = 0;
  int _tileVersion = 0;
  static const int _maxTiles = 48;
  static const int _maxLoading = 3;

  ui.Size get _displaySize => widget.quarterTurns.isOdd
      ? ui.Size(widget.fullSize.height, widget.fullSize.width)
      : widget.fullSize;

  @override
  void initState() {
    super.initState();
    widget.controller?._state = this;
    _zoom.addListener(_onZoom);
  }

  @override
  void didUpdateWidget(ViewerSurface old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller?._state = null;
      widget.controller?._state = this;
    }
    if (old.mode != widget.mode ||
        old.quarterTurns != widget.quarterTurns ||
        old.fullSize != widget.fullSize) {
      _rebuildGeometry();
      _zoom.value = _geometry.initial;
    }
    if (old.base != widget.base) _clearTiles();
  }

  @override
  void dispose() {
    widget.controller?._state = null;
    _tileTimer?.cancel();
    _fling?.dispose();
    _anim.dispose();
    _zoom
      ..removeListener(_onZoom)
      ..dispose();
    _clearTiles();
    super.dispose();
  }

  void _rebuildGeometry() {
    _geometry = ZoomGeometry(
      image: _displaySize,
      viewport: _viewport,
      devicePixelRatio: _dpr,
      mode: widget.mode,
    );
  }

  void _onZoom() {
    final s = _zoom.value;
    final atFit = _geometry.isAtFit(s);
    if (atFit != _atFit) {
      _atFit = atFit;
      widget.onAtFitChanged?.call(atFit);
    }
    widget.onZoomChanged?.call(s, _geometry.percent(s));
    widget.controller?._changed();
    _scheduleTiles();
  }

  // ---- gestures --------------------------------------------------------

  void _stopMotion() {
    _anim.stop();
    _fling?.stop();
  }

  void _setZoom(ZoomState s) => _zoom.value = _geometry.clamp(s);

  void _zoomBy(double factor) {
    _stopMotion();
    final focal = ui.Offset(_viewport.width / 2, _viewport.height / 2);
    _animateTo(_geometry.zoomAt(_zoom.value, factor, focal));
  }

  void _animateToScale(double scale) {
    final focal = ui.Offset(_viewport.width / 2, _viewport.height / 2);
    _animateTo(_geometry.zoomAt(_zoom.value, scale / _zoom.value.scale, focal));
  }

  void _animateTo(ZoomState target) {
    _stopMotion();
    final from = _zoom.value;
    final to = _geometry.clamp(target);
    final reduce = KAccessibility.reduceMotion(context);
    if (reduce) {
      _zoom.value = to;
      return;
    }
    final curve = CurvedAnimation(parent: _anim, curve: Curves.easeOutCubic);
    void tick() {
      final t = curve.value;
      // Interpolate the scale geometrically so zooms feel even.
      final scale = from.scale * math.pow(to.scale / from.scale, t);
      _zoom.value = ZoomState(
        scale,
        ui.Offset.lerp(from.centre, to.centre, t)!,
      );
    }

    _anim
      ..duration = KMotion.base
      ..addListener(tick);
    _anim.forward(from: 0).whenCompleteOrCancel(() {
      _anim.removeListener(tick);
      curve.dispose();
    });
  }

  void _onScaleStart(ScaleStartDetails d) {
    _stopMotion();
    _startZoom = _zoom.value;
    _startFocal = d.localFocalPoint;
  }

  void _onScaleUpdate(ScaleUpdateDetails d) {
    if (_atFit && d.pointerCount < 2 && d.scale == 1) {
      // A one-finger drag at fit belongs to the page view; do nothing.
      return;
    }
    final zoomed = _geometry.zoomAt(_startZoom, d.scale, _startFocal);
    _setZoom(_geometry.pan(zoomed, d.localFocalPoint - _startFocal));
  }

  void _onScaleEnd(ScaleEndDetails d) {
    final v = d.velocity.pixelsPerSecond;
    if (_atFit || v.distance < 300 || d.pointerCount > 0) return;
    final dir = v / v.distance;
    final sim = FrictionSimulation(0.02, 0, v.distance);
    var last = 0.0;
    _fling?.dispose();
    _fling = createTicker((elapsed) {
      final t = elapsed.inMicroseconds / 1e6;
      final x = sim.x(t);
      _setZoom(_geometry.pan(_zoom.value, dir * (x - last)));
      last = x;
      if (sim.isDone(t)) _fling?.stop();
    })..start();
  }

  void _onPointerSignal(PointerSignalEvent e) {
    if (e is PointerScrollEvent) {
      _stopMotion();
      final factor = math.exp(-e.scrollDelta.dy / 300);
      _setZoom(_geometry.zoomAt(_zoom.value, factor, e.localPosition));
    } else if (e is PointerScaleEvent) {
      _setZoom(_geometry.zoomAt(_zoom.value, e.scale, e.localPosition));
    }
  }

  // ---- tiles -----------------------------------------------------------

  bool get _tiled => widget.tileLoader != null;

  void _scheduleTiles() {
    if (!_tiled || !_initialised) return;
    _tileTimer?.cancel();
    _tileTimer = Timer(const Duration(milliseconds: 60), _requestTiles);
  }

  /// Source-pixel rectangle of a display-space rectangle after [turns]
  /// quarter turns clockwise.
  static ui.Rect toSource(ui.Rect r, int turns, ui.Size src) {
    switch (turns % 4) {
      case 1:
        // display (x, y) = (src.height - sy, sx)
        return ui.Rect.fromLTRB(
          r.top,
          src.height - r.right,
          r.bottom,
          src.height - r.left,
        );
      case 2:
        return ui.Rect.fromLTRB(
          src.width - r.right,
          src.height - r.bottom,
          src.width - r.left,
          src.height - r.top,
        );
      case 3:
        // display (x, y) = (sy, src.width - sx)
        return ui.Rect.fromLTRB(
          src.width - r.bottom,
          r.left,
          src.width - r.top,
          r.right,
        );
      default:
        return r;
    }
  }

  List<TileKey> _wanted() {
    final s = _zoom.value;
    final level = levelFor(s.scale * _dpr);
    final visible = toSource(
      _geometry.visibleRect(s),
      widget.quarterTurns,
      widget.fullSize,
    );
    return planTiles(image: widget.fullSize, visible: visible, level: level);
  }

  void _requestTiles() {
    final loader = widget.tileLoader;
    if (loader == null || !mounted) return;
    final gen = _tileGeneration;
    final wanted = _wanted();
    for (final key in wanted) {
      if (_tiles.containsKey(key) || _loading.contains(key)) continue;
      if (_loading.length >= _maxLoading) break;
      _loading.add(key);
      unawaited(
        loader(key).then((img) {
          _loading.remove(key);
          if (!mounted || gen != _tileGeneration) {
            img?.dispose();
            return;
          }
          if (img != null) {
            _tiles[key] = img;
            while (_tiles.length > _maxTiles) {
              _tiles.remove(_tiles.keys.first)?.dispose();
            }
            setState(() => _tileVersion++);
          }
          _requestTiles();
        }),
      );
    }
  }

  void _clearTiles() {
    _tileGeneration++;
    for (final t in _tiles.values) {
      t.dispose();
    }
    _tiles.clear();
    _tileVersion++;
  }

  // ---- build -------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    _dpr = MediaQuery.devicePixelRatioOf(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        if (size != _viewport || !_initialised) {
          final first = !_initialised;
          _viewport = size;
          _rebuildGeometry();
          _initialised = true;
          _zoom.value = _geometry.initial;
          if (first) {
            _atFit = true;
            WidgetsBinding.instance.addPostFrameCallback((_) => _onZoom());
          }
        }
        return Listener(
          onPointerSignal: _onPointerSignal,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onTap,
            onDoubleTapDown: (d) => _doubleTapAt = d.localPosition,
            onDoubleTap: () {
              _stopMotion();
              _animateTo(_geometry.nextStop(_zoom.value, _doubleTapAt));
            },
            onScaleStart: _onScaleStart,
            onScaleUpdate: _onScaleUpdate,
            onScaleEnd: _onScaleEnd,
            child: ClipRect(
              child: RepaintBoundary(
                child: CustomPaint(
                  size: size,
                  painter: _SurfacePainter(
                    zoom: _zoom,
                    base: widget.base,
                    fullSize: widget.fullSize,
                    quarterTurns: widget.quarterTurns,
                    viewport: size,
                    tiles: _tiles,
                    wanted: _tiled ? _wanted : null,
                    repaintCount: _tileVersion,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _SurfacePainter extends CustomPainter {
  _SurfacePainter({
    required this.zoom,
    required this.base,
    required this.fullSize,
    required this.quarterTurns,
    required this.viewport,
    required this.tiles,
    required this.wanted,
    required this.repaintCount,
  }) : super(repaint: zoom);

  final ValueNotifier<ZoomState> zoom;
  final ui.Image base;
  final ui.Size fullSize;
  final int quarterTurns;
  final ui.Size viewport;
  final Map<TileKey, ui.Image> tiles;
  final List<TileKey> Function()? wanted;
  final int repaintCount;

  @override
  void paint(Canvas canvas, ui.Size size) {
    final s = zoom.value;
    final display = quarterTurns.isOdd
        ? ui.Size(fullSize.height, fullSize.width)
        : fullSize;
    canvas
      ..save()
      ..translate(size.width / 2, size.height / 2)
      ..scale(s.scale)
      ..translate(-s.centre.dx, -s.centre.dy);
    // Source space → display space.
    switch (quarterTurns % 4) {
      case 1:
        canvas
          ..translate(display.width, 0)
          ..rotate(math.pi / 2);
      case 2:
        canvas
          ..translate(display.width, display.height)
          ..rotate(math.pi);
      case 3:
        canvas
          ..translate(0, display.height)
          ..rotate(-math.pi / 2);
    }
    final paint = Paint()..filterQuality = FilterQuality.medium;
    canvas.drawImageRect(
      base,
      ui.Rect.fromLTWH(0, 0, base.width.toDouble(), base.height.toDouble()),
      ui.Rect.fromLTWH(0, 0, fullSize.width, fullSize.height),
      paint,
    );
    final keys = wanted?.call();
    if (keys != null) {
      for (final k in keys) {
        final t = tiles[k];
        if (t == null) continue;
        canvas.drawImageRect(
          t,
          ui.Rect.fromLTWH(0, 0, t.width.toDouble(), t.height.toDouble()),
          k.sourceRect(fullSize),
          paint,
        );
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_SurfacePainter old) =>
      old.base != base ||
      old.quarterTurns != quarterTurns ||
      old.repaintCount != repaintCount ||
      old.viewport != viewport;
}
