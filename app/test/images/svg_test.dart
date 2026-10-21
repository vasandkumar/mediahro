import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mediahro/core/db/library_database.dart';
import 'package:mediahro/images/image_pipeline.dart';
import 'package:mediahro/images/pipeline/image_worker.dart';
import 'package:mediahro/images/pipeline/mediahro_image_pipeline.dart';
import 'package:mediahro/images/pipeline/pixel_codec.dart';
import 'package:mediahro/images/pipeline/thumbnail_cache.dart';
import 'package:mediahro/images/pipeline/worker_pool.dart';
import 'package:mediahro/images/svg/svg_rasteriser.dart';

import 'pipeline_fakes.dart';

Uint8List svg(String body, {String attrs = 'viewBox="0 0 100 50"'}) =>
    Uint8List.fromList(
      utf8.encode(
        '<?xml version="1.0"?>\n'
        '<svg xmlns="http://www.w3.org/2000/svg" '
        'xmlns:xlink="http://www.w3.org/1999/xlink" $attrs>$body</svg>',
      ),
    );

/// A red left half, a blue square in the middle, the rest empty.
final Uint8List sample = svg(
  '<rect width="50" height="50" fill="#ff0000"/>'
  ' <rect x="60" y="15" width="20" height="20" fill="#0000ff"/>',
);

