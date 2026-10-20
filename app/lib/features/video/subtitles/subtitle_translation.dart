import 'package:mediahro/features/video/player/languages.dart';
import 'package:mediahro/platform/platform_facades.dart';
import 'package:mediahro_subtitles/mediahro_subtitles.dart';

/// On-device subtitle translation (SUB-053) through the platform's
/// `TranslationFacade` (Apple Translation, ML Kit, Windows). Text never
/// leaves the device; downloading a language pack is a network step the
/// user agrees to first.
final class SubtitleTranslator {
  SubtitleTranslator(this.translation, {this.batch = 50});

  final TranslationFacade translation;

  /// Lines per call, so long files show progress and stay responsive.
  final int batch;

  Future<List<TranslationPair>> _pairs() => translation.supportedPairs();

  /// Languages subtitles can be translated from (ISO 639-1).
  Future<List<String>> sources() async =>
      {for (final p in await _pairs()) ?primaryLanguage(p.from)}.toList();

  /// Languages [from] can be translated into.
  Future<List<String>> targetsFor(String from) async => {
    for (final p in await _pairs())
      if (primaryLanguage(p.from) == from) ?primaryLanguage(p.to),
  }.toList();

  /// True when the pair's model must be downloaded first (ask the user).
  Future<bool> needsDownload(String from, String to) async =>
      !await translation.isReady(from, to);

  /// Downloads the pair's model; call only after the user agreed.
  Future<void> download(String from, String to) =>
      translation.prepare(from, to);

  /// [doc] with every line translated, same times, as plain SRT text.
  Future<SubtitleDocument> translate(
    SubtitleDocument doc, {
    required String from,
    required String to,
    void Function(double done)? onProgress,
  }) async {
    final lines = [for (final c in doc.cues) c.plainText];
    final out = <String>[];
    for (var i = 0; i < lines.length; i += batch) {
      final chunk = lines.sublist(i, (i + batch).clamp(0, lines.length));
      final translated = await translation.translate(chunk, from: from, to: to);
      if (translated.length != chunk.length) {
        throw StateError('translation changed the line count');
      }
      out.addAll(translated);
      onProgress?.call(out.length / lines.length);
    }
    return SubtitleDocument(
      format: SubtitleFormat.srt,
      cues: [
        for (final (i, c) in doc.cues.indexed)
          SubtitleCue(start: c.start, end: c.end, text: out[i]),
      ],
    );
  }
}
