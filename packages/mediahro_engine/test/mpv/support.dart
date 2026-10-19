import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:mediahro_engine/mediahro_engine.dart';
import 'package:mediahro_ffi/src/mpv/mpv.dart';

/// Why FFI contract tests cannot run here, or null when they can.
///
/// They need libmpv (`MEDIAHRO_LIBMPV`, the `.deps-cache` archives or the
/// ADR-004 bootstrap) and the generated corpus (`tools/corpus/generate.dart`).
/// CI's engine workflow provides both on Windows and macOS; the plain unit
/// job skips them.
String? get ffiSkipReason {
  if (!_libmpvFound) return 'libmpv not available (set MEDIAHRO_LIBMPV)';
  if (corpusDir == null) {
    return 'corpus not generated (tools/corpus/generate.dart)';
  }
  return null;
}

final bool _libmpvFound = () {
  if (Platform.environment[libmpvEnvironmentKey] == null) {
    final bootstrap = _bootstrapLibmpv();
    if (bootstrap == null) return Libmpv.isAvailable();
    // Tests and the harness read MEDIAHRO_LIBMPV; point it at the bootstrap.
    _bootstrapPath = bootstrap;
  }
  return Libmpv.isAvailable(path: _bootstrapPath);
}();

String? _bootstrapPath;

String? _bootstrapLibmpv() {
  final root = repoRoot;
  final candidates = [
    if (Platform.isWindows) ...[
      '$root/.deps-cache/windows-x64/lib/mpv.dll',
      '$root/.deps-cache/bootstrap/windows-x64/lib/libmpv-2.dll',
    ],
    if (Platform.isMacOS) ...[
      '$root/.deps-cache/bootstrap/macos-dylibs/lib/libmpv.dylib',
    ],
  ];
  return candidates.where((p) => File(p).existsSync()).firstOrNull;
}

/// Repository root (tests run with the package as working directory).
String get repoRoot {
  var dir = Directory.current;
  while (!File('${dir.path}/deps.lock').existsSync()) {
    final parent = dir.parent;
    if (parent.path == dir.path) return Directory.current.path;
    dir = parent;
  }
  return dir.path;
}

/// Generated corpus directory, or null.
final Directory? corpusDir = () {
  final env = Platform.environment['MEDIAHRO_CORPUS_DIR'];
  final dir = Directory(env ?? '$repoRoot/test-media/generated');
  return File('${dir.path}/manifest.json').existsSync() ? dir : null;
}();

/// One manifest entry.
final class CorpusItem {
  CorpusItem(this.file, this.category, this.ids, this.expect);

  final String file;
  final String? category;
  final List<String> ids;
  final Map<String, Object?> expect;

  String get path => '${corpusDir!.path}${Platform.pathSeparator}$file';
  Uri get uri => Uri.file(path);

  @override
  String toString() => file;
}

List<CorpusItem> corpusItems({String? category, String? id}) {
  final dir = corpusDir;
  if (dir == null) return const [];
  final json = jsonDecode(
    File('${dir.path}/manifest.json').readAsStringSync(),
  ) as Map<String, Object?>;
  return [
    for (final i in (json['items']! as List).cast<Map<String, Object?>>())
      CorpusItem(
        i['file']! as String,
        i['category'] as String?,
        (i['ids']! as List).cast<String>(),
        (i['expect']! as Map).cast<String, Object?>(),
      ),
  ].where((i) {
    if (category != null && i.category != category) return false;
    if (id != null && !i.ids.contains(id)) return false;
    return true;
  }).toList();
}

CorpusItem corpusFile(String name) =>
    corpusItems().firstWhere((i) => i.file == name);

/// Path of a generated file that is not a manifest item (e.g. `subs.srt`).
String corpusPath(String name) =>
    '${corpusDir!.path}${Platform.pathSeparator}$name';

/// A headless engine: software renderer, null audio unless `extraOptions`
/// replace it (e.g. `ao=pcm` to capture output).
MpvEngine headlessEngine({
  EngineRole role = EngineRole.video,
  Map<String, String> extraOptions = const {},
  bool nullAudio = true,
  (int, int) size = (320, 180),
  void Function(String line)? log,
}) {
  final path = _bootstrapPath;
  return MpvEngine(
    role,
    config: MpvEngineConfig(
      video: role == EngineRole.video
          ? VideoOutputMode.software
          : VideoOutputMode.none,
      nullAudio: nullAudio,
      softwareSize: size,
      extraOptions: extraOptions,
      libmpvPath: path,
      logLevel: log == null ? 'warn' : 'v',
      onLog: log == null ? null : (m) => log('$m'),
    ),
  );
}

/// Waits until [engine]'s state satisfies [test].
Future<PlaybackState> waitFor(
  PlaybackEngine engine,
  bool Function(PlaybackState s) test, {
  Duration timeout = const Duration(seconds: 15),
  String? reason,
}) async {
  if (test(engine.current)) return engine.current;
  return await engine.state
      .firstWhere(test)
      .timeout(
        timeout,
        onTimeout: () => throw TimeoutException(
          'waiting for ${reason ?? 'state'}; last: ${engine.current}',
        ),
      );
}

/// Reads a property directly from the engine's core.
Future<Object?> prop(MpvEngine engine, String name) =>
    engine.client!.getProperty(name);
