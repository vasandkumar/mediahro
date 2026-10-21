import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:mediahro/platform/storage.dart';
import 'package:mediahro_ffi/mediahro_ffi.dart' show FdIo, PosixFdIo;
import 'package:meta/meta.dart';

/// What a picked file is, by its name: the kinds the vault keeps.
enum VaultKind { image, video, audio }

const Set<String> _videoExt = {
  'mp4', 'm4v', 'mkv', 'webm', 'mov', 'avi', 'wmv', 'flv', 'ts', 'm2ts', //
  'mts', 'mpg', 'mpeg', '3gp', 'ogv', 'vob', 'divx',
};

const Set<String> _audioExt = {
  'mp3', 'm4a', 'aac', 'flac', 'wav', 'ogg', 'oga', 'opus', 'wma', 'aiff', //
  'aif', 'ape', 'wv', 'mka', 'amr', 'mpc', 'm4b',
};

const Set<String> _imageExt = {
  'jpg', 'jpeg', 'png', 'gif', 'webp', 'heic', 'heif', 'avif', 'jxl', 'bmp', //
  'tif', 'tiff', 'svg', 'ico', 'dng', 'cr2', 'cr3', 'nef', 'arw', 'orf', //
  'rw2', 'raf', 'jp2',
};

/// The kind of a file called [name], or null when the vault does not keep it.
VaultKind? vaultKindOf(String name) {
  final dot = name.lastIndexOf('.');
  if (dot < 0 || dot == name.length - 1) return null;
  final ext = name.substring(dot + 1).toLowerCase();
  if (_videoExt.contains(ext)) return VaultKind.video;
  if (_audioExt.contains(ext)) return VaultKind.audio;
  if (_imageExt.contains(ext)) return VaultKind.image;
  return null;
}

/// One piece of a picked file at a time (1 MiB), so a film does not have to
/// fit in memory.
const int _piece = 1 << 20;

/// Positional reads of a file that was handed out as a detached fd, off the
/// UI isolate. The fd is the app's own (a content document opened by the
/// platform), read with `pread` rather than opened again by path:
/// `/proc/self/fd/N` is refused on Android 16.
abstract interface class FdReader {
  /// Up to [length] bytes at [at]; fewer only at the end of the file.
  Future<Uint8List> read(int at, int length);

  /// Closes the fd; later calls do nothing.
  Future<void> close();
}

/// Makes the reader of a detached [fd]; tests replace it.
typedef FdReaderOpener = Future<FdReader> Function(int fd);

/// An [FdReader] whose `pread` calls run on one worker isolate, so nothing
/// is read on the UI isolate. Bytes come back as transferred memory, not a
/// copy. If the worker dies, every read waiting on it fails (the add stops
/// instead of hanging) and the fd is closed from here.
final class IsolateFdReader implements FdReader {
  IsolateFdReader._(this._fd, this._isolate, this._commands, this._guards);

  /// Starts the worker for [fd], which it closes with [close]. When the
  /// worker cannot be started the fd is left to the caller.
  static Future<IsolateFdReader> open(int fd) async {
    final ready = ReceivePort();
    final exit = ReceivePort();
    final errors = ReceivePort();
    final started = Completer<SendPort>();
    IsolateFdReader? reader;
    void gone(Object? _) {
      if (!started.isCompleted) {
        started.completeError(
          const FileSystemException('the reader did not start'),
        );
      }
      reader?._died();
    }

    ready.listen((m) {
      if (m is SendPort && !started.isCompleted) started.complete(m);
    });
    exit.listen(gone);
    errors.listen(gone);
    try {
      final isolate = await Isolate.spawn(
        _serve,
        ready.sendPort,
        onExit: exit.sendPort,
        onError: errors.sendPort,
      );
      try {
        final commands = await started.future;
        return reader = IsolateFdReader._(fd, isolate, commands, [
          exit,
          errors,
        ]);
      } on Object {
        isolate.kill();
        rethrow;
      }
    } on Object {
      exit.close();
      errors.close();
      rethrow;
    } finally {
      ready.close();
    }
  }

  final int _fd;
  final Isolate _isolate;
  final SendPort _commands;
  final List<ReceivePort> _guards;
  final Set<Completer<Object?>> _waiting = {};
  bool _closed = false;
  bool _dead = false;

