import 'dart:math' as math;

import 'package:mediahro_engine/src/api/models.dart';

/// Centre frequencies of the 10-band graphic EQ (AUD-005), one octave apart.
const List<double> graphicEqFrequencies = [
  31,
  62,
  125,
  250,
  500,
  1000,
  2000,
  4000,
  8000,
  16000,
];

/// Q of a one-octave peaking band.
const double graphicEqQ = math.sqrt2;

/// Maximum parametric bands (AUD-005).
const int maxParametricBands = 32;

String _n(double v) {
  if (v == v.roundToDouble() && v.abs() < 1e15) return v.toInt().toString();
  return v
      .toStringAsFixed(4)
      .replaceFirst(RegExp(r'0+$'), '')
      .replaceFirst(RegExp(r'\.$'), '');
}

String _band(EqBand b) {
  final f = _n(b.frequencyHz);
  final q = _n(b.q);
  final g = _n(b.gainDb);
  return switch (b.type) {
    EqBandType.peaking => 'equalizer=f=$f:t=q:w=$q:g=$g',
    EqBandType.lowShelf => 'lowshelf=f=$f:t=q:w=$q:g=$g',
    EqBandType.highShelf => 'highshelf=f=$f:t=q:w=$q:g=$g',
    EqBandType.lowPass => 'lowpass=f=$f:t=q:w=$q',
    EqBandType.highPass => 'highpass=f=$f:t=q:w=$q',
    EqBandType.notch => 'bandreject=f=$f:t=q:w=$q',
  };
}

/// libavfilter chain for [chain] (AUD-005), in processing order:
/// pre-amp → graphic EQ → parametric EQ → bass/treble → channel matrix /
/// mono / balance → crossfeed → limiter → skip-silence.
///
/// Loudness (AUD-004) and pitch are applied by mpv itself (`replaygain*`,
/// `pitch`; see [dspProperties]) so they compose with gapless playback.
/// No GPL filter (rubberband) is ever emitted (docs/09 §2).
List<String> dspFilters(
  AudioDspChain chain, {
  String? sourceCodec,
  DsdFilter? dsd,
}) {
  if (chain.parametricEq.length > maxParametricBands) {
    throw ArgumentError.value(
      chain.parametricEq.length,
      'parametricEq',
      'at most $maxParametricBands bands',
    );
  }
  final f = <String>[];
  if (sourceCodec != null && sourceCodec.startsWith('dsd') && dsd != null) {
    f.add('lowpass=f=${dsdCutoffHz(dsd)}:p=2');
  }
  if (chain.preampDb != 0) f.add('volume=${_n(chain.preampDb)}dB');
  for (var i = 0; i < chain.graphicEq.length && i < 10; i++) {
    final g = chain.graphicEq[i];
    if (g == 0) continue;
    f.add(
      _band(
        EqBand(
          type: EqBandType.peaking,
          frequencyHz: graphicEqFrequencies[i],
          gainDb: g,
          q: graphicEqQ,
        ),
      ),
    );
  }
  for (final b in chain.parametricEq) {
    if (b.gainDb == 0 &&
        (b.type == EqBandType.peaking ||
            b.type == EqBandType.lowShelf ||
            b.type == EqBandType.highShelf)) {
      continue;
    }
    f.add(_band(b));
  }
  if (chain.bassDb != 0) f.add('bass=g=${_n(chain.bassDb)}');
  if (chain.trebleDb != 0) f.add('treble=g=${_n(chain.trebleDb)}');
  if (chain.channelMatrix.isNotEmpty) {
    f.add(_pan(chain.channelMatrix));
  } else if (chain.mono) {
    f.add('pan=stereo|c0=0.5*c0+0.5*c1|c1=0.5*c0+0.5*c1');
  }
  if (chain.balance != 0) {
    f.add('stereotools=balance_out=${_n(chain.balance.clamp(-1, 1))}');
  }
  if (chain.crossfeed) f.add('crossfeed=strength=0.3:range=0.5');
  if (chain.limiter) {
    f.add('alimiter=limit=0.966:attack=5:release=50:level=disabled');
  }
  if (chain.skipSilence) {
    f.add(
      'silenceremove=start_periods=1:start_threshold=-50dB:'
      'stop_periods=-1:stop_duration=0.6:stop_threshold=-50dB',
    );
  }
  return f;
}

String _pan(List<List<double>> m) {
  final layout = switch (m.length) {
    1 => 'mono',
    2 => 'stereo',
    6 => '5.1',
    8 => '7.1',
    final n => '${n}c',
  };
  final rows = <String>[];
  for (var o = 0; o < m.length; o++) {
    final terms = <String>[];
    for (var i = 0; i < m[o].length; i++) {
      if (m[o][i] != 0) terms.add('${_n(m[o][i])}*c$i');
    }
    rows.add('c$o=${terms.isEmpty ? '0*c0' : terms.join('+')}');
  }
  return 'pan=$layout|${rows.join('|')}';
}

