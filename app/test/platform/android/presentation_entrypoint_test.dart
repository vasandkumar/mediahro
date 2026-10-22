import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mediahro/platform/android/bindings.dart' as android;
import 'package:mediahro/platform/android/presentation_main.dart';

/// The native side starts the external display's engine by function and
/// library name (`PresentationModule.kt`). A function that is not in
/// `main.dart` can only be found with its library, and a mismatch shows as a
/// blank screen on the display with no error (batch 6, IMG-012), so the two
/// names are checked against the Dart source.
void main() {
  final kotlin = File(
    'android/app/src/main/kotlin/com/mediahro/mediahro/platform/display/PresentationModule.kt',
  ).readAsStringSync();

  String constant(String name) =>
      RegExp('const val $name = "([^"]+)"').firstMatch(kotlin)!.group(1)!;

  test('IMG-012 the native entrypoint names a Dart function that exists', () {
    final library = constant('ENTRYPOINT_LIBRARY');
    final function = constant('ENTRYPOINT');
    expect(library, startsWith('package:mediahro/'));
    final path = 'lib/${library.substring('package:mediahro/'.length)}';
    final source = File(path).readAsStringSync().replaceAll('\r\n', '\n');
    expect(
      source,
      contains("@pragma('vm:entry-point')\nvoid $function()"),
      reason: '$path must define $function() with the entry-point pragma',
    );
  });

  test('IMG-012 the module starts the engine with the library as well', () {
    expect(
      kotlin,
      contains('DartEntrypoint(bundle, ENTRYPOINT_LIBRARY, ENTRYPOINT)'),
      reason: 'the two-argument form looks in main.dart only',
    );
  });

  test('IMG-012 the entrypoint is kept in the compiled program', () {
    expect(android.nativeEntryPoints, contains(presentationMain));
  });
}
