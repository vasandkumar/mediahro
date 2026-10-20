import 'dart:typed_data';

import 'package:mediahro/platform/android/gen/text_api.pigeon.dart';
import 'package:mediahro/platform/text_services.dart';

/// [SpeechSynthesisFacade] on Android (SUB-040): the system TextToSpeech
/// engine, offline voices only, rate relative to the user's default
/// (`SpeechModule.kt`).
final class AndroidSpeechSynthesis implements SpeechSynthesisFacade {
  AndroidSpeechSynthesis({SpeechHostApi? api}) : _api = api ?? SpeechHostApi();

  final SpeechHostApi _api;

  @override
  Future<List<SpeechVoice>> voices() async => [
    for (final v in await _api.voices())
      SpeechVoice(id: v.id, name: v.name, languageTag: v.languageTag),
  ];

  @override
  Future<void> speak(
    String text, {
    String? languageTag,
    String? voiceId,
    double rate = 1,
  }) => _api.speak(text, languageTag, voiceId, rate);

  @override
  Future<void> stop() => _api.stop();
}

/// [TextRecognitionFacade] on Android (SUB-051): ML Kit in the `store` and
/// `direct` builds (Latin, Chinese, Devanagari, Japanese, Korean scripts);
/// [isSupported] is false in `foss`/`enterprise`, or without Google Play
/// services, and SUB-051 then uses Tesseract (`TextServices.kt`).
final class AndroidTextRecognition implements TextRecognitionFacade {
  AndroidTextRecognition({TextRecognitionHostApi? api})
    : _api = api ?? TextRecognitionHostApi();

  final TextRecognitionHostApi _api;

  @override
  Future<bool> isSupported(String languageTag) => _api.isSupported(languageTag);

  @override
  Future<List<RecognizedLine>> recognize(
    Uint8List rgba, {
    required int width,
    required int height,
    List<String> languageTags = const [],
  }) async => [
    for (final l in await _api.recognize(rgba, width, height, languageTags))
      RecognizedLine(l.text, l.confidence, l.left, l.top, l.width, l.height),
  ];

  @override
  Future<String?> identifyLanguage(String text) => _api.identifyLanguage(text);
}

/// [TranslationFacade] on Android (SUB-053): ML Kit on-device translation
/// in the `store` and `direct` builds. Models download only through
/// [prepare], after the user agreed (PRIV-004); [translate] never
/// downloads. Unavailable (no pairs) in `foss`/`enterprise`.
final class AndroidTranslation implements TranslationFacade {
  AndroidTranslation({TranslationHostApi? api})
    : _api = api ?? TranslationHostApi();

  final TranslationHostApi _api;

  @override
  Future<List<TranslationPair>> supportedPairs() async => [
    for (final p in await _api.supportedPairs()) TranslationPair(p.from, p.to),
  ];

  @override
  Future<bool> isReady(String from, String to) => _api.isReady(from, to);

  @override
  Future<void> prepare(String from, String to) => _api.prepare(from, to);

  @override
  Future<List<String>> translate(
    List<String> lines, {
    required String from,
    required String to,
  }) => _api.translate(lines, from, to);
}
