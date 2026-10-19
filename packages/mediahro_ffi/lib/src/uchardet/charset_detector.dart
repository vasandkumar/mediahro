import 'dart:ffi' as ffi;
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:mediahro_ffi/src/native/native_library.dart';
import 'package:mediahro_ffi/src/uchardet/uchardet_bindings.dart';

/// Detects the charset of legacy text (playlists, subtitles, NFO):
/// returns an IANA-ish name such as `WINDOWS-1251`, `SHIFT_JIS`, `GB18030`,
/// `UTF-8`, or null when unsure. Reads at most [maxBytes].
String? detectCharset(
  Uint8List bytes, {
  int maxBytes = 256 * 1024,
  UchardetBindings? bindings,
}) {
  final b =
      bindings ??
      UchardetBindings(NativeLibraries.open(NativeLibrary.uchardet));
  final ud = b.uchardet_new();
  if (ud == ffi.nullptr) return null;
  final n = bytes.length < maxBytes ? bytes.length : maxBytes;
  final p = calloc<ffi.Uint8>(n == 0 ? 1 : n);
  try {
    p.asTypedList(n).setAll(0, Uint8List.sublistView(bytes, 0, n));
    if (b.uchardet_handle_data(ud, p.cast(), n) != 0) return null;
    b.uchardet_data_end(ud);
    final name = b.uchardet_get_charset(ud).cast<Utf8>().toDartString();
    return name.isEmpty ? null : name.toUpperCase();
  } finally {
    calloc.free(p);
    b.uchardet_delete(ud);
  }
}
