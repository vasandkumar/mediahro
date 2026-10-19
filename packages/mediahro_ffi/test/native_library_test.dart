import 'package:mediahro_ffi/mediahro_ffi.dart';
import 'package:mediahro_ffi/src/native/native_library.dart'
    show nativeLibraryFileName;
import 'package:test/test.dart';

void main() {
  test('every LGPL library is dynamic-only (docs/09 §2)', () {
    for (final lib in NativeLibrary.values) {
      if (lib.licence.startsWith('LGPL')) {
        expect(lib.dynamicOnly, isTrue, reason: lib.name);
      }
      expect(
        lib.licence,
        isNot(startsWith('GPL')),
        reason: 'no GPL in binaries (ADR-002)',
      );
    }
  });

  test('file names follow the mediahro-deps archive layout', () {
    expect(
      nativeLibraryFileName(NativeLibrary.mpv, os: 'android'),
      'libmpv.so',
    );
    expect(nativeLibraryFileName(NativeLibrary.mpv, os: 'windows'), 'mpv.dll');
    expect(
      nativeLibraryFileName(NativeLibrary.vips, os: 'ios'),
      'vips.framework/vips',
    );
  });

  test('missing library is reported, not thrown as a crash', () {
    // No native deps are bundled into the Dart test runner.
    expect(NativeLibraries.isAvailable(NativeLibrary.whisper), isFalse);
  });
}
