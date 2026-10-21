import 'package:flutter_test/flutter_test.dart';
import 'package:mediahro/features/photos/archive/archive_book.dart';
import 'package:mediahro_ffi/mediahro_ffi.dart';

import 'archive_support.dart';

void main() {
  Future<ArchiveBook> open(FakeArchiveFs fs, {void Function()? onClose}) =>
      ArchiveBook.open(
        name: 'book.cbz',
        fs: fs,
        root: testRoot,
        onClose: onClose == null ? null : () async => onClose(),
      );

  group('IMG-017 an archive as a book', () {
    test(
      'IMG-017 the pictures of every folder come in reading order',
      () async {
        final book = await open(
          FakeArchiveFs([
            'ch2/10.jpg',
            'ch1/2.jpg',
            'ch2/2.jpg',
            'ch1/10.jpg',
            'ch1/1.jpg',
            'ComicInfo.xml',
            '__MACOSX/ch1/._1.jpg',
            'cover.png',
          ]),
        );
        expect(book.paths, [
          'ch1/1.jpg',
          'ch1/2.jpg',
          'ch1/10.jpg',
          'ch2/2.jpg',
          'ch2/10.jpg',
          'cover.png',
        ]);
        expect(book.pageCount, 6);
        expect(book.pageName(2), '10.jpg');
      },
    );

    test('IMG-017 a page opens by its entry path', () async {
      final fs = FakeArchiveFs(['ch1/1.jpg', 'ch1/2.jpg']);
      final book = await open(fs);
      final file = await book.openPage(1);
      expect(fs.opened, ['ch1/2.jpg']);
      await file.close();
      expect(fs.closedFiles, 1);
    });

    test('IMG-017 names with spaces and accents open too', () async {
      final fs = FakeArchiveFs(['Chapitre 1/Pâge 01.jpg']);
      final book = await open(fs);
      await (await book.openPage(0)).close();
      expect(fs.opened, ['Chapitre 1/Pâge 01.jpg']);
    });

    test('IMG-017 an archive with no pictures says so and lets go', () async {
      var closed = 0;
      await expectLater(
        open(FakeArchiveFs(['a.txt', 'b.xml']), onClose: () => closed++),
        throwsA(
          isA<ArchiveBookException>().having(
            (e) => e.problem,
            'problem',
            ArchiveProblem.noPages,
          ),
        ),
      );
      expect(closed, 1);
    });

    test('IMG-017 an unreadable archive says so and lets go', () async {
      var closed = 0;
      final fs = FakeArchiveFs(
        [],
        listError: VirtualFileException(
          VirtualFileError.unsupported,
          testRoot,
          'not a readable archive',
        ),
      );
      await expectLater(
        open(fs, onClose: () => closed++),
        throwsA(
          isA<ArchiveBookException>().having(
            (e) => e.problem,
            'problem',
            ArchiveProblem.unreadable,
          ),
        ),
      );
      expect(closed, 1);
    });

    test('IMG-017 a listing that needs a password asks for one', () async {
      final fs = FakeArchiveFs(
        [],
        listError: VirtualFileException(
          VirtualFileError.authenticationRequired,
          testRoot,
        ),
      );
      await expectLater(
        open(fs),
        throwsA(
          isA<ArchiveBookException>().having(
            (e) => e.problem,
            'problem',
            ArchiveProblem.needsPassphrase,
          ),
        ),
      );
    });

    test('IMG-017 an encrypted page asks for a password when opened', () async {
      final fs = FakeArchiveFs(['1.jpg', '2.jpg'], encrypted: {'2.jpg'});
      final book = await open(fs);
      await (await book.openPage(0)).close();
      await expectLater(
        book.openPage(1),
        throwsA(
          isA<ArchiveBookException>().having(
            (e) => e.problem,
            'problem',
            ArchiveProblem.needsPassphrase,
          ),
        ),
      );
    });

    test('IMG-017 closing lets go once and later reads are refused', () async {
      var closed = 0;
      final book = await open(
        FakeArchiveFs(['1.jpg']),
        onClose: () => closed++,
      );
      await book.close();
      await book.close();
      expect(closed, 1);
      await expectLater(
        book.openPage(0),
        throwsA(
          isA<VirtualFileException>().having(
            (e) => e.error,
            'error',
            VirtualFileError.closed,
          ),
        ),
      );
    });

    test('IMG-017 a failure while listing lets go too', () async {
      var closed = 0;
      final fs = FakeArchiveFs([])..listError = null;
      final broken = _Broken(fs);
      await expectLater(
        ArchiveBook.open(
          name: 'x',
          fs: broken,
          root: testRoot,
          onClose: () async => closed++,
        ),
        throwsA(isA<StateError>()),
      );
      expect(closed, 1);
    });
  });
}

/// A file system whose listing fails with something unexpected.
final class _Broken implements VirtualFileSystem {
  _Broken(this.inner);

  final VirtualFileSystem inner;

  @override
  Set<String> get schemes => inner.schemes;

  @override
  Set<VirtualFsCapability> get capabilities => inner.capabilities;

  @override
  Stream<VirtualEntry> list(Uri directory) =>
      Stream<VirtualEntry>.error(StateError('boom'));

  @override
  Future<VirtualFile> open(Uri uri) => inner.open(uri);

  @override
  Future<VirtualEntry> stat(Uri uri) => inner.stat(uri);
}
