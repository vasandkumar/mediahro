import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:mediahro_ffi/src/native/native_library.dart';
import 'package:mediahro_ffi/src/vips/vips_bindings.dart';
import 'package:meta/meta.dart';

/// A libvips call failed; [message] is libvips' own error text.
final class VipsException implements Exception {
  const VipsException(this.message);

  final String message;

  @override
  String toString() => 'VipsException: $message';
}

/// What libvips reports about an image without decoding it.
@immutable
final class VipsHeader {
  const VipsHeader({
    required this.width,
    required this.height,
    required this.bands,
    required this.pages,
    required this.pageHeight,
    required this.hasAlpha,
    required this.loader,
  });

  final int width;
  final int height;
  final int bands;

  /// Frames of an animated GIF/WebP or pages of a TIFF.
  final int pages;

  /// Height of one page (equals [height] for single-page images).
  final int pageHeight;
  final bool hasAlpha;

  /// The libvips loader class that opened it (`VipsForeignLoadJpegBuffer`).
  final String loader;
}

/// Row-major RGBA8888, straight alpha, no padding.
@immutable
final class VipsPixels {
  const VipsPixels(this.width, this.height, this.rgba);

  final int width;
  final int height;
  final Uint8List rgba;
}

enum VipsSaveFormat { jpeg, png, webp, tiff }

/// Where libvips reads from: a memory buffer (any `VirtualFile`) or a local
/// file, which libvips streams with shrink-on-load so 100 MP+ images never
/// need to sit in Dart memory.
@immutable
sealed class VipsInput {
  const VipsInput();

  const factory VipsInput.bytes(Uint8List bytes) = _BytesInput;
  const factory VipsInput.file(String path) = _FileInput;
}

final class _BytesInput extends VipsInput {
  const _BytesInput(this.bytes);

  final Uint8List bytes;
}

final class _FileInput extends VipsInput {
  const _FileInput(this.path);

  final String path;
}

/// Thin, blocking wrapper over the libvips calls the image pipeline needs
/// (docs/05 §5): header probing, shrink-on-load thumbnails, region decode
/// at a scale, and encoding. Everything works on in-memory buffers so the
/// same code serves local files and any `VirtualFile`. Run it on a worker
/// isolate, never the UI isolate.
final class VipsCodec {
  VipsCodec._(this._v, this._g);

  /// Loads libvips once per isolate and initialises it single-threaded per
  /// call (the pipeline parallelises across isolates instead).
  ///
  /// Throws [NativeLibraryUnavailable] when libvips is missing.
  factory VipsCodec.open({VipsBindings? bindings, GLibBindings? glib}) {
    final existing = _instance;
    if (existing != null) return existing;
    final v =
        bindings ?? VipsBindings(NativeLibraries.open(NativeLibrary.vips));
    final g = glib ?? _openGLib();
    final name = 'mediahro'.toNativeUtf8();
    try {
      if (v.vips_init(name.cast()) != 0) {
        throw const VipsException('vips_init failed');
      }
    } finally {
      malloc.free(name);
    }
    v
      ..vips_concurrency_set(1)
      ..vips_cache_set_max(0)
      ..vips_cache_set_max_mem(16 << 20);
    return _instance = VipsCodec._(v, g);
  }

  static const _vipsSizeDown = 2;
  static const _uchar = 0;
  static const _srgb = 22;

  static VipsCodec? _instance;

  static GLibBindings _openGLib() {
    String name(String base) => switch (Platform.operatingSystem) {
      'windows' => '$base.dll',
      'macos' || 'ios' => 'lib$base.dylib',
      _ => 'lib$base.so',
    };
    return GLibBindings(
      ffi.DynamicLibrary.open(name('gobject-2.0')),
      ffi.DynamicLibrary.open(name('glib-2.0')),
    );
  }

  final VipsBindings _v;
  final GLibBindings _g;

  String _error() {
    final p = _v.vips_error_buffer();
    final s = p == ffi.nullptr
        ? 'unknown libvips error'
        : p.cast<Utf8>().toDartString().trim();
    _v.vips_error_clear();
    return s;
  }

  void _unref(ffi.Pointer<VipsImage> img) => _g.g_object_unref(img.cast());

  /// Runs [body] with [input] opened: bytes are copied into native memory
  /// for the duration (libvips reads lazily from the buffer, so everything
  /// that touches the image must finish inside [body]).
  T _with<T>(VipsInput input, T Function(_Source s) body) {
    switch (input) {
      case _FileInput(:final path):
        final name = path.toNativeUtf8();
        try {
          return body(_Source(this, null, 0, name));
        } finally {
          malloc.free(name);
        }
      case _BytesInput(:final bytes):
        final p = malloc<ffi.Uint8>(bytes.isEmpty ? 1 : bytes.length);
        try {
          p.asTypedList(bytes.length).setAll(0, bytes);
          return body(_Source(this, p.cast(), bytes.length, null));
        } finally {
          malloc.free(p);
        }
    }
  }

