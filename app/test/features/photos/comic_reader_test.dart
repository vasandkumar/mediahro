import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart' hide ImageInfo;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediahro/app/l10n/gen/app_localizations.dart';
import 'package:mediahro/features/photos/archive/archive_book.dart';
import 'package:mediahro/features/photos/archive/archive_providers.dart';
import 'package:mediahro/features/photos/archive/comic_reader.dart';
import 'package:mediahro/features/photos/archive/reader_layout.dart';
import 'package:mediahro/features/photos/archive/reader_positions.dart';
import 'package:mediahro/features/photos/archive/reader_settings.dart';
import 'package:mediahro/features/photos/viewer/viewer_image.dart';
import 'package:mediahro/features/settings/settings_providers.dart';
import 'package:mediahro/features/settings/settings_store.dart';
import 'package:mediahro/images/image_pipeline.dart';
import 'package:mediahro_ffi/mediahro_ffi.dart'
    show VirtualFileError, VirtualFileException;

import '../../helpers.dart';
import 'archive_support.dart';

const _portrait = ui.Size(600, 900);
const _wide = ui.Size(1800, 900);

Future<ui.Image> _pic(WidgetTester tester) async {
  final made = await tester.runAsync(() {
    final rec = ui.PictureRecorder();
    ui.Canvas(rec).drawRect(
      const ui.Rect.fromLTWH(0, 0, 8, 6),
      ui.Paint()..color = const Color(0xFF336699),
    );
    return rec.endRecording().toImage(8, 6);
  });
  return made!;
}

/// Places kept in memory (the widget tests do no file work).
final class MemoryPositions extends ReaderPositions {
  final Map<String, int> pages = {};

  @override
  Future<int> page(String book) async => pages[book] ?? 0;

  @override
  Future<void> save(String book, int page) async => pages[book] = page;
}

