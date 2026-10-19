import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mediahro_engine/mediahro_engine.dart';
import 'package:mediahro_ffi/src/mpv/mpv.dart';

/// Where the engine conformance suites run (docs/11 §1).
///
/// The same suites run under `flutter test` on desktop runners (FFI contract
/// tests) and inside the engine example app on Android, iOS, macOS and
/// Windows (integration tests), so every AC is proven per platform by CI.
final class ConformanceEnv {
  ConformanceEnv({
    required this.corpusDir,
    required String? manifestJson,
    this.libmpvPath,
    this.prepare,
    this.renderBridge,
    this.platformName = 'desktop',
  }) : _manifest = manifestJson;

  /// Desktop `flutter test`: the repository's generated corpus and the
  /// libmpv from `MEDIAHRO_LIBMPV`, `.deps-cache` or the ADR-004 bootstrap.
  factory ConformanceEnv.desktop() {
    final root = repoRoot;
    final dir =
        Platform.environment['MEDIAHRO_CORPUS_DIR'] ??
        '$root/test-media/generated';
    final manifest = File('$dir/manifest.json');
    return ConformanceEnv(
      corpusDir: dir,
      manifestJson: manifest.existsSync() ? manifest.readAsStringSync() : null,
      libmpvPath: _desktopLibmpv(root),
      platformName: Platform.operatingSystem,
    );
  }

  static ConformanceEnv? current;

  final String corpusDir;
  final String? _manifest;
  final String? libmpvPath;

  /// Copies the corpus into [corpusDir] (device runs); called in setUpAll.
  final Future<void> Function()? prepare;

  /// Set when suites run in the example app with a real render bridge.
  final RenderBridge? renderBridge;
  final String platformName;

  Map<String, Object?>? get manifest =>
      _manifest == null ? null : jsonDecode(_manifest) as Map<String, Object?>;

  static String? _desktopLibmpv(String root) {
    if (Platform.environment[libmpvEnvironmentKey] != null) return null;
    final candidates = [
      if (Platform.isWindows) ...[
        '$root/.deps-cache/windows-x64/lib/mpv.dll',
        '$root/.deps-cache/bootstrap/windows-x64/lib/libmpv-2.dll',
      ],
      if (Platform.isMacOS)
        '$root/.deps-cache/bootstrap/macos-dylibs/lib/libmpv.dylib',
    ];
    return candidates.where((p) => File(p).existsSync()).firstOrNull;
  }
}

ConformanceEnv get env => ConformanceEnv.current ??= ConformanceEnv.desktop();

/// Why the suites cannot run here, or null when they can.
String? get ffiSkipReason {
  if (!Libmpv.isAvailable(path: env.libmpvPath)) {
    return 'libmpv not available (set MEDIAHRO_LIBMPV)';
  }
  if (env.manifest == null) {
    return 'corpus not generated (tools/corpus/generate.dart)';
  }
  return null;
}

/// Registers the corpus preparation step for the enclosing suite.
void prepareCorpus() {
  final prepare = env.prepare;
  if (prepare != null) setUpAll(prepare);
}

/// Repository root (desktop tests run with the package as working directory).
String get repoRoot {
  var dir = Directory.current;
  while (!File('${dir.path}/deps.lock').existsSync()) {
    final parent = dir.parent;
    if (parent.path == dir.path) return Directory.current.path;
    dir = parent;
  }
  return dir.path;
}

/// One manifest entry.
final class CorpusItem {
  CorpusItem(this.file, this.category, this.ids, this.expect);

  final String file;
  final String? category;
  final List<String> ids;
  final Map<String, Object?> expect;

  String get path => corpusPath(file);
  Uri get uri => Uri.file(path);

  @override
  String toString() => file;
}

List<CorpusItem> corpusItems({String? category, String? id}) {
  final json = env.manifest;
  if (json == null) return const [];
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

/// Path of a generated file (manifest item or helper such as `subs.srt`).
String corpusPath(String name) =>
    '${env.corpusDir}${Platform.pathSeparator}$name';

/// A headless engine: software renderer and null audio unless overridden
/// (e.g. `ao=pcm` to capture output).
MpvEngine headlessEngine({
  EngineRole role = EngineRole.video,
  Map<String, String> extraOptions = const {},
  bool nullAudio = true,
  (int, int) size = (320, 180),
  void Function(String line)? log,
}) => MpvEngine(
  role,
  config: MpvEngineConfig(
    video: role == EngineRole.video
        ? VideoOutputMode.software
        : VideoOutputMode.none,
    nullAudio: nullAudio,
    softwareSize: size,
    extraOptions: extraOptions,
    libmpvPath: env.libmpvPath,
    logLevel: log == null ? 'warn' : 'v',
    onLog: log == null ? null : (m) => log('$m'),
  ),
);

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

/// Waits until playback has visibly started (or failed / ended).
Future<PlaybackState> waitPlaying(PlaybackEngine e, {String? reason}) =>
    waitFor(
      e,
      (s) =>
          s.status == PlaybackStatus.error ||
          s.status == PlaybackStatus.ended ||
          (s.status == PlaybackStatus.playing && s.position > Duration.zero),
      reason: reason ?? 'playing',
    );

/// Reads a property directly from the engine's core.
Future<Object?> prop(MpvEngine engine, String name) =>
    engine.client!.getProperty(name);

/// Opens [file] in a fresh headless engine that is disposed after the test.
Future<MpvEngine> openItem(
  String file, {
  OpenOptions? opts,
  Map<String, String> extraOptions = const {},
  EngineRole role = EngineRole.video,
}) async {
  final e = headlessEngine(extraOptions: extraOptions, role: role);
  addTearDown(e.dispose);
  await e.open(UriSource(Uri.file(corpusPath(file))), opts: opts);
  return e;
}
