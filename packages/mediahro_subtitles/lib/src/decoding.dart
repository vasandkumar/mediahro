import 'dart:convert';
import 'dart:typed_data';

import 'package:mediahro_subtitles/src/codepages.dart';
import 'package:mediahro_subtitles/src/subtitle_parser.dart';

/// Character sets [decodeSubtitleText] can decode: Unicode plus the
/// single-byte code pages (SUB-013, SUB-030 "fix encoding").
Set<String> get decodableCharsets => {
  'utf-8',
  'utf-16le',
  'utf-16be',
  'iso-8859-1',
  ...singleByteCodepages.keys,
};

/// Bytes to text for the editor and parsers (SUB-013):
///
/// - a byte-order mark decides (UTF-8, UTF-16 LE/BE) and is dropped;
/// - [charset] forces a character set ("fix encoding");
/// - otherwise strict UTF-8, then [fallback] (Windows-1252 unless the
///   caller's detector, e.g. uchardet in the app, says otherwise).
///
/// Throws [SubtitleParseException] for an unknown [charset].
String decodeSubtitleText(
  Uint8List bytes, {
  String? charset,
  String fallback = 'cp1252',
}) {
  if (bytes.length >= 3 &&
      bytes[0] == 0xEF &&
      bytes[1] == 0xBB &&
      bytes[2] == 0xBF) {
    return utf8.decode(bytes.sublist(3), allowMalformed: true);
  }
  if (bytes.length >= 2 && bytes[0] == 0xFF && bytes[1] == 0xFE) {
    return _utf16(bytes.sublist(2), little: true);
  }
  if (bytes.length >= 2 && bytes[0] == 0xFE && bytes[1] == 0xFF) {
    return _utf16(bytes.sublist(2), little: false);
  }
  if (charset != null) return decodeWith(bytes, charset);
  try {
    return utf8.decode(bytes);
  } on FormatException {
    return decodeWith(bytes, fallback);
  }
}

/// Decodes [bytes] as [charset] exactly.
String decodeWith(Uint8List bytes, String charset) {
  final name = charset.toLowerCase().replaceAll('_', '-');
  switch (name) {
    case 'utf-8' || 'utf8':
      return utf8.decode(bytes, allowMalformed: true);
    case 'utf-16' || 'utf-16le':
      return _utf16(bytes, little: true);
    case 'utf-16be':
      return _utf16(bytes, little: false);
    case 'iso-8859-1' || 'latin1':
      return latin1.decode(bytes);
  }
  final table =
      singleByteCodepages[name] ??
      singleByteCodepages[name.replaceFirst('windows-', 'cp')];
  if (table == null) {
    throw SubtitleParseException('unsupported character set $charset');
  }
  final out = StringBuffer();
  for (final b in bytes) {
    out.writeCharCode(b < 0x80 ? b : table.codeUnitAt(b - 0x80));
  }
  return out.toString();
}

String _utf16(Uint8List b, {required bool little}) {
  final units = Uint16List(b.length ~/ 2);
  for (var i = 0; i < units.length; i++) {
    final lo = b[2 * i];
    final hi = b[2 * i + 1];
    units[i] = little ? (hi << 8) | lo : (lo << 8) | hi;
  }
  return String.fromCharCodes(units);
}

/// Text to bytes for saving: UTF-8 with a BOM so every player recognises
/// it (SUB-030).
Uint8List encodeSubtitleText(String text) =>
    Uint8List.fromList([0xEF, 0xBB, 0xBF, ...utf8.encode(text)]);
