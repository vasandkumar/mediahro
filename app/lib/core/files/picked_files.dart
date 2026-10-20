import 'dart:typed_data';

import 'package:mediahro/core/files/media_store_file_system.dart';
import 'package:mediahro/core/files/saf_file_system.dart';
import 'package:mediahro/platform/storage.dart';
import 'package:mediahro_ffi/mediahro_ffi.dart';

/// Reads a file the user picked ([StorageFacade.pickFiles]): Android hands
/// out `content://` URIs, read through a detached fd; elsewhere a `file:`
/// URI read with dart:io. Refuses files over [maxBytes] (backups, playlists).
Future<Uint8List> readPickedFile(
  StorageFacade storage,
  Uri uri, {
  int maxBytes = 64 << 20,
  FdIo? io,
}) async {
  if (uri.scheme == 'content') {
    final fdIo = io ?? PosixFdIo();
    final fd = await storage.openDocumentFd(uri);
    try {
      final size = fdIo.size(fd);
      if (size > maxBytes) {
        throw VirtualFileException(VirtualFileError.io, uri, 'too large');
      }
      return fdIo.pread(fd, 0, size);
    } finally {
      fdIo.close(fd);
    }
  }
  final f = await const LocalFileSystem().open(uri);
  try {
    final len = await f.length() ?? 0;
    if (len > maxBytes) {
      throw VirtualFileException(VirtualFileError.io, uri, 'too large');
    }
    return await f.read(0, len);
  } finally {
    await f.close();
  }
}

/// The URI another app can open for [uri] browsed through [fs] (FILE-002
/// share / open in): the SAF document or MediaStore content URI on Android,
/// the file itself elsewhere. Null for network sources, which have no
/// local copy to hand over.
Future<Uri?> shareableUri(VirtualFileSystem fs, Uri uri) async => switch (fs) {
  final SafFileSystem s => await s.documentUri(uri),
  final MediaStoreFileSystem m => await m.contentUri(uri),
  _ when uri.scheme == 'file' => uri,
  _ => null,
};
