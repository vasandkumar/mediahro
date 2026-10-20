// Pigeon messages for SpeechSynthesisFacade on Android (lane C4a, SUB-040).
// OCR, language ID and translation are the open Dart FFI services
// (ADR-034), not platform code.
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

@HostApi()
abstract class SpeechHostApi {
  @async
  List<SpeechVoiceMsg> voices();

  /// Completes when the utterance ends or is stopped.
  @async
  void speak(String text, String? languageTag, String? voiceId, double rate);

  void stop();
}
