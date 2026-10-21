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
  final List<int> closed = [];

  @override
  void close(int fd) => closed.add(fd);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
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

    test('PRIV-007 a content document is read through its fd path and the fd is closed at once', () async {
      final f = File('${dir.path}/doc.bin')
        ..writeAsBytesSync(bytes((2 << 20) + 3));
      final storage = _Storage();
      final io = _Closes();
      final r = await openPickedStream(
        storage,
        Uri.parse('content://media/doc/1'),
        io: io,
        pathOfFd: (fd) => f.path,
      );
      expect(r.size, (2 << 20) + 3);
      // The probe's fd is closed already; the read opens and closes its own.
      expect(io.closed, [100]);
      final all = BytesBuilder();
      await r.content.forEach(all.add);
      expect(all.takeBytes(), bytes((2 << 20) + 3));
      expect(io.closed, [100, 101]);
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

    test('PRIV-007 cancelling the stream closes the file', () async {
      final f = File('${dir.path}/c.bin')..writeAsBytesSync(bytes(3 << 20));
      final r = await openPickedStream(_Storage(), f.uri);
      await r.content.first;
      f.deleteSync();
      expect(f.existsSync(), isFalse);
    });
  });
}
