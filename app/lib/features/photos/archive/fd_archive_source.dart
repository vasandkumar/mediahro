import 'dart:typed_data';

import 'package:mediahro_ffi/mediahro_ffi.dart';

/// A detached fd (an Android `content://` document opened by the platform)
/// as the outer file of an archive: libarchive reads it through the worker's
/// read and seek callbacks, with `pread` on the fd. The fd is never opened
/// again by path: `/proc/self/fd/N` is refused on Android 16.
///
/// The fd is the caller's: it closes it after the archive worker is gone, so
/// [dispose] leaves it alone.
final class FdSyncFileSystem implements SyncFileSystem {
  FdSyncFileSystem(this.fd, {FdIo? io}) : _io = io ?? PosixFdIo();

  final int fd;
  final FdIo _io;

  @override
  int open(String path, {bool write = false, bool create = false}) => fd;

  @override
  int? length(int handle) => _io.size(fd);

  @override
  Uint8List read(int handle, int offset, int length) =>
      _io.pread(fd, offset, length);

  @override
  void close(int handle) {}

  @override
  void dispose() {}

  // An archive is read-only and has no folders on its outer side.
  @override
  List<VirtualEntry> list(String path) => throw _readOnly(path);

  @override
  VirtualEntry stat(String path) => throw _readOnly(path);

  @override
  void write(int handle, int offset, List<int> bytes) =>
      throw _readOnly('$handle');

  @override
  void mkdir(String path) => throw _readOnly(path);

  @override
  void rename(String from, String to) => throw _readOnly(from);

  @override
  void unlink(String path) => throw _readOnly(path);

  @override
  void rmdir(String path) => throw _readOnly(path);

  static VirtualFileException _readOnly(String what) => VirtualFileException(
    VirtualFileError.unsupported,
    Uri(path: what),
    'the archive file is read-only',
  );
}

/// The factory the archive worker calls; it holds only the fd, so it can be
/// sent to the worker isolate.
SyncFileSystemFactory fdSyncFileSystem(int fd) =>
    () => FdSyncFileSystem(fd);
