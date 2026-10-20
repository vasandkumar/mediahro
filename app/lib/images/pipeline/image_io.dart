import 'dart:typed_data';

import 'package:mediahro/core/files/file_systems.dart';
import 'package:mediahro_ffi/mediahro_ffi.dart';

/// How the image pipeline reaches bytes: reads through `VirtualFile`, writes
/// atomically through the source's `MutableFileSystem`.
abstract interface class ImageIo {
  /// Local path when [uri] is a plain `file:` URI (libvips streams these).
  String? localPath(Uri uri);

  Future<VirtualFile> open(Uri uri);

  /// Replaces [uri] with [bytes]; readers never see a partial file.
  Future<void> replace(Uri uri, Uint8List bytes);

  /// Creates [uri] with [bytes]; throws when it exists.
  Future<void> create(Uri uri, Uint8List bytes);

  Future<bool> exists(Uri uri);

  Future<void> delete(Uri uri);
}

/// [ImageIo] over the app's mounted sources.
final class MountedImageIo implements ImageIo {
  MountedImageIo(this.mounts);

  final MountedFileSystems mounts;

  @override
  String? localPath(Uri uri) => uri.scheme == 'file' ? uri.toFilePath() : null;

  @override
  Future<VirtualFile> open(Uri uri) => mounts.forUri(uri).open(uri);

  MutableFileSystem _mutable(Uri uri) {
    final fs = mounts.forUri(uri);
    if (fs is! MutableFileSystem ||
        !fs.capabilities.contains(VirtualFsCapability.write)) {
      throw VirtualFileException(
        VirtualFileError.unsupported,
        uri,
        'this source is read-only',
      );
    }
    return fs;
  }

  Future<void> _write(Uri uri, Uint8List bytes) async {
    final w = await _mutable(uri).create(uri);
    try {
      await w.write(bytes);
      await w.close();
    } on Object {
      await w.abort();
      rethrow;
    }
  }

  @override
  Future<void> replace(Uri uri, Uint8List bytes) => _write(uri, bytes);

  @override
  Future<void> create(Uri uri, Uint8List bytes) async {
    if (await exists(uri)) {
      throw VirtualFileException(VirtualFileError.alreadyExists, uri);
    }
    await _write(uri, bytes);
  }

  @override
  Future<bool> exists(Uri uri) async {
    try {
      await mounts.forUri(uri).stat(uri);
      return true;
    } on VirtualFileException catch (e) {
      if (e.error == VirtualFileError.notFound) return false;
      rethrow;
    }
  }

  @override
  Future<void> delete(Uri uri) => _mutable(uri).delete(uri);
}
