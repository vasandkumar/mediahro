import 'dart:ffi' as ffi;
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:mediahro_ffi/src/native/native_library.dart';
import 'package:mediahro_ffi/src/tesseract/tesseract_bindings.dart';
import 'package:meta/meta.dart';

/// One recognised line of text and its box in image pixels.
@immutable
final class OcrLine {
  const OcrLine(
    this.text,
    this.confidence,
    this.left,
    this.top,
    this.width,
    this.height,
  );

  final String text;

  /// 0…1.
  final double confidence;
  final int left;
  final int top;
  final int width;
  final int height;
}

/// Converts subtitle RGBA (light text with a dark outline on a transparent
/// background, as DVD, Blu-ray and DVB subtitles are) into 8-bit grey with
/// dark text on white, which is what Tesseract reads best. Transparent
/// pixels become white.
Uint8List subtitleToGrey(Uint8List rgba, int width, int height) {
  if (rgba.length < width * height * 4) {
    throw ArgumentError.value(rgba.length, 'rgba', 'shorter than w × h × 4');
  }
  final out = Uint8List(width * height);
  for (var i = 0, p = 0; i < out.length; i++, p += 4) {
    final a = rgba[p + 3];
    // Luma (BT.601) composited over black, then inverted.
    final y = (rgba[p] * 299 + rgba[p + 1] * 587 + rgba[p + 2] * 114) ~/ 1000;
    out[i] = 255 - (y * a ~/ 255);
  }
  return out;
}

/// Tesseract with its language data loaded, for one thread at a time.
/// Create it inside a worker isolate: recognising a frame takes tens to
/// hundreds of milliseconds (PRIV-005, nothing heavy on the UI isolate).
final class TesseractOcr {
  TesseractOcr._(this._b, this._api);

  /// Loads [languages] (Tesseract codes such as `eng`, `deu`, `chi_sim`)
  /// from [tessdata], the folder holding the `.traineddata` files.
  /// Throws [NativeLibraryUnavailable] without Tesseract in the build and
  /// [StateError] when the data can't be loaded.
  factory TesseractOcr.open(
    String tessdata,
    List<String> languages, {
    TesseractBindings? bindings,
  }) {
    if (languages.isEmpty) throw ArgumentError('no languages');
    final b =
        bindings ??
        TesseractBindings(NativeLibraries.open(NativeLibrary.tesseract));
    final api = b.TessBaseAPICreate();
    if (api == ffi.nullptr) throw StateError('TessBaseAPICreate failed');
    final path = tessdata.toNativeUtf8();
    final langs = languages.join('+').toNativeUtf8();
    try {
      if (b.TessBaseAPIInit3(api, path.cast(), langs.cast()) != 0) {
        b.TessBaseAPIDelete(api);
        throw StateError('Tesseract could not load ${languages.join('+')}');
      }
    } finally {
      calloc
        ..free(path)
        ..free(langs);
    }
    // Subtitles are one block of one or two centred lines.
    b.TessBaseAPISetPageSegMode(api, TessPageSegMode.PSM_SINGLE_BLOCK);
    return TesseractOcr._(b, api);
  }

  final TesseractBindings _b;
  ffi.Pointer<TessBaseAPI> _api;

  /// Recognises 8-bit grey [grey], [width] × [height], line by line.
  List<OcrLine> recognize(Uint8List grey, int width, int height) {
    if (_api == ffi.nullptr) throw StateError('closed');
    if (grey.length < width * height) {
      throw ArgumentError.value(grey.length, 'grey', 'shorter than w × h');
    }
    final b = _b;
    final img = calloc<ffi.UnsignedChar>(width * height);
    final box = calloc<ffi.Int>(4);
    final lines = <OcrLine>[];
    try {
      img.cast<ffi.Uint8>().asTypedList(width * height).setAll(0, grey);
      b.TessBaseAPISetImage(_api, img, width, height, 1, width);
      if (b.TessBaseAPIRecognize(_api, ffi.nullptr) != 0) return const [];
      final it = b.TessBaseAPIGetIterator(_api);
      if (it == ffi.nullptr) return const [];
      const level = TessPageIteratorLevel.RIL_TEXTLINE;
      try {
        do {
          final p = b.TessResultIteratorGetUTF8Text(it, level);
          if (p == ffi.nullptr) continue;
          final text = p.cast<Utf8>().toDartString().trim();
          b.TessDeleteText(p);
          if (text.isEmpty) continue;
          final conf = b.TessResultIteratorConfidence(it, level) / 100;
          final page = b.TessResultIteratorGetPageIterator(it);
          b.TessPageIteratorBoundingBox(
            page,
            level,
            box,
            box + 1,
            box + 2,
            box + 3,
          );
          lines.add(
            OcrLine(
              text,
              conf.clamp(0, 1).toDouble(),
              box[0],
              box[1],
              box[2] - box[0],
              box[3] - box[1],
            ),
          );
        } while (b.TessResultIteratorNext(it, level) != 0);
      } finally {
        b.TessResultIteratorDelete(it);
      }
      return lines;
    } finally {
      b.TessBaseAPIClear(_api);
      calloc
        ..free(img)
        ..free(box);
    }
  }

  void close() {
    if (_api == ffi.nullptr) return;
    _b
      ..TessBaseAPIEnd(_api)
      ..TessBaseAPIDelete(_api);
    _api = ffi.nullptr;
  }
}
