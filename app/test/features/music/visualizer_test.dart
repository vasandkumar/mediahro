import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediahro/features/music/visualizer/analysis.dart';
import 'package:mediahro/features/music/visualizer/visualizer.dart';

Float32List sine(double hz, {int n = 2048, int rate = 44100, double amp = 1}) =>
    Float32List.fromList([
      for (var i = 0; i < n; i++) amp * math.sin(2 * math.pi * hz * i / rate),
    ]);

void main() {
  group('AUD-046 analysis', () {
    test('AUD-046 FFT finds a pure tone in the right bin', () {
      const n = 1024;
      final re = Float64List(n);
      final im = Float64List(n);
      for (var i = 0; i < n; i++) {
        re[i] = math.sin(2 * math.pi * 64 * i / n);
      }
      fft(re, im);
      var best = 0;
      var bestMag = 0.0;
      for (var k = 1; k < n ~/ 2; k++) {
        final m = re[k] * re[k] + im[k] * im[k];
        if (m > bestMag) {
          bestMag = m;
          best = k;
        }
      }
      expect(best, 64);
      expect(() => fft(Float64List(3), Float64List(3)), throwsArgumentError);
    });

    test('AUD-046 a 1 kHz tone lights the band containing 1 kHz; louder is '
        'taller; silence falls back with caps falling slower', () {
      final a = SpectrumAnalyzer(attack: 1, release: 1);
      final f = a.process(VisualizerInput(samples: sine(1000)));
      var top = 0;
      for (var i = 0; i < f.bands.length; i++) {
        if (f.bands[i] > f.bands[top]) top = i;
      }
      // Log bands from 30 Hz to 16 kHz: 1 kHz sits ~56 % up the scale.
      final expected = (math.log(1000 / 30) / math.log(16000 / 30) * 64)
          .floor();
      expect((top - expected).abs(), lessThanOrEqualTo(1));
      expect(f.bands[top], greaterThan(0.9));
      final quiet = SpectrumAnalyzer(
        attack: 1,
        release: 1,
      ).process(VisualizerInput(samples: sine(1000, amp: 0.01)));
      expect(quiet.bands[top], lessThan(f.bands[top]));
      expect(f.levels.first, greaterThan(0.8));

      final slow = SpectrumAnalyzer(release: 0.2, capFall: 0.01);
      final loud = slow.process(VisualizerInput(samples: sine(1000)));
      final after = slow.decay();
      expect(after.bands[top], lessThan(loud.bands[top]));
      expect(after.caps[top], greaterThan(after.bands[top]));
    });

    test('AUD-046 band-only taps (ADR-027 alternative) pass through with '
        'resampling to the bar count; no waveform', () {
      final a = SpectrumAnalyzer(bandCount: 32, attack: 1);
      final bands = Float32List(64)..[10] = 0.8;
      final f = a.process(
        VisualizerInput(
          bands: bands,
          rms: const [0.5, 0.25],
          peak: const [0.9, 0.5],
        ),
      );
      expect(f.bands.length, 32);
      expect(f.bands[5], closeTo(0.8, 1e-6));
      expect(f.waveform, isEmpty);
      expect(f.levels[0], greaterThan(f.levels[1]));
    });

    test('AUD-046 waveform keeps the extremes when downsampling', () {
      final s = Float32List(1024)..[500] = -0.9;
      final f = SpectrumAnalyzer(waveformPoints: 64)
          .process(VisualizerInput(samples: s));
      expect(f.waveform.length, 64);
      expect(f.waveform.reduce(math.min), closeTo(-0.9, 1e-6));
    });
  });

  group('AUD-046 controller and view', () {
    test('AUD-046 frames are throttled to 60 fps, 15 in low-power mode; '
        'the tap is listened to only while running', () async {
      final feed = _FakeFeed();
      var now = DateTime(2026);
      final c = VisualizerController(feed: feed, clock: () => now);
      var published = 0;
      c.addListener(() => published++);
      expect(feed.listening, isFalse);
      c.start();
      expect(feed.listening, isTrue);
      for (var i = 0; i < 100; i++) {
        now = now.add(const Duration(milliseconds: 5)); // 200 Hz input
        feed.add(VisualizerInput(samples: sine(440)));
      }
      await Future<void>.delayed(Duration.zero);
      expect(published, inInclusiveRange(25, 34)); // ~60 fps over 0.5 s
      c.lowPower = true;
      expect(c.frame.bands.length, 64);
      published = 0;
      for (var i = 0; i < 100; i++) {
        now = now.add(const Duration(milliseconds: 5));
        feed.add(VisualizerInput(samples: sine(440)));
      }
      await Future<void>.delayed(Duration.zero);
      expect(published, inInclusiveRange(6, 9)); // ~15 fps
      expect(c.frame.bands.length, 32);
      c.stop();
      expect(feed.listening, isFalse);
      c.dispose();
    });

    testWidgets('AUD-046 painter draws every style without errors', (
      tester,
    ) async {
      final feed = _FakeFeed();
      final c = VisualizerController(feed: feed)..start();
      feed.add(VisualizerInput(samples: sine(300)));
      await tester.pump();
      for (final style in VisualizerStyle.values) {
        await tester.pumpWidget(
          CustomPaint(
            size: const Size(300, 200),
            painter: VisualizerPainter(
              controller: c,
              style: style,
              primary: Colors.blue,
              secondary: Colors.pink,
              track: Colors.grey,
            ),
          ),
        );
        expect(tester.takeException(), isNull);
      }
      c.dispose();
      await tester.pumpWidget(const SizedBox());
    });
  });
}

final class _FakeFeed implements VisualizerFeed {
  StreamController<VisualizerInput>? _c;

  bool get listening => _c?.hasListener ?? false;

  void add(VisualizerInput i) => _c?.add(i);

  @override
  Stream<VisualizerInput> frames() {
    _c = StreamController<VisualizerInput>(sync: true);
    return _c!.stream;
  }
}
