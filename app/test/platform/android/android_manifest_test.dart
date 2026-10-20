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

  test('IMG-015 wallpaper permission is the normal one, nothing broader', () {
    expect(has('SET_WALLPAPER'), isTrue);
    expect(has('SET_WALLPAPER_HINTS'), isFalse);
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

  test('SYS-006 mediaPlayback foreground service for the Media3 session', () {
    expect(has('FOREGROUND_SERVICE'), isTrue);
    expect(has('FOREGROUND_SERVICE_MEDIA_PLAYBACK'), isTrue);
    expect(has('POST_NOTIFICATIONS'), isTrue);
    expect(
      RegExp(
        r'PlaybackService"\s+android:exported="true"\s+android:foregroundServiceType="mediaPlayback"',
      ).hasMatch(manifest),
      isTrue,
    );
    expect(
      manifest.contains('androidx.media3.session.MediaLibraryService'),
      isTrue,
    );
  });

  test('CORE-001 predictive back is enabled for the app', () {
    expect(
      manifest.contains('android:enableOnBackInvokedCallback="true"'),
      isTrue,
    );
  });

  test(
    'MUS-013 Android Auto media app, browsed through the library service',
    () {
      expect(
        manifest.contains('com.google.android.gms.car.application'),
        isTrue,
      );
      expect(
        File('android/app/src/main/res/xml/automotive_app_desc.xml')
            .readAsStringSync()
            .contains('<uses name="media" />'),
        isTrue,
      );
    },
  );

  test('MUS-011 wake alarms: exact alarms and a private receiver', () {
    expect(has('SCHEDULE_EXACT_ALARM'), isTrue);
    expect(
      RegExp(r'AlarmReceiver"\s+android:exported="false"').hasMatch(manifest),
      isTrue,
    );
    // USE_EXACT_ALARM is reserved for alarm-clock apps on Play.
    expect(has('USE_EXACT_ALARM'), isFalse);
  });

  test('CORE-003 open with and SYS-004 share targets; URIs are not routes', () {
    for (final action in ['VIEW', 'SEND', 'SEND_MULTIPLE']) {
      expect(
        manifest.contains('android.intent.action.$action"'),
        isTrue,
        reason: action,
      );
    }
    expect(
      manifest.contains('android:mimeType="application/x-subrip"'),
      isTrue,
    );
    expect(manifest.contains('android:scheme="rtsp"'), isTrue);
    expect(
      RegExp(r'flutter_deeplinking_enabled"\s+android:value="false"')
          .hasMatch(manifest),
      isTrue,
    );
  });

  test('SYS-003 App Actions for every build id', () {
    expect(manifest.contains('android.app.shortcuts'), isTrue);
    final main = File('android/app/src/main/res/xml/shortcuts.xml')
        .readAsStringSync();
    final enterprise = File('android/app/src/enterprise/res/xml/shortcuts.xml')
        .readAsStringSync();
    expect(main.contains('targetPackage="com.mediahro.app"'), isTrue);
    expect(
      enterprise.contains('targetPackage="com.mediahro.app.enterprise"'),
      isTrue,
    );
    for (final xml in [main, enterprise]) {
      expect(xml.contains('actions.intent.OPEN_APP_FEATURE'), isTrue);
      expect(xml.contains('actions.intent.GET_THING'), isTrue);
    }
  });
}
