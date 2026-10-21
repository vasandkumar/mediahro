import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart' hide ImageInfo;
import 'package:flutter_test/flutter_test.dart';
import 'package:mediahro/core/db/library_database.dart';
import 'package:mediahro/features/photos/output/output_actions.dart';
import 'package:mediahro/features/photos/output/photo_output_service.dart';
import 'package:mediahro/features/photos/photo_files.dart';
import 'package:mediahro/features/photos/photos_providers.dart';
import 'package:mediahro/features/photos/photos_settings.dart';
import 'package:mediahro/features/photos/timeline/timeline_model.dart';
import 'package:mediahro/images/image_pipeline.dart';
import 'package:mediahro/images/metadata/jpeg.dart';
import 'package:mediahro/images/pipeline/image_worker.dart';
import 'package:mediahro/images/pipeline/mediahro_image_pipeline.dart';
import 'package:mediahro/images/pipeline/thumbnail_cache.dart';
import 'package:mediahro/images/pipeline/worker_pool.dart';
import 'package:mediahro/platform/imaging.dart';
import 'package:mediahro/platform/storage.dart';
import 'package:mediahro_design/mediahro_design.dart';

import '../../images/fixtures.dart';
import '../../images/pipeline_fakes.dart';
import 'photos_harness.dart';

final class _Imaging implements ImagingFacade {
  ImagingSupport supportValue = const ImagingSupport(
    wallpaperTargets: {
      WallpaperTarget.home,
      WallpaperTarget.lock,
      WallpaperTarget.both,
    },
    print: true,
  );
  final List<(Uri, WallpaperTarget)> wallpapers = [];
  final List<(List<Uri>, PrintLayout)> prints = [];
  final List<Uri> copies = [];
  bool printResult = true;
  bool fail = false;

  @override
  Future<ImagingSupport> support() async => supportValue;

  @override
  Future<void> setWallpaper(Uri image, WallpaperTarget target) async {
    if (fail) throw StateError('no');
    wallpapers.add((image, target));
  }

  @override
  Future<bool> printImages(List<Uri> images, PrintLayout layout) async {
    if (fail) throw StateError('no');
    prints.add((images, layout));
    return printResult;
  }

  @override
  Future<void> copyImage(Uri image) async {
    if (fail) throw StateError('no');
    copies.add(image);
  }

