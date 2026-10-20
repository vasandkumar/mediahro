import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mediahro/platform/android/android_caption_style.dart';
import 'package:mediahro/platform/platform_bindings.dart';
import 'package:mediahro/platform/platform_facades.dart';

/// Lane C4a: CaptionStyleFacade on an Android device (ADR-030, SUB-014):
/// the system caption settings come through CaptioningManager. The values
/// are the phone's own (Settings > Accessibility > Caption preferences).
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final android = Platform.isAndroid;

  testWidgets('SUB-014 Android bindings provide the system caption style', (
    tester,
  ) async {
    final c = ProviderContainer(overrides: platformOverrides());
    addTearDown(c.dispose);
    expect(c.read(captionStyleProvider), isA<AndroidCaptionStyle>());
  }, skip: !android);

  testWidgets('SUB-014 the system caption style is readable and well formed', (
    tester,
  ) async {
    final captions = AndroidCaptionStyle();
    final style = await captions.current();
    expect(style, isNotNull, reason: 'CaptioningManager exists on phones');
    expect(style!.scale, greaterThan(0));
    for (final argb in [
      style.foregroundArgb,
      style.backgroundArgb,
      style.windowArgb,
      style.edgeArgb,
    ]) {
      if (argb != null) expect(argb, inInclusiveRange(0, 0xFFFFFFFF));
    }
    expect(CaptionEdge.values, contains(style.edge));
    // Listening registers a CaptioningChangeListener; cancelling removes it.
    final sub = captions.changes.listen((_) {});
    await Future<void>.delayed(const Duration(milliseconds: 200));
    await sub.cancel();
  }, skip: !android);
}
