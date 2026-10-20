import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mediahro/platform/android/android_text.dart';
import 'package:mediahro/platform/platform_bindings.dart';
import 'package:mediahro/platform/platform_facades.dart';

/// Lane C4a: speech, text recognition and translation on an Android device.
/// ML Kit ships only in the `store` and `direct` builds (ADR-025 §5); in
/// `foss` and `enterprise` the facades report unsupported, and SUB-051 uses
/// Tesseract. Run with `--flavor store --dart-define=MEDIAHRO_FLAVOR=store`
/// to exercise ML Kit, and with `foss` for the fallback contract.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final android = Platform.isAndroid;
  const flavor = String.fromEnvironment(
    'MEDIAHRO_FLAVOR',
    defaultValue: 'foss',
  );
  const mlKit = flavor == 'store' || flavor == 'direct';

  /// White text on black, as RGBA, the way subtitle bitmaps arrive.
  Future<(Uint8List, int, int)> renderText(String text) async {
    const width = 640;
    const height = 120;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)
      ..drawRect(
        const Rect.fromLTWH(0, 0, width + 0.0, height + 0.0),
        Paint()..color = const Color(0xFF000000),
      );
    TextPainter(
        text: TextSpan(
          text: text,
          style: const TextStyle(color: Color(0xFFFFFFFF), fontSize: 56),
        ),
        textDirection: TextDirection.ltr,
      )
      ..layout(maxWidth: width - 40)
      ..paint(canvas, const Offset(20, 25))
      ..dispose();
    final image = await recorder.endRecording().toImage(width, height);
    final bytes = await image.toByteData();
    return (bytes!.buffer.asUint8List(), width, height);
  }

  testWidgets('SUB-040 Android bindings provide the text services', (
    tester,
  ) async {
    final c = ProviderContainer(overrides: platformOverrides());
    addTearDown(c.dispose);
    expect(c.read(speechSynthesisProvider), isA<AndroidSpeechSynthesis>());
    expect(c.read(textRecognitionProvider), isA<AndroidTextRecognition>());
    expect(c.read(translationProvider), isA<AndroidTranslation>());
  }, skip: !android);

  testWidgets('SUB-040 offline voices and a short utterance', (tester) async {
    final speech = AndroidSpeechSynthesis();
    final voices = await speech.voices();
    for (final v in voices) {
      expect(v.languageTag, isNotEmpty);
    }
    // Speaks "OK" once, then completes when the utterance ends.
    await speech
        .speak('OK', languageTag: 'en-US')
        .timeout(const Duration(seconds: 20));
    await speech.stop();
  }, skip: !android);

  testWidgets('SUB-051 ML Kit reads text from a subtitle bitmap', (
    tester,
  ) async {
    final ocr = AndroidTextRecognition();
    if (!await ocr.isSupported('en')) {
      return markTestSkipped('Google Play services unavailable');
    }
    final (rgba, w, h) = await renderText('HELLO WORLD');
    // The recogniser module may still be downloading on first use.
    final deadline = DateTime.now().add(const Duration(seconds: 90));
    while (true) {
      try {
        final lines = await ocr.recognize(
          rgba,
          width: w,
          height: h,
          languageTags: const ['en'],
        );
        final text = lines.map((l) => l.text).join(' ').toUpperCase();
        expect(text, contains('HELLO'));
        expect(lines.first.width, greaterThan(0));
        expect(lines.first.confidence, inInclusiveRange(0, 1));
        break;
      } on PlatformException catch (e) {
        if (DateTime.now().isAfter(deadline)) rethrow;
        debugPrint('OCR not ready yet: ${e.message}');
        await Future<void>.delayed(const Duration(seconds: 5));
      }
    }
  }, skip: !android || !mlKit);

  testWidgets('SUB-053 ML Kit identifies a language on the device', (
    tester,
  ) async {
    final ocr = AndroidTextRecognition();
    final deadline = DateTime.now().add(const Duration(seconds: 90));
    String? tag;
    while (tag == null && DateTime.now().isBefore(deadline)) {
      tag = await ocr.identifyLanguage(
        'Ceci est une phrase écrite en français pour le test.',
      );
      if (tag == null) await Future<void>.delayed(const Duration(seconds: 5));
    }
    expect(tag, 'fr');
  }, skip: !android || !mlKit);

  testWidgets(
    'SUB-053 translation lists pairs and never downloads implicitly',
    (tester) async {
      final translation = AndroidTranslation();
      final pairs = await translation.supportedPairs();
      expect(pairs.any((p) => p.from == 'en' && p.to == 'de'), isTrue);
      if (!await translation.isReady('de', 'fr')) {
        await expectLater(
          translation.translate(['Hallo'], from: 'de', to: 'fr'),
          throwsA(
            isA<PlatformException>().having((e) => e.code, 'code', 'notReady'),
          ),
        );
      }
    },
    skip: !android || !mlKit,
  );

  testWidgets('SUB-051 builds without ML Kit report unsupported', (
    tester,
  ) async {
    final ocr = AndroidTextRecognition();
    expect(await ocr.isSupported('en'), isFalse);
    expect(await ocr.identifyLanguage('Hello there'), isNull);
    expect(await AndroidTranslation().supportedPairs(), isEmpty);
  }, skip: !android || mlKit);
}
