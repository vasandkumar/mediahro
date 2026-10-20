// ignore_for_file: type=lint, unused_field

// Written by hand to match what `package:ffigen` generates from
// ffigen/cld3.yaml (lib/src/cld3/include/mediahro_cld3.h). Regenerate:
//   (cd packages/mediahro_ffi && dart run ffigen --config ffigen/cld3.yaml)
import 'dart:ffi' as ffi;

/// Bindings to Mediahro's C API over CLD3 (language ID; ADR-034).
class Cld3Bindings {
  /// Holds the symbol lookup function.
  final ffi.Pointer<T> Function<T extends ffi.NativeType>(String symbolName)
  _lookup;

  /// The symbols are looked up in [dynamicLibrary].
  Cld3Bindings(ffi.DynamicLibrary dynamicLibrary)
    : _lookup = dynamicLibrary.lookup;

  /// The symbols are looked up with [lookup].
  Cld3Bindings.fromLookup(
    ffi.Pointer<T> Function<T extends ffi.NativeType>(String symbolName) lookup,
  ) : _lookup = lookup;

  ffi.Pointer<mh_cld3> mh_cld3_new(int min_bytes, int max_bytes) {
    return _mh_cld3_new(min_bytes, max_bytes);
  }

  late final _mh_cld3_newPtr =
      _lookup<
        ffi.NativeFunction<ffi.Pointer<mh_cld3> Function(ffi.Int, ffi.Int)>
      >('mh_cld3_new');
  late final _mh_cld3_new = _mh_cld3_newPtr
      .asFunction<ffi.Pointer<mh_cld3> Function(int, int)>();

  void mh_cld3_free(ffi.Pointer<mh_cld3> id) {
    return _mh_cld3_free(id);
  }

  late final _mh_cld3_freePtr =
      _lookup<ffi.NativeFunction<ffi.Void Function(ffi.Pointer<mh_cld3>)>>(
        'mh_cld3_free',
      );
  late final _mh_cld3_free = _mh_cld3_freePtr
      .asFunction<void Function(ffi.Pointer<mh_cld3>)>();

  int mh_cld3_find(
    ffi.Pointer<mh_cld3> id,
    ffi.Pointer<ffi.Char> utf8,
    int len,
    ffi.Pointer<ffi.Char> out,
    int out_len,
    ffi.Pointer<ffi.Float> probability,
  ) {
    return _mh_cld3_find(id, utf8, len, out, out_len, probability);
  }

  late final _mh_cld3_findPtr =
      _lookup<
        ffi.NativeFunction<
          ffi.Int Function(
            ffi.Pointer<mh_cld3>,
            ffi.Pointer<ffi.Char>,
            ffi.Int,
            ffi.Pointer<ffi.Char>,
            ffi.Int,
            ffi.Pointer<ffi.Float>,
          )
        >
      >('mh_cld3_find');
  late final _mh_cld3_find = _mh_cld3_findPtr
      .asFunction<
        int Function(
          ffi.Pointer<mh_cld3>,
          ffi.Pointer<ffi.Char>,
          int,
          ffi.Pointer<ffi.Char>,
          int,
          ffi.Pointer<ffi.Float>,
        )
      >();
}

final class mh_cld3 extends ffi.Opaque {}
