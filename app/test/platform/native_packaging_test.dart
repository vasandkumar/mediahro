import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The native libraries the Dart code opens (`NativeLibraries.open`) must be
/// packaged in the Android app. Gradle packages the DT_NEEDED closure of libmpv
/// plus the roots in `mediahroNativeLibs`; a library that libmpv does not pull
/// in and that is not listed is simply absent on the phone, and every feature
/// built on it skips as "library missing" (batch 6: libarchive, libebur128,
/// libchromaprint, libsmb2 and libnfs). This keeps the two in step.
void main() {
  // Libraries the app opens but deliberately does not package yet, and why.
  const notPackaged = {
    'curl':
        'no app feature opens libcurl yet (FTP and WebDAV are Dart clients)',
    'whisper': 'speech models are downloaded on demand (SUB-052), not built in',
    'tesseract': 'on-device OCR is not offered on Android yet (ADR-034)',
    'cld3': 'on-device language detection is not offered on Android yet',
    'bergamot': 'on-device translation is not offered on Android yet',
  };
  // Pulled in by libmpv's own DT_NEEDED closure (libuchardet is one of them).
  const viaMpv = {'mpv', 'uchardet'};

  Set<String> packagedRoots() {
    final line = File('android/gradle.properties')
        .readAsLinesSync()
        .firstWhere((l) => l.startsWith('mediahroNativeLibs='));
    return line
        .substring('mediahroNativeLibs='.length)
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toSet();
  }

  Set<String> opened() {
    final open = RegExp(r'NativeLibraries\.open\(\s*NativeLibrary\.(\w+)\s*\)');
    return {
      for (final f
          in Directory('../packages/mediahro_ffi/lib/src')
              .listSync(recursive: true)
              .whereType<File>()
              .where((f) => f.path.endsWith('.dart')))
        for (final m in open.allMatches(f.readAsStringSync())) m.group(1)!,
    };
  }

  test(
    'LIB-014/FILE-004/NET-001/NET-002 every library the app opens is packaged',
    () {
      final roots = packagedRoots();
      final missing = [
        for (final name in opened())
          if (!viaMpv.contains(name) &&
              !notPackaged.containsKey(name) &&
              !roots.contains('lib$name.so'))
            'lib$name.so',
      ];
      expect(
        missing,
        isEmpty,
        reason:
            'add them to mediahroNativeLibs in android/gradle.properties '
            '(or to notPackaged here, with the reason)',
      );
    },
  );

  test('the five libraries batch 6 found missing are packaged', () {
    expect(
      packagedRoots(),
      containsAll([
        'libarchive.so',
        'libebur128.so',
        'libchromaprint.so',
        'libsmb2.so',
        'libnfs.so',
      ]),
    );
  });

  test('the image libraries stay packaged', () {
    expect(
      packagedRoots(),
      containsAll([
        'libvips.so',
        'libjxl.so',
        'libjxl_threads.so',
        'libavif.so',
        'libraw.so',
      ]),
    );
  });

  test(
    'a library that is not packaged names its reason and is still opened',
    () {
      final used = opened();
      for (final name in notPackaged.keys) {
        expect(
          used.contains(name) || name == 'whisper',
          isTrue,
          reason:
              '$name is listed as not packaged but nothing opens it any more',
        );
      }
    },
  );

  test(
    'every packaged root exists in the pinned archive, when it is fetched',
    () {
      final dir = Directory('../.deps-cache/android-arm64-v8a/lib');
      if (!dir.existsSync()) {
        markTestSkipped('run tools/deps/fetch.py to check against the archive');
        return;
      }
      for (final root in packagedRoots()) {
        expect(File('${dir.path}/$root').existsSync(), isTrue, reason: root);
      }
    },
  );
}
