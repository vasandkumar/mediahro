import 'dart:typed_data';

import 'package:meta/meta.dart';

/// System text-to-speech (SUB-040): AVSpeechSynthesizer (I M),
/// android.speech.tts (A), Windows.Media.SpeechSynthesis (W). Honours the
/// user's system voice and rate unless overridden.
abstract interface class SpeechSynthesisFacade {
  Future<List<SpeechVoice>> voices();

  /// Speaks [text]; completes when the utterance ends or is stopped.
  /// [rate] is relative to the system default (1.0).
  Future<void> speak(
    String text, {
    String? languageTag,
    String? voiceId,
    double rate = 1,
  });

  Future<void> stop();
}

@immutable
final class SpeechVoice {
  const SpeechVoice({
    required this.id,
    required this.name,
    required this.languageTag,
  });

  final String id;
  final String name;

  /// BCP 47.
  final String languageTag;
}

/// On-device OCR for image subtitles (SUB-051): Vision (I M), ML Kit text
/// recognition (A, `store`/`direct` only), Windows.Media.Ocr (W). Builds
/// without a platform recogniser report [isSupported] false and SUB-051
/// uses the Tesseract fallback over FFI.
abstract interface class TextRecognitionFacade {
  Future<bool> isSupported(String languageTag);

  /// Recognises text in one subtitle bitmap. [rgba] is 8-bit RGBA,
  /// row-major, [width] × [height].
  Future<List<RecognizedLine>> recognize(
    Uint8List rgba, {
    required int width,
    required int height,
    List<String> languageTags = const [],
  });

  /// Best-guess language of [text] (BCP 47), or null.
  Future<String?> identifyLanguage(String text);
}

@immutable
final class RecognizedLine {
  const RecognizedLine(
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

/// On-device translation (SUB-053): Apple Translation (I M), ML Kit
/// translation (A, `store`/`direct`), Windows on-device translation where
/// present. Never sends text off the device; a language-pack download is a
/// network call the user confirms first (PRIV-004).
abstract interface class TranslationFacade {
  Future<List<TranslationPair>> supportedPairs();

  /// Whether the model for the pair is already on the device.
  Future<bool> isReady(String from, String to);

  /// Downloads the pair's model; call only after explicit consent.
  Future<void> prepare(String from, String to);

  /// Translates [lines], keeping order and count.
  Future<List<String>> translate(
    List<String> lines, {
    required String from,
    required String to,
  });
}

@immutable
final class TranslationPair {
  const TranslationPair(this.from, this.to);

  final String from;
  final String to;
}
