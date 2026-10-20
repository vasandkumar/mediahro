import 'dart:async';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:mediahro_subtitles/src/editing.dart';
import 'package:mediahro_subtitles/src/subtitle_parser.dart';
import 'package:meta/meta.dart';

// Audio-based subtitle sync (SUB-050), the ffsubsync approach: speech
// activity from the audio (energy VAD at 10 ms frames) is cross-correlated
// with subtitle activity, for the plain offset and for the common
// frame-rate mismatches, using an FFT. Everything heavy runs in an isolate.

/// Analysis frame: 10 ms.
const Duration syncFrame = Duration(milliseconds: 10);

/// Frame-rate ratios tried besides 1 (subtitles timed for another rate).
const List<double> syncRatios = [
  1,
  25 / 23.976,
  23.976 / 25,
  25 / 24,
  24 / 25,
  24 / 23.976,
  23.976 / 24,
  25 / 29.97,
  29.97 / 25,
];

/// The correction that lines subtitles up with the speech: a subtitle at
/// time t should show at t × [factor] + [offset].
@immutable
final class SyncResult {
  const SyncResult({
    required this.offset,
    required this.factor,
    required this.score,
    required this.confidence,
  });

  final Duration offset;
  final double factor;

  /// Agreement between speech and subtitles after the correction, −1…1.
  final double score;

  /// How clearly the best answer beats the next-best offset, 0…1. Below
  /// about 0.15 the result is a guess and the UI says so.
  final double confidence;

  bool get confident => confidence >= 0.15;

  SubtitleDocument apply(SubtitleDocument doc) =>
      (factor == 1 ? doc : doc.stretch(factor)).shift(offset);

  @override
  String toString() =>
      'SyncResult($offset, ×${factor.toStringAsFixed(5)}, score '
      '${score.toStringAsFixed(3)}, confidence ${confidence.toStringAsFixed(2)})';
}

/// Speech activity per 10 ms frame from mono PCM (energy VAD with an
/// adaptive noise floor and a hangover that bridges short pauses).
final class SpeechActivity {
  SpeechActivity({required this.sampleRate})
    : _frame = (sampleRate * syncFrame.inMicroseconds / 1e6).round();

  final int sampleRate;
  final int _frame;
  final List<double> _db = [];
  double _sum = 0;
  int _n = 0;

  /// Adds the next samples (in order).
  void add(Float32List samples) {
    for (final s in samples) {
      _sum += s * s;
      if (++_n == _frame) {
        final rms = math.sqrt(_sum / _n);
        _db.add(rms <= 1e-9 ? -120 : 20 * math.log(rms) / math.ln10);
        _sum = 0;
        _n = 0;
      }
    }
  }

  int get frames => _db.length;

  /// 1 for speech, 0 for silence, per frame.
  Uint8List activity() {
    if (_db.isEmpty) return Uint8List(0);
    final sorted = [..._db]..sort();
    final floor = sorted[(sorted.length * 0.2).floor()];
    final threshold = math.max(floor + 9, -55);
    final raw = Uint8List(_db.length);
    for (var i = 0; i < _db.length; i++) {
      raw[i] = _db[i] > threshold ? 1 : 0;
    }
    // Hangover: speech pauses under 200 ms stay speech.
    const bridge = 20;
    var lastOn = -1000;
    for (var i = 0; i < raw.length; i++) {
      if (raw[i] == 1) {
        if (i - lastOn > 1 && i - lastOn <= bridge) {
          raw.fillRange(lastOn + 1, i, 1);
        }
        lastOn = i;
      }
    }
    return raw;
  }
}

/// Subtitle activity per 10 ms frame (times scaled by [factor]).
Uint8List subtitleActivity(
  SubtitleDocument doc, {
  required int frames,
  double factor = 1,
}) {
  final out = Uint8List(frames);
  final ms = syncFrame.inMicroseconds;
  for (final c in doc.cues) {
    if (c.plainText.trim().isEmpty) continue;
    final a = (c.start.inMicroseconds * factor / ms).floor();
    final b = (c.end.inMicroseconds * factor / ms).ceil();
    for (var i = math.max(0, a); i < math.min(frames, b); i++) {
      out[i] = 1;
    }
  }
  return out;
}

/// Finds the offset and frame-rate factor that best line [doc] up with
/// [speech] (from [SpeechActivity.activity]), trying offsets up to
/// [maxOffset] either way.
SyncResult alignSubtitles(
  SubtitleDocument doc,
  Uint8List speech, {
  Duration maxOffset = const Duration(seconds: 60),
  List<double> ratios = syncRatios,
}) {
  if (speech.isEmpty || doc.cues.isEmpty) {
    return const SyncResult(
      offset: Duration.zero,
      factor: 1,
      score: 0,
      confidence: 0,
    );
  }
  final maxLag = maxOffset.inMicroseconds ~/ syncFrame.inMicroseconds;
  final n = speech.length;
  final size = _nextPow2(n + maxLag * 2 + 1);
  final a = _bipolar(speech, size, 0);
  _fft(a, inverse: false);
  _CorrBest? best;
  _CorrBest? runnerUp;
  for (final r in ratios) {
    final subs = subtitleActivity(doc, frames: n, factor: r);
    final b = _bipolar(subs, size, 0);
    _fft(b, inverse: false);
    // Cross-correlation: IFFT(A · conj(B)).
    final c = Float64List(size * 2);
    for (var i = 0; i < size; i++) {
      final ar = a[2 * i];
      final ai = a[2 * i + 1];
      final br = b[2 * i];
      final bi = b[2 * i + 1];
      c[2 * i] = ar * br + ai * bi;
      c[2 * i + 1] = ai * br - ar * bi;
    }
    _fft(c, inverse: true);
    // Lag k > 0: subtitles should move later by k frames.
    for (var k = -maxLag; k <= maxLag; k++) {
      final idx = k >= 0 ? k : size + k;
      final v = c[2 * idx] / size / n;
      final cand = _CorrBest(v, k, r);
      if (best == null || v > best.value) {
        if (best != null && (best.lag - k).abs() > 50) runnerUp = best;
        best = cand;
      } else if ((best.lag - k).abs() > 50 &&
          (runnerUp == null || v > runnerUp.value)) {
        runnerUp = cand;
      }
    }
  }
  final b = best!;
  final second = runnerUp?.value ?? -1;
  final confidence = ((b.value - second) / (1 - second)).clamp(0.0, 1.0);
  return SyncResult(
    offset: syncFrame * b.lag,
    factor: b.ratio,
    score: b.value,
    confidence: confidence,
  );
}

