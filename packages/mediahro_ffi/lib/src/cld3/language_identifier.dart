import 'dart:convert';
import 'dart:ffi' as ffi;

import 'package:ffi/ffi.dart';
import 'package:mediahro_ffi/src/cld3/cld3_bindings.dart';
import 'package:mediahro_ffi/src/native/native_library.dart';
import 'package:meta/meta.dart';

/// CLD3's guess for a piece of text.
@immutable
final class LanguageGuess {
  const LanguageGuess(this.code, this.probability, {required this.reliable});

  /// CLD3's code: ISO 639-1 where one exists (`en`, `zh`), sometimes with a
  /// script (`ja-Latn`), `und` when unknown.
  final String code;

  /// 0…1.
  final double probability;
  final bool reliable;
}

/// CLD3 language identification (ADR-034). Cheap enough to call on the
/// worker isolate per subtitle file, not per line.
final class Cld3LanguageIdentifier {
  Cld3LanguageIdentifier._(this._b, this._id);

  factory Cld3LanguageIdentifier.open({
    int maxBytes = 1000,
    Cld3Bindings? bindings,
  }) {
    final b =
        bindings ?? Cld3Bindings(NativeLibraries.open(NativeLibrary.cld3));
    final id = b.mh_cld3_new(0, maxBytes);
    if (id == ffi.nullptr) throw StateError('mh_cld3_new failed');
    return Cld3LanguageIdentifier._(b, id);
  }

  final Cld3Bindings _b;
  ffi.Pointer<mh_cld3> _id;

  LanguageGuess identify(String text) {
    if (_id == ffi.nullptr) throw StateError('closed');
    final bytes = utf8.encode(text);
    final input = calloc<ffi.Uint8>(bytes.isEmpty ? 1 : bytes.length);
    const outLen = 32;
    final out = calloc<ffi.Char>(outLen);
    final prob = calloc<ffi.Float>();
    try {
      input.asTypedList(bytes.length).setAll(0, bytes);
      final r = _b.mh_cld3_find(
        _id,
        input.cast(),
        bytes.length,
        out,
        outLen,
        prob,
      );
      if (r < 0) return const LanguageGuess('und', 0, reliable: false);
      return LanguageGuess(
        out.cast<Utf8>().toDartString(),
        prob.value.clamp(0, 1).toDouble(),
        reliable: r == 1,
      );
    } finally {
      calloc
        ..free(input)
        ..free(out)
        ..free(prob);
    }
  }

  void close() {
    if (_id == ffi.nullptr) return;
    _b.mh_cld3_free(_id);
    _id = ffi.nullptr;
  }
}