  /// Stops the worker as a crash would (for tests).
  @visibleForTesting
  void killWorker() => _isolate.kill(priority: Isolate.immediate);

  void _died() {
    if (_dead) return;
    _dead = true;
    for (final c in _waiting.toList()) {
      if (!c.isCompleted) {
        c.completeError(const FileSystemException('the reader stopped'));
      }
    }
    _waiting.clear();
  }

  Future<Object?> _ask(List<Object?> body) async {
    if (_dead) throw const FileSystemException('the reader stopped');
    final reply = ReceivePort();
    final done = Completer<Object?>();
    _waiting.add(done);
    reply.listen((m) {
      if (!done.isCompleted) done.complete(m);
    });
    try {
      _commands.send([reply.sendPort, ...body]);
      return await done.future;
    } finally {
      _waiting.remove(done);
      reply.close();
    }
  }

  @override
  Future<Uint8List> read(int at, int length) async {
    if (_closed) throw const FileSystemException('the file is closed');
    final answer = await _ask([_fd, at, length]);
    if (answer is TransferableTypedData) {
      return answer.materialize().asUint8List();
    }
    throw FileSystemException('the file could not be read: $answer');
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    var closedByWorker = false;
    try {
      if (!_dead) {
        await _ask([_fd, -1, 0]);
        closedByWorker = true;
      }
    } on Object {
      // The worker went while closing.
    } finally {
      // A worker that is gone cannot close the fd.
      if (!closedByWorker) {
        try {
          PosixFdIo().close(_fd);
        } on Object {
          // Nothing more can be done for it.
        }
      }
      _isolate.kill();
      for (final g in _guards) {
        g.close();
      }
    }
  }

  static void _serve(SendPort ready) {
    final port = ReceivePort();
    final io = PosixFdIo();
    ready.send(port.sendPort);
    port.listen((m) {
      final msg = m! as List<Object?>;
      final reply = msg[0]! as SendPort;
      final fd = msg[1]! as int;
      final at = msg[2]! as int;
      if (at < 0) {
        io.close(fd);
        port.close();
        reply.send(true);
        return;
      }
      try {
        reply.send(
          TransferableTypedData.fromList([io.pread(fd, at, msg[3]! as int)]),
        );
      } on Object catch (e) {
        reply.send('$e');
      }
    });
  }
}

/// A file the user picked, to be read in pieces: its size and the bytes as
/// a stream. Nothing stays open until the stream is listened to, and the file
/// is closed when the stream ends or is cancelled. Reads are asynchronous and
/// off the UI isolate, and each piece is handed on without another copy.
/// Android hands out `content://` documents as a detached fd, read with
/// `pread` ([FdReader]); other platforms read the `file:` path with dart:io.
Future<({int size, Stream<List<int>> content})> openPickedStream(
  StorageFacade storage,
  Uri uri, {
  FdIo? io,
  FdReaderOpener openReader = IsolateFdReader.open,
}) async {
  final fdIo = io ?? PosixFdIo();
  final int size;
  if (uri.scheme == 'content') {
    final fd = await storage.openDocumentFd(uri);
    try {
      size = fdIo.size(fd);
    } finally {
      fdIo.close(fd);
    }
  } else {
    size = await File(uri.toFilePath()).length();
  }

  Stream<List<int>> fromFd() async* {
    final fd = await storage.openDocumentFd(uri);
    final FdReader reader;
    try {
      reader = await openReader(fd);
    } on Object {
      // The reader never took the fd over: it is closed here.
      fdIo.close(fd);
      rethrow;
    }
    try {
      for (var at = 0; at < size; at += _piece) {
        final n = size - at < _piece ? size - at : _piece;
        final piece = await reader.read(at, n);
        if (piece.length != n) {
          throw FileSystemException('the file ended early', uri.path);
        }
        yield piece;
      }
    } finally {
      await reader.close();
    }
  }

  Stream<List<int>> fromFile() async* {
    final file = await File(uri.toFilePath()).open();
    try {
      for (var at = 0; at < size; at += _piece) {
        final n = size - at < _piece ? size - at : _piece;
        final piece = await file.read(n);
        if (piece.length != n) {
          throw FileSystemException('the file ended early', uri.path);
        }
        yield piece;
      }
    } finally {
      await file.close();
    }
  }

  return (size: size, content: uri.scheme == 'content' ? fromFd() : fromFile());
}
