// Pigeon messages for SpeechSynthesisFacade, TextRecognitionFacade and
// TranslationFacade on Android (lane C4a, SUB-040, SUB-051, SUB-053,
// ADR-025 §5: ML Kit only in the store and direct builds).
//
//   dart run pigeon --input pigeons/android/text_api.dart   (from app/)

import 'package:pigeon/pigeon.dart';

@ConfigurePigeon(
  PigeonOptions(
    dartOut: 'lib/platform/android/gen/text_api.pigeon.dart',
    kotlinOut:
        'android/app/src/main/kotlin/com/mediahro/mediahro/pigeon/TextApi.g.kt',
    kotlinOptions: KotlinOptions(
      // Shares FlutterError with StorageApi.g.kt.
      package: 'com.mediahro.mediahro.pigeon',
      includeErrorClass: false,
    ),
    dartPackageName: 'mediahro',
  ),
)
class SpeechVoiceMsg {
  SpeechVoiceMsg(this.id, this.name, this.languageTag);
  String id;
  String name;
  String languageTag;
}

class RecognizedLineMsg {
  RecognizedLineMsg(
    this.text,
    this.confidence,
    this.left,
    this.top,
    this.width,
    this.height,
  );
  String text;
  double confidence;
  int left;
  int top;
  int width;
  int height;
}

class TranslationPairMsg {
  TranslationPairMsg(this.from, this.to);
  String from;
  String to;
}

@HostApi()
abstract class SpeechHostApi {
  @async
  List<SpeechVoiceMsg> voices();

  /// Completes when the utterance ends or is stopped.
  @async
  void speak(String text, String? languageTag, String? voiceId, double rate);

  void stop();
}

@HostApi()
abstract class TextRecognitionHostApi {
  @async
  bool isSupported(String languageTag);

  @async
  List<RecognizedLineMsg> recognize(
    Uint8List rgba,
    int width,
    int height,
    List<String> languageTags,
  );

  @async
  String? identifyLanguage(String text);
}

@HostApi()
abstract class TranslationHostApi {
  List<TranslationPairMsg> supportedPairs();

  @async
  bool isReady(String from, String to);

  /// Downloads the pair's models (call only after the user agreed).
  @async
  void prepare(String from, String to);

  @async
  List<String> translate(List<String> lines, String from, String to);
}
