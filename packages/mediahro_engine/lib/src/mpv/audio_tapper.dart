import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:mediahro_engine/src/api/audio_tap.dart';
import 'package:mediahro_engine/src/api/media_source.dart';
import 'package:mediahro_engine/src/mpv/mpv_client.dart';
import 'package:mediahro_engine/src/mpv/render_mapping.dart';
import 'package:mediahro_engine/src/mpv/stream_protocol.dart';
// The mpv bindings are an engine-private part of mediahro_ffi (lane B1).
// ignore: implementation_imports
import 'package:mediahro_ffi/src/mpv/mpv.dart' show Libmpv;

/// Sample rate of the analysis PCM (bands up to 11 kHz are plenty for a
/// visualiser and keep the tap cheap).
const tapSampleRate = 22050;

/// Channels of the analysis PCM (per-channel RMS/peak).
const tapChannels = 2;

/// Number of log-spaced bands in [AudioTapFrame.bands].
const tapBands = 64;

/// AUD-046 (ADR-027): libmpv has no PCM callback, so the tap runs a second,
/// silent libmpv core over the same source while someone listens. It decodes
/// to raw PCM (`ao=pcm`, float32 stereo at [tapSampleRate]) into a temporary
/// file, kept 1–3 s ahead of the playback position, and cuts each window at
/// the playback position. The core starts with the first listener and is
/// destroyed with the last one, so an unused tap costs nothing. It restarts
/// on seeks, item changes and every minute (bounding the file). Network
/// sources are fetched a second time while the tap runs.
final class AnalysisTap {
  AnalysisTap({
    required this.frames,
    required this.source,
    required this.item,
    required this.position,
    required this.playing,
    this.libmpvPath,
    this.period = const Duration(milliseconds: 33),
  }) {
    _controller = StreamController<AudioTapFrame>.broadcast(
      onListen: _start,
      onCancel: () => unawaited(_stop()),
    );
  }

  final int frames;
  final MediaSource? Function() source;
  final int Function() item;
  final Duration Function() position;
  final bool Function() playing;
  final String? libmpvPath;
  final Duration period;

  late final StreamController<AudioTapFrame> _controller;
  Timer? _timer;
  bool _busy = false;
  MpvClient? _client;
  MpvStreamProtocol? _protocol;
  Directory? _dir;
  File? _pcm;
  RandomAccessFile? _raf;
  Duration _start0 = Duration.zero;
  int _item = -1;
  bool _paused = false;

  Stream<AudioTapFrame> get stream => _controller.stream;

  /// Whether the analysis core is running (tests).
  bool get active => _client != null;

  void _start() {
    _timer ??= Timer.periodic(period, (_) => unawaited(_tick()));
  }

  Future<void> _tick() async {
    if (_busy) return;
    _busy = true;
    try {
      await _step();
    } on Object {
      // Analysis is best effort: a failing core is rebuilt on the next tick.
      await _destroy();
    } finally {
      _busy = false;
    }
  }

  Future<void> _step() async {
    if (!playing()) return;
    final p = position();
    final written = await _writtenFrames();
    final ahead = _start0 + _frameTime(written) - p;
    final stale =
        _client == null ||
        item() != _item ||
        p < _start0 ||
        p - _start0 > const Duration(minutes: 1) ||
        ahead > const Duration(seconds: 10);
    if (stale) {
      await _restart(p);
      return;
    }
    final c = _client!;
    if (ahead < const Duration(seconds: 1) && _paused) {
      _paused = false;
      await c.setProperty('pause', 'no');
    } else if (ahead > const Duration(seconds: 3) && !_paused) {
      _paused = true;
      await c.setProperty('pause', 'yes');
    }
    final end = ((p - _start0).inMicroseconds * tapSampleRate / 1e6).round();
    final begin = end - frames;
    if (begin < 0 || end > written) return;
    final raf = _raf ??= await _pcm!.open();
    await raf.setPosition(begin * tapChannels * 4);
    final bytes = await raf.read(frames * tapChannels * 4);
    if (bytes.length < frames * tapChannels * 4) return;
    final pcm = Float32List.view(
      Uint8List.fromList(bytes).buffer,
      0,
      frames * tapChannels,
    );
    if (!_controller.isClosed && _controller.hasListener) {
      _controller.add(
        analyseWindow(
          pcm,
          channels: tapChannels,
          sampleRate: tapSampleRate,
          position: p,
        ),
      );
    }
  }

  Duration _frameTime(int frames) =>
      Duration(microseconds: frames * 1000000 ~/ tapSampleRate);

  Future<int> _writtenFrames() async {
    final f = _pcm;
    if (f == null || !f.existsSync()) return 0;
    return await f.length() ~/ (tapChannels * 4);
  }

  Future<void> _restart(Duration from) async {
    await _destroy();
    final src = source();
    if (src == null) return;
    final dir = _dir = await Directory.systemTemp.createTemp('mediahro-tap');
    final pcm = _pcm = File('${dir.path}${Platform.pathSeparator}tap.pcm');
    final client = await MpvClient.create(
      options: {
        'config': 'no',
        'terminal': 'no',
        'load-scripts': 'no',
        'ytdl': 'no',
        'idle': 'yes',
        'vid': 'no',
        'sid': 'no',
        'ao': 'pcm',
        'ao-pcm-file': pcm.path,
        'ao-pcm-waveheader': 'no',
        'audio-format': 'float',
        'audio-channels': 'stereo',
        'audio-samplerate': '$tapSampleRate',
        'start': secondsValue(from),
        'hr-seek': 'yes',
      },
      library: Libmpv.open(path: libmpvPath),
    );
    _client = client;
    final protocol = _protocol = MpvStreamProtocol.register(client);
    _start0 = from;
    _item = item();
    _paused = false;
    final url = switch (src) {
      UriSource(:final uri) =>
        uri.scheme == 'file' ? uri.toFilePath() : uri.toString(),
      VirtualFileSource(:final file) => protocol?.urlFor(file),
    };
    if (url == null) {
      await _destroy();
      return;
    }
    await client.loadfile(url);
  }

