import 'dart:convert';
import 'dart:typed_data';

/// ID3v2 text encodings (byte 0 of text frames).
enum Id3Encoding { latin1, utf16, utf16be, utf8 }

Id3Encoding id3Encoding(int b) => switch (b) {
  1 => Id3Encoding.utf16,
  2 => Id3Encoding.utf16be,
  3 => Id3Encoding.utf8,
  _ => Id3Encoding.latin1,
};

String decodeLatin1(List<int> b) => latin1.decode(b);

String decodeUtf8(List<int> b) => utf8.decode(b, allowMalformed: true);

/// UTF-16 with an optional BOM; [bigEndian] is the default without one.
String decodeUtf16(Uint8List b, {bool bigEndian = false}) {
  var be = bigEndian;
  var i = 0;
  if (b.length >= 2) {
    if (b[0] == 0xFF && b[1] == 0xFE) {
      be = false;
      i = 2;
    } else if (b[0] == 0xFE && b[1] == 0xFF) {
      be = true;
      i = 2;
    }
  }
  final units = <int>[];
  for (; i + 1 < b.length; i += 2) {
    final u = be ? (b[i] << 8) | b[i + 1] : b[i] | (b[i + 1] << 8);
    if (u == 0xFEFF && units.isEmpty) continue;
    units.add(u);
  }
  // String.fromCharCodes keeps lone surrogates; replace them.
  final s = String.fromCharCodes(units);
  return s.replaceAll(
    RegExp(
      r'[\uD800-\uDBFF](?![\uDC00-\uDFFF])|(?<![\uD800-\uDBFF])[\uDC00-\uDFFF]',
    ),
    '�',
  );
}

String decodeId3(Uint8List b, Id3Encoding e) => switch (e) {
  Id3Encoding.latin1 => decodeLatin1(b),
  Id3Encoding.utf16 => decodeUtf16(b),
  Id3Encoding.utf16be => decodeUtf16(b, bigEndian: true),
  Id3Encoding.utf8 => decodeUtf8(b),
};

int terminatorWidth(Id3Encoding e) =>
    e == Id3Encoding.utf16 || e == Id3Encoding.utf16be ? 2 : 1;

/// Index of the terminator for [e] at or after [from], or -1.
int findTerminator(Uint8List b, int from, Id3Encoding e) {
  if (terminatorWidth(e) == 1) {
    for (var i = from; i < b.length; i++) {
      if (b[i] == 0) return i;
    }
    return -1;
  }
  for (var i = from; i + 1 < b.length; i += 2) {
    if (b[i] == 0 && b[i + 1] == 0) return i;
  }
  return -1;
}

/// Reads a terminated string at [from]; returns it and the offset after the
/// terminator (or the end).
(String, int) readTerminated(Uint8List b, int from, Id3Encoding e) {
  if (from >= b.length) return ('', b.length);
  final t = findTerminator(b, from, e);
  final end = t < 0 ? b.length : t;
  final s = decodeId3(Uint8List.sublistView(b, from, end), e);
  return (s, t < 0 ? b.length : t + terminatorWidth(e));
}

/// Splits a text-frame body on the encoding's NUL separator (ID3v2.4 multi
/// values; v2.3 writers use it too).
List<String> splitId3Text(Uint8List b, Id3Encoding e) {
  final out = <String>[];
  var i = 0;
  while (i < b.length) {
    final (s, next) = readTerminated(b, i, e);
    out.add(s);
    if (next <= i) break;
    i = next;
  }
  return out;
}

/// Encoders for the writer (MUS-003).
Uint8List encodeUtf8(String s) => Uint8List.fromList(utf8.encode(s));

Uint8List encodeUtf16le(String s, {bool bom = true}) {
  final out = BytesBuilder(copy: false);
  if (bom) out.add(const [0xFF, 0xFE]);
  for (final u in s.codeUnits) {
    out.add([u & 0xFF, u >> 8]);
  }
  return out.toBytes();
}

/// Latin-1 when every character fits, otherwise null.
Uint8List? tryLatin1(String s) {
  for (final u in s.codeUnits) {
    if (u > 0xFF) return null;
  }
  return Uint8List.fromList(s.codeUnits);
}
