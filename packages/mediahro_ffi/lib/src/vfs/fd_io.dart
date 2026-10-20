import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

/// Positional I/O on a file descriptor the platform handed over (Android
/// SAF / MediaStore via `ParcelFileDescriptor.detachFd`). Random access
/// without a seek pointer, so concurrent readers of one fd are safe.
abstract interface class FdIo {
  /// Up to [length] bytes at [offset]; fewer only at end of file.
  Uint8List pread(int fd, int offset, int length);

  /// Writes all of [bytes] at [offset].
  void pwrite(int fd, int offset, List<int> bytes);

  /// Size in bytes (`lseek(fd, 0, SEEK_END)`).
  int size(int fd);

  void close(int fd);
}

/// [FdIo] over libc (`pread64`/`pwrite64`/`lseek64` on Android, so 32-bit
/// ABIs get 64-bit offsets; the plain calls elsewhere). Symbols resolve on
/// first use: only platforms that hand out fds (Android) ever call it.
final class PosixFdIo implements FdIo {
  PosixFdIo();

  static final DynamicLibrary _libc = DynamicLibrary.process();
  static final bool _lfs = Platform.isAndroid;

  late final _PreadD _pread = _libc.lookupFunction<_PreadC, _PreadD>(
    _lfs ? 'pread64' : 'pread',
  );
  late final _PwriteD _pwrite = _libc.lookupFunction<_PwriteC, _PwriteD>(
    _lfs ? 'pwrite64' : 'pwrite',
  );
  late final _LseekD _lseek = _libc.lookupFunction<_LseekC, _LseekD>(
    _lfs ? 'lseek64' : 'lseek',
  );
  late final _CloseD _close = _libc.lookupFunction<_CloseC, _CloseD>('close');

  @override
  Uint8List pread(int fd, int offset, int length) {
    final buf = malloc<Uint8>(length);
    try {
      var got = 0;
      while (got < length) {
        final n = _pread(fd, buf + got, length - got, offset + got);
        if (n < 0) throw const FileSystemException('pread failed');
        if (n == 0) break;
        got += n;
      }
      return Uint8List.fromList(buf.asTypedList(got));
    } finally {
      malloc.free(buf);
    }
  }

  @override
  void pwrite(int fd, int offset, List<int> bytes) {
    final buf = malloc<Uint8>(bytes.length);
    try {
      buf.asTypedList(bytes.length).setAll(0, bytes);
      var put = 0;
      while (put < bytes.length) {
        final n = _pwrite(fd, buf + put, bytes.length - put, offset + put);
        if (n < 0) throw const FileSystemException('pwrite failed');
        put += n;
      }
    } finally {
      malloc.free(buf);
    }
  }

  @override
  int size(int fd) {
    final n = _lseek(fd, 0, 2); // SEEK_END
    if (n < 0) throw const FileSystemException('lseek failed');
    return n;
  }

  @override
  void close(int fd) => _close(fd);
}

typedef _PreadC = IntPtr Function(Int32, Pointer<Uint8>, Size, Int64);
typedef _PreadD = int Function(int, Pointer<Uint8>, int, int);
typedef _PwriteC = IntPtr Function(Int32, Pointer<Uint8>, Size, Int64);
typedef _PwriteD = int Function(int, Pointer<Uint8>, int, int);
typedef _LseekC = Int64 Function(Int32, Int64, Int32);
typedef _LseekD = int Function(int, int, int);
typedef _CloseC = Int32 Function(Int32);
typedef _CloseD = int Function(int);