  @override
  Object? noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _Storage implements StorageFacade {
  final List<List<Uri>> shared = [];
  bool fail = false;

  @override
  Future<void> share(List<Uri> uris, {String? subject}) async {
    if (fail) throw StateError('no');
    shared.add(uris);
  }

  @override
  Object? noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Every photo lives at the URI given in [uris] (default: a plain local
/// file in [dir]); opening reads [data].
final class _Files implements PhotoFileOpener {
  _Files(this.dir);

  final Directory dir;
  final Map<String, Uri> uris = {};
  final Map<String, Uint8List> data = {};

  @override
  Future<Uri> uriOf(PhotoEntry e) async =>
      uris[e.relPath] ?? File('${dir.path}/${e.relPath}').uri;

  @override
  Future<ImageSource> open(PhotoEntry e) async {
    final uri = await uriOf(e);
    return ImageSource(
      MemoryFile(uri, data[e.relPath]!),
      mtime: DateTime.utc(2026, 10, 21),
    );
  }
}

PhotoEntry _photo(String rel, {int id = 1, bool video = false}) {
  final base = fakeEntries(days: 1, perDay: 1, firstId: id).single;
  final name = rel.split('/').last;
  return PhotoEntry(
    id: id,
    sourceId: 1,
    relPath: rel,
    name: name,
    ext: name.split('.').last.toLowerCase(),
    isVideo: video,
    size: 1,
    mtime: base.mtime,
    date: base.date,
  );
}

void main() {
  group('IMG-015 output service', () {
    late Directory dir;
    late LibraryDatabase db;
    late MediahroImagePipeline pipeline;
    late _Imaging imaging;
    late _Storage storage;
    late _Files files;
    late PhotoOutputService out;
    var now = DateTime.now();

    setUp(() {
      dir = Directory.systemTemp.createTempSync('mediahro-output');
      db = LibraryDatabase.memory();
      imaging = _Imaging();
      storage = _Storage();
      files = _Files(dir);
      now = DateTime.now();
      pipeline = MediahroImagePipeline(
        worker: ImageWorkerClient(
          IsolateWorkerPool(size: 1, factory: fakeWorker),
        ),
        cache: ThumbnailCache(db: db, directory: Directory('${dir.path}/.t')),
        io: MemoryIo(),
        fallback: FakeUiFallback(),
      );
      out = PhotoOutputService(
        files: files,
        pipeline: pipeline,
        imaging: imaging,
        storage: storage,
        staging: Directory('${dir.path}/staging'),
        clock: () => now,
      );
    });

    tearDown(() async {
      await pipeline.dispose();
      await db.close();
      dir.deleteSync(recursive: true);
    });

    final remote = Uri.parse('mediastore://device/42');

    test('IMG-015 a plain local photo is shared as it is', () async {
      files.data['p/a.jpg'] = sampleJpeg();
      await out.share([_photo('p/a.jpg')], const ShareOptions());
      expect(storage.shared.single.single, File('${dir.path}/p/a.jpg').uri);
      expect(
        Directory('${dir.path}/staging')
            .listSync(recursive: true)
            .whereType<File>(),
        isEmpty,
      );
    });

    test(
      'IMG-015 a photo from the device library is copied out first',
      () async {
        final bytes = sampleJpeg(exif: sampleExif());
        files.uris['p/a.jpg'] = remote;
        files.data['p/a.jpg'] = bytes;
        await out.share([_photo('p/a.jpg')], const ShareOptions());
        final shared = storage.shared.single.single;
        expect(shared.scheme, 'file');
        expect(shared.pathSegments.last, 'a.jpg');
        expect(File.fromUri(shared).readAsBytesSync(), bytes);
      },
    );

    test(
      'IMG-015 a smaller size is re-encoded into the staging folder',
      () async {
        files.data['p/a.png'] = fakeImage(8, 4);
        await out.share([_photo('p/a.png')], const ShareOptions(maxEdge: 4));
        final f = File.fromUri(storage.shared.single.single);
        expect(
          f.path,
          startsWith('${dir.path}${Platform.pathSeparator}staging'),
        );
        final b = f.readAsBytesSync();
        expect((b[1], b[2]), (4, 2));
      },
    );

    test(
      'IMG-015 removing metadata alone does not re-encode the picture',
      () async {
        final original = sampleJpeg(exif: sampleExif());
        files.data['p/a.jpg'] = original;
        await out.share([
          _photo('p/a.jpg'),
        ], const ShareOptions(stripMetadata: true));
        final sent = File.fromUri(storage.shared.single.single)
            .readAsBytesSync();
        expect(
          JpegFile.parse(sent).exif,
          isNotNull,
          reason: 'orientation stays',
        );
        expect(sent.length, lessThan(original.length));
      },
    );

    test(
      'IMG-015 a format that cannot be cleaned is re-encoded as JPEG',
      () async {
        files.data['p/a.heic'] = fakeImage(4, 2);
        await out.share([
          _photo('p/a.heic'),
        ], const ShareOptions(stripMetadata: true));
        expect(storage.shared.single.single.pathSegments.last, 'a.jpg');
      },
    );

    test('IMG-015 videos go as they are', () async {
      files.uris['v/c.mp4'] = remote;
      files.data['v/c.mp4'] = Uint8List.fromList([1, 2, 3, 4]);
      await out.share([
        _photo('v/c.mp4', video: true),
      ], const ShareOptions(maxEdge: 100, stripMetadata: true));
      expect(File.fromUri(storage.shared.single.single).readAsBytesSync(), [
        1,
        2,
        3,
        4,
      ]);
    });

    test('IMG-015 several photos are shared together', () async {
      files.data['p/a.jpg'] = sampleJpeg();
      files.data['p/b.jpg'] = sampleJpeg();
      await out.share([
        _photo('p/a.jpg'),
        _photo('p/b.jpg', id: 2),
      ], const ShareOptions());
      expect(storage.shared.single, hasLength(2));
    });

    test('IMG-015 old staged copies are cleaned up, new ones kept', () async {
      files.uris['p/a.jpg'] = remote;
      files.data['p/a.jpg'] = sampleJpeg();
      await out.share([_photo('p/a.jpg')], const ShareOptions());
      final staging = Directory('${dir.path}/staging');
      expect(staging.listSync(), hasLength(1));
      now = now.add(const Duration(minutes: 30));
      await out.cleanStaging();
      expect(staging.listSync(), hasLength(1));
      now = now.add(const Duration(hours: 3));
      await out.cleanStaging();
      expect(staging.listSync(), isEmpty);
    });

    test('IMG-015 setting a wallpaper hands the OS a readable file', () async {
      files.data['p/a.jpg'] = sampleJpeg();
      await out.setWallpaper(_photo('p/a.jpg'), WallpaperTarget.lock);
      expect(imaging.wallpapers.single.$1, File('${dir.path}/p/a.jpg').uri);
      expect(imaging.wallpapers.single.$2, WallpaperTarget.lock);
    });

    test(
      'IMG-015 printing passes the layout and says if it was cancelled',
      () async {
        files.data['p/a.jpg'] = sampleJpeg();
        files.data['p/b.jpg'] = sampleJpeg();
        imaging.printResult = false;
        const layout = PrintLayout(perPage: 4, fill: true, captions: true);
        final printed = await out.print([
          _photo('p/a.jpg'),
          _photo('p/b.jpg', id: 2),
        ], layout);
        expect(printed, isFalse);
        expect(imaging.prints.single.$1, hasLength(2));
        expect(imaging.prints.single.$2.perPage, 4);
      },
    );

    test('IMG-015 a library photo is staged before it is copied', () async {
      files.uris['p/a.jpg'] = remote;
      files.data['p/a.jpg'] = sampleJpeg();
      await out.copy(_photo('p/a.jpg'));
      expect(imaging.copies.single.scheme, 'file');
      expect(File.fromUri(imaging.copies.single).existsSync(), isTrue);
    });

    test('IMG-015 what the OS offers is passed on', () async {
      expect((await out.support()).print, isTrue);
    });
  });

  group('IMG-015 menus and sheets', () {
    Future<(PhotosHarness, _FakeOutput)> open(
      WidgetTester tester, {
      ImagingSupport support = const ImagingSupport(
        wallpaperTargets: {
          WallpaperTarget.home,
          WallpaperTarget.lock,
          WallpaperTarget.both,
        },
        print: true,
      ),
      Map<String, Object?> settings = const {},
      bool failing = false,
    }) async {
      final h = await PhotosHarness.create(tester);
      final fake = _FakeOutput(support)..fail = failing;
      await h.pump(
        tester,
        entries: fakeEntries(days: 1, firstId: 1),
        settings: settings,
        extra: [photoOutputProvider.overrideWithValue(fake)],
      );
      return (h, fake);
    }

    Future<void> openViewerMenu(WidgetTester tester) async {
      await tester.tap(find.byType(KGridTile).first);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('More'));
      await tester.pumpAndSettle();
    }

    testWidgets('IMG-015 the viewer menu offers what this device can do', (
      tester,
    ) async {
      await open(tester);
      await openViewerMenu(tester);
      for (final t in ['Share', 'Set as wallpaper', 'Print', 'Copy image']) {
        expect(find.text(t), findsOneWidget, reason: t);
      }
    });

    testWidgets(
      'IMG-015 without wallpaper or printing those items are not shown',
      (tester) async {
        await open(tester, support: const ImagingSupport());
        await openViewerMenu(tester);
        expect(find.text('Share'), findsOneWidget);
        expect(find.text('Copy image'), findsOneWidget);
        expect(find.text('Set as wallpaper'), findsNothing);
        expect(find.text('Print'), findsNothing);
      },
    );

    testWidgets(
      'IMG-015 the share sheet sends the chosen size and metadata option',
      (tester) async {
        final (h, fake) = await open(tester);
        await openViewerMenu(tester);
        await tester.tap(find.text('Share'));
        await tester.pumpAndSettle();
        expect(find.text('Share 1 photo'), findsOneWidget);
        await tester.tap(find.widgetWithText(ChoiceChip, 'Up to 1280 px'));
        await tester.tap(find.byType(Switch));
        await tester.pump();
        await tester.tap(find.widgetWithText(FilledButton, 'Share'));
        await tester.pumpAndSettle();
        expect(
          fake.shared.single.$1.single.id,
          h.opened.isEmpty ? 1 : h.opened.first.id,
        );
        expect(fake.shared.single.$2.maxEdge, 1280);
        expect(fake.shared.single.$2.stripMetadata, isTrue);
      },
    );

    testWidgets('IMG-015 the share sheet starts as the setting says', (
      tester,
    ) async {
      final (_, fake) = await open(
        tester,
        settings: {PhotoSettings.stripOnShare.id: true},
      );
      await openViewerMenu(tester);
      await tester.tap(find.text('Share'));
      await tester.pumpAndSettle();
      expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);
      await tester.tap(find.widgetWithText(FilledButton, 'Share'));
      await tester.pumpAndSettle();
      expect(fake.shared.single.$2.stripMetadata, isTrue);
      expect(fake.shared.single.$2.maxEdge, isNull);
    });

    testWidgets('IMG-015 sharing is off to start with, as the spec asks', (
      tester,
    ) async {
      final (_, fake) = await open(tester);
      await openViewerMenu(tester);
      await tester.tap(find.text('Share'));
      await tester.pumpAndSettle();
      expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
      await tester.tap(find.widgetWithText(FilledButton, 'Share'));
      await tester.pumpAndSettle();
      expect(fake.shared.single.$2.isPlain, isTrue);
    });

    testWidgets('IMG-015 a share that fails says so', (tester) async {
      await open(tester, failing: true);
      await openViewerMenu(tester);
      await tester.tap(find.text('Share'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Share'));
      await tester.pumpAndSettle();
      expect(find.textContaining("Couldn't share"), findsOneWidget);
    });

    testWidgets('IMG-015 wallpaper asks home, lock or both', (tester) async {
      final (_, fake) = await open(tester);
      await openViewerMenu(tester);
      await tester.tap(find.text('Set as wallpaper'));
      await tester.pumpAndSettle();
      expect(find.text('Home screen'), findsOneWidget);
      expect(find.text('Lock screen'), findsOneWidget);
      await tester.tap(find.text('Home and lock screens'));
      await tester.pumpAndSettle();
      expect(fake.wallpapers.single.$2, WallpaperTarget.both);
      expect(find.text('Wallpaper set.'), findsOneWidget);
    });

    testWidgets('IMG-015 one possible target needs no question', (
      tester,
    ) async {
      final (_, fake) = await open(
        tester,
        support: const ImagingSupport(
          wallpaperTargets: {WallpaperTarget.desktop},
        ),
      );
      await openViewerMenu(tester);
      await tester.tap(find.text('Set as wallpaper'));
      await tester.pumpAndSettle();
      expect(fake.wallpapers.single.$2, WallpaperTarget.desktop);
    });

    testWidgets('IMG-015 print takes the layout from a dialog', (tester) async {
      final (_, fake) = await open(tester);
      await openViewerMenu(tester);
      await tester.tap(find.text('Print'));
      await tester.pumpAndSettle();
      expect(find.text('Print layout'), findsOneWidget);
      await tester.tap(find.widgetWithText(ChoiceChip, '4 photos per page'));
      await tester.tap(find.text('Add the file name under each photo'));
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Print'));
      await tester.pumpAndSettle();
      expect(fake.prints.single.$2.perPage, 4);
      expect(fake.prints.single.$2.captions, isTrue);
      expect(fake.prints.single.$2.fill, isFalse);
    });

    testWidgets('IMG-015 copy image confirms', (tester) async {
      final (_, fake) = await open(tester);
      await openViewerMenu(tester);
      await tester.tap(find.text('Copy image'));
      await tester.pumpAndSettle();
      expect(fake.copies, hasLength(1));
      expect(find.text('Image copied.'), findsOneWidget);
    });

    testWidgets('IMG-015 the selection bar shares and prints several photos', (
      tester,
    ) async {
      final (_, fake) = await open(tester);
      await tester.longPress(find.byType(KGridTile).at(0));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(KGridTile).at(1));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('More'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Share'));
      await tester.pumpAndSettle();
      expect(find.text('Share 2 photos'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Share'));
      await tester.pumpAndSettle();
      expect(fake.shared.single.$1, hasLength(2));
      await tester.tap(find.byTooltip('More'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Print'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Print'));
      await tester.pumpAndSettle();
      expect(fake.prints.single.$1, hasLength(2));
    });

    test('IMG-015 the menu lists only what makes sense for the selection', () {
      const all = ImagingSupport(
        wallpaperTargets: {WallpaperTarget.home},
        print: true,
      );
      expect(outputActionsFor(all), [
        OutputAction.share,
        OutputAction.wallpaper,
        OutputAction.print,
        OutputAction.copy,
        OutputAction.vault,
        OutputAction.delete,
      ]);
      expect(outputActionsFor(all, single: false), [
        OutputAction.share,
        OutputAction.print,
        OutputAction.vault,
        OutputAction.delete,
      ]);
      expect(outputActionsFor(const ImagingSupport()), [
        OutputAction.share,
        OutputAction.copy,
        OutputAction.vault,
        OutputAction.delete,
      ]);
    });
  });
}

final class _FakeOutput implements PhotoOutput {
  _FakeOutput(this.supportValue);

  final ImagingSupport supportValue;
  bool fail = false;
  final List<(List<PhotoEntry>, ShareOptions)> shared = [];
  final List<(PhotoEntry, WallpaperTarget)> wallpapers = [];
  final List<(List<PhotoEntry>, PrintLayout)> prints = [];
  final List<PhotoEntry> copies = [];

  @override
  Future<ImagingSupport> support() async => supportValue;

  @override
  Future<void> share(List<PhotoEntry> photos, ShareOptions options) async {
    if (fail) throw StateError('no');
    shared.add((photos, options));
  }

  @override
  Future<void> setWallpaper(PhotoEntry photo, WallpaperTarget target) async =>
      wallpapers.add((photo, target));

  @override
  Future<bool> print(List<PhotoEntry> photos, PrintLayout layout) async {
    prints.add((photos, layout));
    return true;
  }

  @override
  Future<void> copy(PhotoEntry photo) async => copies.add(photo);

  @override
  Future<Uri> readableUri(PhotoEntry photo) async =>
      Uri.parse('file:///tmp/${photo.name}');
}
