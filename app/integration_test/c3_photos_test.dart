// Lane C3 device batch (IMG-001, IMG-003, IMG-004, IMG-006): runs on the
// owner's Samsung under the orchestrator's on-device lock. It needs the
// Android build with libvips from mediahro-deps, so it cannot run on a
// desktop test host.
//
//   flutter test integration_test/c3_photos_test.dart -d <serial> --no-dds \
//     -P kotlin.incremental=false
//
// Reports (binding.reportData): photos_thumb_ms, photos_region_ms,
// photos_scroll_frames, photos_scroll_jank_frames.
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart' hide ImageInfo;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mediahro/app/app.dart';
import 'package:mediahro/app/router.dart';
import 'package:mediahro/core/db/library_database.dart';
import 'package:mediahro/core/files/file_systems.dart';
import 'package:mediahro/core/providers.dart';
import 'package:mediahro/features/photos/photos_providers.dart';
import 'package:mediahro/features/photos/timeline/thumbnail_controller.dart';
import 'package:mediahro/features/photos/timeline/timeline_model.dart';
import 'package:mediahro/images/image_pipeline.dart';
import 'package:mediahro/images/pipeline/image_io.dart';
import 'package:mediahro/images/pipeline/image_worker.dart';
import 'package:mediahro/images/pipeline/mediahro_image_pipeline.dart';
import 'package:mediahro/images/pipeline/thumbnail_cache.dart';
import 'package:mediahro/images/pipeline/worker_pool.dart';
import 'package:mediahro_ffi/mediahro_ffi.dart';

