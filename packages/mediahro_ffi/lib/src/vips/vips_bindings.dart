// ignore_for_file: type=lint, unused_field

// Written by hand to match what `package:ffigen` generates from
// ffigen/vips.yaml (headers: .deps-cache/<platform>/include/vips, libvips
// 8.18.7 from mediahro-deps). This PC has no libclang, as for cld3. libvips'
// option lists are C varargs terminated by NULL; each shape used is bound
// once with `VarArgs` (ffigen: `functions: variadic-arguments`).
// Regenerate:
//   (cd packages/mediahro_ffi && dart run ffigen --config ffigen/vips.yaml)
import 'dart:ffi' as ffi;

/// Opaque `VipsImage` (a GObject).
final class VipsImage extends ffi.Opaque {}

abstract final class VipsBandFormat {
  static const int UCHAR = 0;
  static const int USHORT = 2;
  static const int FLOAT = 6;
}

abstract final class VipsInterpretation {
  static const int B_W = 1;
  static const int sRGB = 22;
  static const int RGB16 = 25;
  static const int GREY16 = 26;
  static const int scRGB = 28;
}

abstract final class VipsSize {
  static const int BOTH = 0;
  static const int UP = 1;
  static const int DOWN = 2;
  static const int FORCE = 3;
}

/// Bindings to libvips (LGPL-2.1-or-later, always loaded dynamically).
class VipsBindings {
  final ffi.Pointer<T> Function<T extends ffi.NativeType>(String symbolName)
  _lookup;

  VipsBindings(ffi.DynamicLibrary dynamicLibrary)
    : _lookup = dynamicLibrary.lookup;

  VipsBindings.fromLookup(
    ffi.Pointer<T> Function<T extends ffi.NativeType>(String symbolName) lookup,
  ) : _lookup = lookup;

  late final vips_init = _lookup<
    ffi.NativeFunction<ffi.Int Function(ffi.Pointer<ffi.Char>)>
  >('vips_init').asFunction<int Function(ffi.Pointer<ffi.Char>)>();

  late final vips_error_buffer = _lookup<
    ffi.NativeFunction<ffi.Pointer<ffi.Char> Function()>
  >('vips_error_buffer').asFunction<ffi.Pointer<ffi.Char> Function()>();

  late final vips_error_clear = _lookup<ffi.NativeFunction<ffi.Void Function()>>(
    'vips_error_clear',
  ).asFunction<void Function()>();

  late final vips_concurrency_set = _lookup<
    ffi.NativeFunction<ffi.Void Function(ffi.Int)>
  >('vips_concurrency_set').asFunction<void Function(int)>();

  late final vips_cache_set_max = _lookup<
    ffi.NativeFunction<ffi.Void Function(ffi.Int)>
  >('vips_cache_set_max').asFunction<void Function(int)>();

  late final vips_cache_set_max_mem = _lookup<
    ffi.NativeFunction<ffi.Void Function(ffi.Size)>
  >('vips_cache_set_max_mem').asFunction<void Function(int)>();

  late final vips_foreign_find_load = _lookup<
    ffi.NativeFunction<ffi.Pointer<ffi.Char> Function(ffi.Pointer<ffi.Char>)>
  >('vips_foreign_find_load').asFunction<
    ffi.Pointer<ffi.Char> Function(ffi.Pointer<ffi.Char>)
  >();

  late final vips_foreign_find_load_buffer = _lookup<
    ffi.NativeFunction<
      ffi.Pointer<ffi.Char> Function(ffi.Pointer<ffi.Void>, ffi.Size)
    >
  >('vips_foreign_find_load_buffer').asFunction<
    ffi.Pointer<ffi.Char> Function(ffi.Pointer<ffi.Void>, int)
  >();

  /// `vips_image_new_from_file(name, NULL)`; options go in the name
  /// (`photo.gif[n=-1]`).
  late final vips_image_new_from_file = _lookup<
    ffi.NativeFunction<
      ffi.Pointer<VipsImage> Function(
        ffi.Pointer<ffi.Char>,
        ffi.VarArgs<(ffi.Pointer<ffi.Void>,)>,
      )
    >
  >('vips_image_new_from_file').asFunction<
    ffi.Pointer<VipsImage> Function(ffi.Pointer<ffi.Char>, ffi.Pointer<ffi.Void>)
  >();