  /// Whether libvips has a loader for [input].
  bool canLoad(VipsInput input) =>
      _with(input, (s) => s.findLoader() != ffi.nullptr);

  /// Image size and kind from the header only.
  VipsHeader header(VipsInput input) => _with(input, (s) {
    final loaderName = s.findLoader();
    if (loaderName == ffi.nullptr) {
      throw const VipsException('no libvips loader for this image');
    }
    final loader = loaderName.cast<Utf8>().toDartString();
    final img = s.load();
    try {
      return VipsHeader(
        width: _v.vips_image_get_width(img),
        height: _v.vips_image_get_height(img),
        bands: _v.vips_image_get_bands(img),
        pages: _v.vips_image_get_n_pages(img),
        pageHeight: _v.vips_image_get_page_height(img),
        hasAlpha: _v.vips_image_hasalpha(img) != 0,
        loader: loader,
      );
    } finally {
      _unref(img);
    }
  });

  /// A [size]-pixel (longest edge) thumbnail with EXIF orientation applied,
  /// using shrink-on-load where the format allows it (JPEG, WebP, TIFF).
  VipsPixels thumbnail(VipsInput input, int size) => _with(input, (s) {
    final out = malloc<ffi.Pointer<VipsImage>>();
    final height = 'height'.toNativeUtf8();
    final sizeName = 'size'.toNativeUtf8();
    try {
      final rc = s.thumbnail(out, size, height, sizeName);
      if (rc != 0) throw VipsException(_error());
      return _toRgba(out.value);
    } finally {
      malloc
        ..free(out)
        ..free(height)
        ..free(sizeName);
    }
  });

  /// Decodes [region] (the whole image when null) at [scale] (1.0 = 1:1),
  /// orientation applied. [region] is in source pixels.
  VipsPixels decode(
    VipsInput input, {
    ({int left, int top, int width, int height})? region,
    double scale = 1,
    int page = 0,
  }) => _with(input, (s) {
    var img = s.load(options: page > 0 ? '[page=$page]' : '');
    try {
      final loaded = img;
      img = _step(loaded, (o) => _v.vips_autorot(loaded, o, ffi.nullptr));
      if (scale != 1) {
        final src = img;
        img = _step(src, (o) => _v.vips_resize(src, o, scale, ffi.nullptr));
      }
      if (region != null) {
        final w = _v.vips_image_get_width(img);
        final h = _v.vips_image_get_height(img);
        final left = (region.left * scale).round().clamp(0, w - 1);
        final top = (region.top * scale).round().clamp(0, h - 1);
        final width = (region.width * scale).round().clamp(1, w - left);
        final height = (region.height * scale).round().clamp(1, h - top);
        final src = img;
        img = _step(
          src,
          (o) => _v.vips_extract_area(
            src,
            o,
            left,
            top,
            width,
            height,
            ffi.nullptr,
          ),
        );
      }
    } on Object {
      _unref(img);
      rethrow;
    }
    // _toRgba takes ownership of img.
    return _toRgba(img);
  });

  /// Runs one operation and releases its input.
  ffi.Pointer<VipsImage> _step(
    ffi.Pointer<VipsImage> input,
    int Function(ffi.Pointer<ffi.Pointer<VipsImage>> out) op,
  ) {
    final out = malloc<ffi.Pointer<VipsImage>>();
    try {
      if (op(out) != 0) throw VipsException(_error());
      final r = out.value;
      _unref(input);
      return r;
    } finally {
      malloc.free(out);
    }
  }

  /// Converts [input] (consumed) to sRGB 8-bit RGBA and copies the pixels.
  VipsPixels _toRgba(ffi.Pointer<VipsImage> input) {
    var img = input;
    try {
      if (_v.vips_image_get_interpretation(img) != _srgb) {
        final src = img;
        img = _step(
          src,
          (o) => _v.vips_colourspace(src, o, _srgb, ffi.nullptr),
        );
      }
      if (_v.vips_image_get_format(img) != _uchar) {
        final src = img;
        img = _step(src, (o) => _v.vips_cast(src, o, _uchar, ffi.nullptr));
      }
      if (_v.vips_image_get_bands(img) == 3) {
        final src = img;
        img = _step(
          src,
          (o) => _v.vips_bandjoin_const1(src, o, 255, ffi.nullptr),
        );
      }
      if (_v.vips_image_get_bands(img) != 4) {
        throw VipsException(
          'unexpected band count ${_v.vips_image_get_bands(img)}',
        );
      }
      final w = _v.vips_image_get_width(img);
      final h = _v.vips_image_get_height(img);
      final size = malloc<ffi.Size>();
      try {
        final mem = _v.vips_image_write_to_memory(img, size);
        if (mem == ffi.nullptr) throw VipsException(_error());
        final rgba = Uint8List.fromList(
          mem.cast<ffi.Uint8>().asTypedList(size.value),
        );
        _g.g_free(mem);
        return VipsPixels(w, h, rgba);
      } finally {
        malloc.free(size);
      }
    } finally {
      _unref(img);
    }
  }

