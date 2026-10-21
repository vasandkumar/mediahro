import 'dart:async';
import 'dart:math';
import 'dart:ui' as ui show FlutterView;

import 'package:flutter/material.dart' hide ImageInfo;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mediahro/app/l10n/gen/app_localizations.dart';
import 'package:mediahro/features/photos/photos_providers.dart';
import 'package:mediahro/features/photos/slideshow/slideshow_music.dart';
import 'package:mediahro/features/photos/slideshow/slideshow_options.dart';
import 'package:mediahro/features/photos/slideshow/slideshow_sheet.dart';
import 'package:mediahro/features/photos/timeline/timeline_model.dart';
import 'package:mediahro/features/photos/viewer/viewer_image.dart';
import 'package:mediahro/features/settings/settings_providers.dart';
import 'package:mediahro/platform/platform_facades.dart';
import 'package:mediahro_design/mediahro_design.dart';

/// Opens the slideshow of [photos] (videos are left out), starting at
/// [start] (IMG-012).
Future<void> openSlideshow(
  BuildContext context,
  List<PhotoEntry> photos, {
  int start = 0,
}) {
  final shown = [
    for (final p in photos)
      if (!p.isVideo) p,
  ];
  if (shown.isEmpty) return Future<void>.value();
  // Start at the same picture in the list without the videos.
  final at = start.clamp(0, photos.length - 1);
  var first = 0;
  for (var i = 0; i < at; i++) {
    if (!photos[i].isVideo) first++;
  }
  if (photos[at].isVideo && first >= shown.length) first = shown.length - 1;
  return Navigator.of(context).push<void>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => SlideshowScreen(photos: shown, start: first),
    ),
  );
}

/// A picture on its way to the screen or on it.
class _Slide {
  _Slide(this.index, this.entry, this.image);

  final int index;
  final PhotoEntry entry;
  final ViewerImage image;
}

/// The slideshow (IMG-012): one picture after another, with a transition,
/// an optional slow zoom (Ken Burns), the order of the list or a shuffle,
/// loop, a speed you can change while it runs, and music from the Music
/// library. Tap for the controls.
class SlideshowScreen extends ConsumerStatefulWidget {
  const SlideshowScreen({
    required this.photos,
    this.start = 0,
    this.random,
    super.key,
  });

  final List<PhotoEntry> photos;
  final int start;

  /// Source of the shuffle; tests give a seeded one.
  final Random? random;

  @override
  ConsumerState<SlideshowScreen> createState() => _SlideshowScreenState();
}

