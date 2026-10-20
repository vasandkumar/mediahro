import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediahro/features/video/text/open_text_services.dart';
import 'package:mediahro/platform/android/android_text.dart';
import 'package:mediahro/platform/android/bindings.dart' as android;
import 'package:mediahro/platform/android/gen/text_api.pigeon.dart';
import 'package:mediahro/platform/platform_facades.dart';

/// The Dart half of lane C4a's speech; OCR and translation are the open
/// services (ADR-034).
final class _FakeSpeech extends SpeechHostApi {
  final spoken = <Object?>[];

  @override
  Future<List<SpeechVoiceMsg>> voices() async => [
    SpeechVoiceMsg(id: 'en-us-x-1', name: 'en-us-x-1', languageTag: 'en-US'),
  ];

  @override
  Future<void> speak(
    String text,
    String? languageTag,
    String? voiceId,
    double rate,
  ) async => spoken.addAll([text, languageTag, voiceId, rate]);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('SUB-040 voices and speak parameters cross unchanged', () async {
    final api = _FakeSpeech();
    final s = AndroidSpeechSynthesis(api: api);
    expect((await s.voices()).single.languageTag, 'en-US');
    await s.speak('Hi', languageTag: 'en-GB', rate: 1.25);
    expect(api.spoken, ['Hi', 'en-GB', null, 1.25]);
  });

  test('SUB-051 ADR-034 Android uses the open OCR and translation', () {
    final c = ProviderContainer(overrides: android.overrides());
    addTearDown(c.dispose);
    expect(c.read(speechSynthesisProvider), isA<AndroidSpeechSynthesis>());
    expect(c.read(textRecognitionProvider), isA<OpenTextRecognition>());
    expect(c.read(translationProvider), isA<OpenTranslation>());
  });
}
