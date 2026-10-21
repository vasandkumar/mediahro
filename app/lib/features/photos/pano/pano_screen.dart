import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mediahro/app/l10n/gen/app_localizations.dart';
import 'package:mediahro/features/photos/pano/pano_controller.dart';
import 'package:mediahro/features/photos/pano/pano_math.dart';
import 'package:mediahro/features/photos/pano/pano_providers.dart';
import 'package:mediahro/features/photos/pano/pano_view.dart';
import 'package:mediahro/features/photos/timeline/timeline_model.dart';
import 'package:mediahro_design/mediahro_design.dart';

/// Opens the 360° look-around for [entry] (IMG-001).
Future<void> openPanorama(BuildContext context, PhotoEntry entry) =>
    Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => PanoramaScreen(entry: entry)),
    );

/// A 360° photo to look around in: drag, pinch, keys, buttons, or by moving
/// the phone. The buttons are always on screen so nothing depends on a
/// gesture; with reduced motion the phone's motion is off to begin with and
/// a flick does not coast.
class PanoramaScreen extends ConsumerStatefulWidget {
  const PanoramaScreen({required this.entry, super.key});

  final PhotoEntry entry;

  @override
  ConsumerState<PanoramaScreen> createState() => _PanoramaScreenState();
}

class _PanoramaScreenState extends ConsumerState<PanoramaScreen>
    with WidgetsBindingObserver {
  PanoImage? _pano;
  PanoController? _controller;
  Object? _error;
  bool _disposed = false;
  bool _started = false;
  bool _reduceMotion = false;
  bool _motionAvailable = false;
  StreamSubscription<PanoAttitude>? _motion;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_load());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = KAccessibility.reduceMotion(context);
    if (!_started && _controller != null) _maybeStartMotion();
  }

  Future<void> _load() async {
    try {
      final pano = await ref.read(panoImageLoaderProvider)(widget.entry);
      if (_disposed) {
        pano.dispose();
        return;
      }
      var sensor = false;
      final source = _source;
      if (source != null) {
        try {
          sensor = await source.available;
        } on Object {
          sensor = false;
        }
      }
      if (_disposed) {
        pano.dispose();
        return;
      }
      setState(() {
        _pano = pano;
        _motionAvailable = sensor;
        _controller = PanoController(meta: pano.meta);
      });
      _maybeStartMotion();
    } on Object catch (e) {
      if (!_disposed) setState(() => _error = e);
    }
  }

  PanoMotionSource? get _source => ref.read(panoMotionProvider);

  /// The phone's motion starts on its own only where it exists and the
  /// person has not asked for reduced motion.
  void _maybeStartMotion() {
    if (_started) return;
    _started = true;
    if (_motionAvailable && !_reduceMotion) _startMotion();
  }

  void _startMotion() {
    final c = _controller;
    final source = _source;
    if (c == null || source == null || _motion != null) return;
    c.startMotion();
    _motion = source.attitude.listen(c.onAttitude);
    setState(() {});
  }

  void _stopMotion() {
    unawaited(_motion?.cancel());
    _motion = null;
    _controller?.stopMotion();
    if (mounted) setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // The sensors are let go while the app is not on screen.
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      if (_motion != null) _stopMotion();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_motion?.cancel());
    _controller?.dispose();
    _pano?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final c = _controller;
    final pano = _pano;
    final program = ref.watch(panoProgramProvider).value;
    final loadingProgram = ref.watch(panoProgramProvider).isLoading;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          if (_error != null)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(KSpacing.s24),
                child: Text(
                  l10n.photosPanoError,
                  style: const TextStyle(color: Colors.white),
                  textAlign: TextAlign.center,
                ),
              ),
            )
          else if (c == null || pano == null || loadingProgram)
            const Center(child: CircularProgressIndicator())
          else
            Positioned.fill(
              child: PanoramaView(
                image: pano.image,
                controller: c,
                program: program,
                reduceMotion: _reduceMotion,
              ),
            ),
          PositionedDirectional(
            top: 0,
            start: 0,
            end: 0,
            child: SafeArea(
              child: Row(
                children: [
                  IconButton(
                    tooltip: MaterialLocalizations.of(context)
                        .backButtonTooltip,
                    color: Colors.white,
                    icon: const BackButtonIcon(),
                    onPressed: () => Navigator.of(context).maybePop(),
                  ),
                  Expanded(
                    child: Text(
                      l10n.photosPanoTitle,
                      style: Theme.of(context).textTheme.titleMedium
                          ?.copyWith(color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (c != null)
            PositionedDirectional(
              bottom: 0,
              start: 0,
              end: 0,
              child: SafeArea(
                child: _Controls(
                  controller: c,
                  motionAvailable: _motionAvailable,
                  motionOn: _motion != null,
                  onMotion: () =>
                      _motion == null ? _startMotion() : _stopMotion(),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Controls extends StatelessWidget {
  const _Controls({
    required this.controller,
    required this.motionAvailable,
    required this.motionOn,
    required this.onMotion,
  });

  final PanoController controller;
  final bool motionAvailable;
  final bool motionOn;
  final VoidCallback onMotion;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    Widget button(String tip, IconData icon, VoidCallback onTap) => IconButton(
      tooltip: tip,
      color: Colors.white,
      iconSize: 28,
      constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
      icon: Icon(icon),
      onPressed: onTap,
    );
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [Color(0xCC000000), Color(0x00000000)],
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: KSpacing.s8),
        child: Wrap(
          alignment: WrapAlignment.center,
          children: [
            button(
              l10n.photosPanoLeft,
              Icons.arrow_back,
              () => controller.step(right: -1),
            ),
            button(
              l10n.photosPanoUp,
              Icons.arrow_upward,
              () => controller.step(up: 1),
            ),
            button(
              l10n.photosPanoDown,
              Icons.arrow_downward,
              () => controller.step(up: -1),
            ),
            button(
              l10n.photosPanoRight,
              Icons.arrow_forward,
              () => controller.step(right: 1),
            ),
            button(
              l10n.photosPanoZoomOut,
              Icons.zoom_out,
              () => controller.zoomStep(zoomIn: false),
            ),
            button(
              l10n.photosPanoZoomIn,
              Icons.zoom_in,
              () => controller.zoomStep(zoomIn: true),
            ),
            button(l10n.photosPanoReset, Icons.restart_alt, controller.reset),
            if (motionAvailable)
              button(
                motionOn ? l10n.photosPanoMotionOff : l10n.photosPanoMotionOn,
                motionOn ? Icons.screen_rotation : Icons.screen_rotation_alt,
                onMotion,
              ),
          ],
        ),
      ),
    );
  }
}
