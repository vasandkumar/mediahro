// Lane C3 device batch, editing (IMG-009): the real image worker edits a
// full-size photo on the Samsung: geometry, light, curves, drawing, and a
// timing line for the owner's phone.
//
//   flutter test integration_test/c3_edit_test.dart -d <serial> --no-dds \
//     -P kotlin.incremental=false
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mediahro/core/db/library_database.dart';
import 'package:mediahro/core/files/file_systems.dart';
import 'package:mediahro/images/edit/edit_recipe.dart';
import 'package:mediahro/images/image_pipeline.dart';
import 'package:mediahro/images/pipeline/image_io.dart';
import 'package:mediahro/images/pipeline/image_worker.dart';
import 'package:mediahro/images/pipeline/mediahro_image_pipeline.dart';
import 'package:mediahro/images/pipeline/pixel_codec.dart';
import 'package:mediahro/images/pipeline/thumbnail_cache.dart';
import 'package:mediahro/images/pipeline/worker_pool.dart';
import 'package:mediahro_ffi/mediahro_ffi.dart' show LocalFileSystem;

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
    dir = Directory.systemTemp.createTempSync('c3-edit');
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

  Future<ImageSource> photo(int w, int h) async {
    final jpeg = await pipeline.encode(
      DecodedImage(width: w, height: h, pixels: gradient(w, h)),
      const EncodeOptions(format: EncodeFormat.jpeg),
    );
    final f = File('${dir.path}/p$w.jpg')..writeAsBytesSync(jpeg);
    return ImageSource(await const LocalFileSystem().open(f.uri));
  }

  testWidgets('IMG-009 a recipe is applied to a real JPEG and re-encoded', (
    tester,
  ) async {
    final src = await photo(1200, 800);
    final bytes = await pipeline.renderEdited(
      src,
      const EditRecipe(
        turns: 1,
        crop: NormRect(0, 0, 0.5, 1),
        adjust: {AdjustKind.exposure: 0.5, AdjustKind.sharpen: 0.4},
        curves: CurveSet(master: [(0, 0), (0.5, 0.6), (1, 1)]),
        strokes: [
          StrokeSpec(
            [(0.1, 0.1), (0.9, 0.9)],
            colorArgb: 0xFFFF0000,
            width: 0.02,
          ),
        ],
        blurs: [BlurSpec(NormRect(0.1, 0.5, 0.3, 0.3))],
      ),
      const EncodeOptions(format: EncodeFormat.jpeg),
    );
    final out = File('${dir.path}/edited.jpg')..writeAsBytesSync(bytes);
    final info = await pipeline.info(await _open(out));
    // Turned a quarter (800 x 1200), then the left half cropped.
    expect((info.width, info.height), (400, 1200));
    expect(info.format, 'jpeg');
  });

  testWidgets('IMG-009 a 12 megapixel edit finishes in a few seconds', (
    tester,
  ) async {
    final src = await photo(4000, 3000);
    final sw = Stopwatch()..start();
    final bytes = await pipeline.renderEdited(
      src,
      const EditRecipe(
        straighten: 1.5,
        adjust: {
          AdjustKind.exposure: 0.2,
          AdjustKind.contrast: 0.3,
          AdjustKind.shadows: 0.4,
          AdjustKind.saturation: 0.2,
          AdjustKind.sharpen: 0.5,
          AdjustKind.vignette: 0.3,
        },
      ),
      const EncodeOptions(format: EncodeFormat.jpeg),
    );
    sw.stop();
    // A timing line for the device report.
    // ignore: avoid_print
    print('IMG-009 12 MP edit and JPEG encode: ${sw.elapsedMilliseconds} ms');
    expect(bytes.length, greaterThan(100000));
    expect(sw.elapsedMilliseconds, lessThan(30000));
  });

  testWidgets('IMG-009 the preview path is fast enough to follow a slider', (
    tester,
  ) async {
    final src = await photo(1400, 1050);
    final frame = await pipeline.decode(src);
    final proxy = PixelFrame(
      width: frame.width,
      height: frame.height,
      rgba: frame.pixels,
    );
    final sw = Stopwatch()..start();
    for (var i = 0; i < 10; i++) {
      await pipeline.editFrame(
        proxy,
        EditRecipe(
          adjust: {AdjustKind.exposure: i / 10, AdjustKind.sharpen: 0.3},
        ),
      );
    }
    sw.stop();
    final each = sw.elapsedMilliseconds / 10;
    // A timing line for the device report.
    // ignore: avoid_print
    print('IMG-009 preview render at 1400 px: ${each.toStringAsFixed(0)} ms');
    expect(each, lessThan(400));
  });
}

Future<ImageSource> _open(File f) async =>
    ImageSource(await const LocalFileSystem().open(f.uri));
