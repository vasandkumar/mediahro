import 'dart:math' as math;
import 'dart:typed_data';

import 'package:meta/meta.dart';

/// One frame from the engine's audio tap (ADR-027): either a window of
/// mono PCM ([samples]) or pre-computed log-band magnitudes ([bands],
/// 0…1) with per-channel RMS/peak. B1 picks per platform which one it
/// delivers; the visualiser handles both.
@immutable
final class VisualizerInput {
  const VisualizerInput({
    this.samples,
    this.sampleRate = 44100,
    this.bands,
    this.rms = const [],
    this.peak = const [],
    this.position = Duration.zero,
  });

  /// Mono float PCM, −1…1.
  final Float32List? samples;
  final int sampleRate;

  /// Log-spaced band magnitudes, 0…1.
  final Float32List? bands;

  /// Per-channel RMS and peak, 0…1 (linear).
  final List<double> rms;
  final List<double> peak;
  final Duration position;
}

/// What the painters draw (AUD-046): smoothed bands with peak caps, a
/// waveform and VU levels.
@immutable
final class VisualizerFrame {
  const VisualizerFrame({
    required this.bands,
    required this.caps,
    required this.waveform,
    required this.levels,
    required this.peaks,
  });

  static final silent = VisualizerFrame(
    bands: Float32List(0),
    caps: Float32List(0),
    waveform: Float32List(0),
    levels: const [0, 0],
    peaks: const [0, 0],
  );

  /// 0…1 per band, smoothed.
  final Float32List bands;

  /// Falling peak caps per band, 0…1.
  final Float32List caps;

  /// −1…1, downsampled for drawing (empty when the tap gives bands only).
  final Float32List waveform;

  /// VU level per channel, 0…1 on a dB scale.
  final List<double> levels;
  final List<double> peaks;
}

/// In-place radix-2 FFT of [re]/[im] (length a power of two).
void fft(Float64List re, Float64List im) {
  final n = re.length;
  if (n & (n - 1) != 0) throw ArgumentError('length must be a power of two');
  for (var i = 1, j = 0; i < n; i++) {
    var bit = n >> 1;
    for (; j & bit != 0; bit >>= 1) {
      j ^= bit;
    }
    j ^= bit;
    if (i < j) {
      final tr = re[i];
      re[i] = re[j];
      re[j] = tr;
      final ti = im[i];
      im[i] = im[j];
      im[j] = ti;
    }
  }
  for (var len = 2; len <= n; len <<= 1) {
    final ang = -2 * math.pi / len;
    final wr = math.cos(ang);
    final wi = math.sin(ang);
    for (var i = 0; i < n; i += len) {
      var cr = 1.0;
      var ci = 0.0;
      for (var k = 0; k < len ~/ 2; k++) {
        final a = i + k;
        final b = a + len ~/ 2;
        final xr = re[b] * cr - im[b] * ci;
        final xi = re[b] * ci + im[b] * cr;
        re[b] = re[a] - xr;
        im[b] = im[a] - xi;
        re[a] += xr;
        im[a] += xi;
        final ncr = cr * wr - ci * wi;
        ci = cr * wi + ci * wr;
        cr = ncr;
      }
    }
  }
}

/// Turns tap frames into [VisualizerFrame]s: Hann-windowed FFT, log bands
/// from [minHz] to [maxHz] on a −[floorDb]…0 dB scale, fast attack / slow
/// release smoothing and falling peak caps.
final class SpectrumAnalyzer {
  SpectrumAnalyzer({
    this.bandCount = 64,
    this.minHz = 30,
    this.maxHz = 16000,
    this.floorDb = 70,
    this.attack = 0.6,
    this.release = 0.15,
    this.capFall = 0.012,
    this.waveformPoints = 256,
  }) : _bands = Float32List(bandCount),
       _caps = Float32List(bandCount);

  final int bandCount;
  final double minHz;
  final double maxHz;
  final double floorDb;

  /// Smoothing towards a louder value (0…1 per frame) and a quieter one.
  final double attack;
  final double release;

  /// How far peak caps fall per frame.
  final double capFall;
  final int waveformPoints;

  final Float32List _bands;
  final Float32List _caps;
  final List<double> _levels = [0, 0];
  final List<double> _peaks = [0, 0];