  /// `vips_image_new_from_buffer(buf, len, option_string, NULL)`.
  late final vips_image_new_from_buffer = _lookup<
    ffi.NativeFunction<
      ffi.Pointer<VipsImage> Function(
        ffi.Pointer<ffi.Void>,
        ffi.Size,
        ffi.Pointer<ffi.Char>,
        ffi.VarArgs<(ffi.Pointer<ffi.Void>,)>,
      )
    >
  >('vips_image_new_from_buffer').asFunction<
    ffi.Pointer<VipsImage> Function(
      ffi.Pointer<ffi.Void>,
      int,
      ffi.Pointer<ffi.Char>,
      ffi.Pointer<ffi.Void>,
    )
  >();

  late final vips_image_new_from_memory_copy = _lookup<
    ffi.NativeFunction<
      ffi.Pointer<VipsImage> Function(
        ffi.Pointer<ffi.Void>,
        ffi.Size,
        ffi.Int,
        ffi.Int,
        ffi.Int,
        ffi.Int,
      )
    >
  >('vips_image_new_from_memory_copy').asFunction<
    ffi.Pointer<VipsImage> Function(ffi.Pointer<ffi.Void>, int, int, int, int, int)
  >();

  /// `vips_thumbnail(name, &out, width, "height", h, "size", size, NULL)`.
  late final vips_thumbnail = _lookup<
    ffi.NativeFunction<
      ffi.Int Function(
        ffi.Pointer<ffi.Char>,
        ffi.Pointer<ffi.Pointer<VipsImage>>,
        ffi.Int,
        ffi.VarArgs<
          (
            ffi.Pointer<ffi.Char>,
            ffi.Int,
            ffi.Pointer<ffi.Char>,
            ffi.Int,
            ffi.Pointer<ffi.Void>,
          )
        >,
      )
    >
  >('vips_thumbnail').asFunction<
    int Function(
      ffi.Pointer<ffi.Char>,
      ffi.Pointer<ffi.Pointer<VipsImage>>,
      int,
      ffi.Pointer<ffi.Char>,
      int,
      ffi.Pointer<ffi.Char>,
      int,
      ffi.Pointer<ffi.Void>,
    )
  >();

  /// `vips_thumbnail_buffer(buf, len, &out, width, "height", h, "size",
  /// size, NULL)`.
  late final vips_thumbnail_buffer = _lookup<
    ffi.NativeFunction<
      ffi.Int Function(
        ffi.Pointer<ffi.Void>,
        ffi.Size,
        ffi.Pointer<ffi.Pointer<VipsImage>>,
        ffi.Int,
        ffi.VarArgs<
          (
            ffi.Pointer<ffi.Char>,
            ffi.Int,
            ffi.Pointer<ffi.Char>,
            ffi.Int,
            ffi.Pointer<ffi.Void>,
          )
        >,
      )
    >
  >('vips_thumbnail_buffer').asFunction<
    int Function(
      ffi.Pointer<ffi.Void>,
      int,
      ffi.Pointer<ffi.Pointer<VipsImage>>,
      int,
      ffi.Pointer<ffi.Char>,
      int,
      ffi.Pointer<ffi.Char>,
      int,
      ffi.Pointer<ffi.Void>,
    )
  >();

  // ---- unary operations with no options: op(in, &out, NULL) ----

  late final vips_autorot = _unary('vips_autorot');
  late final vips_flatten = _unary('vips_flatten');
  late final vips_copy = _unary('vips_copy');

  int Function(
    ffi.Pointer<VipsImage>,
    ffi.Pointer<ffi.Pointer<VipsImage>>,
    ffi.Pointer<ffi.Void>,
  )
  _unary(String name) => _lookup<
    ffi.NativeFunction<
      ffi.Int Function(
        ffi.Pointer<VipsImage>,
        ffi.Pointer<ffi.Pointer<VipsImage>>,
        ffi.VarArgs<(ffi.Pointer<ffi.Void>,)>,
      )
    >
  >(name).asFunction();

