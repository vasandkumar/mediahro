import 'dart:io';
import 'dart:typed_data';

import 'package:mediahro_ffi/src/vfs/virtual_file.dart';
import 'package:mediahro_ffi/src/vfs/win32_find.dart';

/// [VirtualFileSystem] for `file:` URIs backed by `dart:io`.
///
/// Platform-scoped access (SAF trees, security-scoped bookmarks) is resolved
/// by the storage facade before a `file:` URI reaches this class.
final class LocalFileSystem implements VirtualFileSystem {
  const LocalFileSystem();

  @override
  Set<String> get schemes => const {'file'};

  @override
  Set<VirtualFsCapability> get capabilities => const {
    VirtualFsCapability.list,
    VirtualFsCapability.write,
    VirtualFsCapability.rename,
    VirtualFsCapability.delete,
    VirtualFsCapability.watch,
  };

  @override
  Future<VirtualFile> open(Uri uri) async {
    final file = File.fromUri(uri);
    try {
      final raf = await file.open();
      return _LocalVirtualFile(uri, raf);
    } on FileSystemException catch (e) {
      throw VirtualFileException(_map(e), uri, e.message);
    }
  }

  @override
  Future<VirtualEntry> stat(Uri uri) async {
    final path = uri.toFilePath();
    final s = await FileStat.stat(path);
    if (s.type == FileSystemEntityType.notFound) {
      throw VirtualFileException(VirtualFileError.notFound, uri);
    }
    return VirtualEntry(
      uri: uri,
      name: _basename(path),
      isDirectory: s.type == FileSystemEntityType.directory,
      size: s.type == FileSystemEntityType.directory ? null : s.size,
      modified: s.modified,
    );
  }

  @override
  Stream<VirtualEntry> list(Uri directory) async* {
    final dir = Directory.fromUri(directory);
    // One FindFirstFileExW pass returns sizes and mtimes (no per-file stat).
    final fast = win32ListDirectory(dir.path);
    if (fast != null) {
      for (final e in fast) {
        // Links and junctions are never followed (same as followLinks: false).
        if (e.isReparsePoint) continue;
        final base = dir.path.endsWith(Platform.pathSeparator)
            ? dir.path.substring(0, dir.path.length - 1)
            : dir.path;
        final path = '$base${Platform.pathSeparator}${e.name}';
        yield VirtualEntry(
          uri: e.isDirectory ? Directory(path).uri : File(path).uri,
          name: e.name,
          isDirectory: e.isDirectory,
          size: e.isDirectory ? null : e.size,
          modified: DateTime.fromMillisecondsSinceEpoch(e.modifiedMs),
        );
      }
      return;
    }
    try {
      await for (final entity in dir.list(followLinks: false)) {
        // Async on purpose: callers may be on the UI isolate (docs/05 §7).
        // ignore: avoid_slow_async_io
        final s = await entity.stat();
        final isDir = s.type == FileSystemEntityType.directory;
        yield VirtualEntry(
          uri: isDir ? Directory(entity.path).uri : File(entity.path).uri,
          name: _basename(entity.path),
          isDirectory: isDir,
          size: isDir ? null : s.size,
          modified: s.modified,
        );
      }
    } on FileSystemException catch (e) {
      throw VirtualFileException(_map(e), directory, e.message);
    }
  }

  static String _basename(String path) {
    final trimmed = path.endsWith(Platform.pathSeparator)
        ? path.substring(0, path.length - 1)
        : path;
    final i = trimmed.lastIndexOf(Platform.pathSeparator);
    return i < 0 ? trimmed : trimmed.substring(i + 1);
  }

  static VirtualFileError _map(FileSystemException e) {
    final code = e.osError?.errorCode;
    // ENOENT (2) on POSIX and ERROR_FILE_NOT_FOUND/ERROR_PATH_NOT_FOUND (2/3) on Windows.
    if (code == 2 || code == 3) return VirtualFileError.notFound;
    // EACCES (13) / ERROR_ACCESS_DENIED (5).
    if (code == 13 || code == 5) return VirtualFileError.permissionDenied;
    return VirtualFileError.io;
  }
}

final class _LocalVirtualFile implements VirtualFile {
  _LocalVirtualFile(this.uri, this._raf);

  @override
  final Uri uri;
  RandomAccessFile? _raf;

  // RandomAccessFile allows one pending operation at a time; serialise reads.
  Future<void> _tail = Future.value();

  RandomAccessFile get _open =>
      _raf ?? (throw VirtualFileException(VirtualFileError.closed, uri));

  @override
  bool get isSeekable => true;

  @override
  Future<int?> length() => _serial(() => _open.length());

  @override
  Future<Uint8List> read(int offset, int length) {
    RangeError.checkNotNegative(offset, 'offset');
    RangeError.checkNotNegative(length, 'length');
    return _serial(() async {
      final raf = _open;
      await raf.setPosition(offset);
      return await raf.read(length);
    });
  }

  Future<T> _serial<T>(Future<T> Function() op) {
    final result = _tail.then((_) => op());
    _tail = result.then((_) {}, onError: (_) {});
    return result;
  }

  @override
  Future<void> close() => _serial(() async {
    final raf = _raf;
    _raf = null;
    await raf?.close();
  });
}
