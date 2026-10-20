import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:mediahro_engine/src/api/audio_tap.dart';
import 'package:mediahro_engine/src/api/media_source.dart';
import 'package:mediahro_engine/src/mpv/mpv_client.dart';
import 'package:mediahro_engine/src/mpv/render_mapping.dart';
import 'package:mediahro_engine/src/mpv/tap_storage.dart';
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

/// AUD-046 (ADR-027): libmpv has no PCM callback, so the tap decodes the
/// audio being played a second time, on a silent libmpv core that exists
/// only while someone listens (an unused tap costs nothing). The core writes
/// raw PCM (`ao=pcm`, s16 stereo at [tapSampleRate], about 86 KB/s) to
/// [TapStorage], RAM-backed where the OS offers it, and each window is cut
/// from it at the playback position.
///
/// The core decodes 3 s slices just ahead of playback, one after the other,
/// appending their PCM, so it writes at the pace of playback:
/// - Local files ([isLocal]): each slice is the file itself between `start`
///   and `end`.
/// - Everything else (HTTP, radio, servers, network shares): the source is
///   never fetched twice. Each slice is the main core's demuxer cache for
///   that range (`dump-cache`, [dumpCache]).
///
/// The PCM is restarted on seeks, item changes and every minute, which bounds
/// it to about 5 MB.
final class AnalysisTap {
  AnalysisTap({
    required this.frames,
    required this.source,
    required this.item,
    required this.position,
    required this.playing,
    required this.isLocal,
    required this.dumpCache,
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

  /// Whether the current item is a local file the tap may read directly.
  final bool Function() isLocal;

  /// Writes the main core's cached range a…b to a file (mpv `dump-cache`);
  /// false when nothing could be written.
  final Future<bool> Function(Duration a, Duration b, String path) dumpCache;
  final String? libmpvPath;
  final Duration period;

  late final StreamController<AudioTapFrame> _controller;
  Timer? _timer;
  bool _busy = false;
  MpvClient? _client;
  StreamSubscription<MpvEvent>? _events;
  Completer<void>? _ended;
  TapStorage? _storage;
  RandomAccessFile? _raf;
  // Playback time of the first sample in the PCM file.
  Duration _start0 = Duration.zero;
  int _item = -1;
  bool _local = true;

  Stream<AudioTapFrame> get stream => _controller.stream;

  /// Whether the analysis core is running (tests).
  bool get active => _client != null;

  // PCM bytes of earlier files (rotations), for the write-rate measurement.
  int _rotatedBytes = 0;

  /// PCM bytes written since the tap started (tests measure the rate).
  int get bytesWritten => _rotatedBytes + (_storage?.pcmLength ?? 0);

  void _start() {
    _timer ??= Timer.periodic(period, (_) => unawaited(_tick()));
  }

  Future<void> _tick() async {
    if (_busy) return;
    _busy = true;
    try {
      if (!playing()) return;
      final p = position();
      await _stepSlices(p, local: isLocal());
      await _emit(p);
    } on Object {
      // Analysis is best effort: a failing core is rebuilt on the next tick.
      await _destroy().catchError((Object _) {});
    } finally {
      _busy = false;
    }
  }

  Future<void> _stepSlices(Duration p, {required bool local}) async {
    final covered = _start0 + _frameTime(await _writtenFrames());
    final stale =
        _client == null ||
        local != _local ||
        item() != _item ||
        p < _start0 ||
        p > covered + const Duration(seconds: 2) ||
        p - _start0 > const Duration(minutes: 1);
    if (stale) {
      await _restart(p, local: local);
      return;
    }
    if (covered - p > const Duration(milliseconds: 1500)) return;
    // The next slice starts where the PCM ends, so packet-boundary cuts do
    // not accumulate.
    final a = covered;
    final b = covered + const Duration(seconds: 3);
    final ended = _ended = Completer<void>();
    if (local) {
      final src = source();
      if (src is! UriSource || src.uri.scheme != 'file') return;
      await _client!.loadfile(
        src.uri.toFilePath(),
        options: 'start=${secondsValue(a)},end=${secondsValue(b)}',
      );
      await ended.future.timeout(const Duration(seconds: 10));
      return;
    }
    final storage = _storage!;
    // Each slice overwrites the previous one, which has been decoded.
    if (!await dumpCache(a, b, storage.slicePath) || storage.sliceLength == 0) {
      return;
    }
    await _client!.loadfile(storage.slicePath);
    await ended.future.timeout(const Duration(seconds: 10));
  }

  Future<void> _emit(Duration p) async {
    final written = await _writtenFrames();
    final end = ((p - _start0).inMicroseconds * tapSampleRate / 1e6).round();
    final begin = end - frames;
    if (begin < 0 || end > written) return;
    final raf = _raf ??= await File(_storage!.pcmPath).open();
    await raf.setPosition(begin * _frameBytes);
    final bytes = await raf.read(frames * _frameBytes);
    if (bytes.length < frames * _frameBytes) return;
    final s16 = Int16List.view(
      Uint8List.fromList(bytes).buffer,
      0,
      frames * tapChannels,
    );
    final pcm = Float32List(s16.length);
    for (var i = 0; i < s16.length; i++) {
      pcm[i] = s16[i] / 32768;
    }
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

  // s16 interleaved.
  static const int _frameBytes = tapChannels * 2;

  Future<int> _writtenFrames() async =>
      (_storage?.pcmLength ?? 0) ~/ _frameBytes;

  Future<void> _restart(Duration from, {required bool local}) async {
    await _destroy();
    if (source() == null) return;
    final storage = _storage = await TapStorage.create();
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
        'ao-pcm-file': storage.pcmPath,
        'ao-pcm-waveheader': 'no',
        // Slices are decoded one after the other into the same file.
        'ao-pcm-append': 'yes',
        'audio-format': 's16',
        'audio-channels': 'stereo',
        'audio-samplerate': '$tapSampleRate',
        'hr-seek': 'yes',
      },
      library: Libmpv.open(path: libmpvPath),
    );
    _client = client;
    _events = client.events.listen((e) {
      if (e is MpvEndFile) {
        final ended = _ended;
        if (ended != null && !ended.isCompleted) ended.complete();
      }
    });
    _start0 = from;
    _item = item();
    _local = local;
  }

  Future<void> _destroy() async {
    final raf = _raf;
    _raf = null;
    if (raf != null) {
      try {
        await raf.close();
      } on FileSystemException {
        // Already closed.
      }
    }
    await _events?.cancel();
    _events = null;
    final ended = _ended;
    if (ended != null && !ended.isCompleted) ended.complete();
    _ended = null;
    final client = _client;
    _client = null;
    if (client != null) await client.destroy();
    final storage = _storage;
    _storage = null;
    if (storage != null) {
      _rotatedBytes += storage.pcmLength;
      await storage.dispose();
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
