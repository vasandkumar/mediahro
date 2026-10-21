import 'package:flutter_test/flutter_test.dart';
import 'package:mediahro/features/photos/archive/archive_providers.dart';
import 'package:mediahro/features/photos/archive/comic_reader.dart';
import 'package:mediahro/platform/platform_facades.dart';

import 'archive_support.dart';
import 'photos_harness.dart';

final class _Storage implements StorageFacade {
  final List<PickedFile> picks = [];

  @override
  Future<List<PickedFile>> pickFiles({
    Set<PickKind> kinds = const {PickKind.any},
    bool multiple = false,
  }) async => picks;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late _Storage storage;
  late FakeBooks books;

  Future<void> open(WidgetTester tester) async {
    storage = _Storage();
    books = FakeBooks((_) => FakeArchiveFs(['1.jpg', '2.jpg']));
    final h = await PhotosHarness.create(tester);
    await h.pump(
      tester,
      entries: fakeEntries(days: 1, firstId: 1),
      extra: [
        storageProvider.overrideWithValue(storage),
        archiveBooksProvider.overrideWithValue(books),
      ],
    );
    await tester.tap(find.text('Albums'));
    await tester.pumpAndSettle();
  }

  testWidgets('IMG-017 the Albums tab leads to the comic reader', (
    tester,
  ) async {
    await open(tester);
    expect(find.text('Comics and archives'), findsOneWidget);
    storage.picks.add(
      PickedFile(uri: Uri.parse('file:///books/vol1.cbz'), name: 'vol1.cbz'),
    );
    await tester.tap(find.text('Comics and archives'));
    // The pages' spinners never rest, so there is no settling.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.byType(ComicReaderScreen), findsOneWidget);
    expect(find.text('vol1.cbz'), findsWidgets);
    expect(books.passphrases, [null]);
  });

  testWidgets('IMG-017 a file that is not an archive is refused', (
    tester,
  ) async {
    await open(tester);
    storage.picks.add(
      PickedFile(uri: Uri.parse('file:///books/notes.txt'), name: 'notes.txt'),
    );
    await tester.tap(find.text('Comics and archives'));
    await tester.pumpAndSettle();
    expect(find.byType(ComicReaderScreen), findsNothing);
    expect(
      find.text(
        'That is not an archive the reader opens (ZIP, CBZ, RAR, CBR, 7z).',
      ),
      findsOneWidget,
    );
    expect(books.passphrases, isEmpty);
  });

  testWidgets('IMG-017 choosing nothing does nothing', (tester) async {
    await open(tester);
    await tester.tap(find.text('Comics and archives'));
    await tester.pumpAndSettle();
    expect(find.byType(ComicReaderScreen), findsNothing);
  });
}
