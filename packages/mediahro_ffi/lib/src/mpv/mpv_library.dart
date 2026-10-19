import 'dart:ffi';
import 'dart:io';

import 'package:mediahro_ffi/src/mpv/bindings/mpv_bindings.dart';
import 'package:mediahro_ffi/src/native/native_library.dart';
import 'package:meta/meta.dart';

/// Lowest libmpv client API the engine relies on (mpv 0.35). Newer
/// properties (Dolby Vision track fields, secondary-sub-delay) degrade to
/// "unavailable" on older builds instead of failing.
const int minimumMpvClientApi = (2 << 16) | 1;

/// Environment variable that points tests, the corpus harness and the perf
/// harness at a specific libmpv file (absolute path).
const String libmpvEnvironmentKey = 'MEDIAHRO_LIBMPV';

/// File names tried for libmpv on [os], in order.
///
/// The first entry is the `mediahro-deps` layout (docs/05 §10,
/// `nativeLibraryFileName`); the others are the bootstrap prebuilts allowed by
/// ADR-004 until the deps archives are pinned (media_kit xcframeworks and
/// dylibs on Apple, the LGPL `libmpv-2.dll` on Windows) and system installs
/// used only by desktop test runners.
@visibleForTesting
List<String> libmpvCandidates(String os) => switch (os) {
  'android' => const ['libmpv.so'],
  'ios' || 'macos' => const [
    'mpv.framework/mpv',
    'Mpv.framework/Mpv',
    'libmpv.2.dylib',
    'libmpv.dylib',
  ],
  'windows' => const ['mpv.dll', 'libmpv-2.dll'],
  'linux' => const ['libmpv.so', 'libmpv.so.2'],
  _ => const <String>[],
};

/// A loaded libmpv with its bindings.
final class Libmpv {
  Libmpv._(this.library, this.bindings, this.path);

  final DynamicLibrary library;
  final MpvBindings bindings;

  /// The name or path that was opened (shown in the info sheet).
  final String path;

  static Libmpv? _instance;

  /// Opens libmpv once per isolate; [path] (then `MEDIAHRO_LIBMPV`) is tried
  /// before the platform names.
  ///
  /// Throws [NativeLibraryUnavailable] when no candidate can be opened or the
  /// library is older than [minimumMpvClientApi]; callers map this to
  /// `EngineErrorCode.libraryMissing` (CORE-011).
  static Libmpv open({String? path}) => _instance ??= _load(path);

  /// Whether libmpv can be opened in this process.
  static bool isAvailable({String? path}) {
    try {
      open(path: path);
      return true;
    } on NativeLibraryUnavailable {
      return false;
    }
  }

  static Libmpv _load(String? path) {
    final override = Platform.environment[libmpvEnvironmentKey];
    final candidates = [
      ?path,
      if (override != null && override.isNotEmpty) override,
      ...libmpvCandidates(Platform.operatingSystem),
    ];
    final failures = <String>[];
    for (final name in candidates) {
      final DynamicLibrary lib;
      try {
        lib = DynamicLibrary.open(name);
        // DynamicLibrary.open reports a missing library only as ArgumentError.
        // ignore: avoid_catching_errors
      } on ArgumentError catch (e) {
        failures.add('$name: ${e.message}');
        continue;
      }
      final bindings = MpvBindings(lib);
      final version = bindings.mpv_client_api_version();
      if (version < minimumMpvClientApi) {
        throw NativeLibraryUnavailable(
          NativeLibrary.mpv,
          'libmpv client API ${version >> 16}.${version & 0xffff} at $name is '
          'older than ${minimumMpvClientApi >> 16}.'
          '${minimumMpvClientApi & 0xffff}',
        );
      }
      return Libmpv._(lib, bindings, name);
    }
    throw NativeLibraryUnavailable(NativeLibrary.mpv, failures.join('; '));
  }
}
