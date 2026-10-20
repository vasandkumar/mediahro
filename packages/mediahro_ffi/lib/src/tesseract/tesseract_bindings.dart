// ignore_for_file: type=lint, unused_field

// Written by hand to match what `package:ffigen` generates from
// ffigen/tesseract.yaml (Tesseract 5.5.3 `include/tesseract/capi.h`): no
// libclang on the machine that wrote it, and the headers arrive with
// mediahro-deps v2026.10.5. Regenerate once they are in .deps-cache:
//   (cd packages/mediahro_ffi && dart run ffigen --config ffigen/tesseract.yaml)
import 'dart:ffi' as ffi;

/// Bindings to Tesseract's C API (OCR, SUB-051; ADR-034).
class TesseractBindings {
  /// Holds the symbol lookup function.
  final ffi.Pointer<T> Function<T extends ffi.NativeType>(String symbolName)
  _lookup;

  /// The symbols are looked up in [dynamicLibrary].
  TesseractBindings(ffi.DynamicLibrary dynamicLibrary)
    : _lookup = dynamicLibrary.lookup;

  /// The symbols are looked up with [lookup].
  TesseractBindings.fromLookup(
    ffi.Pointer<T> Function<T extends ffi.NativeType>(String symbolName) lookup,
  ) : _lookup = lookup;

  ffi.Pointer<ffi.Char> TessVersion() {
    return _TessVersion();
  }

  late final _TessVersionPtr =
      _lookup<ffi.NativeFunction<ffi.Pointer<ffi.Char> Function()>>(
        'TessVersion',
      );
  late final _TessVersion =
      _TessVersionPtr.asFunction<ffi.Pointer<ffi.Char> Function()>();

  void TessDeleteText(ffi.Pointer<ffi.Char> text) {
    return _TessDeleteText(text);
  }

  late final _TessDeleteTextPtr =
      _lookup<ffi.NativeFunction<ffi.Void Function(ffi.Pointer<ffi.Char>)>>(
        'TessDeleteText',
      );
  late final _TessDeleteText =
      _TessDeleteTextPtr.asFunction<void Function(ffi.Pointer<ffi.Char>)>();

  ffi.Pointer<TessBaseAPI> TessBaseAPICreate() {
    return _TessBaseAPICreate();
  }

  late final _TessBaseAPICreatePtr =
      _lookup<ffi.NativeFunction<ffi.Pointer<TessBaseAPI> Function()>>(
        'TessBaseAPICreate',
      );
  late final _TessBaseAPICreate =
      _TessBaseAPICreatePtr.asFunction<ffi.Pointer<TessBaseAPI> Function()>();

  void TessBaseAPIDelete(ffi.Pointer<TessBaseAPI> handle) {
    return _TessBaseAPIDelete(handle);
  }

  late final _TessBaseAPIDeletePtr =
      _lookup<ffi.NativeFunction<ffi.Void Function(ffi.Pointer<TessBaseAPI>)>>(
        'TessBaseAPIDelete',
      );
  late final _TessBaseAPIDelete =
      _TessBaseAPIDeletePtr.asFunction<
        void Function(ffi.Pointer<TessBaseAPI>)
      >();

  /// Returns 0 on success. [datapath] is the `tessdata` directory.
  int TessBaseAPIInit3(
    ffi.Pointer<TessBaseAPI> handle,
    ffi.Pointer<ffi.Char> datapath,
    ffi.Pointer<ffi.Char> language,
  ) {
    return _TessBaseAPIInit3(handle, datapath, language);
  }

  late final _TessBaseAPIInit3Ptr =
      _lookup<
        ffi.NativeFunction<
          ffi.Int Function(
            ffi.Pointer<TessBaseAPI>,
            ffi.Pointer<ffi.Char>,
            ffi.Pointer<ffi.Char>,
          )
        >
      >('TessBaseAPIInit3');
  late final _TessBaseAPIInit3 =
      _TessBaseAPIInit3Ptr.asFunction<
        int Function(
          ffi.Pointer<TessBaseAPI>,
          ffi.Pointer<ffi.Char>,
          ffi.Pointer<ffi.Char>,
        )
      >();

  void TessBaseAPISetPageSegMode(ffi.Pointer<TessBaseAPI> handle, int mode) {
    return _TessBaseAPISetPageSegMode(handle, mode);
  }

  late final _TessBaseAPISetPageSegModePtr =
      _lookup<
        ffi.NativeFunction<
          ffi.Void Function(ffi.Pointer<TessBaseAPI>, ffi.UnsignedInt)
        >
      >('TessBaseAPISetPageSegMode');
  late final _TessBaseAPISetPageSegMode =
      _TessBaseAPISetPageSegModePtr.asFunction<
        void Function(ffi.Pointer<TessBaseAPI>, int)
      >();

