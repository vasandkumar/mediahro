import 'dart:typed_data';

import 'package:meta/meta.dart';

/// Formats handled by Mediahro's own parsers (SUB-010). Image formats
/// (PGS, VobSub, DVB) are rendered by the engine and reach this package only
/// for OCR (SUB-051).
enum SubtitleFormat {
  srt,
  webvtt,
  ass,
  ssa,
  smi,
  microDvd,
  ttml,
  lrc,
  txt,
  pgs,
  vobSub,
  dvb,
}

/// Maps a file extension to a format; `null` when unknown.
SubtitleFormat? subtitleFormatForExtension(String extension) =>
    switch (extension.toLowerCase().replaceFirst('.', '')) {
      'srt' => SubtitleFormat.srt,
      'vtt' || 'webvtt' => SubtitleFormat.webvtt,
      'ass' => SubtitleFormat.ass,
      'ssa' => SubtitleFormat.ssa,
      'smi' || 'sami' => SubtitleFormat.smi,
      'sub' => SubtitleFormat.microDvd,
      'ttml' || 'dfxp' || 'xml' => SubtitleFormat.ttml,
      'lrc' => SubtitleFormat.lrc,
      'txt' => SubtitleFormat.txt,
      'sup' => SubtitleFormat.pgs,
      'idx' => SubtitleFormat.vobSub,
      _ => null,
    };

@immutable
final class SubtitleCue {
  const SubtitleCue({
    required this.start,
    required this.end,
    required this.text,
    this.style,
  });

  final Duration start;
  final Duration end;

  /// Plain text with `\n` line breaks; markup is in [style] for ASS.
  final String text;
  final String? style;

  @override
  bool operator ==(Object other) =>
      other is SubtitleCue &&
      other.start == start &&
      other.end == end &&
      other.text == text &&
      other.style == style;

  @override
  int get hashCode => Object.hash(start, end, text, style);
}

@immutable
final class SubtitleDocument {
  const SubtitleDocument({
    required this.format,
    required this.cues,
    this.header,
  });

  final SubtitleFormat format;
  final List<SubtitleCue> cues;

  /// Raw script/style header kept for lossless ASS round-trips (SUB-030).
  final String? header;
}

/// Limits applied to every parse (PRIV-005).
@immutable
final class ParseLimits {
  const ParseLimits({
    this.maxBytes = 20 * 1024 * 1024,
    this.maxCues = 200000,
    this.timeout = const Duration(seconds: 10),
  });

  final int maxBytes;
  final int maxCues;
  final Duration timeout;
}

final class SubtitleParseException implements Exception {
  const SubtitleParseException(this.message);

  final String message;

  @override
  String toString() => 'SubtitleParseException: $message';
}

/// Contract for text-subtitle parsers. Implementations are pure and are run
/// inside an isolate by `parseSubtitlesIsolated` (lane C1).
abstract interface class SubtitleParser {
  Set<SubtitleFormat> get formats;

  /// Parses decoded text (charset detection happens before, SUB-013).
  SubtitleDocument parse(
    String text, {
    ParseLimits limits = const ParseLimits(),
  });

  /// Serialises for the editor's "save as" (SUB-030).
  String write(SubtitleDocument document);
}

/// Decodes raw bytes to text with charset detection (uchardet, SUB-013).
abstract interface class SubtitleDecoder {
  String decode(Uint8List bytes, {String? overrideCharset});
}
