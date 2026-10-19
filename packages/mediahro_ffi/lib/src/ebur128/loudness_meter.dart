import 'dart:ffi' as ffi;
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:mediahro_ffi/src/ebur128/ebur128_bindings.dart';
import 'package:mediahro_ffi/src/native/native_library.dart';

/// EBU R128 loudness of interleaved float PCM (ReplayGain 2.0 analysis for
/// lanes C2/B1). Blocking; use on a worker isolate.
final class LoudnessMeter {
  LoudnessMeter(this.channels, this.sampleRate, {Ebur128Bindings? bindings})
    : _b =
          bindings ??
          Ebur128Bindings(NativeLibraries.open(NativeLibrary.ebur128)) {
    final m =
        mode.EBUR128_MODE_I.value |
        mode.EBUR128_MODE_LRA.value |
        mode.EBUR128_MODE_TRUE_PEAK.value;
    _st = _b.ebur128_init(channels, sampleRate, m);
    if (_st == ffi.nullptr) throw StateError('ebur128_init failed');
  }

  final int channels;
  final int sampleRate;
  final Ebur128Bindings _b;
  late final ffi.Pointer<ebur128_state> _st;

  void addFrames(Float32List interleaved) {
    if (interleaved.isEmpty) return;
    final p = calloc<ffi.Float>(interleaved.length);
    try {
      p.asTypedList(interleaved.length).setAll(0, interleaved);
      _check(
        _b.ebur128_add_frames_float(_st, p, interleaved.length ~/ channels),
      );
    } finally {
      calloc.free(p);
    }
  }

  /// Integrated loudness in LUFS (−∞ for silence).
  double get integrated => _double((o) => _b.ebur128_loudness_global(_st, o));

  /// Loudness range in LU.
  double get range => _double((o) => _b.ebur128_loudness_range(_st, o));

  /// True peak of [channel] (linear, 1.0 = 0 dBTP).
  double truePeak(int channel) =>
      _double((o) => _b.ebur128_true_peak(_st, channel, o));

  /// ReplayGain 2.0 gain in dB (reference −18 LUFS).
  double get replayGainDb => -18 - integrated;

  void dispose() {
    final p = calloc<ffi.Pointer<ebur128_state>>()..value = _st;
    _b.ebur128_destroy(p);
    calloc.free(p);
  }

  double _double(int Function(ffi.Pointer<ffi.Double>) f) {
    final o = calloc<ffi.Double>();
    try {
      _check(f(o));
      return o.value;
    } finally {
      calloc.free(o);
    }
  }

  static void _check(int rc) {
    // EBUR128_SUCCESS (enum error) is 0.
    if (rc != 0) throw StateError('ebur128 error $rc');
  }
}