final class _CorrBest {
  const _CorrBest(this.value, this.lag, this.ratio);

  final double value;
  final int lag;
  final double ratio;
}

int _nextPow2(int v) {
  var p = 1;
  while (p < v) {
    p <<= 1;
  }
  return p;
}

/// Activity as ±1 (silence counts as much as speech), zero-padded, as
/// interleaved complex numbers.
Float64List _bipolar(Uint8List act, int size, int shift) {
  final out = Float64List(size * 2);
  for (var i = 0; i < act.length; i++) {
    out[2 * (i + shift)] = act[i] == 1 ? 1 : -1;
  }
  return out;
}

/// In-place iterative radix-2 FFT over interleaved complex [x] (length
/// 2 × a power of two).
void _fft(Float64List x, {required bool inverse}) {
  final n = x.length ~/ 2;
  for (var i = 1, j = 0; i < n; i++) {
    var bit = n >> 1;
    for (; j & bit != 0; bit >>= 1) {
      j ^= bit;
    }
    j ^= bit;
    if (i < j) {
      final tr = x[2 * i];
      final ti = x[2 * i + 1];
      x[2 * i] = x[2 * j];
      x[2 * i + 1] = x[2 * j + 1];
      x[2 * j] = tr;
      x[2 * j + 1] = ti;
    }
  }
  for (var len = 2; len <= n; len <<= 1) {
    final ang = 2 * math.pi / len * (inverse ? 1 : -1);
    final wr = math.cos(ang);
    final wi = math.sin(ang);
    for (var i = 0; i < n; i += len) {
      var cr = 1.0;
      var ci = 0.0;
      final half = len >> 1;
      for (var k = 0; k < half; k++) {
        final a = 2 * (i + k);
        final b = 2 * (i + k + half);
        final vr = x[b] * cr - x[b + 1] * ci;
        final vi = x[b] * ci + x[b + 1] * cr;
        x[b] = x[a] - vr;
        x[b + 1] = x[a + 1] - vi;
        x[a] += vr;
        x[a + 1] += vi;
        final nr = cr * wr - ci * wi;
        ci = cr * wi + ci * wr;
        cr = nr;
      }
    }
  }
}

/// Runs speech detection and alignment in a worker isolate (SUB-050): feed
/// PCM with [add] as it is decoded, then [finish]. [cancel] stops the
/// worker.
final class AutoSyncSession {
  AutoSyncSession._(this._isolate, this._send, this._replies);

  static Future<AutoSyncSession> start({required int sampleRate}) async {
    final replies = ReceivePort();
    final isolate = await Isolate.spawn(_worker, (
      replies.sendPort,
      sampleRate,
    ), onExit: replies.sendPort);
    final stream = replies.asBroadcastStream();
    final send = await stream.first as SendPort;
    return AutoSyncSession._(isolate, send, stream);
  }

  final Isolate _isolate;
  final SendPort _send;
  final Stream<Object?> _replies;
  bool _done = false;

  void add(Float32List samples) {
    if (_done) return;
    _send.send(TransferableTypedData.fromList([samples]));
  }

  /// Aligns [doc] with everything added so far, then ends the worker.
  Future<SyncResult> finish(
    SubtitleDocument doc, {
    Duration maxOffset = const Duration(seconds: 60),
  }) async {
    _done = true;
    final reply = _replies.firstWhere((m) => m is SyncResult || m == null);
    _send.send((doc, maxOffset));
    try {
      final r = await reply;
      if (r is! SyncResult) throw StateError('auto-sync stopped');
      return r;
    } finally {
      _isolate.kill(priority: Isolate.immediate);
    }
  }

  void cancel() {
    _done = true;
    _isolate.kill(priority: Isolate.immediate);
  }
}

void _worker((SendPort, int) args) {
  final (reply, rate) = args;
  final port = ReceivePort();
  reply.send(port.sendPort);
  final vad = SpeechActivity(sampleRate: rate);
  port.listen((message) {
    if (message is TransferableTypedData) {
      vad.add(message.materialize().asFloat32List());
    } else if (message is (SubtitleDocument, Duration)) {
      reply.send(
        alignSubtitles(message.$1, vad.activity(), maxOffset: message.$2),
      );
      port.close();
    }
  });
}
