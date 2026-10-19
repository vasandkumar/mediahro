import 'dart:ffi' as ffi;
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:mediahro_ffi/src/chromaprint/chromaprint_bindings.dart';
import 'package:mediahro_ffi/src/native/native_library.dart';

/// Chromaprint acoustic fingerprints of 16-bit PCM (LIB-014 duplicate
/// audio, AcoustID lookups). Blocking; use on a worker isolate.
final class Fingerprinter {
  Fingerprinter({ChromaprintBindings? bindings})
    : _b =
          bindings ??
          ChromaprintBindings(NativeLibraries.open(NativeLibrary.chromaprint)) {
    _ctx = _b.chromaprint_new(
      ChromaprintAlgorithm.CHROMAPRINT_ALGORITHM_DEFAULT.value,
    );
    if (_ctx == ffi.nullptr) throw StateError('chromaprint_new failed');
  }

  final ChromaprintBindings _b;
  late final ffi.Pointer<ChromaprintContextPrivate> _ctx;

  void start(int sampleRate, int channels) =>
      _check(_b.chromaprint_start(_ctx, sampleRate, channels));

  /// Interleaved samples; chromaprint needs ~120 s for AcoustID, any
  /// length for duplicate comparison.
  void feed(Int16List samples) {
    if (samples.isEmpty) return;
    final p = calloc<ffi.Int16>(samples.length);
    try {
      p.asTypedList(samples.length).setAll(0, samples);
      _check(_b.chromaprint_feed(_ctx, p, samples.length));
    } finally {
      calloc.free(p);
    }
  }

  void finish() => _check(_b.chromaprint_finish(_ctx));

  /// Raw fingerprint words (compare with bit error rate).
  Uint32List raw() {
    final fp = calloc<ffi.Pointer<ffi.Uint32>>();
    final size = calloc<ffi.Int>();
    try {
      _check(_b.chromaprint_get_raw_fingerprint(_ctx, fp, size));
      final out = Uint32List.fromList(fp.value.asTypedList(size.value));
      _b.chromaprint_dealloc(fp.value.cast());
      return out;
    } finally {
      calloc
        ..free(fp)
        ..free(size);
    }
  }

  /// Compressed base64 fingerprint (AcoustID API format).
  String encoded() {
    final fp = calloc<ffi.Pointer<ffi.Char>>();
    try {
      _check(_b.chromaprint_get_fingerprint(_ctx, fp));
      final s = fp.value.cast<Utf8>().toDartString();
      _b.chromaprint_dealloc(fp.value.cast());
      return s;
    } finally {
      calloc.free(fp);
    }
  }

  void dispose() => _b.chromaprint_free(_ctx);

  static void _check(int rc) {
    if (rc != 1) throw StateError('chromaprint call failed');
  }
}