/// The mpv `af` value: [dspFilters] wrapped in one lavfi graph, followed by
/// `scaletempo2` for pitch-corrected speed (VID-062).
String audioFilterValue(
  AudioDspChain chain, {
  String? sourceCodec,
  DsdFilter? dsd,
}) {
  final f = dspFilters(chain, sourceCodec: sourceCodec, dsd: dsd);
  if (f.isEmpty) return 'scaletempo2';
  return 'lavfi=[${f.join(',')}],scaletempo2';
}

/// Low-pass cutoff after DSD→PCM conversion (AUD-043).
int dsdCutoffHz(DsdFilter f) => switch (f) {
  DsdFilter.standard => 24000,
  DsdFilter.sharp => 20000,
  DsdFilter.slow => 30000,
};

/// ReplayGain 2.0 reference loudness (LUFS).
const double replayGainReferenceLufs = -18;

/// mpv properties that carry the loudness and pitch parts of [chain]
/// (AUD-004, AUD-005). [scannedGainDb] is the background EBU R128 scan result
/// for files without tags; mpv applies it as `replaygain-fallback`.
Map<String, String> dspProperties(
  AudioDspChain chain, {
  double? scannedGainDb,
}) {
  final preamp = chain.r128TargetLufs - replayGainReferenceLufs;
  return {
    'replaygain': switch (chain.loudness) {
      LoudnessMode.off => 'no',
      LoudnessMode.replayGainTrack || LoudnessMode.ebuR128 => 'track',
      LoudnessMode.replayGainAlbum => 'album',
    },
    'replaygain-preamp': _n(chain.loudness == LoudnessMode.off ? 0 : preamp),
    'replaygain-clip': chain.clippingPrevention ? 'no' : 'yes',
    'replaygain-fallback': _n(
      chain.loudness == LoudnessMode.off ? 0 : (scannedGainDb ?? 0) + preamp,
    ),
    'pitch': _n(chain.pitch),
  };
}

/// Gain that brings a track measured at [integratedLufs] to [targetLufs],
/// reduced so the true peak stays below -1 dBTP when clipping prevention is
/// on (AUD-004).
double loudnessGainDb({
  required double integratedLufs,
  required double targetLufs,
  double? truePeakDbtp,
  bool preventClipping = true,
}) {
  var gain = targetLufs - integratedLufs;
  if (preventClipping && truePeakDbtp != null) {
    final headroom = -1 - truePeakDbtp;
    if (gain > headroom) gain = headroom;
  }
  return gain;
}

/// Biquad coefficients (RBJ cookbook) for [band] at [sampleRate]; used by the
/// EQ curve preview and to verify the lavfi graph in tests (AUD-005).
({double b0, double b1, double b2, double a1, double a2}) biquad(
  EqBand band,
  double sampleRate,
) {
  final w0 = 2 * math.pi * band.frequencyHz / sampleRate;
  final cosw = math.cos(w0);
  final alpha = math.sin(w0) / (2 * band.q);
  final a = math.pow(10, band.gainDb / 40).toDouble();
  double b0;
  double b1;
  double b2;
  double a0;
  double a1;
  double a2;
  switch (band.type) {
    case EqBandType.peaking:
      b0 = 1 + alpha * a;
      b1 = -2 * cosw;
      b2 = 1 - alpha * a;
      a0 = 1 + alpha / a;
      a1 = -2 * cosw;
      a2 = 1 - alpha / a;
    case EqBandType.lowShelf:
      final s = 2 * math.sqrt(a) * alpha;
      b0 = a * ((a + 1) - (a - 1) * cosw + s);
      b1 = 2 * a * ((a - 1) - (a + 1) * cosw);
      b2 = a * ((a + 1) - (a - 1) * cosw - s);
      a0 = (a + 1) + (a - 1) * cosw + s;
      a1 = -2 * ((a - 1) + (a + 1) * cosw);
      a2 = (a + 1) + (a - 1) * cosw - s;
    case EqBandType.highShelf:
      final s = 2 * math.sqrt(a) * alpha;
      b0 = a * ((a + 1) + (a - 1) * cosw + s);
      b1 = -2 * a * ((a - 1) + (a + 1) * cosw);
      b2 = a * ((a + 1) + (a - 1) * cosw - s);
      a0 = (a + 1) - (a - 1) * cosw + s;
      a1 = 2 * ((a - 1) - (a + 1) * cosw);
      a2 = (a + 1) - (a - 1) * cosw - s;
    case EqBandType.lowPass:
      b0 = (1 - cosw) / 2;
      b1 = 1 - cosw;
      b2 = (1 - cosw) / 2;
      a0 = 1 + alpha;
      a1 = -2 * cosw;
      a2 = 1 - alpha;
    case EqBandType.highPass:
      b0 = (1 + cosw) / 2;
      b1 = -(1 + cosw);
      b2 = (1 + cosw) / 2;
      a0 = 1 + alpha;
      a1 = -2 * cosw;
      a2 = 1 - alpha;
    case EqBandType.notch:
      b0 = 1;
      b1 = -2 * cosw;
      b2 = 1;
      a0 = 1 + alpha;
      a1 = -2 * cosw;
      a2 = 1 - alpha;
  }
  return (b0: b0 / a0, b1: b1 / a0, b2: b2 / a0, a1: a1 / a0, a2: a2 / a0);
}

