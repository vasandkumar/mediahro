import 'dart:ffi' as ffi;
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:mediahro_ffi/src/native/native_library.dart';
import 'package:mediahro_ffi/src/raw/raw_bindings.dart';
import 'package:meta/meta.dart';

/// LibRaw could not read or develop the file.
final class RawException implements Exception {
  const RawException(this.message);

  final String message;

  @override
  String toString() => 'RawException: $message';
}

/// A developed RAW: RGBA8888 in sRGB.
@immutable
final class RawImage {
  const RawImage(this.width, this.height, this.rgba);

  final int width;
  final int height;
  final Uint8List rgba;
}

/// The preview LibRaw found in a file: a JPEG to hand to another decoder, or
/// already-decoded RGBA.
@immutable
final class RawThumbnail {
  const RawThumbnail({this.jpeg, this.image});

  final Uint8List? jpeg;
  final RawImage? image;
}

/// Camera RAW through LibRaw (IMG-001): sensor size, the embedded preview,
/// and a full development to 8-bit sRGB. Blocking and memory hungry (a
/// 45 MP file needs several hundred MB); use on a worker isolate and refuse
/// files above [maxPixels].
///
/// `libraw_processed_image_t` { type 0 (int), height 4, width 6, colors 8,
/// bits 10 (all u16), data_size 12 (u32), data 16 }.
final class RawCodec {
  RawCodec._(this._r);

  factory RawCodec.open({LibRawBindings? bindings}) => _instance ??= RawCodec._(
    bindings ?? LibRawBindings(NativeLibraries.open(NativeLibrary.raw)),
  );

  static RawCodec? _instance;

  final LibRawBindings _r;

  /// Development is refused above this many pixels.
  static const int maxPixels = 64 * 1000 * 1000;

  String _err(int code) => _r.libraw_strerror(code).cast<Utf8>().toDartString();

  void _check(int code, String what) {
    if (code != 0) throw RawException('$what: ${_err(code)}');
  }

  T _with<T>(Uint8List bytes, T Function(ffi.Pointer<LibRawData> lr) body) {
    final lr = _r.libraw_init(0);
    if (lr == ffi.nullptr) throw const RawException('cannot start LibRaw');
    final data = malloc<ffi.Uint8>(bytes.isEmpty ? 1 : bytes.length);
    try {
      data.asTypedList(bytes.length).setAll(0, bytes);
      _check(_r.libraw_open_buffer(lr, data.cast(), bytes.length), 'open');
      return body(lr);
    } finally {
      _r.libraw_close(lr);
      malloc.free(data);
    }
  }

  /// Sensor image size (before the camera's rotation).
  ({int width, int height}) size(Uint8List bytes) => _with(
    bytes,
    (lr) =>
        (width: _r.libraw_get_iwidth(lr), height: _r.libraw_get_iheight(lr)),
  );

  RawImage _copy(ffi.Pointer<ffi.Void> p) {
    final h16 = p.cast<ffi.Uint16>();
    final height = h16[2];
    final width = h16[3];
    final colors = h16[4];
    final bits = h16[5];
    final dataSize = p.cast<ffi.Uint32>()[3];
    if (bits != 8 || (colors != 3 && colors != 4)) {
      throw RawException('unexpected ${bits}bit $colors-colour output');
    }
    if (dataSize < width * height * colors) {
      throw const RawException('short output');
    }
    final src = (p.cast<ffi.Uint8>() + 16).asTypedList(width * height * colors);
    final out = Uint8List(width * height * 4);
    if (colors == 4) {
      out.setAll(0, src);
    } else {
      for (var i = 0, j = 0; i < src.length; i += 3, j += 4) {
        out[j] = src[i];
        out[j + 1] = src[i + 1];
        out[j + 2] = src[i + 2];
        out[j + 3] = 255;
      }
    }
    return RawImage(width, height, out);
  }

  /// Develops the file: demosaic, white balance from the camera, sRGB 8-bit,
  /// rotated upright.
  RawImage develop(Uint8List bytes) => _with(bytes, (lr) {
    final pixels = _r.libraw_get_iwidth(lr) * _r.libraw_get_iheight(lr);
    if (pixels > maxPixels) {
      throw RawException('too large to develop ($pixels pixels)');
    }
    _r
      ..libraw_set_output_bps(lr, 8)
      ..libraw_set_output_color(lr, 1) // sRGB
      ..libraw_set_demosaic(lr, 2); // PPG: fast and good enough on a phone
    _check(_r.libraw_unpack(lr), 'unpack');
    _check(_r.libraw_dcraw_process(lr), 'develop');
    final err = malloc<ffi.Int>();
    try {
      final img = _r.libraw_dcraw_make_mem_image(lr, err);
      if (img == ffi.nullptr) throw RawException('output: ${_err(err.value)}');
      try {
        return _copy(img);
      } finally {
        _r.libraw_dcraw_clear_mem(img);
      }
    } finally {
      malloc.free(err);
    }
  });

  /// The preview LibRaw extracts (CR3 and others whose previews are not in
  /// TIFF directories).
  RawThumbnail thumbnail(Uint8List bytes) => _with(bytes, (lr) {
    _check(_r.libraw_unpack_thumb(lr), 'thumbnail');
    final err = malloc<ffi.Int>();
    try {
      final t = _r.libraw_dcraw_make_mem_thumb(lr, err);
      if (t == ffi.nullptr) throw RawException('thumbnail: ${_err(err.value)}');
      try {
        final type = t.cast<ffi.Int32>()[0];
        if (type == LibRawImageFormat.jpeg) {
          final size = t.cast<ffi.Uint32>()[3];
          return RawThumbnail(
            jpeg: Uint8List.fromList(
              (t.cast<ffi.Uint8>() + 16).asTypedList(size),
            ),
          );
        }
        return RawThumbnail(image: _copy(t));
      } finally {
        _r.libraw_dcraw_clear_mem(t);
      }
    } finally {
      malloc.free(err);
    }
  });
}