/// A [w]×[h] RGBA gradient.
VipsPixels gradient(int w, int h) {
  final b = Uint8List(w * h * 4);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final i = (y * w + x) * 4;
      b[i] = (x * 255) ~/ (w - 1);
      b[i + 1] = (y * 255) ~/ (h - 1);
      b[i + 2] = ((x + y) * 255) ~/ (w + h - 2);
      b[i + 3] = 255;
    }
  }
  return VipsPixels(w, h, b);
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late LibraryDatabase db;
  late MediahroImagePipeline pipeline;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('c3-photos');
    db = LibraryDatabase.memory();
    pipeline = MediahroImagePipeline(
      worker: ImageWorkerClient(
        IsolateWorkerPool(size: 2, factory: defaultImageWorker),
      ),
      cache: ThumbnailCache(db: db, directory: Directory('${dir.path}/thumbs')),
      io: MountedImageIo(MountedFileSystems()),
    );
  });

  tearDown(() async {
    await pipeline.dispose();
    await db.close();
    dir.deleteSync(recursive: true);
  });

  Future<ImageSource> open(File f) async {
    final vf = await const LocalFileSystem().open(f.uri);
    return ImageSource(vf, mtime: f.lastModifiedSync());
  }

  File write(String name, List<int> bytes) =>
      File('${dir.path}/$name')..writeAsBytesSync(bytes);

  testWidgets('IMG-001 libvips is loaded and reads JPEG, PNG, WebP and TIFF', (
    tester,
  ) async {
    expect(NativeLibraries.isAvailable(NativeLibrary.vips), isTrue);
    final vips = VipsCodec.open();
    final src = gradient(320, 200);
    for (final (name, format) in [
      ('a.jpg', VipsSaveFormat.jpeg),
      ('a.png', VipsSaveFormat.png),
      ('a.webp', VipsSaveFormat.webp),
      ('a.tif', VipsSaveFormat.tiff),
    ]) {
      final f = write(name, vips.encode(src, format));
      final info = await pipeline.info(await open(f));
      expect((info.width, info.height), (320, 200), reason: name);
    }
  });

  testWidgets('IMG-003 thumbnails come from the worker pool and are cached', (
    tester,
  ) async {
    final vips = VipsCodec.open();
    final f = write(
      'big.jpg',
      vips.encode(gradient(4000, 3000), VipsSaveFormat.jpeg),
    );
    final src = await open(f);
    final sw = Stopwatch()..start();
    final thumb = await pipeline.thumbnailFile(src, 256);
    sw.stop();
    binding.reportData = {'photos_thumb_ms': sw.elapsedMilliseconds};
    expect(thumb.path, endsWith('.webp'));
    final head = thumb.readAsBytesSync().sublist(0, 12);
    expect(String.fromCharCodes(head.sublist(0, 4)), 'RIFF');
    expect(String.fromCharCodes(head.sublist(8, 12)), 'WEBP');
    final again = await pipeline.thumbnailFile(src, 256);
    expect(again.path, thumb.path);
    final decoded = await pipeline.thumbnail(src, 256);
    expect(decoded.width, 256);
    expect(decoded.height, 192);
  });

  testWidgets('IMG-004 regions of a large image decode at 1:1 and reduced', (
    tester,
  ) async {
    final vips = VipsCodec.open();
    final f = write(
      'large.png',
      vips.encode(gradient(3000, 2000), VipsSaveFormat.png),
    );
    final src = await open(f);
    final sw = Stopwatch()..start();
    final tile = await pipeline.decode(
      src,
      region: const ImageRegion(1000, 500, 512, 512),
    );
    sw.stop();
    binding.reportData = {'photos_region_ms': sw.elapsedMilliseconds};
    expect((tile.width, tile.height), (512, 512));
    final half = await pipeline.decode(
      src,
      region: const ImageRegion(0, 0, 1024, 1024),
      scale: 0.5,
    );
    expect((half.width, half.height), (512, 512));
  });

  testWidgets('IMG-006 metadata written to a JPEG on disk reads back', (
    tester,
  ) async {
    final vips = VipsCodec.open();
    final f = write(
      'meta.jpg',
      vips.encode(gradient(200, 100), VipsSaveFormat.jpeg),
    );
    final src = await open(f);
    await pipeline.writeMetadata(
      src,
      ImageMetadataEdit(
        captured: DateTime(2024, 5, 1, 10, 20, 30),
        location: (48.8584, 2.2945),
        title: 'Device test',
        keywords: const ['c3', 'samsung'],
        rating: 4,
      ),
    );
    // The file was replaced; open it again.
    final m = await pipeline.metadata(await open(f));
    expect(m.title, 'Device test');
    expect(m.rating, 4);
    expect(m.keywords, containsAll(['c3', 'samsung']));
    expect(m.latitude, closeTo(48.8584, 1e-4));
    expect(m.captured, DateTime(2024, 5, 1, 10, 20, 30));
    // Still a decodable JPEG of the same size.
    final info = await pipeline.info(await open(f));
    expect((info.width, info.height), (200, 100));
  });

  testWidgets(
    'IMG-003 the timeline scrolls 50 000 items without dropped frames',
    (tester) async {
      final now = DateTime.now();
      final entries = [
        for (var i = 0; i < 50000; i++)
          PhotoEntry(
            id: i,
            sourceId: 1,
            relPath: 'p/$i.jpg',
            name: '$i.jpg',
            ext: 'jpg',
            isVideo: false,
            size: 1 << 20,
            mtime: now.subtract(Duration(minutes: i * 7)),
            date: now.subtract(Duration(minutes: i * 7)),
            width: 4000,
            height: 3000,
          ),
      ];
      final png = File('${dir.path}/t.png')..writeAsBytesSync(await _tinyPng());
      final store = _Thumbs(png);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            libraryDatabaseProvider.overrideWithValue(db),
            photoEntriesProvider.overrideWith((ref) => Stream.value(entries)),
            thumbnailSourceProvider.overrideWith((ref, edge) => store),
          ],
          child: MediahroApp(router: buildRouter(initialLocation: '/photos')),
        ),
      );
      await tester.pumpAndSettle();
      var frames = 0;
      var jank = 0;
      void onTimings(List<ui.FrameTiming> t) {
        for (final f in t) {
          frames++;
          if (f.totalSpan.inMicroseconds > 16667) jank++;
        }
      }

      binding.addTimingsCallback(onTimings);
      final list = find.byType(ListView).first;
      for (var i = 0; i < 8; i++) {
        await tester.fling(list, const Offset(0, -1500), 4000);
        await tester.pump(const Duration(milliseconds: 600));
      }
      await tester.pumpAndSettle();
      binding
        ..removeTimingsCallback(onTimings)
        ..reportData = {
          'photos_scroll_frames': frames,
          'photos_scroll_jank_frames': jank,
        };
      // docs/11 §5: 0 jank frames at 60 Hz in profile/release builds.
      if (!kDebugMode) expect(jank, 0);
    },
  );
}

Future<Uint8List> _tinyPng() async {
  final rec = ui.PictureRecorder();
  ui.Canvas(rec).drawColor(const Color(0xFF446688), BlendMode.src);
  final img = await rec.endRecording().toImage(8, 8);
  final data = await img.toByteData(format: ui.ImageByteFormat.png);
  return data!.buffer.asUint8List();
}

final class _Thumbs implements ThumbnailSource {
  _Thumbs(this.file);

  final File file;

  @override
  Future<File> load(
    PhotoEntry entry,
    ThumbnailPriority priority,
    void Function(JobHandle) onQueued,
  ) async => file;

  @override
  void reprioritise(int entryId, ThumbnailPriority priority) {}

  @override
  void cancel(int entryId) {}
}
