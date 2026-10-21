import 'dart:async';
import 'dart:typed_data';

import 'package:mediahro/platform/storage.dart';
import 'package:mediahro_ffi/mediahro_ffi.dart';

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

/// A file the user picked, to be read in pieces: its size and the bytes as
/// a stream. Nothing stays open until the stream is listened to, and the file
/// is closed when the stream ends or is cancelled. Android hands out
/// `content://` URIs, read through a detached fd; elsewhere a `file:` URI read
/// with dart:io.
Future<({int size, Stream<List<int>> content})> openPickedStream(
  StorageFacade storage,
  Uri uri, {
  FdIo? io,
}) async {
  if (uri.scheme == 'content') {
    final fdIo = io ?? PosixFdIo();
    final probe = await storage.openDocumentFd(uri);
    final int size;
    try {
      size = fdIo.size(probe);
    } finally {
      fdIo.close(probe);
    }
    Stream<List<int>> read() async* {
      final fd = await storage.openDocumentFd(uri);
      try {
        for (var at = 0; at < size; at += _piece) {
          final n = size - at < _piece ? size - at : _piece;
          yield Uint8List.fromList(fdIo.pread(fd, at, n));
        }
      } finally {
        fdIo.close(fd);
      }
    }

    return (size: size, content: read());
  }
  const fs = LocalFileSystem();
  final probe = await fs.open(uri);
  final int size;
  try {
    size = await probe.length() ?? 0;
  } finally {
    await probe.close();
  }
  Stream<List<int>> read() async* {
    final file = await fs.open(uri);
    try {
      for (var at = 0; at < size; at += _piece) {
        yield await file.read(at, size - at < _piece ? size - at : _piece);
      }
    } finally {
      await file.close();
    }
  }

  return (size: size, content: read());
}