  /// Encodes RGBA pixels. [quality] is JPEG/WebP Q (1–100); for PNG it maps
  /// to the zlib level (0–9).
  Uint8List encode(
    VipsPixels image,
    VipsSaveFormat format, {
    int quality = 90,
  }) {
    final mem = malloc<ffi.Uint8>(image.rgba.length);
    try {
      mem.asTypedList(image.rgba.length).setAll(0, image.rgba);
      final img = _v.vips_image_new_from_memory_copy(
        mem.cast(),
        image.rgba.length,
        image.width,
        image.height,
        4,
        _uchar,
      );
      if (img == ffi.nullptr) throw VipsException(_error());
      final buf = malloc<ffi.Pointer<ffi.Void>>();
      final len = malloc<ffi.Size>();
      final key = (format == VipsSaveFormat.png ? 'compression' : 'Q')
          .toNativeUtf8();
      try {
        final save = switch (format) {
          VipsSaveFormat.jpeg => _v.vips_jpegsave_buffer,
          VipsSaveFormat.png => _v.vips_pngsave_buffer,
          VipsSaveFormat.webp => _v.vips_webpsave_buffer,
          VipsSaveFormat.tiff => _v.vips_tiffsave_buffer,
        };
        final q = format == VipsSaveFormat.png
            ? (quality / 11).round().clamp(0, 9)
            : quality;
        if (save(img, buf, len, key.cast(), q, ffi.nullptr) != 0) {
          throw VipsException(_error());
        }
        final out = Uint8List.fromList(
          buf.value.cast<ffi.Uint8>().asTypedList(len.value),
        );
        _g.g_free(buf.value);
        return out;
      } finally {
        _unref(img);
        malloc
          ..free(buf)
          ..free(len)
          ..free(key);
      }
    } finally {
      malloc.free(mem);
    }
  }
}

/// One opened input: a native buffer or a file name, with the libvips calls
/// that differ between them.
final class _Source {
  _Source(this._c, this._buf, this._len, this._name);

  final VipsCodec _c;
  final ffi.Pointer<ffi.Void>? _buf;
  final int _len;
  final ffi.Pointer<Utf8>? _name;

  ffi.Pointer<ffi.Char> findLoader() => _name != null
      ? _c._v.vips_foreign_find_load(_name.cast())
      : _c._v.vips_foreign_find_load_buffer(_buf!, _len);

  ffi.Pointer<VipsImage> load({String options = ''}) {
    final ffi.Pointer<VipsImage> img;
    if (_name != null) {
      // Options ride on the file name (`photo.tif[page=2]`).
      final named = options.isEmpty
          ? _name
          : '${_name.toDartString()}$options'.toNativeUtf8();
      try {
        img = _c._v.vips_image_new_from_file(named.cast(), ffi.nullptr);
      } finally {
        if (options.isNotEmpty) malloc.free(named);
      }
    } else {
      final opt = options.toNativeUtf8();
      try {
        img = _c._v.vips_image_new_from_buffer(
          _buf!,
          _len,
          opt.cast(),
          ffi.nullptr,
        );
      } finally {
        malloc.free(opt);
      }
    }
    if (img == ffi.nullptr) throw VipsException(_c._error());
    return img;
  }

  int thumbnail(
    ffi.Pointer<ffi.Pointer<VipsImage>> out,
    int size,
    ffi.Pointer<Utf8> height,
    ffi.Pointer<Utf8> sizeName,
  ) => _name != null
      ? _c._v.vips_thumbnail(
          _name.cast(),
          out,
          size,
          height.cast(),
          size,
          sizeName.cast(),
          VipsCodec._vipsSizeDown,
          ffi.nullptr,
        )
      : _c._v.vips_thumbnail_buffer(
          _buf!,
          _len,
          out,
          size,
          height.cast(),
          size,
          sizeName.cast(),
          VipsCodec._vipsSizeDown,
          ffi.nullptr,
        );
}
