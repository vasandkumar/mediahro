import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mediahro/app/l10n/gen/app_localizations.dart';
import 'package:mediahro/features/photos/map/map_tiles.dart';
import 'package:mediahro/features/photos/map/web_mercator.dart';

/// Holds where a map looks and moves it on request (zoom buttons, "show all",
/// opening a cluster). The [MapSurface] that owns it animates the moves.
class MapController extends ChangeNotifier {
  MapController({this.initialBounds, this.initialCenter, this.initialZoom = 3});

  /// Shown at first layout when there are photos to frame.
  final GeoBounds? initialBounds;
  final GeoPoint? initialCenter;
  final double initialZoom;

  MapCamera? _camera;
  Future<void> Function(MapCamera target)? _animate;

  /// Null until the map has been laid out once.
  MapCamera? get camera => _camera;

  set camera(MapCamera? value) {
    if (value == _camera) return;
    _camera = value;
    notifyListeners();
  }

  /// Glides to [target] (jumps when the map is not on screen).
  Future<void> animateTo(MapCamera target) {
    final run = _animate;
    if (run == null) {
      camera = target;
      return Future.value();
    }
    return run(target);
  }

  /// Frames [bounds].
  Future<void> fit(GeoBounds bounds, {double maxZoom = 15}) {
    final c = _camera;
    if (c == null) return Future.value();
    return animateTo(MapCamera.fit(bounds, c.size, maxZoom: maxZoom));
  }

  Future<void> zoomBy(double delta) {
    final c = _camera;
    if (c == null) return Future.value();
    return animateTo(
      c.zoomedAt(Offset(c.size.width / 2, c.size.height / 2), c.zoom + delta),
    );
  }
}

/// A pannable, zoomable map: tiles when they are available (and allowed),
/// a plain graticule otherwise, with [overlay] drawn in screen coordinates
/// on top (photo markers, a pin). Pan and pinch by touch, drag and wheel by
/// mouse, arrows and +/- by keyboard (IMG-007).
class MapSurface extends StatefulWidget {
  const MapSurface({
    required this.controller,
    required this.tiles,
    required this.overlay,
    this.onTap,
    this.autofocus = false,
    super.key,
  });

  /// Takes keyboard focus when shown (the location picker).
  final bool autofocus;

  final MapController controller;
  final MapTileSource tiles;

  /// Positioned children for the current camera.
  final List<Widget> Function(BuildContext context, MapCamera camera) overlay;

  /// A tap on empty map.
  final void Function(MapCamera camera, Offset at)? onTap;

  @override
  State<MapSurface> createState() => _MapSurfaceState();
}

