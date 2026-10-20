// Lane C3 device batch, compare and reject (IMG-008, IMG-005): the compare
// screen on two real JPEGs, with the real image worker and real XMP
// write-back, checking that rejecting writes xmp:Rating -1 into the file and
// taking the rejection back gives the file its stars again.
//
//   flutter test integration_test/c3_compare_test.dart -d <serial> --no-dds \
//     -P kotlin.incremental=false
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart' hide ImageInfo;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mediahro/app/l10n/gen/app_localizations.dart';
import 'package:mediahro/core/db/library_database.dart';
import 'package:mediahro/core/files/file_systems.dart';
import 'package:mediahro/core/providers.dart';
import 'package:mediahro/features/photos/compare/compare_screen.dart';
import 'package:mediahro/features/photos/image_prober.dart';
import 'package:mediahro/features/photos/info/metadata_edit_service.dart';
import 'package:mediahro/features/photos/organise/photo_organiser.dart';
import 'package:mediahro/features/photos/organise/write_back.dart';
import 'package:mediahro/features/photos/photo_files.dart';
import 'package:mediahro/features/photos/photos_providers.dart';
import 'package:mediahro/features/photos/timeline/timeline_model.dart';
import 'package:mediahro/images/image_pipeline.dart';
import 'package:mediahro/images/pipeline/image_io.dart';
import 'package:mediahro/images/pipeline/image_worker.dart';
import 'package:mediahro/images/pipeline/mediahro_image_pipeline.dart';
import 'package:mediahro/images/pipeline/thumbnail_cache.dart';
import 'package:mediahro/images/pipeline/worker_pool.dart';
import 'package:mediahro_ffi/mediahro_ffi.dart' show LocalFileSystem;

import '../test/core/seed.dart';

Uint8List gradient(int w, int h, int tint) {
  final b = Uint8List(w * h * 4);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final i = (y * w + x) * 4;
      b[i] = (x * 255) ~/ (w - 1);
      b[i + 1] = (y * 255) ~/ (h - 1);
      b[i + 2] = tint;
      b[i + 3] = 255;
    }
  }
  return b;
}

/// Photos at `dir/relPath`.
final class _Files implements PhotoFileOpener {
  _Files(this.dir);

  final Directory dir;

  @override
  Future<Uri> uriOf(PhotoEntry e) async => File('${dir.path}/${e.relPath}').uri;

