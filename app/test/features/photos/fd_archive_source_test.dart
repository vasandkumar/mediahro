import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mediahro/features/photos/archive/fd_archive_source.dart';
import 'package:mediahro_ffi/mediahro_ffi.dart';

final class _Fd implements FdIo {
  _Fd(this.bytes);

  final Uint8List bytes;
  final List<int> closed = [];

  @override
  int size(int fd) => bytes.length;

  @override
  Uint8List pread(int fd, int offset, int length) => offset >= bytes.length
      ? Uint8List(0)
      : Uint8List.sublistView(
          bytes,
          offset,
          offset + length > bytes.length ? bytes.length : offset + length,
        );

  @override
  void close(int fd) => closed.add(fd);

  @override
  void pwrite(int fd, int offset, List<int> bytes) =>
      throw UnimplementedError();
}

void main() {
  group('IMG-017 an archive handed out as a detached fd', () {
    test('IMG-017 it is read by position on the fd and sized by it', () {
      final io = _Fd(Uint8List.fromList(List.generate(100, (i) => i)));
      final fs = FdSyncFileSystem(7, io: io);
      final h = fs.open('anything.cbz');
      expect(fs.length(h), 100);
      expect(fs.read(h, 98, 10), [98, 99]);
      expect(fs.read(h, 10, 3), [10, 11, 12]);
      expect(fs.read(h, 100, 4), isEmpty);
    });

    test(
      "IMG-017 the fd is the caller's: closing the file system leaves it",
      () {
        final io = _Fd(Uint8List(4));
        final fs = FdSyncFileSystem(7, io: io);
        fs
          ..close(fs.open('a'))
          ..dispose();
        expect(io.closed, isEmpty);
      },
    );

    // A real descriptor, as the platform hands one out. libc is POSIX-only.
    test('IMG-017 a real file descriptor is read and sized', () {
      final dir = Directory.systemTemp.createTempSync('c3-fd');
      addTearDown(() => dir.deleteSync(recursive: true));
      final bytes = Uint8List.fromList(List.generate(70000, (i) => i % 251));
      final file = File('${dir.path}/a.cbz')..writeAsBytesSync(bytes);
      final libc = DynamicLibrary.process();
      final cMalloc = libc
          .lookupFunction<
            Pointer<Uint8> Function(IntPtr),
            Pointer<Uint8> Function(int)
          >('malloc');
      final cFree = libc
          .lookupFunction<
            Void Function(Pointer<Uint8>),
            void Function(Pointer<Uint8>)
          >('free');
      final open = libc
          .lookupFunction<
            Int32 Function(Pointer<Uint8>, Int32),
            int Function(Pointer<Uint8>, int)
          >('open');
      final name = utf8.encode(file.path);
      final path = cMalloc(name.length + 1);
      path.asTypedList(name.length + 1)
        ..setAll(0, name)
        ..[name.length] = 0;
      final fd = open(path, 0); // O_RDONLY
      cFree(path);
      expect(fd, greaterThanOrEqualTo(0));
      final io = PosixFdIo();
      addTearDown(() => io.close(fd));
      final fs = FdSyncFileSystem(fd);
      final h = fs.open('whatever');
      expect(fs.length(h), 70000);
      expect(fs.read(h, 69998, 10), bytes.sublist(69998));
      expect(fs.read(h, 65536, 3), bytes.sublist(65536, 65539));
      expect(fs.read(h, 70000, 4), isEmpty);
      fs.dispose();
      // The file system does not close the fd; it is still readable.
      expect(io.size(fd), 70000);
    }, skip: Platform.isWindows ? 'libc is POSIX-only' : false);

    test('IMG-017 nothing can be written to the archive', () {
      final fs = FdSyncFileSystem(7, io: _Fd(Uint8List(4)));
      expect(() => fs.unlink('a'), throwsA(isA<VirtualFileException>()));
      expect(() => fs.write(1, 0, [1]), throwsA(isA<VirtualFileException>()));
    });

    test('IMG-017 the worker factory holds only the fd', () {
      final factory = fdSyncFileSystem(9);
      expect(factory(), isA<FdSyncFileSystem>().having((f) => f.fd, 'fd', 9));
    });
  });
}