  VisualizerFrame process(VisualizerInput input) {
    final raw = input.bands ?? _spectrum(input);
    for (var i = 0; i < bandCount; i++) {
      final target = raw.isEmpty ? 0.0 : raw[_map(i, raw.length)];
      final k = target > _bands[i] ? attack : release;
      _bands[i] += (target - _bands[i]) * k;
      _caps[i] = math.max(_bands[i], _caps[i] - capFall);
    }
    _vu(input);
    return VisualizerFrame(
      bands: Float32List.fromList(_bands),
      caps: Float32List.fromList(_caps),
      waveform: _waveform(input.samples),
      levels: List.of(_levels),
      peaks: List.of(_peaks),
    );
  }

  /// Lets bars and caps fall to rest while paused.
  VisualizerFrame decay() =>
      process(VisualizerInput(bands: Float32List(bandCount)));

  int _map(int i, int n) => n == bandCount ? i : (i * n ~/ bandCount);

  Float32List _spectrum(VisualizerInput input) {
    final s = input.samples;
    final out = Float32List(bandCount);
    if (s == null || s.length < 16) return out;
    var n = 1;
    while (n * 2 <= s.length && n < 4096) {
      n *= 2;
    }
    final re = Float64List(n);
    final im = Float64List(n);
    for (var i = 0; i < n; i++) {
      final w = 0.5 - 0.5 * math.cos(2 * math.pi * i / (n - 1)); // Hann
      re[i] = s[i] * w;
    }
    fft(re, im);
    final binHz = input.sampleRate / n;
    final nyquist = input.sampleRate / 2;
    final hi = math.min(maxHz, nyquist);
    final ratio = math.pow(hi / minHz, 1 / bandCount).toDouble();
    var lo = minHz;
    for (var b = 0; b < bandCount; b++) {
      final top = lo * ratio;
      var from = (lo / binHz).floor();
      var to = (top / binHz).ceil();
      from = from.clamp(1, n ~/ 2 - 1);
      to = to.clamp(from + 1, n ~/ 2);
      var power = 0.0;
      for (var k = from; k < to; k++) {
        power = math.max(power, re[k] * re[k] + im[k] * im[k]);
      }
      // Amplitude normalised to a full-scale sine with a Hann window.
      final amp = math.sqrt(power) / (n / 4);
      final db = amp > 0 ? 20 * math.log(amp) / math.ln10 : -floorDb;
      out[b] = ((db + floorDb) / floorDb).clamp(0.0, 1.0);
      lo = top;
    }
    return out;
  }

  void _vu(VisualizerInput input) {
    var rms = input.rms;
    var peak = input.peak;
    final s = input.samples;
    if (rms.isEmpty && s != null && s.isNotEmpty) {
      var sum = 0.0;
      var p = 0.0;
      for (final v in s) {
        sum += v * v;
        p = math.max(p, v.abs());
      }
      final r = math.sqrt(sum / s.length);
      rms = [r, r];
      peak = [p, p];
    }
    for (var c = 0; c < 2; c++) {
      final r = rms.isEmpty ? 0.0 : rms[math.min(c, rms.length - 1)];
      final p = peak.isEmpty ? r : peak[math.min(c, peak.length - 1)];
      final target = _dbScale(r);
      final k = target > _levels[c] ? attack : release;
      _levels[c] += (target - _levels[c]) * k;
      _peaks[c] = math.max(_dbScale(p), _peaks[c] - capFall);
    }
  }

  double _dbScale(double linear) {
    if (linear <= 0) return 0;
    final db = 20 * math.log(linear) / math.ln10;
    return ((db + floorDb) / floorDb).clamp(0.0, 1.0);
  }

  Float32List _waveform(Float32List? s) {
    if (s == null || s.isEmpty) return Float32List(0);
    final n = math.min(waveformPoints, s.length);
    final out = Float32List(n);
    final step = s.length / n;
    for (var i = 0; i < n; i++) {
      // Keep the extreme of each slice so transients stay visible.
      final a = (i * step).floor();
      final b = math.min(s.length, ((i + 1) * step).ceil());
      var v = 0.0;
      for (var k = a; k < b; k++) {
        if (s[k].abs() > v.abs()) v = s[k];
      }
      out[i] = v;
    }
    return out;
  }
}