class _SlideshowScreenState extends ConsumerState<SlideshowScreen>
    with TickerProviderStateMixin {
  late final AnimationController _clock = AnimationController(vsync: this)
    ..addStatusListener((s) {
      if (s == AnimationStatus.completed && _playing) unawaited(_advance());
    });
  late final AnimationController _fade = AnimationController(vsync: this)
    ..addStatusListener((s) {
      if (s == AnimationStatus.completed) _dropOutgoing();
    });

  late SlideshowOptions _o;
  late SlideOrder _order;
  late final SlideshowMusic _music;
  _Slide? _current;
  _Slide? _outgoing;
  final Map<int, Future<ViewerImage?>> _preload = {};
  bool _playing = true;
  bool _chrome = true;
  bool _ended = false;
  bool _musicOn = false;
  bool _failedAll = false;
  bool _disposed = false;
  int _failures = 0;
  Timer? _hide;
  late final Random _rng = widget.random ?? Random();

  List<PhotoEntry> get _photos => widget.photos;

  @override
  void initState() {
    super.initState();
    _o = SlideshowSettings.read(ref.read(settingsStoreProvider));
    _music = ref.read(slideshowMusicProvider);
    // Kept: the provider cannot be read once the screen is disposed, and the
    // screen must be let go then.
    try {
      _display = ref.read(displayProvider);
    } on Object {
      _display = null;
    }
    _order = _newOrder(widget.start);
    unawaited(_enter());
    unawaited(_watchDisplays());
    unawaited(_show(_order.current, first: true));
    unawaited(_startMusic());
  }

  SlideOrder _newOrder(int start) => SlideOrder(
    count: _photos.length,
    start: start,
    random: _o.random,
    loop: _o.loop,
    rng: _rng,
  );

  Future<void> _enter() async {
    // Independent of the system bars: neither waits for the other.
    unawaited(_syncAwake());
    try {
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    } on Object {
      // A platform without it.
    }
  }

  Future<void> _watchDisplays() async {
    final display = _display;
    if (display == null) return;
    try {
      _look(await display.displays());
      _displayChanges = display.changes.listen(_look);
    } on Object {
      // No display facade here: the show stays on this screen.
    }
  }

  void _look(List<DisplayInfo> displays) {
    if (_disposed || !mounted) return;
    DisplayInfo? found;
    for (final d in displays) {
      if (d.isExternal) {
        found = d;
        break;
      }
    }
    final held = _presentation;
    final gone = held != null && found?.id != held.displayId;
    if (found?.id == _external?.id && !gone) return;
    setState(() {
      _external = found;
      if (gone) {
        // The presentation closes by itself when its display goes.
        _presentation = null;
        _externalView = null;
      }
    });
  }

  /// Starts or stops the show on the external display.
  Future<void> _toggleExternal() async {
    final display = _display;
    final held = _presentation;
    if (display == null) return;
    if (held != null) {
      setState(() {
        _presentation = null;
        _externalView = null;
      });
      try {
        await display.closePresentation(held);
      } on Object {
        // Closed with the display at the latest.
      }
      return;
    }
    final target = _external;
    if (target == null) return;
    PresentationHandle? handle;
    try {
      handle = await display.openPresentation(target.id);
    } on Object {
      handle = null;
    }
    if (_disposed || !mounted) {
      if (handle != null) unawaited(display.closePresentation(handle));
      return;
    }
    final view = handle == null
        ? null
        : WidgetsBinding.instance.platformDispatcher.view(id: handle.id);
    if (handle == null || view == null) {
      // This platform cannot draw there: the show stays on this screen, which
      // is what mirroring shows.
      if (handle != null) unawaited(display.closePresentation(handle));
      _toastExternalFailed();
      return;
    }
    setState(() {
      _presentation = handle;
      _externalView = view;
    });
  }

  void _toastExternalFailed() {
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.of(context).photosSlideshowExternalFailed,
          ),
        ),
      );
  }

  Future<void> _leave() async {
    try {
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    } on Object {
      // Nothing to undo.
    }
  }

  Future<void> _startMusic() async {
    if (_o.music == SlideMusicSource.none || !_music.available) return;
    final ok = await _music.start(_o);
    if (_disposed) {
      await _music.stop();
      return;
    }
    if (mounted) setState(() => _musicOn = ok);
  }

  @override
  void dispose() {
    _disposed = true;
    _hide?.cancel();
    _clock.dispose();
    _fade.dispose();
    _current?.image.dispose();
    _outgoing?.image.dispose();
    for (final f in _preload.values) {
      unawaited(f.then((i) => i?.dispose()));
    }
    _preload.clear();
    unawaited(_music.stop());
    unawaited(_displayChanges?.cancel());
    final held = _presentation;
    if (held != null) {
      try {
        unawaited(_display?.closePresentation(held) ?? Future<void>.value());
      } on Object {
        // Closed with the display at the latest.
      }
    }
    unawaited(_leave());
    if (_awake) {
      _awake = false;
      try {
        unawaited(_display?.keepScreenOn(on: false) ?? Future<void>.value());
      } on Object {
        // See _syncAwake.
      }
    }
    super.dispose();
  }

  // ---- the pictures ----------------------------------------------------

  Future<ViewerImage?> _load(int index) {
    return _preload[index] ??= () async {
      try {
        return await ref.read(viewerImageLoaderProvider)(_photos[index]);
      } on Object {
        return null;
      }
    }();
  }

  /// Shows picture [index]; one that cannot be opened is skipped.
  Future<void> _show(int index, {bool first = false}) async {
    final image = await _load(index);
    await _preload.remove(index);
    if (_disposed) {
      image?.dispose();
      return;
    }
    if (image == null) {
      _failures++;
      if (_failures >= _photos.length) {
        setState(() => _failedAll = true);
        return;
      }
      if (_order.next() || first) {
        await _show(_order.current);
      } else {
        _finish();
      }
      return;
    }
    _failures = 0;
    final old = _outgoing;
    old?.image.dispose();
    setState(() {
      _outgoing = _current;
      _current = _Slide(index, _photos[index], image);
      _ended = false;
    });
    _begin(first: first);
    final next = _order.peekNext;
    if (next != null && next != index) unawaited(_load(next));
  }

  void _begin({required bool first}) {
    final reduce = KAccessibility.reduceMotion(context);
    if (_o.transition == SlideChange.none || first || _outgoing == null) {
      _dropOutgoing();
    } else {
      _fade
        ..duration = reduce ? KMotion.fast : const Duration(milliseconds: 700)
        ..forward(from: 0);
    }
    _clock.duration = _o.slideDuration;
    if (_playing) _clock.forward(from: 0);
    _scheduleHide();
  }

  void _dropOutgoing() {
    final old = _outgoing;
    if (old == null) return;
    setState(() => _outgoing = null);
    old.image.dispose();
  }

  Future<void> _advance() async {
    if (!_order.next()) {
      _finish();
      return;
    }
    await _show(_order.current);
  }

  void _finish() {
    _clock.stop();
    if (mounted) {
      setState(() {
        _ended = true;
        _chrome = true;
      });
    }
    unawaited(_syncAwake());
  }

  Future<void> _previous() async {
    if (!_order.previous()) return;
    await _show(_order.current);
  }

  Future<void> _next() async {
    if (_ended) return;
    await _advance();
  }

  void _restart() {
    _order = _newOrder(_o.random ? _order.current : 0);
    setState(() => _ended = false);
    unawaited(_syncAwake());
    unawaited(_show(_order.current));
  }

  // ---- the controls ----------------------------------------------------

  void _togglePlay() {
    setState(() => _playing = !_playing);
    if (_playing) {
      _clock.forward();
      _scheduleHide();
    } else {
      _clock.stop();
      _hide?.cancel();
      setState(() => _chrome = true);
    }
    unawaited(_syncAwake());
  }

  DisplayFacade? _display;
  bool _awake = false;

  // An external display, if one is connected, and the show on it (ADR-044).
  // The pictures are drawn there; the controls stay on this screen. The
  // slideshow shows library photos only (never the vault, ADR-043), so
  // nothing sensitive reaches the other screen.
  DisplayInfo? _external;
  PresentationHandle? _presentation;
  ui.FlutterView? _externalView;
  StreamSubscription<List<DisplayInfo>>? _displayChanges;

  /// The screen stays on while the show plays and may sleep while it is
  /// paused or has ended.
  Future<void> _syncAwake() async {
    final want = _playing && !_ended && !_disposed;
    if (want == _awake) return;
    _awake = want;
    try {
      await _display?.keepScreenOn(on: want);
    } on Object {
      // No display facade here: the screen may time out.
    }
  }

  void _scheduleHide() {
    _hide?.cancel();
    if (!_playing || _ended) return;
    if (!KPlayerChrome.shouldAutoHide(context)) return;
    _hide = Timer(const Duration(seconds: 3), () {
      if (mounted && _playing) setState(() => _chrome = false);
    });
  }

  void _toggleChrome() {
    setState(() => _chrome = !_chrome);
    if (_chrome) _scheduleHide();
  }

  void _setOptions(SlideshowOptions next, {bool persist = true}) {
    final reshuffle = next.random != _o.random || next.loop != _o.loop;
    final retime = next.slideDuration != _o.slideDuration;
    final musicChanged =
        next.music != _o.music || next.playlistId != _o.playlistId;
    setState(() => _o = next);
    if (persist) {
      SlideshowSettings.write(ref.read(settingsStoreProvider), next);
    }
    if (reshuffle) {
      _order = SlideOrder(
        count: _photos.length,
        start: _current?.index ?? widget.start,
        random: next.random,
        loop: next.loop,
        rng: _rng,
      );
    }
    if (retime) {
      // Keep how far the picture has got when the speed changes.
      final v = _clock.value;
      _clock.duration = next.slideDuration;
      if (_playing && !_ended) _clock.forward(from: v);
    }
    if (musicChanged) {
      unawaited(_music.stop());
      setState(() => _musicOn = false);
      unawaited(_startMusic());
    }
  }

  void _faster() => _setOptions(
    _o.copyWith(speed: _o.speed * 1.25 > 4 ? 4 : _o.speed * 1.25),
  );

  void _slower() => _setOptions(
    _o.copyWith(speed: _o.speed / 1.25 < 0.25 ? 0.25 : _o.speed / 1.25),
  );

  Future<void> _options() async {
    _hide?.cancel();
    await showSlideshowSheet(context, ref, _o, onChanged: _setOptions);
    _scheduleHide();
  }

  // ---- drawing ---------------------------------------------------------

  Widget _layer(_Slide s, {required bool incoming}) {
    final reduce = KAccessibility.reduceMotion(context);
    final kenBurns = _o.kenBurns && !reduce;
    return AnimatedBuilder(
      animation: Listenable.merge([_clock, _fade]),
      builder: (context, _) {
        final picture = RawImage(image: s.image.base, fit: BoxFit.contain);
        Widget child = SizedBox.expand(child: picture);
        if (kenBurns) {
          final r = Random(s.entry.id);
          final zoomIn = r.nextBool();
          final k = Curves.easeInOut.transform(_clock.value);
          final scale = zoomIn ? 1 + 0.14 * k : 1.14 - 0.14 * k;
          final dx = (r.nextDouble() - 0.5) * 0.06 * k;
          final dy = (r.nextDouble() - 0.5) * 0.06 * k;
          child = Transform(
            alignment: Alignment.center,
            transform: Matrix4.identity()
              ..scaleByDouble(scale, scale, 1, 1)
              ..translateByDouble(dx * 400, dy * 400, 0, 1),
            child: child,
          );
        }
        final t = _fade.isAnimating || _fade.value > 0
            ? Curves.easeInOut.transform(_fade.value)
            : 1.0;
        final done = _outgoing == null;
        final width = MediaQuery.sizeOf(context).width;
        if (done) return child;
        // With reduced motion nothing slides or zooms: at most a short fade.
        final change = reduce && _o.transition != SlideChange.none
            ? SlideChange.fade
            : _o.transition;
        switch (change) {
          case SlideChange.none:
            return child;
          case SlideChange.fade:
            return Opacity(opacity: incoming ? t : 1, child: child);
          case SlideChange.slide:
            return Transform.translate(
              offset: Offset(incoming ? (1 - t) * width : -t * width * 0.3, 0),
              child: child,
            );
          case SlideChange.zoom:
            return Opacity(
              opacity: incoming ? t : 1 - t,
              child: Transform.scale(
                scale: incoming ? 1.2 - 0.2 * t : 1 + 0.2 * t,
                child: child,
              ),
            );
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final current = _current;
    final scrim = Colors.black.withValues(alpha: 0.6);
    return ViewAnchor(
      view: _externalView == null
          ? null
          : View(
              view: _externalView!,
              child: _ExternalSurface(
                children: [
                  if (_outgoing != null) _layer(_outgoing!, incoming: false),
                  if (current != null) _layer(current, incoming: true),
                ],
              ),
            ),
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.space): _togglePlay,
          const SingleActivator(LogicalKeyboardKey.arrowRight): () =>
              unawaited(_next()),
          const SingleActivator(LogicalKeyboardKey.arrowLeft): () =>
              unawaited(_previous()),
          const SingleActivator(LogicalKeyboardKey.equal): _faster,
          const SingleActivator(LogicalKeyboardKey.add): _faster,
          const SingleActivator(LogicalKeyboardKey.minus): _slower,
          const SingleActivator(LogicalKeyboardKey.escape): () =>
              Navigator.of(context).maybePop(),
        },
        child: Focus(
          autofocus: true,
          child: Scaffold(
            backgroundColor: Colors.black,
            body: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _toggleChrome,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (_outgoing != null) _layer(_outgoing!, incoming: false),
                  if (current != null)
                    Semantics(
                      liveRegion: true,
                      label: current.entry.name,
                      child: _layer(current, incoming: true),
                    )
                  else if (!_failedAll)
                    const Center(child: CircularProgressIndicator()),
                  if (_failedAll)
                    Center(
                      child: Text(
                        l10n.photosSlideshowFailed,
                        style: const TextStyle(color: Colors.white),
                      ),
                    ),
                  if (_ended)
                    Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            l10n.photosSlideshowEnded,
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(color: Colors.white),
                          ),
                          const SizedBox(height: 12),
                          FilledButton(
                            onPressed: _restart,
                            child: Text(l10n.photosSlideshowAgain),
                          ),
                        ],
                      ),
                    ),
                  // Top bar.
                  PositionedDirectional(
                    top: 0,
                    start: 0,
                    end: 0,
                    child: IgnorePointer(
                      ignoring: !_chrome,
                      child: AnimatedOpacity(
                        opacity: _chrome ? 1 : 0,
                        duration: KMotion.base,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [scrim, Colors.transparent],
                            ),
                          ),
                          child: SafeArea(
                            bottom: false,
                            child: Row(
                              children: [
                                IconButton(
                                  tooltip: l10n.photosSlideshowClose,
                                  color: Colors.white,
                                  icon: const Icon(Icons.close),
                                  onPressed: () =>
                                      Navigator.of(context).maybePop(),
                                ),
                                Expanded(
                                  child: Text(
                                    l10n.photosSlideshowPosition(
                                      _order.place,
                                      _photos.length,
                                    ),
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleSmall
                                        ?.copyWith(color: Colors.white),
                                  ),
                                ),
                                if (_musicOn)
                                  Padding(
                                    padding: const EdgeInsets.all(12),
                                    child: Icon(
                                      Icons.music_note,
                                      color: Colors.white,
                                      semanticLabel:
                                          l10n.photosSlideshowMusicOn,
                                    ),
                                  ),
                                if (_external != null)
                                  IconButton(
                                    tooltip: _presentation == null
                                        ? l10n.photosSlideshowExternal
                                        : l10n.photosSlideshowExternalStop,
                                    color: Colors.white,
                                    icon: Icon(
                                      _presentation == null
                                          ? Icons.cast
                                          : Icons.cast_connected,
                                    ),
                                    onPressed: () =>
                                        unawaited(_toggleExternal()),
                                  ),
                                IconButton(
                                  tooltip: l10n.photosSlideshowOptions,
                                  color: Colors.white,
                                  icon: const Icon(Icons.tune),
                                  onPressed: () => unawaited(_options()),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  // Bottom bar.
                  PositionedDirectional(
                    bottom: 0,
                    start: 0,
                    end: 0,
                    child: IgnorePointer(
                      ignoring: !_chrome,
                      child: AnimatedOpacity(
                        opacity: _chrome ? 1 : 0,
                        duration: KMotion.base,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.bottomCenter,
                              end: Alignment.topCenter,
                              colors: [scrim, Colors.transparent],
                            ),
                          ),
                          child: SafeArea(
                            top: false,
                            // A wrap: the buttons and the speed fit a narrow phone.
                            child: Wrap(
                              alignment: WrapAlignment.center,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                IconButton(
                                  tooltip: l10n.photosSlideshowSlower,
                                  color: Colors.white,
                                  icon: const Icon(Icons.fast_rewind),
                                  onPressed:
                                      _o.speed > SlideshowOptions.minSpeed
                                      ? _slower
                                      : null,
                                ),
                                IconButton(
                                  tooltip: l10n.photosSlideshowPrevious,
                                  color: Colors.white,
                                  icon: const Icon(Icons.skip_previous),
                                  onPressed: () => unawaited(_previous()),
                                ),
                                IconButton(
                                  tooltip: _playing
                                      ? l10n.photosSlideshowPause
                                      : l10n.photosSlideshowPlay,
                                  color: Colors.white,
                                  iconSize: 40,
                                  icon: Icon(
                                    _playing
                                        ? Icons.pause_circle_outline
                                        : Icons.play_circle_outline,
                                  ),
                                  onPressed: _togglePlay,
                                ),
                                IconButton(
                                  tooltip: l10n.photosSlideshowNext,
                                  color: Colors.white,
                                  icon: const Icon(Icons.skip_next),
                                  onPressed: () => unawaited(_next()),
                                ),
                                IconButton(
                                  tooltip: l10n.photosSlideshowFaster,
                                  color: Colors.white,
                                  icon: const Icon(Icons.fast_forward),
                                  onPressed:
                                      _o.speed < SlideshowOptions.maxSpeed
                                      ? _faster
                                      : null,
                                ),
                                Semantics(
                                  liveRegion: true,
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                    ),
                                    child: Text(
                                      l10n.photosSlideshowSpeed(
                                        slideshowSpeedText(context, _o.speed),
                                      ),
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelLarge
                                          ?.copyWith(color: Colors.white),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The pictures alone, on black, for the external display.
class _ExternalSurface extends StatelessWidget {
  const _ExternalSurface({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: Colors.black,
    child: Stack(fit: StackFit.expand, children: children),
  );
}