  int TessBaseAPISetVariable(
    ffi.Pointer<TessBaseAPI> handle,
    ffi.Pointer<ffi.Char> name,
    ffi.Pointer<ffi.Char> value,
  ) {
    return _TessBaseAPISetVariable(handle, name, value);
  }

  late final _TessBaseAPISetVariablePtr =
      _lookup<
        ffi.NativeFunction<
          ffi.Int Function(
            ffi.Pointer<TessBaseAPI>,
            ffi.Pointer<ffi.Char>,
            ffi.Pointer<ffi.Char>,
          )
        >
      >('TessBaseAPISetVariable');
  late final _TessBaseAPISetVariable =
      _TessBaseAPISetVariablePtr.asFunction<
        int Function(
          ffi.Pointer<TessBaseAPI>,
          ffi.Pointer<ffi.Char>,
          ffi.Pointer<ffi.Char>,
        )
      >();

  void TessBaseAPISetImage(
    ffi.Pointer<TessBaseAPI> handle,
    ffi.Pointer<ffi.UnsignedChar> imagedata,
    int width,
    int height,
    int bytes_per_pixel,
    int bytes_per_line,
  ) {
    return _TessBaseAPISetImage(
      handle,
      imagedata,
      width,
      height,
      bytes_per_pixel,
      bytes_per_line,
    );
  }

  late final _TessBaseAPISetImagePtr =
      _lookup<
        ffi.NativeFunction<
          ffi.Void Function(
            ffi.Pointer<TessBaseAPI>,
            ffi.Pointer<ffi.UnsignedChar>,
            ffi.Int,
            ffi.Int,
            ffi.Int,
            ffi.Int,
          )
        >
      >('TessBaseAPISetImage');
  late final _TessBaseAPISetImage =
      _TessBaseAPISetImagePtr.asFunction<
        void Function(
          ffi.Pointer<TessBaseAPI>,
          ffi.Pointer<ffi.UnsignedChar>,
          int,
          int,
          int,
          int,
        )
      >();

  /// Returns 0 on success. [monitor] may be null.
  int TessBaseAPIRecognize(
    ffi.Pointer<TessBaseAPI> handle,
    ffi.Pointer<ETEXT_DESC> monitor,
  ) {
    return _TessBaseAPIRecognize(handle, monitor);
  }

  late final _TessBaseAPIRecognizePtr =
      _lookup<
        ffi.NativeFunction<
          ffi.Int Function(ffi.Pointer<TessBaseAPI>, ffi.Pointer<ETEXT_DESC>)
        >
      >('TessBaseAPIRecognize');
  late final _TessBaseAPIRecognize =
      _TessBaseAPIRecognizePtr.asFunction<
        int Function(ffi.Pointer<TessBaseAPI>, ffi.Pointer<ETEXT_DESC>)
      >();

  ffi.Pointer<TessResultIterator> TessBaseAPIGetIterator(
    ffi.Pointer<TessBaseAPI> handle,
  ) {
    return _TessBaseAPIGetIterator(handle);
  }

  late final _TessBaseAPIGetIteratorPtr =
      _lookup<
        ffi.NativeFunction<
          ffi.Pointer<TessResultIterator> Function(ffi.Pointer<TessBaseAPI>)
        >
      >('TessBaseAPIGetIterator');
  late final _TessBaseAPIGetIterator =
      _TessBaseAPIGetIteratorPtr.asFunction<
        ffi.Pointer<TessResultIterator> Function(ffi.Pointer<TessBaseAPI>)
      >();

  void TessBaseAPIClear(ffi.Pointer<TessBaseAPI> handle) {
    return _TessBaseAPIClear(handle);
  }

  late final _TessBaseAPIClearPtr =
      _lookup<ffi.NativeFunction<ffi.Void Function(ffi.Pointer<TessBaseAPI>)>>(
        'TessBaseAPIClear',
      );
  late final _TessBaseAPIClear =
      _TessBaseAPIClearPtr.asFunction<
        void Function(ffi.Pointer<TessBaseAPI>)
      >();

  void TessBaseAPIEnd(ffi.Pointer<TessBaseAPI> handle) {
    return _TessBaseAPIEnd(handle);
  }

  late final _TessBaseAPIEndPtr =
      _lookup<ffi.NativeFunction<ffi.Void Function(ffi.Pointer<TessBaseAPI>)>>(
        'TessBaseAPIEnd',
      );
  late final _TessBaseAPIEnd =
      _TessBaseAPIEndPtr.asFunction<void Function(ffi.Pointer<TessBaseAPI>)>();

  void TessResultIteratorDelete(ffi.Pointer<TessResultIterator> handle) {
    return _TessResultIteratorDelete(handle);
  }

  late final _TessResultIteratorDeletePtr =
      _lookup<
        ffi.NativeFunction<ffi.Void Function(ffi.Pointer<TessResultIterator>)>
      >('TessResultIteratorDelete');
  late final _TessResultIteratorDelete =
      _TessResultIteratorDeletePtr.asFunction<
        void Function(ffi.Pointer<TessResultIterator>)
      >();