class _MapSurfaceState extends State<MapSurface>
    with SingleTickerProviderStateMixin {
  late final AnimationController _anim = AnimationController(vsync: this);
  MapCamera? _startCamera;
  Offset _startFocal = Offset.zero;
  // A double tap is recognised here rather than by the gesture arena: the
  // arena would hold back every single tap (on markers too) for 300 ms.
  Offset? _lastTap;
  Timer? _lastTapTimer;

  @override
  void initState() {
    super.initState();
    widget.controller._animate = _animateTo;
  }

  @override
  void didUpdateWidget(MapSurface old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller._animate = null;
      widget.controller._animate = _animateTo;
    }
  }

  @override
  void dispose() {
    _lastTapTimer?.cancel();
    widget.controller._animate = null;
    _anim.dispose();
    super.dispose();
  }

  MapController get _c => widget.controller;

  /// Runs [apply] with 0..1 eased by [curve] over [duration]. A newer run
  /// (or a finger on the map) supersedes this one.
  Future<void> _run(
    Duration duration,
    Curve curve,
    void Function(double t) apply,
  ) async {
    _anim.stop();
    final eased = CurvedAnimation(parent: _anim, curve: curve);
    void tick() => apply(eased.value);
    eased.addListener(tick);
    _anim
      ..duration = duration
      ..value = 0;
    try {
      await _anim.forward().orCancel;
      apply(1);
    } on TickerCanceled {
      // Superseded.
    } finally {
      eased
        ..removeListener(tick)
        ..dispose();
    }
  }

  Future<void> _animateTo(MapCamera target) async {
    final from = _c.camera;
    if (from == null || MediaQuery.disableAnimationsOf(context)) {
      _c.camera = target;
      return;
    }
    final (ax, ay) = mercatorUnit(from.center.lat, from.center.lon);
    var (bx, by) = mercatorUnit(target.center.lat, target.center.lon);
    // The short way round the antimeridian.
    if (bx - ax > 0.5) bx -= 1;
    if (ax - bx > 0.5) bx += 1;
    await _run(const Duration(milliseconds: 350), Curves.easeInOutCubic, (t) {
      final x = ui.lerpDouble(ax, bx, t)!;
      _c.camera = MapCamera(
        center: geoFromUnit(
          x - x.floorToDouble(),
          ui.lerpDouble(ay, by, t)!.clamp(0.0, 1.0),
        ),
        zoom: ui.lerpDouble(from.zoom, target.zoom, t)!,
        size: target.size,
      ).constrained();
    });
  }

  void _layout(Size size) {
    final cam = _c.camera;
    if (cam == null) {
      final bounds = _c.initialBounds;
      final fresh = bounds != null
          ? MapCamera.fit(bounds, size)
          : MapCamera(
              center: _c.initialCenter ?? (lat: 20, lon: 0),
              zoom: _c.initialZoom,
              size: size,
            ).constrained();
      // Not during build: listeners rebuild.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _c.camera == null) _c.camera = fresh;
      });
    } else if (cam.size != size) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final now = _c.camera;
        if (mounted && now != null && now.size != size) {
          _c.camera = now.copyWith(size: size).constrained();
        }
      });
    }
  }

  void _scaleStart(ScaleStartDetails d) {
    _anim.stop();
    _startCamera = _c.camera;
    _startFocal = d.localFocalPoint;
  }

  void _scaleUpdate(ScaleUpdateDetails d) {
    final start = _startCamera;
    if (start == null) return;
    final zoom = start.zoom + math.log(d.scale) / math.ln2;
    _c.camera = start
        .zoomedAt(_startFocal, zoom)
        .panned(d.localFocalPoint - _startFocal);
  }

  void _scaleEnd(ScaleEndDetails d) {
    final cam = _c.camera;
    final v = d.velocity.pixelsPerSecond;
    if (cam == null || d.pointerCount > 0 || v.distance < 300) return;
    if (MediaQuery.disableAnimationsOf(context)) return;
    // A short glide in the direction of the flick.
    final travel = v * 0.22;
    unawaited(
      _run(
        const Duration(milliseconds: 550),
        Curves.decelerate,
        (t) => _c.camera = cam.panned(travel * t),
      ),
    );
  }

  void _tapped(Offset at) {
    final cam = _c.camera;
    if (cam == null) return;
    final previous = _lastTap;
    if (previous != null && (previous - at).distance < 48) {
      _lastTapTimer?.cancel();
      _lastTap = null;
      unawaited(_c.animateTo(cam.zoomedAt(at, cam.zoom + 1)));
      return;
    }
    _lastTap = at;
    _lastTapTimer?.cancel();
    _lastTapTimer = Timer(const Duration(milliseconds: 300), () {
      _lastTap = null;
    });
    widget.onTap?.call(cam, at);
  }

  void _wheel(PointerSignalEvent e) {
    if (e is! PointerScrollEvent) return;
    GestureBinding.instance.pointerSignalResolver.register(e, (_) {
      final cam = _c.camera;
      if (cam == null) return;
      _c.camera = cam.zoomedAt(
        e.localPosition,
        cam.zoom - e.scrollDelta.dy / 300,
      );
    });
  }

  KeyEventResult _key(FocusNode node, KeyEvent e) {
    if (e is KeyUpEvent) return KeyEventResult.ignored;
    final cam = _c.camera;
    if (cam == null) return KeyEventResult.ignored;
    final k = e.logicalKey;
    const step = 80.0;
    if (k == LogicalKeyboardKey.arrowLeft) {
      _c.camera = cam.panned(const Offset(step, 0));
    } else if (k == LogicalKeyboardKey.arrowRight) {
      _c.camera = cam.panned(const Offset(-step, 0));
    } else if (k == LogicalKeyboardKey.arrowUp) {
      _c.camera = cam.panned(const Offset(0, step));
    } else if (k == LogicalKeyboardKey.arrowDown) {
      _c.camera = cam.panned(const Offset(0, -step));
    } else if (k == LogicalKeyboardKey.equal ||
        k == LogicalKeyboardKey.add ||
        k == LogicalKeyboardKey.numpadAdd) {
      unawaited(_c.zoomBy(1));
    } else if (k == LogicalKeyboardKey.minus ||
        k == LogicalKeyboardKey.numpadSubtract) {
      unawaited(_c.zoomBy(-1));
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return LayoutBuilder(
      builder: (context, box) {
        final size = box.biggest;
        _layout(size);
        return Semantics(
          container: true,
          label: l10n.photosMapLabel,
          child: Focus(
            autofocus: widget.autofocus,
            onKeyEvent: _key,
            child: Listener(
              onPointerSignal: _wheel,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onScaleStart: _scaleStart,
                onScaleUpdate: _scaleUpdate,
                onScaleEnd: _scaleEnd,
                onTapUp: (d) => _tapped(d.localPosition),
                child: ClipRect(
                  child: ListenableBuilder(
                    listenable: _c,
                    builder: (context, _) {
                      final cam = _c.camera;
                      return Stack(
                        fit: StackFit.expand,
                        children: [
                          if (cam != null)
                            ExcludeSemantics(
                              child: TileLayer(
                                camera: cam,
                                source: widget.tiles,
                              ),
                            ),
                          if (cam != null) ...widget.overlay(context, cam),
                        ],
                      );
                    },
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

/// Draws the tiles for [camera]: decoded pictures from [source], a coarser
/// level's picture scaled up while a tile loads, a graticule under both.
class TileLayer extends StatefulWidget {
  const TileLayer({required this.camera, required this.source, super.key});

  final MapCamera camera;
  final MapTileSource source;

  @override
  State<TileLayer> createState() => _TileLayerState();
}

class _TileLayerState extends State<TileLayer> {
  static const _memory = 256;
  static const _parallel = 6;

  final LinkedHashMap<TileId, ui.Image> _images = LinkedHashMap();
  final Set<TileId> _loading = {};
  final Set<TileId> _failed = {};
  List<PlacedTile> _wanted = const [];
  bool _enabledBefore = false;
  int _version = 0;
  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    for (final i in _images.values) {
      i.dispose();
    }
    _images.clear();
    super.dispose();
  }

  void _pump() {
    final enabled = widget.source.enabled;
    if (enabled && !_enabledBefore) _failed.clear();
    _enabledBefore = enabled;
    for (final t in _wanted) {
      if (_loading.length >= _parallel) return;
      if (_images.containsKey(t.id) ||
          _loading.contains(t.id) ||
          _failed.contains(t.id)) {
        continue;
      }
      _loading.add(t.id);
      unawaited(_fetch(t.id));
    }
  }

  Future<void> _fetch(TileId id) async {
    ui.Image? image;
    try {
      final bytes = await widget.source.load(id);
      if (bytes != null && !_disposed) {
        final codec = await ui.instantiateImageCodec(bytes);
        try {
          image = (await codec.getNextFrame()).image;
        } finally {
          codec.dispose();
        }
      }
    } on Object {
      image = null;
    }
    _loading.remove(id);
    if (_disposed) {
      image?.dispose();
      return;
    }
    if (image == null) {
      _failed.add(id);
    } else {
      _images[id] = image;
      while (_images.length > _memory) {
        final oldest = _images.keys.first;
        _images.remove(oldest)?.dispose();
      }
    }
    _version++;
    if (mounted) setState(() {});
    _pump();
  }

  @override
  Widget build(BuildContext context) {
    _wanted = widget.camera.tiles();
    // Request after this frame: fetching may complete synchronously (a tile
    // that is already in memory) and call setState.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_disposed) _pump();
    });
    final scheme = Theme.of(context).colorScheme;
    return CustomPaint(
      isComplex: true,
      painter: _TilePainter(
        camera: widget.camera,
        placed: _wanted,
        images: _images,
        background: scheme.surfaceContainerHighest,
        lines: scheme.outlineVariant,
        revision: _version,
      ),
      child: const SizedBox.expand(),
    );
  }
}

class _TilePainter extends CustomPainter {
  _TilePainter({
    required this.camera,
    required this.placed,
    required this.images,
    required this.background,
    required this.lines,
    required this.revision,
  });

  final MapCamera camera;
  final List<PlacedTile> placed;
  final Map<TileId, ui.Image> images;
  final Color background;
  final Color lines;
  final int revision;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = background);
    _graticule(canvas, size);
    final paint = Paint()..filterQuality = FilterQuality.medium;
    for (final t in placed) {
      final image = images[t.id];
      if (image != null) {
        canvas.drawImageRect(
          image,
          Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
          t.rect,
          paint,
        );
        continue;
      }
      // A coarser tile stretched over this one until its own arrives.
      for (var k = 1; k <= 6 && t.id.z - k >= 0; k++) {
        final up = TileId(t.id.z - k, t.id.x >> k, t.id.y >> k);
        final coarse = images[up];
        if (coarse == null) continue;
        final part = coarse.width / (1 << k);
        final sx = (t.id.x - (up.x << k)) * part;
        final sy = (t.id.y - (up.y << k)) * part;
        canvas.drawImageRect(
          coarse,
          Rect.fromLTWH(sx, sy, part, part),
          t.rect,
          paint,
        );
        break;
      }
    }
  }

  void _graticule(Canvas canvas, Size size) {
    final pxPerDegree = camera.worldPixels / 360;
    const steps = [0.5, 1.0, 2.0, 5.0, 10.0, 15.0, 30.0, 45.0, 90.0];
    final step = steps.firstWhere(
      (s) => s * pxPerDegree >= 90,
      orElse: () => 90.0,
    );
    final pen = Paint()
      ..color = lines.withValues(alpha: 0.6)
      ..strokeWidth = 1;
    final b = camera.visibleBounds();
    final north = math.min(b.north, maxMapLatitude);
    final south = math.max(b.south, -maxMapLatitude);
    for (var lat = (south / step).ceil() * step; lat <= north; lat += step) {
      final y = camera.toScreen(lat, camera.center.lon).dy;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), pen);
    }
    // Meridians: from the left edge's longitude across the screen.
    final left = camera.toGeo(Offset.zero).lon;
    final first = (left / step).ceil() * step;
    for (var i = 0; i < 400; i++) {
      final lon = first + i * step;
      final x = camera.toScreen(camera.center.lat, lon).dx;
      if (x > size.width) break;
      if (x >= 0) canvas.drawLine(Offset(x, 0), Offset(x, size.height), pen);
    }
  }

  @override
  bool shouldRepaint(_TilePainter old) =>
      old.camera != camera ||
      old.revision != revision ||
      old.background != background ||
      old.lines != lines;
}