  /// `op(in, &out, int arg, NULL)`: vips_cast, vips_colourspace, vips_rot,
  /// vips_flip.
  late final vips_cast = _unaryInt('vips_cast');
  late final vips_colourspace = _unaryInt('vips_colourspace');
  late final vips_rot = _unaryInt('vips_rot');
  late final vips_flip = _unaryInt('vips_flip');

  int Function(
    ffi.Pointer<VipsImage>,
    ffi.Pointer<ffi.Pointer<VipsImage>>,
    int,
    ffi.Pointer<ffi.Void>,
  )
  _unaryInt(String name) => _lookup<
    ffi.NativeFunction<
      ffi.Int Function(
        ffi.Pointer<VipsImage>,
        ffi.Pointer<ffi.Pointer<VipsImage>>,
        ffi.Int,
        ffi.VarArgs<(ffi.Pointer<ffi.Void>,)>,
      )
    >
  >(name).asFunction();

  /// `op(in, &out, double arg, NULL)`: vips_resize, vips_bandjoin_const1,
  /// vips_rotate, vips_gaussblur.
  late final vips_resize = _unaryDouble('vips_resize');
  late final vips_bandjoin_const1 = _unaryDouble('vips_bandjoin_const1');
  late final vips_rotate = _unaryDouble('vips_rotate');
  late final vips_gaussblur = _unaryDouble('vips_gaussblur');

  int Function(
    ffi.Pointer<VipsImage>,
    ffi.Pointer<ffi.Pointer<VipsImage>>,
    double,
    ffi.Pointer<ffi.Void>,
  )
  _unaryDouble(String name) => _lookup<
    ffi.NativeFunction<
      ffi.Int Function(
        ffi.Pointer<VipsImage>,
        ffi.Pointer<ffi.Pointer<VipsImage>>,
        ffi.Double,
        ffi.VarArgs<(ffi.Pointer<ffi.Void>,)>,
      )
    >
  >(name).asFunction();

  late final vips_extract_area = _lookup<
    ffi.NativeFunction<
      ffi.Int Function(
        ffi.Pointer<VipsImage>,
        ffi.Pointer<ffi.Pointer<VipsImage>>,
        ffi.Int,
        ffi.Int,
        ffi.Int,
        ffi.Int,
        ffi.VarArgs<(ffi.Pointer<ffi.Void>,)>,
      )
    >
  >('vips_extract_area').asFunction<
    int Function(
      ffi.Pointer<VipsImage>,
      ffi.Pointer<ffi.Pointer<VipsImage>>,
      int,
      int,
      int,
      int,
      ffi.Pointer<ffi.Void>,
    )
  >();

  /// `save(in, &buf, &len, "Q", q, NULL)` for jpeg/webp; png/tiff take
  /// "compression" (int) in the same shape.
  late final vips_jpegsave_buffer = _save('vips_jpegsave_buffer');
  late final vips_webpsave_buffer = _save('vips_webpsave_buffer');
  late final vips_pngsave_buffer = _save('vips_pngsave_buffer');
  late final vips_tiffsave_buffer = _save('vips_tiffsave_buffer');

  int Function(
    ffi.Pointer<VipsImage>,
    ffi.Pointer<ffi.Pointer<ffi.Void>>,
    ffi.Pointer<ffi.Size>,
    ffi.Pointer<ffi.Char>,
    int,
    ffi.Pointer<ffi.Void>,
  )
  _save(String name) => _lookup<
    ffi.NativeFunction<
      ffi.Int Function(
        ffi.Pointer<VipsImage>,
        ffi.Pointer<ffi.Pointer<ffi.Void>>,
        ffi.Pointer<ffi.Size>,
        ffi.VarArgs<(ffi.Pointer<ffi.Char>, ffi.Int, ffi.Pointer<ffi.Void>)>,
      )
    >
  >(name).asFunction();

