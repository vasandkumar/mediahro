import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mediahro/platform/android/android_text.dart';
import 'package:mediahro/platform/platform_bindings.dart';
import 'package:mediahro/platform/platform_facades.dart';

/// Lane C4a: speech on an Android device, every flavour (SUB-040). OCR,
/// language ID and translation are the open services (ADR-034), tested
/// with C1's text worker.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final android = Platform.isAndroid;

  testWidgets('SUB-040 Android bindings provide speech synthesis', (
    tester,
  ) async {
    final c = ProviderContainer(overrides: platformOverrides());
    addTearDown(c.dispose);
    expect(c.read(speechSynthesisProvider), isA<AndroidSpeechSynthesis>());
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
}
