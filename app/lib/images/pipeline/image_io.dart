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

  /// Replaces [uri]. A local file system swaps atomically by itself; on
  /// every other source (SAF refuses `create` over an existing document, SMB
  /// and FTP overwrite in place) the new content is written next to the
  /// original and verified first, then swapped in, so a failure at any step
  /// leaves the original as it was.
  @override
  Future<void> replace(Uri uri, Uint8List bytes) async {
    if (uri.scheme == 'file') return await _write(uri, bytes);
    final fs = _mutable(uri);
    final tmp = _sibling(uri, '.mediahro-tmp');
    final bak = _sibling(uri, '.mediahro-bak');
    await _recover(fs, uri, bak);
    if (await exists(tmp)) await _quietDelete(fs, tmp);
    if (!await exists(uri)) return await _write(uri, bytes);
    try {
      await _write(tmp, bytes);
      await _verify(tmp, bytes);
    } on Object {
      await _quietDelete(fs, tmp);
      rethrow;
    }
    final Uri parked;
    try {
      parked = await fs.rename(uri, _lastName(bak));
    } on Object {
      // Nothing moved: the original is untouched.
      await _quietDelete(fs, tmp);
      rethrow;
    }
    try {
      await fs.rename(tmp, _lastName(uri));
    } on Object {
      try {
        await fs.rename(parked, _lastName(uri));
      } on Object {
        // The original is still safe under its parked name.
      }
      await _quietDelete(fs, tmp);
      rethrow;
    }
    await _quietDelete(fs, parked);
  }

  /// A crash between the two renames leaves the original under its parked
  /// name; put it back, or drop a parked copy the swap no longer needs.
  Future<void> _recover(MutableFileSystem fs, Uri uri, Uri bak) async {
    if (!await exists(bak)) return;
    if (await exists(uri)) {
      await _quietDelete(fs, bak);
    } else {
      await fs.rename(bak, _lastName(uri));
    }
  }

  Future<void> _verify(Uri uri, Uint8List bytes) async {
    final f = await open(uri);
    try {
      if (await f.length() != bytes.length) {
        throw VirtualFileException(VirtualFileError.io, uri, 'short write');
      }
      final tail = bytes.length > 65536 ? 65536 : bytes.length;
      for (final at in {0, bytes.length - tail}) {
        final got = await f.read(at, tail);
        if (got.length != tail) {
          throw VirtualFileException(VirtualFileError.io, uri, 'short read');
        }
        for (var i = 0; i < tail; i++) {
          if (got[i] != bytes[at + i]) {
            throw VirtualFileException(VirtualFileError.io, uri, 'differs');
          }
        }
      }
    } finally {
      await f.close();
    }
  }

  Future<void> _quietDelete(MutableFileSystem fs, Uri uri) async {
    try {
      await fs.delete(uri);
    } on Object {
      // Best effort: a leftover temporary name is cleaned up next time.
    }
  }

  static String _lastName(Uri uri) =>
      Uri.decodeComponent(uri.pathSegments.lastWhere((s) => s.isNotEmpty));

  /// `.name<suffix>` next to [uri] (hidden, and not an image extension).
  static Uri _sibling(Uri uri, String suffix) {
    final segments = [...uri.pathSegments]..removeWhere((s) => s.isEmpty);
    final name = segments.removeLast();
    return uri.replace(pathSegments: [...segments, '.$name$suffix']);
  }

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
