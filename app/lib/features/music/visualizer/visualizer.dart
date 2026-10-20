import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:mediahro/features/music/visualizer/analysis.dart';

/// Source of tap frames: the music engine's `audioTap` (ADR-027, lane B1).
abstract interface class VisualizerFeed {
  Stream<VisualizerInput> frames();
}

enum VisualizerStyle { spectrum, waveform, vu }

/// Drives the visualiser (AUD-046): listens to the tap only while a view is
/// shown (the engine taps nothing without a listener), analyses each frame,
/// and publishes at most [fps] frames a second; 15 in low-power mode, with
/// half the bars.
final class VisualizerController extends ChangeNotifier {
  VisualizerController({
    required this.feed,
    bool lowPower = false,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now {
    _lowPower = lowPower;
    _analyzer = _make();
  }

  final VisualizerFeed feed;
  final DateTime Function() _clock;
  late SpectrumAnalyzer _analyzer;
  StreamSubscription<VisualizerInput>? _sub;
  Timer? _idle;
  DateTime _last = DateTime.fromMillisecondsSinceEpoch(0);
  late bool _lowPower;
  VisualizerFrame _frame = VisualizerFrame.silent;

  VisualizerFrame get frame => _frame;
  bool get lowPower => _lowPower;
  int get fps => _lowPower ? 15 : 60;
  bool get running => _sub != null;

  set lowPower(bool v) {
    if (v == _lowPower) return;
    _lowPower = v;
    _analyzer = _make();
    notifyListeners();
  }

  SpectrumAnalyzer _make() => SpectrumAnalyzer(
    bandCount: _lowPower ? 32 : 64,
    waveformPoints: _lowPower ? 128 : 256,
  );

  void start() {
    _sub ??= feed.frames().listen(_onInput);
  }

  void stop() {
    unawaited(_sub?.cancel());
    _sub = null;
    _idle?.cancel();
    _idle = null;
  }

  void _onInput(VisualizerInput input) {
    final now = _clock();
    final f = _analyzer.process(input);
    if (now.difference(_last) < Duration(microseconds: 1000000 ~/ fps)) {
      return;
    }
    _last = now;
    _publish(f);
    // No frames (paused): let the bars fall to rest.
    _idle?.cancel();
    _idle = Timer.periodic(Duration(milliseconds: 1000 ~/ fps), (t) {
      final d = _analyzer.decay();
      _publish(d);
      if (d.bands.every((b) => b < 0.01) && d.caps.every((c) => c < 0.01)) {
        t.cancel();
      }
    });
  }

  void _publish(VisualizerFrame f) {
    _frame = f;
    notifyListeners();
  }

  @override
  void dispose() {
    stop();
    super.dispose();
  }
}

/// Paints a [VisualizerFrame] in one of the [VisualizerStyle]s, coloured
/// from the cover (album-art-reactive).
final class VisualizerPainter extends CustomPainter {
  VisualizerPainter({
    required this.controller,
    required this.style,
    required this.primary,
    required this.secondary,
    required this.track,
  }) : super(repaint: controller);

  final VisualizerController controller;
  final VisualizerStyle style;
  final Color primary;
  final Color secondary;

  /// Background tone for meters and baselines.
  final Color track;

  @override
  void paint(Canvas canvas, Size size) {
    final f = controller.frame;
    switch (style) {
      case VisualizerStyle.spectrum:
        _spectrum(canvas, size, f);
      case VisualizerStyle.waveform:
        _waveform(canvas, size, f);
      case VisualizerStyle.vu:
        _vu(canvas, size, f);
    }
  }

  void _spectrum(Canvas canvas, Size size, VisualizerFrame f) {
    final n = f.bands.length;
    if (n == 0) return;
    final gap = size.width / n * 0.2;
    final w = size.width / n - gap;
    final rect = Offset.zero & size;
    final paint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.bottomCenter,
        end: Alignment.topCenter,
        colors: [primary, secondary],
      ).createShader(rect);
    final cap = Paint()..color = secondary;
    for (var i = 0; i < n; i++) {
      final x = i * (w + gap) + gap / 2;
      final h = math.max(2, f.bands[i] * size.height).toDouble();
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, size.height - h, w, h),
          Radius.circular(w / 3),
        ),
        paint,
      );
      if (f.caps.length > i) {
        final y = size.height - f.caps[i] * size.height;
        canvas.drawRect(Rect.fromLTWH(x, y - 3, w, 2), cap);
      }
    }
  }

  void _waveform(Canvas canvas, Size size, VisualizerFrame f) {
    final mid = size.height / 2;
    final base = Paint()
      ..color = track
      ..strokeWidth = 1;
    canvas.drawLine(Offset(0, mid), Offset(size.width, mid), base);
    final w = f.waveform;
    final path = Path();
    if (w.isEmpty) {
      // Band-only taps: draw the spectrum as a mirrored envelope.
      final n = f.bands.length;
      if (n == 0) return;
      for (var i = 0; i < n; i++) {
        final x = i / (n - 1) * size.width;
        final y = mid - f.bands[i] * mid;
        i == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
      }
      for (var i = n - 1; i >= 0; i--) {
        final x = i / (n - 1) * size.width;
        path.lineTo(x, mid + f.bands[i] * mid);
      }
      path.close();
      canvas.drawPath(path, Paint()..color = primary.withValues(alpha: 0.8));
      return;
    }
    for (var i = 0; i < w.length; i++) {
      final x = i / math.max(1, w.length - 1) * size.width;
      final y = mid - w[i] * mid;
      i == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = primary
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeJoin = StrokeJoin.round,
    );
  }

  void _vu(Canvas canvas, Size size, VisualizerFrame f) {
    final barH = size.height / 5;
    for (var c = 0; c < 2; c++) {
      final y = size.height / 2 + (c == 0 ? -barH * 1.2 : barH * 0.2);
      final r = Rect.fromLTWH(0, y, size.width, barH);
      canvas.drawRRect(
        RRect.fromRectAndRadius(r, const Radius.circular(6)),
        Paint()..color = track,
      );
      final level = f.levels.length > c ? f.levels[c] : 0.0;
      final hot = Rect.fromLTWH(0, y, size.width * level, barH);
      canvas.drawRRect(
        RRect.fromRectAndRadius(hot, const Radius.circular(6)),
        Paint()
          ..shader = LinearGradient(colors: [primary, secondary])
              .createShader(r),
      );
      final peak = f.peaks.length > c ? f.peaks[c] : 0.0;
      canvas.drawRect(
        Rect.fromLTWH(size.width * peak - 2, y, 3, barH),
        Paint()..color = secondary,
      );
    }
  }

  @override
  bool shouldRepaint(VisualizerPainter old) =>
      old.style != style ||
      old.primary != primary ||
      old.secondary != secondary ||
      old.track != track;
}