  int TessResultIteratorNext(
    ffi.Pointer<TessResultIterator> handle,
    int level,
  ) {
    return _TessResultIteratorNext(handle, level);
  }

  late final _TessResultIteratorNextPtr =
      _lookup<
        ffi.NativeFunction<
          ffi.Int Function(ffi.Pointer<TessResultIterator>, ffi.UnsignedInt)
        >
      >('TessResultIteratorNext');
  late final _TessResultIteratorNext =
      _TessResultIteratorNextPtr.asFunction<
        int Function(ffi.Pointer<TessResultIterator>, int)
      >();

  ffi.Pointer<ffi.Char> TessResultIteratorGetUTF8Text(
    ffi.Pointer<TessResultIterator> handle,
    int level,
  ) {
    return _TessResultIteratorGetUTF8Text(handle, level);
  }

  late final _TessResultIteratorGetUTF8TextPtr =
      _lookup<
        ffi.NativeFunction<
          ffi.Pointer<ffi.Char> Function(
            ffi.Pointer<TessResultIterator>,
            ffi.UnsignedInt,
          )
        >
      >('TessResultIteratorGetUTF8Text');
  late final _TessResultIteratorGetUTF8Text =
      _TessResultIteratorGetUTF8TextPtr.asFunction<
        ffi.Pointer<ffi.Char> Function(ffi.Pointer<TessResultIterator>, int)
      >();

  /// 0…100.
  double TessResultIteratorConfidence(
    ffi.Pointer<TessResultIterator> handle,
    int level,
  ) {
    return _TessResultIteratorConfidence(handle, level);
  }

  late final _TessResultIteratorConfidencePtr =
      _lookup<
        ffi.NativeFunction<
          ffi.Float Function(ffi.Pointer<TessResultIterator>, ffi.UnsignedInt)
        >
      >('TessResultIteratorConfidence');
  late final _TessResultIteratorConfidence =
      _TessResultIteratorConfidencePtr.asFunction<
        double Function(ffi.Pointer<TessResultIterator>, int)
      >();

  ffi.Pointer<TessPageIterator> TessResultIteratorGetPageIterator(
    ffi.Pointer<TessResultIterator> handle,
  ) {
    return _TessResultIteratorGetPageIterator(handle);
  }

  late final _TessResultIteratorGetPageIteratorPtr =
      _lookup<
        ffi.NativeFunction<
          ffi.Pointer<TessPageIterator> Function(
            ffi.Pointer<TessResultIterator>,
          )
        >
      >('TessResultIteratorGetPageIterator');
  late final _TessResultIteratorGetPageIterator =
      _TessResultIteratorGetPageIteratorPtr.asFunction<
        ffi.Pointer<TessPageIterator> Function(ffi.Pointer<TessResultIterator>)
      >();

  int TessPageIteratorBoundingBox(
    ffi.Pointer<TessPageIterator> handle,
    int level,
    ffi.Pointer<ffi.Int> left,
    ffi.Pointer<ffi.Int> top,
    ffi.Pointer<ffi.Int> right,
    ffi.Pointer<ffi.Int> bottom,
  ) {
    return _TessPageIteratorBoundingBox(
      handle,
      level,
      left,
      top,
      right,
      bottom,
    );
  }

  late final _TessPageIteratorBoundingBoxPtr =
      _lookup<
        ffi.NativeFunction<
          ffi.Int Function(
            ffi.Pointer<TessPageIterator>,
            ffi.UnsignedInt,
            ffi.Pointer<ffi.Int>,
            ffi.Pointer<ffi.Int>,
            ffi.Pointer<ffi.Int>,
            ffi.Pointer<ffi.Int>,
          )
        >
      >('TessPageIteratorBoundingBox');
  late final _TessPageIteratorBoundingBox =
      _TessPageIteratorBoundingBoxPtr.asFunction<
        int Function(
          ffi.Pointer<TessPageIterator>,
          int,
          ffi.Pointer<ffi.Int>,
          ffi.Pointer<ffi.Int>,
          ffi.Pointer<ffi.Int>,
          ffi.Pointer<ffi.Int>,
        )
      >();
}

final class TessBaseAPI extends ffi.Opaque {}

final class TessResultIterator extends ffi.Opaque {}

final class TessPageIterator extends ffi.Opaque {}

final class ETEXT_DESC extends ffi.Opaque {}

/// `TessPageIteratorLevel`.
abstract final class TessPageIteratorLevel {
  static const RIL_BLOCK = 0;
  static const RIL_PARA = 1;
  static const RIL_TEXTLINE = 2;
  static const RIL_WORD = 3;
  static const RIL_SYMBOL = 4;
}

/// `TessPageSegMode` (the values the app uses).
abstract final class TessPageSegMode {
  static const PSM_AUTO = 3;
  static const PSM_SINGLE_BLOCK = 6;
  static const PSM_SINGLE_LINE = 7;
}