  @override
  Future<ImageSource> open(PhotoEntry e) async => ImageSource(
    await const LocalFileSystem().open(await uriOf(e)),
    mtime: e.mtime,
  );
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late LibraryDatabase db;
  late MediahroImagePipeline pipeline;
  late _Files files;
  late List<PhotoEntry> photos;
  var writeBack = true;

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('c3-compare');
    db = LibraryDatabase.memory();
    pipeline = MediahroImagePipeline(
      worker: ImageWorkerClient(
        IsolateWorkerPool(size: 2, factory: defaultImageWorker),
      ),
      cache: ThumbnailCache(db: db, directory: Directory('${dir.path}/thumbs')),
      io: MountedImageIo(MountedFileSystems()),
    );
    files = _Files(dir);
    writeBack = true;
    final seed = Seed(db);
    final out = <PhotoEntry>[];
    for (var i = 1; i <= 2; i++) {
      final jpeg = await pipeline.encode(
        DecodedImage(
          width: 640,
          height: 480,
          pixels: gradient(640, 480, i * 90),
        ),
        const EncodeOptions(format: EncodeFormat.jpeg),
      );
      File('${dir.path}/IMG_$i.jpg').writeAsBytesSync(jpeg);
      final id = await seed.item('IMG_$i.jpg', kind: ItemKind.image);
      out.add(
        PhotoEntry(
          id: id,
          sourceId: 1,
          relPath: 'IMG_$i.jpg',
          name: 'IMG_$i.jpg',
          ext: 'jpg',
          isVideo: false,
          size: jpeg.length,
          mtime: DateTime(2026, 10, 21),
          date: DateTime(2026, 10, 21, 10, i),
          width: 640,
          height: 480,
        ),
      );
    }
    photos = out;
  });

  tearDown(() async {
    await pipeline.dispose();
    await db.close();
    dir.deleteSync(recursive: true);
  });

  Future<int?> fileRating(PhotoEntry p) async {
    final src = await files.open(p);
    try {
      return (await pipeline.metadata(src)).rating;
    } finally {
      await src.file.close();
    }
  }

  Future<void> giveStars(PhotoEntry p, int stars) async {
    final prober = ImageProber(
      pipeline: pipeline,
      db: db,
      io: MountedImageIo(MountedFileSystems()),
    );
    await MetadataEditService(
      files: files,
      pipeline: pipeline,
      prober: prober,
      db: db,
    ).save(p, ImageMetadataEdit(rating: stars));
    await PhotoOrganiser(db: db).setRating([p.id], stars);
  }

  Future<void> open(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          libraryDatabaseProvider.overrideWithValue(db),
          imagePipelineProvider.overrideWithValue(pipeline),
          photoFilesProvider.overrideWithValue(files),
          imageProberProvider.overrideWith(
            (ref) => ImageProber(
              pipeline: pipeline,
              db: db,
              io: MountedImageIo(MountedFileSystems()),
            ),
          ),
          organisationWriteBackProvider.overrideWith(
            (ref) => OrganisationWriteBack(
              editor: ref.watch(metadataEditServiceProvider),
              organiser: ref.watch(photoOrganiserProvider),
              enabled: () => writeBack,
              fileRating: fileRating,
            ),
          ),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: CompareScreen(photos: photos),
        ),
      ),
    );
    await tester.pumpAndSettle(const Duration(seconds: 1));
  }

  /// Taps the button and waits for the library and the file writes.
  Future<void> tap(WidgetTester tester, String tooltip) async {
    await tester.tap(find.byTooltip(tooltip));
    await tester.pump();
    await Future<void>.delayed(const Duration(milliseconds: 800));
    await tester.pumpAndSettle();
  }

  testWidgets('IMG-008 two real photos load side by side', (tester) async {
    await open(tester);
    expect(find.byType(RawImage), findsNWidgets(2));
  });

  testWidgets(
    'IMG-008 rejecting writes -1 and un-rejecting restores the stars',
    (tester) async {
      await giveStars(photos[0], 3);
      expect(await fileRating(photos[0]), 3);
      await open(tester);
      await tap(tester, 'Reject IMG_1.jpg');
      expect(await fileRating(photos[0]), -1);
      await tap(tester, 'Reject IMG_1.jpg');
      expect(await fileRating(photos[0]), 3);
      expect(
        (await (db.select(
          db.ratings,
        )..where((r) => r.itemId.equals(photos[0].id))).getSingle()).value,
        6,
      );
    },
  );

  testWidgets('IMG-008 a photo rejected with write-back off keeps its stars', (
    tester,
  ) async {
    writeBack = false;
    await giveStars(photos[1], 4);
    await open(tester);
    await tap(tester, 'Reject IMG_2.jpg');
    expect(await fileRating(photos[1]), 4);
    writeBack = true;
    await tap(tester, 'Reject IMG_2.jpg');
    expect(await fileRating(photos[1]), 4);
  });

  testWidgets('IMG-008 with write-back off no file is written', (tester) async {
    writeBack = false;
    await open(tester);
    final before = [
      for (final p in photos)
        File('${dir.path}/${p.relPath}').readAsBytesSync(),
    ];
    await tap(tester, 'Reject IMG_1.jpg');
    await tap(tester, 'Reject IMG_1.jpg');
    for (var i = 0; i < photos.length; i++) {
      expect(
        File('${dir.path}/${photos[i].relPath}').readAsBytesSync(),
        before[i],
      );
    }
  });
}
