import 'package:flutter_test/flutter_test.dart';
import 'package:mediahro/platform/android/android_display.dart';
import 'package:mediahro/platform/display.dart';

void main() {
  test('IMG-012 presentation handles compare by value', () {
    const a = PresentationHandle(id: 1, displayId: '2');
    const b = PresentationHandle(id: 1, displayId: '2');
    expect(a, b);
    expect(a.hashCode, b.hashCode);
    expect(a, isNot(const PresentationHandle(id: 2, displayId: '2')));
    expect(a, isNot(const PresentationHandle(id: 1, displayId: '3')));
  });

  test('IMG-012 Android presentations return null until implemented', () async {
    final display = AndroidDisplay();
    expect(await display.openPresentation('1'), isNull);
    await display.closePresentation(
      const PresentationHandle(id: 1, displayId: '1'),
    );
  });
}
