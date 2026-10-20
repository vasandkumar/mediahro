// ignore_for_file: type=lint, unused_field

// Written by hand to match what `package:ffigen` generates from
// ffigen/bergamot.yaml (lib/src/bergamot/include/mediahro_bergamot.h).
// Regenerate:
//   (cd packages/mediahro_ffi && dart run ffigen --config ffigen/bergamot.yaml)
import 'dart:ffi' as ffi;

/// Bindings to Mediahro's C API over the Bergamot translator (ADR-034).
class BergamotBindings {
  /// Holds the symbol lookup function.
  final ffi.Pointer<T> Function<T extends ffi.NativeType>(String symbolName)
  _lookup;

  /// The symbols are looked up in [dynamicLibrary].
  BergamotBindings(ffi.DynamicLibrary dynamicLibrary)
    : _lookup = dynamicLibrary.lookup;

  /// The symbols are looked up with [lookup].
  BergamotBindings.fromLookup(
    ffi.Pointer<T> Function<T extends ffi.NativeType>(String symbolName) lookup,
  ) : _lookup = lookup;

  ffi.Pointer<mh_bergamot> mh_bergamot_new(int cache_size) {
    return _mh_bergamot_new(cache_size);
  }

  late final _mh_bergamot_newPtr =
      _lookup<ffi.NativeFunction<ffi.Pointer<mh_bergamot> Function(ffi.Int)>>(
        'mh_bergamot_new',
      );
  late final _mh_bergamot_new = _mh_bergamot_newPtr
      .asFunction<ffi.Pointer<mh_bergamot> Function(int)>();

  void mh_bergamot_free(ffi.Pointer<mh_bergamot> service) {
    return _mh_bergamot_free(service);
  }

  late final _mh_bergamot_freePtr =
      _lookup<ffi.NativeFunction<ffi.Void Function(ffi.Pointer<mh_bergamot>)>>(
        'mh_bergamot_free',
      );
  late final _mh_bergamot_free = _mh_bergamot_freePtr
      .asFunction<void Function(ffi.Pointer<mh_bergamot>)>();

  ffi.Pointer<mh_bergamot_model> mh_bergamot_load(
    ffi.Pointer<mh_bergamot> service,
    ffi.Pointer<ffi.Char> config_yaml,
    ffi.Pointer<ffi.Char> err,
    int err_len,
  ) {
    return _mh_bergamot_load(service, config_yaml, err, err_len);
  }

  late final _mh_bergamot_loadPtr =
      _lookup<
        ffi.NativeFunction<
          ffi.Pointer<mh_bergamot_model> Function(
            ffi.Pointer<mh_bergamot>,
            ffi.Pointer<ffi.Char>,
            ffi.Pointer<ffi.Char>,
            ffi.Int,
          )
        >
      >('mh_bergamot_load');
  late final _mh_bergamot_load = _mh_bergamot_loadPtr
      .asFunction<
        ffi.Pointer<mh_bergamot_model> Function(
          ffi.Pointer<mh_bergamot>,
          ffi.Pointer<ffi.Char>,
          ffi.Pointer<ffi.Char>,
          int,
        )
      >();

  void mh_bergamot_model_free(ffi.Pointer<mh_bergamot_model> model) {
    return _mh_bergamot_model_free(model);
  }

  late final _mh_bergamot_model_freePtr =
      _lookup<
        ffi.NativeFunction<ffi.Void Function(ffi.Pointer<mh_bergamot_model>)>
      >('mh_bergamot_model_free');
  late final _mh_bergamot_model_free = _mh_bergamot_model_freePtr
      .asFunction<void Function(ffi.Pointer<mh_bergamot_model>)>();

  int mh_bergamot_translate(
    ffi.Pointer<mh_bergamot> service,
    ffi.Pointer<mh_bergamot_model> model,
    ffi.Pointer<ffi.Pointer<ffi.Char>> lines,
    int n,
    ffi.Pointer<ffi.Pointer<ffi.Char>> out,
  ) {
    return _mh_bergamot_translate(service, model, lines, n, out);
  }

  late final _mh_bergamot_translatePtr =
      _lookup<
        ffi.NativeFunction<
          ffi.Int Function(
            ffi.Pointer<mh_bergamot>,
            ffi.Pointer<mh_bergamot_model>,
            ffi.Pointer<ffi.Pointer<ffi.Char>>,
            ffi.Int,
            ffi.Pointer<ffi.Pointer<ffi.Char>>,
          )
        >
      >('mh_bergamot_translate');
  late final _mh_bergamot_translate = _mh_bergamot_translatePtr
      .asFunction<
        int Function(
          ffi.Pointer<mh_bergamot>,
          ffi.Pointer<mh_bergamot_model>,
          ffi.Pointer<ffi.Pointer<ffi.Char>>,
          int,
          ffi.Pointer<ffi.Pointer<ffi.Char>>,
        )
      >();

  void mh_bergamot_free_text(ffi.Pointer<ffi.Char> text) {
    return _mh_bergamot_free_text(text);
  }

  late final _mh_bergamot_free_textPtr =
      _lookup<ffi.NativeFunction<ffi.Void Function(ffi.Pointer<ffi.Char>)>>(
        'mh_bergamot_free_text',
      );
  late final _mh_bergamot_free_text = _mh_bergamot_free_textPtr
      .asFunction<void Function(ffi.Pointer<ffi.Char>)>();
}

final class mh_bergamot extends ffi.Opaque {}

final class mh_bergamot_model extends ffi.Opaque {}
