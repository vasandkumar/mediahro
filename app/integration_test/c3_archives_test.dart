// Lane C3 device batch, comic reader (IMG-017): a real CBZ built on the
// phone, read through libarchive (`archiveFileSystem`) and the real image
// pipeline: the pages come in reading order and decode.
//
//   flutter test integration_test/c3_archives_test.dart -d <serial> --no-dds \
//     -P kotlin.incremental=false
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mediahro/features/photos/archive/archive_book.dart';
import 'package:mediahro/platform/storage.dart';
import 'package:mediahro_ffi/mediahro_ffi.dart' show PosixFdIo;

/// A stored (uncompressed) ZIP of [files], enough for libarchive.
Uint8List zipOf(Map<String, Uint8List> files) {
  final out = BytesBuilder();
  final central = BytesBuilder();
  var offset = 0;
  final table = List<int>.generate(256, (n) {
    var c = n;
    for (var k = 0; k < 8; k++) {
      c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1;
    }
    return c;
  });
  int crc32(List<int> data) {
    var c = 0xFFFFFFFF;
    for (final b in data) {
      c = table[(c ^ b) & 0xFF] ^ (c >> 8);
    }
    return c ^ 0xFFFFFFFF;
  }

  void u16(BytesBuilder b, int v) => b.add([v & 0xFF, (v >> 8) & 0xFF]);
  void u32(BytesBuilder b, int v) =>
      b.add([v & 0xFF, (v >> 8) & 0xFF, (v >> 16) & 0xFF, (v >> 24) & 0xFF]);

  for (final e in files.entries) {
    final name = e.key.codeUnits;
    final crc = crc32(e.value);
    final local = BytesBuilder();
    u32(local, 0x04034b50);
    u16(local, 20);
    u16(local, 0);
    u16(local, 0);
    u16(local, 0);
    u16(local, 0x21);
    u32(local, crc);
    u32(local, e.value.length);
    u32(local, e.value.length);
    u16(local, name.length);
    u16(local, 0);
    local
      ..add(name)
      ..add(e.value);
    out.add(local.toBytes());
    u32(central, 0x02014b50);
    u16(central, 20);
    u16(central, 20);
    u16(central, 0);
    u16(central, 0);
    u16(central, 0);
    u16(central, 0x21);
    u32(central, crc);
    u32(central, e.value.length);
    u32(central, e.value.length);
    u16(central, name.length);
    u16(central, 0);
    u16(central, 0);
    u16(central, 0);
    u16(central, 0);
    u32(central, 0);
    u32(central, offset);
    central.add(name);
    offset += local.length;
  }
  final start = out.length;
  out.add(central.toBytes());
  u32(out, 0x06054b50);
  u16(out, 0);
  u16(out, 0);
  u16(out, files.length);
  u16(out, files.length);
  u32(out, central.length);
  u32(out, start);
  u16(out, 0);
  return out.toBytes();
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('IMG-017 a CBZ opens in reading order through libarchive', (
    tester,
  ) async {
    final dir = Directory.systemTemp.createTempSync('c3-cbz');
    addTearDown(() => dir.deleteSync(recursive: true));
    Uint8List page(int n) => Uint8List.fromList(List.generate(64, (i) => n));
    final file = File('${dir.path}/vol.cbz')
      ..writeAsBytesSync(
        zipOf({
          'ch1/10.jpg': page(3),
          'ch1/2.jpg': page(2),
          'ch1/1.jpg': page(1),
          'ComicInfo.xml': Uint8List.fromList('<x/>'.codeUnits),
          '__MACOSX/ch1/._1.jpg': page(9),
        }),
      );
    final books = FfiArchiveBooks(_NoStorage());
    final book = await books.open(ArchiveRef(uri: file.uri, name: 'vol.cbz'));
    expect(book.paths, ['ch1/1.jpg', 'ch1/2.jpg', 'ch1/10.jpg']);
    final first = await book.openPage(0);
    expect(await first.read(0, 64), page(1));
    await first.close();
    await book.close();
  });

  // Android hands out content: documents as a detached fd. It is read with
  // pread, never opened again as /proc/self/fd/N (refused on Android 16).
  testWidgets('IMG-017 an archive that arrives as a detached fd is read', (
    tester,
  ) async {
    final dir = Directory.systemTemp.createTempSync('c3-cbz');
    addTearDown(() => dir.deleteSync(recursive: true));
    Uint8List page(int n) => Uint8List.fromList(List.generate(64, (i) => n));
    final file = File('${dir.path}/doc.cbz')
      ..writeAsBytesSync(zipOf({'b/2.jpg': page(2), 'b/1.jpg': page(1)}));
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
    addTearDown(() => cFree(path));
    final fds = <int>[];
    final books = FfiArchiveBooks(
      _FdStorage(() {
        final fd = open(path, 0); // O_RDONLY
        expect(fd, greaterThanOrEqualTo(0));
        fds.add(fd);
        return fd;
      }),
    );
    final book = await books.open(
      ArchiveRef(uri: Uri.parse('content://docs/doc/9'), name: 'doc.cbz'),
    );
    expect(book.paths, ['b/1.jpg', 'b/2.jpg']);
    final second = await book.openPage(1);
    expect(await second.read(0, 64), page(2));
    await second.close();
    await book.close();
    // The fd is closed with the book.
    expect(fds, hasLength(1));
    expect(() => PosixFdIo().size(fds.single), throwsA(anything));
  });

  testWidgets('IMG-017 a file that is not an archive is refused', (
    tester,
  ) async {
    final dir = Directory.systemTemp.createTempSync('c3-cbz');
    addTearDown(() => dir.deleteSync(recursive: true));
    final file = File('${dir.path}/x.cbz')
      ..writeAsBytesSync(List.filled(200, 7));
    await expectLater(
      FfiArchiveBooks(_NoStorage())
          .open(ArchiveRef(uri: file.uri, name: 'x.cbz')),
      throwsA(isA<ArchiveBookException>()),
    );
  });
}

/// Files here are plain paths; the storage facade is not used.
final class _NoStorage implements StorageFacade {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Hands out a fresh detached fd for any document.
final class _FdStorage implements StorageFacade {
  _FdStorage(this._open);

  final int Function() _open;

  @override
  Future<int> openDocumentFd(
    Uri uri, {
    DocumentMode mode = DocumentMode.read,
  }) async => _open();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
