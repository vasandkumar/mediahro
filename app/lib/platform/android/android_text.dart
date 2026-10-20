import 'package:mediahro/platform/android/gen/text_api.pigeon.dart';
import 'package:mediahro/platform/text_services.dart';

/// [SpeechSynthesisFacade] on Android (SUB-040): the system TextToSpeech
/// engine, offline voices only, rate relative to the user's default
/// (`SpeechModule.kt`). Every flavour. OCR, language ID and translation
/// are the open services from `openTextServiceOverrides` (ADR-034).
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
