import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:mediahro/platform/storage.dart';
import 'package:mediahro_ffi/mediahro_ffi.dart' show FdIo, PosixFdIo;

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
/// copy.
final class IsolateFdReader implements FdReader {
  IsolateFdReader._(this._fd, this._isolate, this._commands);

  /// Starts the worker for [fd], which it closes with [close].
  static Future<IsolateFdReader> open(int fd) async {
    final ready = ReceivePort();
    final isolate = await Isolate.spawn(_serve, ready.sendPort);
    final commands = await ready.first as SendPort;
    ready.close();
    return IsolateFdReader._(fd, isolate, commands);
  }

  final int _fd;
  final Isolate _isolate;
  final SendPort _commands;
  bool _closed = false;

  @override
  Future<Uint8List> read(int at, int length) async {
    if (_closed) throw const FileSystemException('the file is closed');
    final reply = ReceivePort();
    _commands.send([reply.sendPort, _fd, at, length]);
    final answer = await reply.first;
    reply.close();
    if (answer is TransferableTypedData) {
      return answer.materialize().asUint8List();
    }
    throw FileSystemException('the file could not be read: $answer');
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    final reply = ReceivePort();
    _commands.send([reply.sendPort, _fd, -1, 0]);
    await reply.first;
    reply.close();
    _isolate.kill();
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
    final reader = await openReader(await storage.openDocumentFd(uri));
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
