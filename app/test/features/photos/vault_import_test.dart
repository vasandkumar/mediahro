import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mediahro/features/photos/vault/vault_import.dart';
import 'package:mediahro/platform/storage.dart';
import 'package:mediahro_ffi/mediahro_ffi.dart' show FdIo;

final class _Storage implements StorageFacade {
  final List<int> opened = [];

  @override
  Future<int> openDocumentFd(
    Uri uri, {
    DocumentMode mode = DocumentMode.read,
  }) async {
    opened.add(opened.length + 100);
    return opened.last;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _Closes implements FdIo {
  _Closes(this.length);

  final int length;
  final List<int> closed = [];

  @override
  int size(int fd) => length;

  @override
  void close(int fd) => closed.add(fd);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Reads a real file as if it were the detached fd, and notes when it is
/// let go.
final class _FileReader implements FdReader {
  _FileReader(this.file, this.closes, this.fd);

  final File file;
  final List<int> closes;
  final int fd;
  var _closed = false;

  @override
  Future<Uint8List> read(int at, int length) async {
    final f = await file.open();
    try {
      await f.setPosition(at);
      return await f.read(length);
    } finally {
      await f.close();
    }
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    closes.add(fd);
  }
}

void main() {
  group('PRIV-007 what the vault keeps', () {
    test('PRIV-007 files are sorted by their ending, whatever the case', () {
      expect(vaultKindOf('film.MKV'), VaultKind.video);
      expect(vaultKindOf('clip.mp4'), VaultKind.video);
      expect(vaultKindOf('song.Flac'), VaultKind.audio);
      expect(vaultKindOf('voice.m4a'), VaultKind.audio);
      expect(vaultKindOf('photo.JPG'), VaultKind.image);
      expect(vaultKindOf('shot.heic'), VaultKind.image);
    });

    test('PRIV-007 anything else is not kept', () {
      expect(vaultKindOf('notes.txt'), isNull);
      expect(vaultKindOf('archive'), isNull);
      expect(vaultKindOf('trailing.'), isNull);
      expect(vaultKindOf('.mp4'), VaultKind.video);
    });
  });

  group('PRIV-007 picked files are read in pieces', () {
    late Directory dir;

    setUp(() => dir = Directory.systemTemp.createTempSync('mediahro-import'));
    tearDown(() => dir.deleteSync(recursive: true));

    Uint8List bytes(int n) =>
        Uint8List.fromList(List.generate(n, (i) => (i * 7) & 0xFF));

    test(
      'PRIV-007 a file larger than a piece comes as several pieces',
      () async {
        final f = File('${dir.path}/a.bin')
          ..writeAsBytesSync(bytes((3 << 20) + 17));
        final r = await openPickedStream(_Storage(), f.uri);
        expect(r.size, (3 << 20) + 17);
        final sizes = <int>[];
        final all = BytesBuilder();
        await for (final piece in r.content) {
          sizes.add(piece.length);
          all.add(piece);
        }
        expect(sizes, [1 << 20, 1 << 20, 1 << 20, 17]);
        expect(all.takeBytes(), bytes((3 << 20) + 17));
      },
    );

    test('PRIV-007 an empty file is an empty stream', () async {
      final f = File('${dir.path}/e.bin')..writeAsBytesSync(const []);
      final r = await openPickedStream(_Storage(), f.uri);
      expect(r.size, 0);
      expect(await r.content.toList(), isEmpty);
    });

    test(
      'PRIV-007 nothing is held open until the stream is listened to',
      () async {
        final f = File('${dir.path}/h.bin')..writeAsBytesSync(bytes(10));
        final r = await openPickedStream(_Storage(), f.uri);
        // The file can be deleted at once: no handle is open (Windows refuses
        // to delete an open file).
        f.deleteSync();
        expect(f.existsSync(), isFalse);
        expect(r.size, 10);
      },
    );

    test('PRIV-007 a content document is read by pread on its fd, never by a path, and the fd is closed', () async {
      final f = File('${dir.path}/doc.bin')
        ..writeAsBytesSync(bytes((2 << 20) + 3));
      final storage = _Storage();
      final io = _Closes((2 << 20) + 3);
      final closes = <int>[];
      final r = await openPickedStream(
        storage,
        Uri.parse('content://media/doc/1'),
        io: io,
        openReader: (fd) async => _FileReader(f, closes, fd),
      );
      expect(r.size, (2 << 20) + 3);
      // The probe's fd is closed already; the read opens and closes its own.
      expect(io.closed, [100]);
      expect(closes, isEmpty);
      final all = BytesBuilder();
      await r.content.forEach(all.add);
      expect(all.takeBytes(), bytes((2 << 20) + 3));
      expect(closes, [101]);
    });

    test('PRIV-007 cancelling a content stream lets go of its fd', () async {
      final f = File('${dir.path}/c2.bin')..writeAsBytesSync(bytes(3 << 20));
      final closes = <int>[];
      final r = await openPickedStream(
        _Storage(),
        Uri.parse('content://media/doc/2'),
        io: _Closes(3 << 20),
        openReader: (fd) async => _FileReader(f, closes, fd),
      );
      await r.content.first;
      expect(closes, [101]);
    });

    test('PRIV-007 a file that shrinks while being read is an error, not a short copy', () async {
      final f = File('${dir.path}/s.bin')..writeAsBytesSync(bytes(3 << 20));
      final r = await openPickedStream(_Storage(), f.uri);
      f.writeAsBytesSync(bytes(1 << 20));
      await expectLater(
        r.content.toList(),
        throwsA(isA<FileSystemException>()),
      );
    });

    test('PRIV-007 an fd the reader never took over is closed', () async {
      final io = _Closes(100);
      final r = await openPickedStream(
        _Storage(),
        Uri.parse('content://media/doc/3'),
        io: io,
        openReader: (fd) async => throw const FileSystemException('no worker'),
      );
      await expectLater(
        r.content.toList(),
        throwsA(isA<FileSystemException>()),
      );
      // The probe's fd, then the one the reader would have owned.
      expect(io.closed, [100, 101]);
    });

    test(
      'PRIV-007 a reader whose worker dies fails the read instead of hanging',
      () async {
        final reader = await IsolateFdReader.open(-1);
        reader.killWorker();
        await expectLater(
          reader.read(0, 10).timeout(const Duration(seconds: 10)),
          throwsA(isA<FileSystemException>()),
        );
        await reader.close().timeout(const Duration(seconds: 10));
        // Later reads fail at once.
        await expectLater(
          reader.read(0, 10),
          throwsA(isA<FileSystemException>()),
        );
      },
    );

    test('PRIV-007 cancelling the stream closes the file', () async {
      final f = File('${dir.path}/c.bin')..writeAsBytesSync(bytes(3 << 20));
      final r = await openPickedStream(_Storage(), f.uri);
      await r.content.first;
      f.deleteSync();
      expect(f.existsSync(), isFalse);
    });
  });
}