void main() {
  late SettingsStore store;
  var positions = MemoryPositions();
  late FakeBooks books;
  late List<ui.Size> sizes;
  final loaded = <int>[];
  final disposed = <int>[];

  final ref = ArchiveRef(
    uri: Uri.parse('file:///books/vol1.cbz'),
    name: 'vol1.cbz',
  );

  Future<void> open(
    WidgetTester tester, {
    int pages = 5,
    FakeBooks? withBooks,
    List<ui.Size>? pageSizes,
    Map<String, Object?>? settings,
    SettingsStore? useStore,
  }) async {
    sizes = pageSizes ?? List.filled(pages, _portrait);
    if (useStore == null) positions = MemoryPositions();
    loaded.clear();
    disposed.clear();
    store = useStore ?? (await tester.runAsync(() => memoryStore(settings)))!;
    books =
        withBooks ??
        FakeBooks(
          (_) => FakeArchiveFs([for (var i = 1; i <= pages; i++) 'p$i.jpg']),
        );
    tester.view
      ..physicalSize = const Size(400, 800)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final picture = await _pic(tester);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsStoreProvider.overrideWithValue(store),
          readerPositionsProvider.overrideWithValue(positions),
          archiveBooksProvider.overrideWithValue(books),
          comicPageLoaderProvider.overrideWithValue((book, index) async {
            loaded.add(index);
            return ViewerImage(
              base: picture.clone(),
              fullSize: sizes[index],
              info: ImageInfo(
                width: sizes[index].width.round(),
                height: sizes[index].height.round(),
                format: 'jpeg',
              ),
              onDispose: () async => disposed.add(index),
            );
          }),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: ComicReaderScreen(archive: ref),
        ),
      ),
    );
    await _settle(tester);
  }

  Future<void> next(WidgetTester tester) async {
    await tester.tapAt(const Offset(380, 400));
    await _settle(tester);
  }

  Future<void> back(WidgetTester tester) async {
    await tester.tapAt(const Offset(20, 400));
    await _settle(tester);
  }

  Future<void> choose(WidgetTester tester, String chip) async {
    await tester.tap(find.byTooltip('Reading settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(chip));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(200, 20));
    await _settle(tester);
  }

  group('IMG-017 reading a book', () {
    testWidgets('IMG-017 it opens on the first page and loads the next', (
      tester,
    ) async {
      await open(tester);
      expect(find.text('Page 1 of 5'), findsWidgets);
      expect(loaded, containsAll([0, 1]));
      expect(loaded, isNot(contains(4)));
    });

    testWidgets('IMG-017 the edges of the screen turn the page', (
      tester,
    ) async {
      await open(tester);
      await next(tester);
      expect(find.text('Page 2 of 5'), findsWidgets);
      await next(tester);
      expect(find.text('Page 3 of 5'), findsWidgets);
      await back(tester);
      expect(find.text('Page 2 of 5'), findsWidgets);
    });

    testWidgets('IMG-017 pages far away are let go and near ones kept', (
      tester,
    ) async {
      await open(tester, pages: 8);
      for (var i = 0; i < 4; i++) {
        await next(tester);
      }
      expect(find.text('Page 5 of 8'), findsWidgets);
      expect(disposed, containsAll([0, 1, 2]));
      expect(disposed, isNot(contains(4)));
    });

    testWidgets('IMG-017 the middle shows and hides the controls', (
      tester,
    ) async {
      await open(tester);
      expect(find.byTooltip('Reading settings'), findsOneWidget);
      final bar = find.byType(AnimatedOpacity).first;
      expect(tester.widget<AnimatedOpacity>(bar).opacity, 1);
      await tester.tapAt(const Offset(200, 400));
      await _settle(tester);
      expect(tester.widget<AnimatedOpacity>(bar).opacity, 0);
    });

    testWidgets('IMG-017 the keyboard turns pages', (tester) async {
      await open(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await _settle(tester);
      expect(find.text('Page 2 of 5'), findsWidgets);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await _settle(tester);
      expect(find.text('Page 1 of 5'), findsWidgets);
      await tester.sendKeyEvent(LogicalKeyboardKey.end);
      await _settle(tester);
      expect(find.text('Page 5 of 5'), findsWidgets);
      await tester.sendKeyEvent(LogicalKeyboardKey.home);
      await _settle(tester);
      expect(find.text('Page 1 of 5'), findsWidgets);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await _settle(tester);
      expect(find.text('Page 2 of 5'), findsWidgets);
    });

    testWidgets('IMG-017 the next button goes forward', (tester) async {
      await open(tester);
      await tester.tap(find.byTooltip('Next page'));
      await _settle(tester);
      expect(find.text('Page 2 of 5'), findsWidgets);
      await tester.tap(find.byTooltip('Previous page'));
      await _settle(tester);
      expect(find.text('Page 1 of 5'), findsWidgets);
    });
  });

  group('IMG-017 right to left', () {
    testWidgets('IMG-017 the left edge goes forward and the buttons swap', (
      tester,
    ) async {
      await open(tester);
      await choose(tester, 'Right to left');
      expect(store.get(ReaderPrefs.direction), ReadingDirection.rightToLeft);
      await back(tester);
      expect(find.text('Page 2 of 5'), findsWidgets);
      await next(tester);
      expect(find.text('Page 1 of 5'), findsWidgets);
      // The chevron on the left now says Next.
      final left = find.widgetWithIcon(IconButton, Icons.chevron_left);
      expect(tester.widget<IconButton>(left).tooltip, 'Next page');
    });

    testWidgets('IMG-017 the left arrow goes forward', (tester) async {
      await open(tester, settings: {'photos.reader.direction': 'rightToLeft'});
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await _settle(tester);
      expect(find.text('Page 2 of 5'), findsWidgets);
    });
  });

  group('IMG-017 two pages', () {
    testWidgets('IMG-017 two pages show together and count together', (
      tester,
    ) async {
      await open(tester, settings: {'photos.reader.mode': 'double'});
      expect(find.text('Pages 1 and 2 of 5'), findsWidgets);
      expect(find.byType(RawImage), findsNWidgets(2));
      await next(tester);
      expect(find.text('Pages 3 and 4 of 5'), findsWidgets);
      await next(tester);
      expect(find.text('Page 5 of 5'), findsWidgets);
    });

    testWidgets('IMG-017 the cover can stay alone', (tester) async {
      await open(tester, settings: {'photos.reader.mode': 'doubleCoverAlone'});
      expect(find.text('Page 1 of 5'), findsWidgets);
      await next(tester);
      expect(find.text('Pages 2 and 3 of 5'), findsWidgets);
    });

    testWidgets('IMG-017 a double-page picture is shown alone', (tester) async {
      await open(
        tester,
        pageSizes: [_portrait, _portrait, _wide, _portrait, _portrait],
        settings: {'photos.reader.mode': 'double'},
      );
      expect(find.text('Pages 1 and 2 of 5'), findsWidgets);
      await next(tester);
      expect(find.text('Page 3 of 5'), findsWidgets);
      await next(tester);
      expect(find.text('Pages 4 and 5 of 5'), findsWidgets);
    });

    testWidgets('IMG-017 changing to two pages keeps the page on screen', (
      tester,
    ) async {
      await open(tester);
      await next(tester);
      await next(tester);
      await next(tester);
      expect(find.text('Page 4 of 5'), findsWidgets);
      await choose(tester, 'Two pages');
      expect(find.text('Pages 3 and 4 of 5'), findsWidgets);
      expect(store.get(ReaderPrefs.mode), PageMode.double);
    });
  });

  group('IMG-017 fit', () {
    testWidgets('IMG-017 the fit is remembered for the next book', (
      tester,
    ) async {
      await open(tester);
      await choose(tester, 'Width');
      expect(store.get(ReaderPrefs.fit), PageFit.width);
      expect(store.get(ReaderPrefs.mode), PageMode.single);
      expect(find.byType(InteractiveViewer), findsWidgets);
    });
  });

  group('IMG-017 the place is kept', () {
    testWidgets('IMG-017 the book opens where it was left', (tester) async {
      await open(tester);
      await next(tester);
      await next(tester);
      expect(find.text('Page 3 of 5'), findsWidgets);
      await tester.pumpWidget(const SizedBox());
      await open(tester, useStore: store);
      expect(find.text('Page 3 of 5'), findsWidgets);
    });

    testWidgets('IMG-017 another book starts at its own first page', (
      tester,
    ) async {
      await open(tester);
      await next(tester);
      expect(await positions.page(ref.key), 1);
      expect(await positions.page('file:///books/other.cbz'), 0);
    });

    test(
      'IMG-017 a place is kept under a hash, not the name of the book',
      () async {
        final dir = Directory.systemTemp.createTempSync('c3-pos');
        addTearDown(() => dir.deleteSync(recursive: true));
        final pos = ReaderPositions(directory: () async => dir);
        await pos.save('content://docs/secret-diary.cbz', 12);
        expect(await pos.page('content://docs/secret-diary.cbz'), 12);
        expect(await pos.page('content://docs/other.cbz'), 0);
        final file = File(
          '${dir.path}/${ReaderPositions.folder}/reader-positions.json',
        );
        final text = file.readAsStringSync();
        expect(text, isNot(contains('secret')));
        expect(text, isNot(contains('content')));
        expect(
          text,
          contains(ReaderPositions.keyOf('content://docs/secret-diary.cbz')),
        );
        expect(ReaderPositions.keyOf('a'), hasLength(64));
      },
    );

    test('IMG-017 places are not part of the settings', () async {
      final s = await memoryStore();
      final dir = Directory.systemTemp.createTempSync('c3-pos');
      addTearDown(() => dir.deleteSync(recursive: true));
      await ReaderPositions(directory: () async => dir).save('book', 3);
      expect(s.exportJson(), isNot(contains('reader.positions')));
      expect(s.exportJson(), isNot(contains('"book"')));
    });

    test('IMG-017 only the most recent books keep their place', () async {
      final dir = Directory.systemTemp.createTempSync('c3-pos');
      addTearDown(() => dir.deleteSync(recursive: true));
      final pos = ReaderPositions(directory: () async => dir);
      for (var i = 0; i < ReaderPositions.remembered + 5; i++) {
        await pos.save('book$i', i + 1);
      }
      expect(await pos.page('book0'), 0);
      expect(await pos.page('book4'), 0);
      expect(await pos.page('book5'), 6);
      expect(
        await pos.page('book${ReaderPositions.remembered + 4}'),
        ReaderPositions.remembered + 5,
      );
    });

    test('IMG-017 a garbled record is just no places', () async {
      final dir = Directory.systemTemp.createTempSync('c3-pos');
      addTearDown(() => dir.deleteSync(recursive: true));
      File('${dir.path}/${ReaderPositions.folder}/reader-positions.json')
        ..createSync(recursive: true)
        ..writeAsStringSync('nonsense');
      final pos = ReaderPositions(directory: () async => dir);
      expect(await pos.page('anything'), 0);
      // And saving over it works.
      await pos.save('anything', 2);
      expect(await pos.page('anything'), 2);
    });
  });

  group('IMG-017 when the archive cannot be read', () {
    testWidgets('IMG-017 an archive with no pictures says so', (tester) async {
      await open(
        tester,
        withBooks: FakeBooks((_) => FakeArchiveFs(['readme.txt'])),
      );
      expect(
        find.text('There are no pictures in this archive.'),
        findsOneWidget,
      );
    });

    testWidgets('IMG-017 a damaged archive says so', (tester) async {
      await open(
        tester,
        withBooks: FakeBooks(
          (_) => FakeArchiveFs(
            [],
            listError: VirtualFileException(
              VirtualFileError.unsupported,
              testRoot,
            ),
          ),
        ),
      );
      expect(
        find.text("This file can't be read as an archive."),
        findsOneWidget,
      );
    });

    testWidgets('IMG-017 a password is asked for and tried', (tester) async {
      await open(
        tester,
        withBooks: FakeBooks(
          (pass) => FakeArchiveFs(
            pass == null ? [] : ['p1.jpg', 'p2.jpg'],
            listError: pass == null
                ? VirtualFileException(
                    VirtualFileError.authenticationRequired,
                    testRoot,
                  )
                : null,
          ),
        ),
      );
      expect(find.text('Password needed'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'secret');
      await tester.tap(find.text('Open'));
      await _settle(tester);
      expect(books.passphrases, [null, 'secret']);
      expect(find.text('Page 1 of 2'), findsWidgets);
    });

    testWidgets('IMG-017 a wrong password is asked for again, once at a time', (
      tester,
    ) async {
      await open(
        tester,
        withBooks: FakeBooks(
          (pass) => switch (pass) {
            null => FakeArchiveFs(
              [],
              listError: VirtualFileException(
                VirtualFileError.authenticationRequired,
                testRoot,
              ),
            ),
            'good' => FakeArchiveFs(['p1.jpg', 'p2.jpg']),
            _ => FakeArchiveFs(['p1.jpg', 'p2.jpg'], encrypted: {'p1.jpg'}),
          },
        ),
      );
      await tester.enterText(find.byType(TextField), 'wrong');
      await tester.tap(find.text('Open'));
      await _settle(tester);
      expect(
        find.text('That password did not open the archive.'),
        findsOneWidget,
      );
      expect(find.byType(TextField), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'good');
      await tester.tap(find.text('Open'));
      await _settle(tester);
      expect(books.passphrases, [null, 'wrong', 'good']);
      expect(find.text('Page 1 of 2'), findsWidgets);
    });

    testWidgets('IMG-017 refusing the password leaves the book', (
      tester,
    ) async {
      await open(
        tester,
        withBooks: FakeBooks(
          (_) => FakeArchiveFs(
            [],
            listError: VirtualFileException(
              VirtualFileError.authenticationRequired,
              testRoot,
            ),
          ),
        ),
      );
      await tester.tap(find.text('Cancel'));
      await _settle(tester);
      expect(books.passphrases, [null]);
    });

    testWidgets('IMG-017 leaving lets go of the archive', (tester) async {
      await open(tester);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      expect(books.closes, 1);
    });
  });

  group('IMG-017 choosing an archive', () {
    test('IMG-017 archives are recognised by their ending', () {
      for (final n in ['a.zip', 'a.CBZ', 'a.rar', 'a.cbr', 'a.7z', 'a.cb7']) {
        expect(isArchiveName(n), isTrue, reason: n);
      }
      for (final n in ['a.jpg', 'a', 'a.', '.zip.txt']) {
        expect(isArchiveName(n), isFalse, reason: n);
      }
    });
  });
}

/// Lets the loads (a few microtasks) and the page animation finish. The
/// spinner of a page that has not loaded keeps animating, so nothing waits
/// for it to rest.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}
