import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// docs/07 §3.1 on the Android manifest (lane C4a): the store-policy guard
/// (tools/compliance) forbids; this asserts what must be there.
void main() {
  final manifest = File('android/app/src/main/AndroidManifest.xml')
      .readAsStringSync();
  bool has(String permission) =>
      manifest.contains('android:name="android.permission.$permission"');

  test('SYS-007 READ_MEDIA_* declared, partial access handled', () {
    for (final p in [
      'READ_MEDIA_AUDIO',
      'READ_MEDIA_VIDEO',
      'READ_MEDIA_IMAGES',
      'READ_MEDIA_VISUAL_USER_SELECTED',
    ]) {
      expect(has(p), isTrue, reason: p);
    }
  });

  test('SYS-007 legacy storage permission stops at API 32', () {
    expect(
      RegExp(r'READ_EXTERNAL_STORAGE"\s+android:maxSdkVersion="32"')
          .hasMatch(manifest),
      isTrue,
    );
    expect(manifest.contains('WRITE_EXTERNAL_STORAGE'), isFalse);
  });

  test('SYS-007 never all-files access', () {
    expect(manifest.contains('MANAGE_EXTERNAL_STORAGE'), isFalse);
    expect(manifest.contains('requestLegacyExternalStorage'), isFalse);
  });

  test('FILE-002 FileProvider shares app-private files', () {
    expect(manifest.contains('androidx.core.content.FileProvider'), isTrue);
    expect(manifest.contains(r'${applicationId}.files'), isTrue);
  });
}