  late final vips_image_write_to_memory = _lookup<
    ffi.NativeFunction<
      ffi.Pointer<ffi.Void> Function(ffi.Pointer<VipsImage>, ffi.Pointer<ffi.Size>)
    >
  >('vips_image_write_to_memory').asFunction<
    ffi.Pointer<ffi.Void> Function(ffi.Pointer<VipsImage>, ffi.Pointer<ffi.Size>)
  >();

  late final vips_image_get_width = _getInt('vips_image_get_width');
  late final vips_image_get_height = _getInt('vips_image_get_height');
  late final vips_image_get_bands = _getInt('vips_image_get_bands');
  late final vips_image_get_format = _getInt('vips_image_get_format');
  late final vips_image_get_interpretation = _getInt(
    'vips_image_get_interpretation',
  );
  late final vips_image_get_n_pages = _getInt('vips_image_get_n_pages');
  late final vips_image_get_page_height = _getInt('vips_image_get_page_height');
  late final vips_image_hasalpha = _getInt('vips_image_hasalpha');

  int Function(ffi.Pointer<VipsImage>) _getInt(String name) => _lookup<
    ffi.NativeFunction<ffi.Int Function(ffi.Pointer<VipsImage>)>
  >(name).asFunction();

  late final vips_image_get_typeof = _lookup<
    ffi.NativeFunction<
      ffi.UnsignedLong Function(ffi.Pointer<VipsImage>, ffi.Pointer<ffi.Char>)
    >
  >('vips_image_get_typeof').asFunction<
    int Function(ffi.Pointer<VipsImage>, ffi.Pointer<ffi.Char>)
  >();

  late final vips_image_get_int = _lookup<
    ffi.NativeFunction<
      ffi.Int Function(
        ffi.Pointer<VipsImage>,
        ffi.Pointer<ffi.Char>,
        ffi.Pointer<ffi.Int>,
      )
    >
  >('vips_image_get_int').asFunction<
    int Function(ffi.Pointer<VipsImage>, ffi.Pointer<ffi.Char>, ffi.Pointer<ffi.Int>)
  >();

  late final vips_image_get_blob = _lookup<
    ffi.NativeFunction<
      ffi.Int Function(
        ffi.Pointer<VipsImage>,
        ffi.Pointer<ffi.Char>,
        ffi.Pointer<ffi.Pointer<ffi.Void>>,
        ffi.Pointer<ffi.Size>,
      )
    >
  >('vips_image_get_blob').asFunction<
    int Function(
      ffi.Pointer<VipsImage>,
      ffi.Pointer<ffi.Char>,
      ffi.Pointer<ffi.Pointer<ffi.Void>>,
      ffi.Pointer<ffi.Size>,
    )
  >();

  late final vips_image_get_array_int = _lookup<
    ffi.NativeFunction<
      ffi.Int Function(
        ffi.Pointer<VipsImage>,
        ffi.Pointer<ffi.Char>,
        ffi.Pointer<ffi.Pointer<ffi.Int>>,
        ffi.Pointer<ffi.Int>,
      )
    >
  >('vips_image_get_array_int').asFunction<
    int Function(
      ffi.Pointer<VipsImage>,
      ffi.Pointer<ffi.Char>,
      ffi.Pointer<ffi.Pointer<ffi.Int>>,
      ffi.Pointer<ffi.Int>,
    )
  >();
}

/// The two GLib entry points libvips callers need: `g_object_unref`
/// (libgobject-2.0) and `g_free` (libglib-2.0).
class GLibBindings {
  GLibBindings(ffi.DynamicLibrary gobject, ffi.DynamicLibrary glib)
    : g_object_unref = gobject
          .lookup<ffi.NativeFunction<ffi.Void Function(ffi.Pointer<ffi.Void>)>>(
            'g_object_unref',
          )
          .asFunction(),
      g_free = glib
          .lookup<ffi.NativeFunction<ffi.Void Function(ffi.Pointer<ffi.Void>)>>(
            'g_free',
          )
          .asFunction();

  final void Function(ffi.Pointer<ffi.Void>) g_object_unref;
  final void Function(ffi.Pointer<ffi.Void>) g_free;
}
