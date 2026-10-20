import 'dart:math' as math;
import 'dart:typed_data';

import 'package:mediahro_subtitles/mediahro_subtitles.dart';
import 'package:test/test.dart';

/// Speech turns over [seconds]: (start, end) in seconds, irregular like
/// dialogue so a wrong offset scores badly.
List<(double, double)> _turns(int seconds, {int seed = 7}) {
  final r = math.Random(seed);
  final out = <(double, double)>[];
  var t = 2.0;
  while (t < seconds - 5) {
    final len = 0.8 + r.nextDouble() * 3.5;
    out.add((t, t + len));
    t += len + 0.4 + r.nextDouble() * 4;
  }
  return out;
}

SubtitleDocument _subs(
  List<(double, double)> turns, {
  double shift = 0,
  double scale = 1,
}) => SubtitleDocument(
  format: SubtitleFormat.srt,
  cues: [
    for (final (a, b) in turns)
      SubtitleCue(
        start: Duration(microseconds: ((a * scale + shift) * 1e6).round()),
        end: Duration(microseconds: ((b * scale + shift) * 1e6).round()),
        text: 'line',
      ),
  ],
);

Uint8List _speech(List<(double, double)> turns, int seconds) {
  final out = Uint8List(seconds * 100);
  for (final (a, b) in turns) {
    for (var i = (a * 100).round(); i < (b * 100).round(); i++) {
      if (i < out.length) out[i] = 1;
    }
  }
  return out;
}

/// Speech as 300 Hz tone bursts over faint noise.
Float32List _pcm(List<(double, double)> turns, int seconds, int rate) {
  final r = math.Random(3);
  final out = Float32List(seconds * rate);
  for (var i = 0; i < out.length; i++) {
    out[i] = (r.nextDouble() - 0.5) * 0.002;
  }
  for (final (a, b) in turns) {
    for (var i = (a * rate).round(); i < (b * rate).round(); i++) {
      if (i < out.length) {
        out[i] += 0.3 * math.sin(2 * math.pi * 300 * i / rate);
      }
    }
  }
  return out;
}

void main() {
  group('SUB-050 auto-sync', () {
    const seconds = 600;
    final turns = _turns(seconds);
    final speech = _speech(turns, seconds);

    test('SUB-050 finds a plain offset (subtitles 2.35 s late)', () {
      final r = alignSubtitles(_subs(turns, shift: 2.35), speech);
      expect(r.factor, 1);
      expect(r.offset.inMilliseconds, closeTo(-2350, 20));
      expect(r.confident, isTrue);
    });

    test('SUB-050 finds early subtitles too', () {
      final r = alignSubtitles(_subs(turns, shift: -7.5), speech);
      expect(r.offset.inMilliseconds, closeTo(7500, 20));
    });

    test('SUB-050 detects a frame-rate mismatch (23.976 timing on 25 fps)', () {
      // Timed for 23.976 fps: every time is 25/23.976 times too small.
      final doc = _subs(turns, scale: 23.976 / 25, shift: 1.2);
      final r = alignSubtitles(doc, speech);
      expect(r.factor, closeTo(25 / 23.976, 1e-9));
      final fixed = r.apply(doc);
      final err =
          (fixed.cues[40].start.inMilliseconds - (turns[40].$1 * 1000).round())
              .abs();
      expect(err, lessThan(60));
    });

    test('SUB-050 the result applied lines the cues up', () {
      final doc = _subs(turns, shift: 3);
      final fixed = alignSubtitles(doc, speech).apply(doc);
      expect(
        fixed.cues.first.start.inMilliseconds,
        closeTo((turns.first.$1 * 1000).round(), 20),
      );
    });

    test('SUB-050 unrelated subtitles are reported as unsure', () {
      final other = _subs(_turns(seconds, seed: 99));
      final r = alignSubtitles(other, speech);
      expect(r.confident, isFalse);
    });

    test('SUB-050 speech detection from PCM', () {
      const rate = 8000;
      final vad = SpeechActivity(sampleRate: rate)
        ..add(_pcm(turns.take(10).toList(), 60, rate));
      final act = vad.activity();
      expect(act.length, 6000);
      final (a, b) = turns.first;
      expect(act[((a + b) / 2 * 100).round()], 1, reason: 'mid-speech');
      expect(act[50], 0, reason: 'silence before the first turn');
    });

    test('SUB-050 end to end in the worker isolate', () async {
      const rate = 8000;
      const secs = 120;
      final t = _turns(secs, seed: 11);
      final pcm = _pcm(t, secs, rate);
      final session = await AutoSyncSession.start(sampleRate: rate);
      for (var i = 0; i < pcm.length; i += rate) {
        session.add(
          Float32List.sublistView(pcm, i, math.min(pcm.length, i + rate)),
        );
      }
      final r = await session.finish(_subs(t, shift: 1.5));
      expect(r.offset.inMilliseconds, closeTo(-1500, 30));
      expect(r.factor, 1);
    });

    test('SUB-050 empty input gives no correction', () {
      final r = alignSubtitles(_subs(turns), Uint8List(0));
      expect(r.offset, Duration.zero);
      expect(r.confident, isFalse);
    });
  });
}