(int, int, int, int) pixel(PixelFrame f, int x, int y) {
  final o = (y * f.width + x) * 4;
  return (f.rgba[o], f.rgba[o + 1], f.rgba[o + 2], f.rgba[o + 3]);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SvgRasteriser r;

  setUp(() => r = SvgRasteriser());
  tearDown(() => r.dispose());

  group('IMG-001 SVG detection', () {
    test('IMG-001 SVG documents are recognised, other text is not', () {
      expect(SvgRasteriser.looksLikeSvg(sample), isTrue);
      expect(
        SvgRasteriser.looksLikeSvg(
          Uint8List.fromList(
            utf8.encode('<!-- hi --><!DOCTYPE svg><svg width="1"/>'),
          ),
        ),
        isTrue,
      );
      expect(
        SvgRasteriser.looksLikeSvg(Uint8List.fromList(utf8.encode('<html/>'))),
        isFalse,
      );
      expect(SvgRasteriser.looksLikeSvg(Uint8List(0)), isFalse);
    });
  });

  group('IMG-001 SVG size', () {
    test(
      'IMG-001 a small picture gets a canvas with a 2048 px long edge',
      () async {
        expect(await r.size(sample), (2048, 1024));
      },
    );

    test('IMG-001 the shape of the picture is kept', () async {
      expect(await r.size(svg('', attrs: 'viewBox="0 0 30 90"')), (683, 2048));
    });

    test(
      'IMG-001 a big picture keeps its size, a huge one is cut to 8192',
      () async {
        expect(await r.size(svg('', attrs: 'width="5000" height="2500"')), (
          5000,
          2500,
        ));
        expect(await r.size(svg('', attrs: 'width="20000" height="10000"')), (
          8192,
          4096,
        ));
      },
    );

    test('IMG-001 the view box decides the shape when there is one', () async {
      expect(
        await r.size(
          svg('', attrs: 'width="400" height="100" viewBox="0 0 2 1"'),
        ),
        (2048, 1024),
      );
    });
  });

  group('IMG-001 SVG drawing', () {
    test('IMG-001 the whole picture reduced to a quarter', () async {
      final f = await r.render(sample, scale: 0.25);
      expect((f.width, f.height), (512, 256));
      expect((f.sourceWidth, f.sourceHeight), (2048, 1024));
      expect(pixel(f, 100, 100), (255, 0, 0, 255));
      expect(pixel(f, 350, 128), (0, 0, 255, 255));
      // Nothing was drawn at the right edge: transparent.
      expect(pixel(f, 500, 10).$4, 0);
    });

    test('IMG-001 a region is drawn crisply at its own size', () async {
      // The blue square spans x 1228..1638, y 307..717 of the 2048 canvas.
      final f = await r.render(
        sample,
        region: const ImageRegion(1200, 300, 500, 450),
      );
      expect((f.width, f.height), (500, 450));
      expect(pixel(f, 100, 100), (0, 0, 255, 255));
      expect(pixel(f, 10, 10).$4, 0);
      // The edge is sharp, not smeared over several pixels.
      expect(pixel(f, 27, 100), (0, 0, 0, 0));
      expect(pixel(f, 29, 100), (0, 0, 255, 255));
    });

    test('IMG-001 a region can also be reduced', () async {
      final f = await r.render(
        sample,
        region: const ImageRegion(0, 0, 1024, 1024),
        scale: 0.5,
      );
      expect((f.width, f.height), (512, 512));
      expect(pixel(f, 100, 100), (255, 0, 0, 255));
    });

    test('IMG-001 text that is not a picture is refused', () async {
      await expectLater(
        r.render(Uint8List.fromList(utf8.encode('<svg <<< nonsense'))),
        throwsA(isA<CodecUnsupported>()),
      );
    });

    test('IMG-001 a file over the limit is refused', () async {
      final small = SvgRasteriser(maxBytes: 100);
      addTearDown(small.dispose);
      await expectLater(small.render(sample), throwsA(isA<CodecUnsupported>()));
    });

    test(
      'IMG-001 an enormous render is refused rather than attempted',
      () async {
        final small = SvgRasteriser(maxPixels: 1000);
        addTearDown(small.dispose);
        await expectLater(
          small.render(sample),
          throwsA(isA<CodecUnsupported>()),
        );
      },
    );

    test(
      'IMG-001 an image from the web is not fetched, the rest still draws',
      () async {
        final f = await r.render(
          svg(
            '<rect width="50" height="50" fill="#00ff00"/> '
            '<image href="http://example.invalid/x.png" x="50" width="50" height="50"/> '
            '<image xlink:href="https://example.invalid/y.png" x="50" width="50" height="50"/>',
          ),
          scale: 0.25,
        );
        expect(pixel(f, 100, 100), (0, 255, 0, 255));
        expect(pixel(f, 400, 100).$4, 0);
      },
    );

    test('IMG-001 the same file is parsed once for many tiles', () async {
      await r.render(sample, scale: 0.1);
      final sw = Stopwatch()..start();
      for (var i = 0; i < 5; i++) {
        await r.render(
          sample,
          region: ImageRegion(i * 100, 0, 100, 100),
          scale: 0.5,
        );
      }
      sw.stop();
      expect(sw.elapsedMilliseconds, lessThan(5000));
    });
  });

  group('IMG-001 SVG through the pipeline', () {
    late LibraryDatabase db;
    late Directory dir;
    late MemoryIo io;
    late MediahroImagePipeline pipeline;

    setUp(() {
      db = LibraryDatabase.memory();
      dir = Directory.systemTemp.createTempSync('mediahro-svg');
      io = MemoryIo();
      pipeline = MediahroImagePipeline(
        worker: ImageWorkerClient(
          IsolateWorkerPool(size: 1, factory: fakeWorker),
        ),
        cache: ThumbnailCache(db: db, directory: dir),
        io: io,
        fallback: FakeUiFallback(),
        svg: r,
      );
    });

    tearDown(() async {
      await pipeline.dispose();
      await db.close();
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });

    ImageSource source(String name) =>
        ImageSource(io.add(name, sample), mtime: DateTime.utc(2026, 10, 21));

    test('IMG-001 the details show the canvas size and the format', () async {
      final info = await pipeline.info(source('logo.svg'));
      expect((info.width, info.height, info.format), (2048, 1024, 'svg'));
    });

    test(
      'IMG-001 decoding draws the picture, regions and reductions included',
      () async {
        final src = source('logo.svg');
        final whole = await pipeline.decode(src, scale: 0.25);
        expect((whole.width, whole.height), (512, 256));
        final tile = await pipeline.decode(
          src,
          region: const ImageRegion(1200, 300, 500, 450),
        );
        expect((tile.width, tile.height), (500, 450));
      },
    );

    test(
      'IMG-001 the thumbnail is a PNG drawn at the thumbnail size',
      () async {
        final f = await pipeline.thumbnailFile(source('logo.svg'), 256);
        expect(f.path, endsWith('.png'));
        expect(f.existsSync(), isTrue);
      },
    );

    test(
      'IMG-001 an SVG that does not draw is a failed thumbnail, not a crash',
      () async {
        final bad = ImageSource(
          io.add('bad.svg', Uint8List.fromList(utf8.encode('<svg <<<'))),
          mtime: DateTime.utc(2026, 10, 21),
        );
        await expectLater(
          pipeline.thumbnailFile(bad, 256),
          throwsA(isA<Object>()),
        );
      },
    );
  });
}
