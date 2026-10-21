import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:mediahro/platform/android/presentation_codec.dart';
import 'package:mediahro/platform/display.dart';

/// Entry point of the engine that draws on an external display (ADR-044
/// amendment 1). `PresentationModule.kt` spawns an engine at this function
/// inside an `android.app.Presentation`; the screen shows only what the app
/// sends through [presentationChannel], never anything else of the app.
@pragma('vm:entry-point')
void presentationMain() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const PresentationPage());
}

/// Frames from the app arrive here (native relays the map unchanged).
const presentationChannel = BasicMessageChannel<Object?>(
  'mediahro/presentation',
  StandardMessageCodec(),
);

/// Sent to native once the page listens, so a frame is not lost before it.
const presentationControl = MethodChannel('mediahro/presentation/control');

/// The external display's page: black, one image with a crossfade, a slow
/// pan-and-zoom (Ken Burns) and a caption. Nothing here reads app state.
class PresentationPage extends StatefulWidget {
  const PresentationPage({super.key});

  @override
  State<PresentationPage> createState() => _PresentationPageState();
}

class _PresentationPageState extends State<PresentationPage>
    with SingleTickerProviderStateMixin {
  PresentationFrame _frame = PresentationFrame.clear;

  /// The picture on top, and the one it is fading in over (a crossfade).
  _Layer? _top;
  _Layer? _below;
  int _generation = 0;
  late final AnimationController _fade = AnimationController(vsync: this);

  @override
  void initState() {
    super.initState();
    presentationChannel.setMessageHandler((message) async {
      if (message is Map<Object?, Object?> && mounted) {
        try {
          _show(PresentationFrameCodec.fromMap(message));
        } on FormatException {
          // A frame outside the limits is dropped; the screen keeps what it shows.
        }
      }
      return null;
    });
    unawaited(
      presentationControl.invokeMethod<void>('ready').catchError((_) {}),
    );
  }

  void _show(PresentationFrame frame) {
    final layer = frame.image == null
        ? null
        : _Layer(_generation++, frame.image!, frame.fit, frame.motion);
    final fading =
        frame.transition == PresentationTransition.crossfade &&
        frame.transitionDuration > Duration.zero &&
        _top != null &&
        layer != null;
    setState(() {
      _frame = frame;
      _below = fading ? _top : null;
      _top = layer;
    });
    if (fading) {
      _fade.duration = frame.transitionDuration;
      unawaited(
        _fade.forward(from: 0).whenComplete(() {
          if (mounted) setState(() => _below = null);
        }),
      );
    } else {
      _fade.value = 1;
    }
  }

  @override
  void dispose() {
    presentationChannel.setMessageHandler(null);
    _fade.dispose();
    super.dispose();
  }

  /// Pictures are decoded no larger than twice the display (room to zoom), and
  /// never beyond [PresentationLimits.maxImageEdge], whatever their own size.
  int _decodeEdge(BuildContext context) {
    final size = View.of(context).physicalSize;
    final longest = size.longestSide <= 0 ? 1920.0 : size.longestSide;
    return (longest * 2).round().clamp(256, PresentationLimits.maxImageEdge);
  }

  @override
  Widget build(BuildContext context) => Directionality(
    textDirection: TextDirection.ltr,
    child: ColoredBox(
      color: const Color(0xFF000000),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (_below != null) _below!.build(_decodeEdge(context)),
          if (_top != null)
            FadeTransition(
              opacity: _fade,
              child: _top!.build(_decodeEdge(context)),
            ),
          if (_frame.caption != null && _frame.caption!.isNotEmpty)
            Align(
              alignment: Alignment.bottomCenter,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(48, 24, 48, 32),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0x00000000), Color(0xB3000000)],
                  ),
                ),
                child: Text(
                  _frame.caption!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Color(0xFFFFFFFF),
                    fontSize: 28,
                    decoration: TextDecoration.none,
                  ),
                ),
              ),
            ),
        ],
      ),
    ),
  );
}

/// One picture on the screen, with its own pan and zoom.
class _Layer {
  _Layer(this.generation, this.image, this.fit, this.motion);

  final int generation;
  final Uint8List image;
  final BoxFit fit;
  final PresentationMotion? motion;

  Widget build(int edge) => KenBurns(
    key: ValueKey(generation),
    motion: motion,
    child: Image(
      image: ResizeImage(
        MemoryImage(image),
        width: edge,
        height: edge,
        policy: ResizeImagePolicy.fit,
      ),
      fit: fit,
      gaplessPlayback: true,
      // A picture that cannot be decoded leaves the screen black, not an error.
      errorBuilder: (context, error, stack) => const SizedBox.expand(),
    ),
  );
}

/// Draws [child] (the image filling the screen) panned and zoomed so the
/// visible part moves from `motion.from` to `motion.to`, normalised image
/// coordinates, over `motion.duration`. Without motion it just fills.
class KenBurns extends StatefulWidget {
  const KenBurns({required this.child, this.motion, super.key});

  final Widget child;
  final PresentationMotion? motion;

  /// The matrix that shows [region] (0..1 of a [size] image) over the whole
  /// box: scale about the box so the region fills it, and centre on it.
  static Matrix4 transformFor(Rect region, Size size) {
    final scale = 1 / region.width.clamp(0.05, 1.0);
    return Matrix4.identity()
      ..translateByDouble(size.width / 2, size.height / 2, 0, 1)
      ..scaleByDouble(scale, scale, 1, 1)
      ..translateByDouble(
        -region.center.dx * size.width,
        -region.center.dy * size.height,
        0,
        1,
      );
  }

  @override
  State<KenBurns> createState() => _KenBurnsState();
}

class _KenBurnsState extends State<KenBurns>
    with SingleTickerProviderStateMixin {
  AnimationController? _controller;

  @override
  void initState() {
    super.initState();
    final m = widget.motion;
    if (m != null && m.duration > Duration.zero) {
      _controller = AnimationController(vsync: this, duration: m.duration)
        ..forward();
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.motion;
    final controller = _controller;
    if (m == null) return SizedBox.expand(child: widget.child);
    return ClipRect(
      child: LayoutBuilder(
        builder: (context, box) {
          final size = box.biggest;
          Widget framed(double t) => Transform(
            transform: KenBurns.transformFor(Rect.lerp(m.from, m.to, t)!, size),
            child: SizedBox.expand(child: widget.child),
          );
          if (controller == null) return framed(1);
          return AnimatedBuilder(
            animation: controller,
            builder: (context, _) =>
                framed(Curves.easeInOut.transform(controller.value)),
          );
        },
      ),
    );
  }
}