  Future<void> _destroy() async {
    await _raf?.close();
    _raf = null;
    final client = _client;
    _client = null;
    _protocol?.shutdown();
    if (client != null) await client.destroy();
    await _protocol?.dispose();
    _protocol = null;
    final dir = _dir;
    _dir = null;
    _pcm = null;
    if (dir != null) {
      await dir.delete(recursive: true).catchError((Object _) => dir);
    }
  }

  Future<void> _stop() async {
    _timer?.cancel();
    _timer = null;
    // Let a running tick finish before the core goes.
    while (_busy) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    await _destroy();
  }

  /// Stops the tap and closes its stream (engine dispose).
  Future<void> close() async {
    await _stop();
    await _controller.close();
  }
}

/// One [AudioTapFrame] from an interleaved float32 window (AUD-046): the
/// mono downmix, per-channel RMS and peak, and [tapBands] log-spaced band
/// magnitudes (Hann-windowed FFT, 20 Hz to Nyquist, 1 = full-scale sine).
AudioTapFrame analyseWindow(
  Float32List interleaved, {
  required int channels,
  required int sampleRate,
  required Duration position,
}) {
  final n = interleaved.length ~/ channels;
  final mono = Float32List(n);
  final sumSq = List<double>.filled(channels, 0);
  final peak = List<double>.filled(channels, 0);
  for (var i = 0; i < n; i++) {
    var m = 0.0;
    for (var c = 0; c < channels; c++) {
      final v = interleaved[i * channels + c];
      m += v;
      sumSq[c] += v * v;
      final a = v.abs();
      if (a > peak[c]) peak[c] = a;
    }
    mono[i] = m / channels;
  }
  final rms = [
    for (final s in sumSq)
      if (n == 0) 0.0 else math.sqrt(s / n),
  ];
  return AudioTapFrame(
    position: position,
    sampleRate: sampleRate,
    samples: mono,
    bands: logBands(mono, sampleRate),
    rms: rms,
    peak: [
      for (final p in peak)
        if (p > 1) 1.0 else p,
    ],
  );
}

/// [tapBands] log-spaced magnitudes of [mono] from 20 Hz to Nyquist.
Float32List logBands(Float32List mono, int sampleRate) {
  var size = 1;
  while (size < mono.length) {
    size <<= 1;
  }
  final re = Float64List(size);
  final im = Float64List(size);
  var windowSum = 0.0;
  for (var i = 0; i < mono.length; i++) {
    final w = 0.5 - 0.5 * math.cos(2 * math.pi * i / (mono.length - 1));
    re[i] = mono[i] * w;
    windowSum += w;
  }
  _fft(re, im);
  final half = size ~/ 2;
  // Amplitude spectrum scaled so a full-scale sine reads 1.
  final mag = Float64List(half);
  final scale = windowSum == 0 ? 0.0 : 2 / windowSum;
  for (var k = 0; k < half; k++) {
    mag[k] = math.sqrt(re[k] * re[k] + im[k] * im[k]) * scale;
  }
  final out = Float32List(tapBands);
  final nyquist = sampleRate / 2;
  final binHz = sampleRate / size;
  for (var b = 0; b < tapBands; b++) {
    final lo = 20 * math.pow(nyquist / 20, b / tapBands);
    final hi = 20 * math.pow(nyquist / 20, (b + 1) / tapBands);
    var k0 = (lo / binHz).floor();
    var k1 = (hi / binHz).ceil();
    if (k0 < 1) k0 = 1;
    if (k1 > half) k1 = half;
    var m = 0.0;
    if (k1 <= k0) {
      // Narrower than a bin: take the bin it falls in.
      m = mag[math.min(k0, half - 1)];
    } else {
      for (var k = k0; k < k1; k++) {
        if (mag[k] > m) m = mag[k];
      }
    }
    out[b] = m > 1 ? 1 : m;
  }
  return out;
}

/// In-place iterative radix-2 FFT ([re].length must be a power of two).
void _fft(Float64List re, Float64List im) {
  final n = re.length;
  for (var i = 1, j = 0; i < n; i++) {
    var bit = n >> 1;
    for (; (j & bit) != 0; bit >>= 1) {
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
        final ar = re[i + k];
        final ai = im[i + k];
        final br = re[i + k + len ~/ 2] * cr - im[i + k + len ~/ 2] * ci;
        final bi = re[i + k + len ~/ 2] * ci + im[i + k + len ~/ 2] * cr;
        re[i + k] = ar + br;
        im[i + k] = ai + bi;
        re[i + k + len ~/ 2] = ar - br;
        im[i + k + len ~/ 2] = ai - bi;
        final nr = cr * wr - ci * wi;
        ci = cr * wi + ci * wr;
        cr = nr;
      }
    }
  }
}
