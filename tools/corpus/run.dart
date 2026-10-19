// Media corpus harness (docs/11 §1), lane B1. Called by the nightly
// workflow:
//
//   dart run tools/corpus/run.dart --report build/corpus-report.json
//
// 1. libmpv: the mediahro-deps archive (.deps-cache/<target>) or the ADR-004
//    bootstrap (packages/mediahro_engine/tool/fetch_libmpv.py).
// 2. Corpus: test-media/generated (tools/corpus/generate.dart) unless
//    MEDIAHRO_CORPUS_DIR points elsewhere; ffmpeg from --ffmpeg, PATH, or the
//    bootstrap build on Windows.
// 3. Drives MpvEngine headless over every file through
//    packages/mediahro_engine/test/corpus_harness_test.dart and writes the
//    JSON report.
import 'dart:io';

Future<void> main(List<String> args) async {
  String? opt(String name) {
    final i = args.indexOf(name);
    return i >= 0 && i + 1 < args.length ? args[i + 1] : null;
  }

  final root = File.fromUri(Platform.script).parent.parent.parent;
  final report = File(opt('--report') ?? 'build/corpus-report.json').absolute;
  final py = await _python();
  final env = <String, String>{'MEDIAHRO_CORPUS_REPORT': report.path};

  final target = switch (Platform.operatingSystem) {
    'windows' => ('windows-x64', 'lib/libmpv-2.dll', 'windows-x64/lib/mpv.dll'),
    'macos' => ('macos-dylibs', 'lib/libmpv.dylib', null),
    _ => (null, null, null),
  };
  if (target.$1 != null) {
    final deps = target.$3 == null
        ? null
        : File('${root.path}/.deps-cache/${target.$3}');
    if (deps != null && deps.existsSync()) {
      env['MEDIAHRO_LIBMPV'] = deps.path;
    } else {
      final dir = await _run(py, [
        '${root.path}/packages/mediahro_engine/tool/fetch_libmpv.py',
        '--print-path',
        target.$1!,
      ]);
      env['MEDIAHRO_LIBMPV'] = '${dir.trim().split('\n').last}/${target.$2}';
      env['DYLD_FALLBACK_LIBRARY_PATH'] = '${dir.trim().split('\n').last}/lib';
    }
  } else if (!File('/usr/lib/x86_64-linux-gnu/libmpv.so.2').existsSync()) {
    stdout.writeln(
      '::notice::corpus: no libmpv for ${Platform.operatingSystem} '
      '(Linux desktop is 1.2, ADR-010); nothing to run',
    );
    return;
  }

  final corpus = Directory(
    Platform.environment['MEDIAHRO_CORPUS_DIR'] ??
        '${root.path}/test-media/generated',
  );
  if (!File('${corpus.path}/manifest.json').existsSync()) {
    var ffmpeg = opt('--ffmpeg') ?? 'ffmpeg';
    if (Platform.isWindows && opt('--ffmpeg') == null) {
      final dir = await _run(py, [
        '${root.path}/packages/mediahro_engine/tool/fetch_libmpv.py',
        '--print-path',
        'ffmpeg-windows-x64',
      ]);
      ffmpeg = '${dir.trim().split('\n').last}/bin/ffmpeg.exe';
    }
    await _run(Platform.resolvedExecutable, [
      'run',
      '${root.path}/tools/corpus/generate.dart',
      '--ffmpeg',
      ffmpeg,
      '--out',
      corpus.path,
    ]);
  }
  env['MEDIAHRO_CORPUS_DIR'] = corpus.path;

  final flutter = Platform.isWindows ? 'flutter.bat' : 'flutter';
  final p = await Process.start(
    flutter,
    ['test', 'test/corpus_harness_test.dart', '--reporter', 'expanded'],
    workingDirectory: '${root.path}/packages/mediahro_engine',
    environment: env,
    mode: ProcessStartMode.inheritStdio,
    runInShell: Platform.isWindows,
  );
  final code = await p.exitCode;
  stdout.writeln('corpus: report ${report.path}');
  exitCode = code;
}

Future<String> _python() async {
  for (final c in ['python3', 'python']) {
    try {
      final r = await Process.run(c, ['--version']);
      if (r.exitCode == 0) return c;
    } on ProcessException {
      continue;
    }
  }
  throw StateError('python 3 is required for tool/fetch_libmpv.py');
}

Future<String> _run(String exe, List<String> args) async {
  final r = await Process.run(exe, args);
  if (r.exitCode != 0) {
    stderr
      ..write(r.stdout)
      ..write(r.stderr);
    throw ProcessException(exe, args, 'exit ${r.exitCode}', r.exitCode);
  }
  return r.stdout as String;
}
