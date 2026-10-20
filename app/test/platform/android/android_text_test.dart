import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mediahro/platform/android/android_text.dart';
import 'package:mediahro/platform/android/gen/text_api.pigeon.dart';

/// The Dart half of lane C4a's text services.
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

final class _FakeOcr extends TextRecognitionHostApi {
  Object? last;

  @override
  Future<List<RecognizedLineMsg>> recognize(
    Uint8List rgba,
    int width,
    int height,
    List<String> languageTags,
  ) async {
    last = [rgba.length, width, height, languageTags];
    return [
      RecognizedLineMsg(
        text: 'HELLO',
        confidence: 0.9,
        left: 1,
        top: 2,
        width: 3,
        height: 4,
      ),
    ];
  }
}

final class _FakeTranslation extends TranslationHostApi {
  @override
  Future<List<TranslationPairMsg>> supportedPairs() async => [
    TranslationPairMsg(from: 'en', to: 'de'),
  ];

  @override
  Future<List<String>> translate(
    List<String> lines,
    String from,
    String to,
  ) async => [for (final l in lines) '$from>$to:$l'];
}

void main() {
  test('SUB-040 voices and speak parameters cross unchanged', () async {
    final api = _FakeSpeech();
    final s = AndroidSpeechSynthesis(api: api);
    expect((await s.voices()).single.languageTag, 'en-US');
    await s.speak('Hi', languageTag: 'en-GB', rate: 1.25);
    expect(api.spoken, ['Hi', 'en-GB', null, 1.25]);
  });

  test('SUB-051 recognised lines keep text, confidence and box', () async {
    final api = _FakeOcr();
    final lines = await AndroidTextRecognition(
      api: api,
    ).recognize(Uint8List(16), width: 2, height: 2, languageTags: const ['ja']);
    expect(api.last, [
      16,
      2,
      2,
      ['ja'],
    ]);
    final l = lines.single;
    expect(
      [l.text, l.confidence, l.left, l.top, l.width, l.height],
      ['HELLO', 0.9, 1, 2, 3, 4],
    );
  });

  test('SUB-053 pairs and translations keep order', () async {
    final t = AndroidTranslation(api: _FakeTranslation());
    expect((await t.supportedPairs()).single.to, 'de');
    expect(await t.translate(['a', 'b'], from: 'en', to: 'de'), [
      'en>de:a',
      'en>de:b',
    ]);
  });
}
