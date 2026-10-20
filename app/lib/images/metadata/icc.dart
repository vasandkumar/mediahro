import 'dart:convert';
import 'dart:typed_data';

import 'package:mediahro/images/metadata/bytes.dart';

/// The human-readable description of an ICC profile (its `desc` tag, v2
/// text or v4 multi-localised), or null when unreadable. Used for the info
/// sheet and the colour-managed viewer's profile badge (IMG-006).
String? iccDescription(Uint8List icc) {
  try {
    final v = ByteView(icc);
    if (icc.length < 132) return null;
    final count = v.u32(128);
    for (var i = 0; i < count && i < 200; i++) {
      final e = 132 + i * 12;
      if (v.fourCC(e) != 'desc') continue;
      final off = v.u32(e + 4);
      final size = v.u32(e + 8);
      if (off + size > icc.length || size < 12) return null;
      final type = v.fourCC(off);
      if (type == 'desc') {
        final n = v.u32(off + 8);
        final end = off + 12 + n;
        if (n < 1 || end > off + size) return null;
        return latin1
            .decode(icc.sublist(off + 12, end))
            .replaceAll('\u0000', '')
            .trim();
      }
      if (type == 'mluc') {
        final recs = v.u32(off + 8);
        if (recs < 1) return null;
        final len = v.u32(off + 20);
        final strOff = v.u32(off + 24);
        final s = off + strOff;
        if (s + len > icc.length) return null;
        final units = <int>[for (var k = 0; k + 1 < len; k += 2) v.u16(s + k)];
        return String.fromCharCodes(units).trim();
      }
      return null;
    }
  } on MetadataFormatException {
    return null;
  }
  return null;
}
