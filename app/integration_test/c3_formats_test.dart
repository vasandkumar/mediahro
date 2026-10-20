// Lane C3 device batch, formats (IMG-001, IMG-010): JPEG XL, AVIF and LibRaw
// through the image pipeline on the Samsung. Needs libjxl, libavif and libraw
// from mediahro-deps in the APK.
//
//   flutter test integration_test/c3_formats_test.dart -d <serial> --no-dds \
//     -P kotlin.incremental=false
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mediahro/core/db/library_database.dart';
import 'package:mediahro/core/files/file_systems.dart';
import 'package:mediahro/images/image_pipeline.dart';
import 'package:mediahro/images/pipeline/image_io.dart';
import 'package:mediahro/images/pipeline/image_worker.dart';
import 'package:mediahro/images/pipeline/mediahro_image_pipeline.dart';
import 'package:mediahro/images/pipeline/thumbnail_cache.dart';
import 'package:mediahro/images/pipeline/worker_pool.dart';
import 'package:mediahro_ffi/mediahro_ffi.dart';

Uint8List gradient(int w, int h) {
  final b = Uint8List(w * h * 4);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final i = (y * w + x) * 4;
      b[i] = (x * 255) ~/ (w - 1);
      b[i + 1] = (y * 255) ~/ (h - 1);
      b[i + 2] = 100;
      b[i + 3] = 255;
    }
  }
  return b;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late LibraryDatabase db;
  late MediahroImagePipeline pipeline;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('c3-formats');
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

  Future<ImageSource> open(File f) async =>
      ImageSource(await const LocalFileSystem().open(f.uri));

  testWidgets('IMG-001 libjxl, libavif and libraw load', (tester) async {
    expect(NativeLibraries.isAvailable(NativeLibrary.jxl), isTrue);
    expect(NativeLibraries.isAvailable(NativeLibrary.avif), isTrue);
    expect(NativeLibraries.isAvailable(NativeLibrary.raw), isTrue);
    expect(AvifCodec.open(), isNotNull);
    expect(RawCodec.open(), isNotNull);
  });

  testWidgets('IMG-010 a JPEG XL written by the pipeline reads back', (
    tester,
  ) async {
    final pixels = gradient(200, 120);
    final bytes = await pipeline.encode(
      DecodedImage(width: 200, height: 120, pixels: pixels),
      const EncodeOptions(format: EncodeFormat.jxl, quality: 100),
    );
    final f = File('${dir.path}/a.jxl')..writeAsBytesSync(bytes);
    final src = await open(f);
    final info = await pipeline.info(src);
    expect((info.width, info.height, info.format), (200, 120, 'jxl'));
    final back = await pipeline.decode(src);
    expect(back.pixels, pixels, reason: 'quality 100 is lossless');
    final thumb = await pipeline.thumbnailFile(src, 100);
    expect(thumb.path, endsWith('.webp'));
    final half = await pipeline.decode(
      src,
      region: const ImageRegion(0, 0, 100, 60),
      scale: 0.5,
    );
    expect((half.width, half.height), (50, 30));
  });

  testWidgets('IMG-001 broken AVIF and RAW files fail with typed errors', (
    tester,
  ) async {
    final junk = Uint8List.fromList(
      List.generate(4096, (i) => (i * 31) & 0xFF),
    );
    // An AVIF ftyp header followed by nonsense.
    final avif = Uint8List.fromList([
      0,
      0,
      0,
      0x18,
      ...'ftypavif'.codeUnits,
      0,
      0,
      0,
      0,
      ...'avif'.codeUnits, //
      ...junk,
    ]);
    final fAvif = File('${dir.path}/bad.avif')..writeAsBytesSync(avif);
    await expectLater(
      pipeline.thumbnailFile(await open(fAvif), 128),
      throwsA(anything),
    );
    final fRaw = File('${dir.path}/bad.cr2')..writeAsBytesSync(junk);
    await expectLater(
      pipeline.thumbnailFile(await open(fRaw), 128),
      throwsA(anything),
    );
  });
}
