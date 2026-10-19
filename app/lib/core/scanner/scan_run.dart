import 'dart:async';
import 'dart:isolate';

import 'package:mediahro/core/scanner/scan_model.dart';
import 'package:mediahro/core/scanner/walker.dart';
import 'package:mediahro_ffi/mediahro_ffi.dart';

/// Builds the file system for a scan inside the scan isolate. Must capture
/// only sendable state (URIs, option maps, resolved credentials).
typedef FileSystemFactory = VirtualFileSystem Function();

/// One walk-and-diff of a source on its own isolate (docs/05 §7: the UI
/// isolate never scans). Pausable and cancellable (LIB-003).
final class ScanRun {
  ScanRun._(this._control, this._progress, this.result);

  final SendPort _control;
  final Stream<(int, int)> _progress;

  /// The diff against the index; errors with [ScanCancelled] or a
  /// [VirtualFileException] when the root cannot be read.
  final Future<ScanDiff> result;

  /// `(files seen, directories seen)` while walking.
  Stream<(int, int)> get progress => _progress;

  void pause() => _control.send(_Control.pause);
  void resume() => _control.send(_Control.resume);
  void cancel() => _control.send(_Control.cancel);

  static Future<ScanRun> start({
    required Uri root,
    required FileSystemFactory fileSystem,
    required Map<String, KnownItem> known,
    ScanOptions options = const ScanOptions(),
  }) async {
    final fromIsolate = ReceivePort();
    final progress = StreamController<(int, int)>.broadcast();
    final result = Completer<ScanDiff>();
    final controlReady = Completer<SendPort>();
    late final StreamSubscription<Object?> sub;
    sub = fromIsolate.listen((msg) {
      switch (msg) {
        case final SendPort p:
          controlReady.complete(p);
        case (final int files, final int dirs):
          progress.add((files, dirs));
        case final ScanDiff diff:
          result.complete(diff);
        case _Failure(:final error):
          result.completeError(error);
        case [final Object? error, _]:
          // Uncaught isolate error (onError delivers [error, stack]).
          result.completeError(StateError('scan isolate failed: $error'));
      }
      if (result.isCompleted) {
        unawaited(sub.cancel());
        fromIsolate.close();
        unawaited(progress.close());
      }
    });
    await Isolate.spawn(
      _entry,
      _Args(fromIsolate.sendPort, root, fileSystem, known, options),
      debugName: 'mediahro-scan',
      onError: fromIsolate.sendPort,
    );
    return ScanRun._(await controlReady.future, progress.stream, result.future);
  }

  /// Same work on the current isolate; for tests and tiny sources.
  static Future<ScanDiff> runHere({
    required Uri root,
    required VirtualFileSystem fileSystem,
    required Map<String, KnownItem> known,
    ScanOptions options = const ScanOptions(),
    PauseToken? token,
    void Function(int files, int dirs)? onProgress,
  }) => _scan(
    root,
    fileSystem,
    known,
    options,
    token ?? PauseToken(),
    onProgress,
  );
}

enum _Control { pause, resume, cancel }

final class _Failure {
  const _Failure(this.error);
  final Object error;
}

final class _Args {
  const _Args(this.reply, this.root, this.fs, this.known, this.options);
  final SendPort reply;
  final Uri root;
  final FileSystemFactory fs;
  final Map<String, KnownItem> known;
  final ScanOptions options;
}

Future<void> _entry(_Args a) async {
  final control = ReceivePort();
  final token = PauseToken();
  control.listen((m) {
    switch (m) {
      case _Control.pause:
        token.pause();
      case _Control.resume:
        token.resume();
      case _Control.cancel:
        token.cancel();
    }
  });
  a.reply.send(control.sendPort);
  try {
    final diff = await _scan(
      a.root,
      a.fs(),
      a.known,
      a.options,
      token,
      (f, d) => a.reply.send((f, d)),
    );
    a.reply.send(diff);
  } on Object catch (e) {
    a.reply.send(
      _Failure(e is ScanCancelled || e is VirtualFileException ? e : '$e'),
    );
  } finally {
    control.close();
  }
}

Future<ScanDiff> _scan(
  Uri root,
  VirtualFileSystem fs,
  Map<String, KnownItem> known,
  ScanOptions options,
  PauseToken token,
  void Function(int files, int dirs)? onProgress,
) async {
  final found = <FoundFile>[];
  var dirs = 0;
  var lastReport = DateTime.now();
  await for (final batch in walk(
    fs,
    root,
    options: options,
    token: token,
    onDirectory: (d) => dirs = d,
  )) {
    found.addAll(batch);
    final now = DateTime.now();
    if (now.difference(lastReport).inMilliseconds >= 100) {
      lastReport = now;
      onProgress?.call(found.length, dirs);
    }
  }
  onProgress?.call(found.length, dirs);
  return await diffWalk(
    found,
    known,
    token: token,
    hashOf: (f) => hashFound(fs, root, f),
  );
}