/// Magnitude response in dB of [bands] at [frequencyHz] (EQ curve, AUD-005).
double eqResponseDb(List<EqBand> bands, double frequencyHz, double sampleRate) {
  final w = 2 * math.pi * frequencyHz / sampleRate;
  var db = 0.0;
  for (final band in bands) {
    final c = biquad(band, sampleRate);
    // |H(e^jw)|² for a normalised biquad.
    final cos1 = math.cos(w);
    final cos2 = math.cos(2 * w);
    final num =
        c.b0 * c.b0 +
        c.b1 * c.b1 +
        c.b2 * c.b2 +
        2 * (c.b0 * c.b1 + c.b1 * c.b2) * cos1 +
        2 * c.b0 * c.b2 * cos2;
    final den =
        1 +
        c.a1 * c.a1 +
        c.a2 * c.a2 +
        2 * (c.a1 + c.a1 * c.a2) * cos1 +
        2 * c.a2 * cos2;
    db += 10 * math.log(num / den) / math.ln10;
  }
  return db;
}

/// Parses an AutoEq / Equalizer APO `ParametricEQ.txt` or a Wavelet
/// `GraphicEQ` line into bands (AUD-005 AutoEq import).
///
/// APO lines: `Preamp: -6.2 dB`, `Filter 1: ON PK Fc 105 Hz Gain 3.1 dB Q 0.70`
/// (`LSC`/`HSC` shelves, `LP`/`HP`, `NO` notch). Wavelet: `GraphicEQ: 20 -1.2;
/// 21 -1.1; …`, converted to at most 32 peaking bands at the nearest
/// third-octave centres.
({double preampDb, List<EqBand> bands}) parseAutoEq(String text) {
  var preamp = 0.0;
  final bands = <EqBand>[];
  final filter = RegExp(
    r'Filter\s*\d*\s*:\s*ON\s+(PK|PEQ|LSC|LS|HSC|HS|LP|LPQ|HP|HPQ|NO)\s+Fc\s+([\d.]+)\s*Hz'
    r'(?:\s+Gain\s+(-?[\d.]+)\s*dB)?(?:\s+Q\s+([\d.]+))?',
    caseSensitive: false,
  );
  for (final raw in text.split(RegExp(r'\r?\n'))) {
    final line = raw.trim();
    final pre = RegExp(
      r'^Preamp:\s*(-?[\d.]+)\s*dB',
      caseSensitive: false,
    ).firstMatch(line);
    if (pre != null) {
      preamp = double.parse(pre.group(1)!);
      continue;
    }
    if (line.toLowerCase().startsWith('graphiceq:')) {
      bands.addAll(_wavelet(line.substring(10)));
      continue;
    }
    final m = filter.firstMatch(line);
    if (m == null) continue;
    final type = switch (m.group(1)!.toUpperCase()) {
      'PK' || 'PEQ' => EqBandType.peaking,
      'LSC' || 'LS' => EqBandType.lowShelf,
      'HSC' || 'HS' => EqBandType.highShelf,
      'LP' || 'LPQ' => EqBandType.lowPass,
      'HP' || 'HPQ' => EqBandType.highPass,
      _ => EqBandType.notch,
    };
    bands.add(
      EqBand(
        type: type,
        frequencyHz: double.parse(m.group(2)!),
        gainDb: double.tryParse(m.group(3) ?? '') ?? 0,
        q: double.tryParse(m.group(4) ?? '') ?? 0.707,
      ),
    );
  }
  if (bands.length > maxParametricBands) {
    bands.removeRange(maxParametricBands, bands.length);
  }
  return (preampDb: preamp, bands: bands);
}

List<EqBand> _wavelet(String data) {
  final points = <(double, double)>[];
  for (final pair in data.split(';')) {
    final p = pair.trim().split(RegExp(r'\s+'));
    if (p.length != 2) continue;
    final f = double.tryParse(p[0]);
    final g = double.tryParse(p[1]);
    if (f != null && g != null) points.add((f, g));
  }
  if (points.isEmpty) return const [];
  // Third-octave centres 25 Hz … 20 kHz (30 bands).
  final centres = [
    for (var i = -16; i <= 13; i++) 1000 * math.pow(2, i / 3).toDouble(),
  ];
  double gainAt(double f) {
    var best = points.first;
    for (final p in points) {
      if ((math.log(p.$1) - math.log(f)).abs() <
          (math.log(best.$1) - math.log(f)).abs()) {
        best = p;
      }
    }
    return best.$2;
  }

  return [
    for (final c in centres)
      EqBand(
        type: EqBandType.peaking,
        frequencyHz: double.parse(c.toStringAsFixed(1)),
        gainDb: gainAt(c),
        q: 4.32,
      ),
  ];
}
