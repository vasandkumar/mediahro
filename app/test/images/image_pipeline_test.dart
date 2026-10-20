import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mediahro/core/db/library_database.dart';
import 'package:mediahro/images/image_pipeline.dart';
import 'package:mediahro/images/metadata/jpeg.dart';
import 'package:mediahro/images/metadata/metadata_codec.dart';
import 'package:mediahro/images/pipeline/image_worker.dart';
import 'package:mediahro/images/pipeline/mediahro_image_pipeline.dart';
import 'package:mediahro/images/pipeline/pixel_codec.dart';
import 'package:mediahro/images/pipeline/thumbnail_cache.dart';
import 'package:mediahro/images/pipeline/worker_pool.dart';
import 'package:mediahro/platform/imaging.dart';

import 'fixtures.dart';
import 'pipeline_fakes.dart';

void main() {
  late LibraryDatabase db;
  late Directory dir;
  late MemoryIo io;
  late FakeUiFallback ui;
  late List<MediahroImagePipeline> made;

  setUp(() {
    db = LibraryDatabase.memory();
    dir = Directory.systemTemp.createTempSync('mediahro-pipe');
    io = MemoryIo();
    ui = FakeUiFallback();
    made = [];
  });

  tearDown(() async {
    for (final p in made) {
      await p.dispose();
    }
    await db.close();
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  MediahroImagePipeline pipeline({
    WorkerHandlerFactory factory = fakeWorker,
    ImagingFacade? imaging,
  }) {
    final p = MediahroImagePipeline(
      worker: ImageWorkerClient(IsolateWorkerPool(size: 1, factory: factory)),
      cache: ThumbnailCache(db: db, directory: dir),
      io: io,
      imaging: imaging,
      fallback: ui,
    );
    made.add(p);
    return p;
  }

  ImageSource source(MemoryFile f, {int? orientation}) => ImageSource(
    f,
    mtime: DateTime.utc(2026, 10, 21),
    orientationHint: orientation,
  );

  group('IMG-003 thumbnails', () {
    test(
      'IMG-003 a thumbnail is generated once and then served from the cache',
      () async {
        final p = pipeline();
        final src = source(io.add('a.jpg', fakeImage(8, 4)));
        var queued = 0;
        final first = await p.thumbnailFile(
          src,
          256,
          onQueued: (_) => queued++,
        );
        expect(first.existsSync(), isTrue);
        expect(first.path, endsWith('.webp'));
        expect(queued, 1);
        final second = await p.thumbnailFile(
          src,
          256,
          onQueued: (_) => queued++,
        );
        expect(second.path, first.path);
        expect(queued, 1, reason: 'the second request is a cache hit');
      },
    );

    test(
      'IMG-003 concurrent requests for one rendition share one job',
      () async {
        final p = pipeline();
        final src = source(io.add('a.jpg', fakeImage(8, 4)));
        var queued = 0;
        final files = await Future.wait([
          for (var i = 0; i < 5; i++)
            p.thumbnailFile(src, 256, onQueued: (_) => queued++),
        ]);
        expect(queued, 1);
        expect(files.map((f) => f.path).toSet(), hasLength(1));
      },
    );

    test('IMG-003 256 and 512 px renditions and changed files get their own entries', () async {
      final p = pipeline();
      final f = io.add('a.jpg', fakeImage(8, 4));
      final a = await p.thumbnailFile(source(f), 256);
      final b = await p.thumbnailFile(source(f), 512);
      final c = await p.thumbnailFile(source(f, orientation: 6), 256);
      expect({a.path, b.path, c.path}, hasLength(3));
    });

    test('IMG-003 the thumbnail bytes are what the worker encoded', () async {
      final p = pipeline();
      final src = source(io.add('a.jpg', fakeImage(8, 4)));
      final file = await p.thumbnailFile(src, 256);
      final b = file.readAsBytesSync();
      expect(b.sublist(0, 3), [0xEE, 8, 4]);
    });

    test('IMG-003 the OS thumbnail is used before libvips', () async {
      final os = FakeImaging(
        thumb: PlatformImage(width: 2, height: 2, pixels: Uint8List(16)),
      );
      final p = pipeline(imaging: os);
      var queued = 0;
      final src = source(io.add('a.heic', fakeImage(8, 4)));
      await p.thumbnailFile(src, 256, onQueued: (_) => queued++);
      expect(os.thumbCalls, 1);
      expect(
        queued,
        0,
        reason: 'no thumbnail job: only the encode of the OS pixels',
      );
    });

    test('IMG-003 without an OS thumbnail the worker pool is used', () async {
      final os = FakeImaging();
      final p = pipeline(imaging: os);
      var queued = 0;
      await p.thumbnailFile(
        source(io.add('a.jpg', fakeImage(8, 4))),
        256,
        onQueued: (_) => queued++,
      );
      expect(os.thumbCalls, 1);
      expect(queued, 1);
    });

    test('IMG-003 without a native codec Flutter codecs are used and PNG is cached', () async {
      final p = pipeline(factory: emptyWorker);
      final src = source(io.add('a.bmp', fakeImage(8, 4)));
      final file = await p.thumbnailFile(src, 256);
      expect(file.path, endsWith('.png'));
      expect(ui.decodes, 1);
    });

    test('IMG-001 a RAW is thumbnailed from its embedded JPEG preview, not the sensor data', () async {
      final raw = _fakeRaw();
      final p = pipeline();
      final src = source(io.add('IMG_0001.NEF', raw.bytes));
      final file = await p.thumbnailFile(src, 256);
      // The fake codec encodes width = preview length mod 200 + 1.
      expect(file.readAsBytesSync()[1], raw.previewLength % 200 + 1);
    });

    test(
      'IMG-003 a RAW without an embedded preview is a typed error, not a crash',
      () async {
        final p = pipeline();
        final src = source(io.add('IMG_0002.nef', sampleTiff()));
        await expectLater(
          p.thumbnailFile(src, 256),
          throwsA(isA<ImageBackendUnavailable>()),
        );
        expect(ui.decodes, 0);
      },
    );

    test('IMG-003 cancelGroup drops queued thumbnails of a tile that scrolled away', () async {
      final p = pipeline();
      final jobs = <Future<File>>[
        for (var i = 0; i < 6; i++)
          p.thumbnailFile(
            source(io.add('p$i.jpg', fakeImage(40, 40, seed: i))),
            256,
            group: 'tile-$i',
          ),
      ];
      // Let the first job start, then drop the last ones.
      await Future<void>.delayed(const Duration(milliseconds: 1));
      for (var i = 3; i < 6; i++) {
        p.cancelGroup('tile-$i');
      }
      final settled = await Future.wait([
        for (final j in jobs)
          j.then((_) => 'ok', onError: (Object e) => e.runtimeType.toString()),
      ]);
      expect(settled.take(3), everyElement('ok'));
      expect(settled.skip(3).where((s) => s == 'JobCancelled'), isNotEmpty);
    });
  });

  group('IMG-001 info and decode', () {
    test('IMG-001 info swaps the size for rotated EXIF orientations', () async {
      final p = pipeline();
      final jpeg = sampleJpeg(exif: sampleExif()); // 4×2, orientation 6
      final info = await p.info(source(io.add('a.jpg', jpeg)));
      expect((info.width, info.height), (2, 4));
      expect(info.format, 'jpeg');
    });

    test('IMG-001 info reports panorama, motion photo and HDR gain map', () async {
      final p = pipeline();
      final pano = await p.info(
        source(
          io.add(
            'pano.jpg',
            sampleJpeg(
              xmp: xmpDoc(
                '<GPano:ProjectionType>equirectangular</GPano:ProjectionType>',
              ),
            ),
          ),
        ),
      );
      expect(pano.isPanorama, isTrue);
      final motion = await p.info(
        source(
          io.add(
            'mp.jpg',
            sampleJpeg(
              xmp: xmpDoc(
                '<GCamera:MicroVideo>1</GCamera:MicroVideo>'
                '<GCamera:MicroVideoOffset>5000</GCamera:MicroVideoOffset>',
              ),
            ),
          ),
        ),
      );
      expect(motion.isMotionPhoto, isTrue);
      final hdr = await p.info(
        source(
          io.add(
            'hdr.jpg',
            sampleJpeg(xmp: xmpDoc('<hdrgm:Version>1.0</hdrgm:Version>')),
          ),
        ),
      );
      expect(hdr.range, ImageDynamicRange.hdrGainMap);
    });

    test('IMG-001 info names a RAW by its extension', () async {
      final p = pipeline();
      final info = await p.info(source(io.add('a.cr2', _fakeRaw().bytes)));
      expect(info.format, 'cr2');
    });

    test('IMG-004 decode returns pixels and crops regions', () async {
      final p = pipeline();
      final src = source(io.add('a.png', fakeImage(8, 6)));
      final full = await p.decode(src);
      expect((full.width, full.height), (8, 6));
      final part = await p.decode(src, region: const ImageRegion(2, 1, 4, 3));
      expect((part.width, part.height), (4, 3));
      expect(part.pixels[0], full.pixels[(1 * 8 + 2) * 4]);
    });

    test('IMG-004 decode uses the OS for formats it lists', () async {
      final os = FakeImaging(
        supported: const ImagingSupport(decodable: {'heic'}),
        decoded: PlatformImage(width: 2, height: 2, pixels: Uint8List(16)),
      );
      final p = pipeline(imaging: os);
      final heic = sampleHeic();
      final img = await p.decode(source(io.add('a.heic', heic)));
      expect(os.decodeCalls, 1);
      expect((img.width, img.height), (2, 2));
    });

    test('IMG-004 decode falls back to Flutter codecs when no native codec reads the format', () async {
      final p = pipeline(factory: emptyWorker);
      final img = await p.decode(source(io.add('a.bmp', fakeImage(5, 3))));
      expect((img.width, img.height), (5, 3));
    });
  });

  group('IMG-006 metadata through the pipeline', () {
    test('IMG-006 metadata reads EXIF off the main isolate', () async {
      final p = pipeline();
      final m = await p.metadata(
        source(io.add('a.jpg', sampleJpeg(exif: sampleExif()))),
      );
      expect(m.cameraModel, 'SM-M176B');
      expect(m.latitude, closeTo(12.975, 1e-6));
    });

    test('IMG-006 writeMetadata rewrites the file in place', () async {
      final p = pipeline();
      final f = io.add('a.jpg', sampleJpeg(exif: sampleExif()));
      final uri = f.uri;
      final out = await p.applyMetadataEdit(
        source(f),
        const ImageMetadataEdit(title: 'Sunset', rating: 5),
      );
      expect(out.sidecar, isNull);
      expect(io.writes, [uri]);
      final m = parseMetadata(io.files[uri]!).metadata;
      expect(m.title, 'Sunset');
      expect(m.rating, 5);
      expect(m.cameraModel, 'SM-M176B');
    });

    test(
      'IMG-006 a RAW gets an XMP sidecar and the RAW file is untouched',
      () async {
        final p = pipeline();
        final raw = _fakeRaw().bytes;
        final f = io.add('2026/IMG_0001.NEF', raw);
        final out = await p.applyMetadataEdit(
          source(f),
          const ImageMetadataEdit(title: 'Raw one', rating: 3),
        );
        expect(out.sidecar?.path, endsWith('/2026/IMG_0001.xmp'));
        expect(io.files[f.uri], raw);
        // A second edit keeps the first one's fields.
        await p.applyMetadataEdit(
          source(f),
          const ImageMetadataEdit(rating: 1),
        );
        final xml = String.fromCharCodes(io.files[out.sidecar]!);
        expect(xml, contains('Raw one'));
        expect(xml, contains('>1<'));
      },
    );

    test('IMG-006 sidecarUri keeps the folder and swaps the extension', () {
      expect(
        MediahroImagePipeline.sidecarUri(Uri.parse('file:///a/b/IMG_1.CR2')),
        Uri.parse('file:///a/b/IMG_1.xmp'),
      );
      expect(
        MediahroImagePipeline.sidecarUri(Uri.parse('file:///a/noext')),
        Uri.parse('file:///a/noext.xmp'),
      );
    });
  });

  group('IMG-009 / IMG-010 encode and export', () {
    test('IMG-010 encode resizes to maxEdge and picks the format', () async {
      final p = pipeline();
      final png = await p.encode(
        DecodedImage(width: 40, height: 20, pixels: Uint8List(40 * 20 * 4)),
        const EncodeOptions(format: EncodeFormat.png, maxEdge: 10),
      );
      expect(png.sublist(0, 3), [0xEE, 10, 5]);
    });

    test(
      'IMG-010 AVIF and HEIC encode need the OS, JXL needs libjxl',
      () async {
        final p = pipeline();
        final img = DecodedImage(width: 2, height: 2, pixels: Uint8List(16));
        for (final f in [
          EncodeFormat.avif,
          EncodeFormat.heic,
          EncodeFormat.jxl,
        ]) {
          await expectLater(
            p.encode(img, EncodeOptions(format: f)),
            throwsUnsupportedError,
            reason: f.name,
          );
        }
      },
    );

    test(
      'IMG-010 encode uses the OS encoder when it lists the format',
      () async {
        final os = FakeImaging(
          supported: const ImagingSupport(encodable: {'heic'}),
        );
        final p = pipeline(imaging: os);
        // FakeImaging has no encode(): the call proves the OS path was taken.
        await expectLater(
          p.encode(
            DecodedImage(width: 2, height: 2, pixels: Uint8List(16)),
            const EncodeOptions(format: EncodeFormat.heic),
          ),
          throwsA(isA<NoSuchMethodError>()),
        );
      },
    );

    test('IMG-010 export converts and keeps the source metadata, orientation reset', () async {
      final p = pipeline();
      // The fake codec decodes any JPEG-looking input to a tiny frame; the
      // metadata comes from the real EXIF in the source file.
      final src = source(io.add('b.jpg', sampleJpeg(exif: sampleExif())));
      final dest = Uri.parse('smb://nas/photos/out.jpg');
      await p.export(
        src,
        const [],
        dest,
        const EncodeOptions(format: EncodeFormat.jpeg),
      );
      expect(io.writes, contains(dest));
      final parsed = parseMetadata(io.files[dest]!);
      expect(parsed.metadata.cameraModel, 'SM-M176B');
      expect(parsed.metadata.latitude, closeTo(12.975, 1e-6));
      expect(parsed.orientation, 1);
    });

    test('IMG-010 export with stripMetadata writes no EXIF', () async {
      final p = pipeline();
      final src = source(io.add('a.png', fakeImage(4, 2)));
      final dest = Uri.parse('smb://nas/photos/out.jpg');
      await p.export(
        src,
        const [],
        dest,
        const EncodeOptions(format: EncodeFormat.jpeg, stripMetadata: true),
      );
      expect(JpegFile.parse(io.files[dest]!).exif, isNull);
    });

    test(
      'IMG-009 export refuses edit operations until the editor supplies them',
      () async {
        final p = pipeline();
        await expectLater(
          p.export(
            source(io.add('a.png', fakeImage(4, 2))),
            const [RotateOp(90)],
            Uri.parse('smb://nas/photos/out.jpg'),
            const EncodeOptions(format: EncodeFormat.jpeg),
          ),
          throwsUnsupportedError,
        );
      },
    );
  });

  group('IMG-003 pixel helpers', () {
    test('IMG-003 downscaleToEdge keeps the aspect ratio and averages', () {
      final f = PixelFrame(
        width: 4,
        height: 2,
        rgba: Uint8List.fromList([
          ...[
            0,
            0,
            0,
            255,
            100,
            100,
            100,
            255,
            200,
            200,
            200,
            255,
            40,
            40,
            40,
            255,
          ],
          ...[
            0,
            0,
            0,
            255,
            100,
            100,
            100,
            255,
            200,
            200,
            200,
            255,
            40,
            40,
            40,
            255,
          ],
        ]),
      );
      final d = downscaleToEdge(f, 2);
      expect((d.width, d.height), (2, 1));
      expect(d.rgba[0], 50); // mean of 0 and 100
      expect(d.rgba[4], 120); // mean of 200 and 40
      expect(downscaleToEdge(f, 100), same(f));
    });

    test('IMG-003 downscale does not bleed colour from transparent pixels', () {
      final f = PixelFrame(
        width: 2,
        height: 1,
        rgba: Uint8List.fromList([255, 0, 0, 255, 0, 255, 0, 0]),
      );
      final d = downscaleToEdge(f, 1);
      expect(d.rgba.sublist(0, 3), [255, 0, 0]);
      expect(d.rgba[3], 127);
    });
  });
}

/// A TIFF "RAW" with IFD0 pointing at a 3000-byte JPEG preview via a
/// JPEGInterchangeFormat pair in IFD1.
({Uint8List bytes, int previewLength}) _fakeRaw() {
  const previewLength = 3000;
  const previewAt = 512;
  final b = Uint8List(previewAt + previewLength + 100);
  final v = ByteData.sublistView(b);
  b
    ..[0] = 0x4D
    ..[1] = 0x4D;
  v
    ..setUint16(2, 42)
    ..setUint32(4, 8) // IFD0 at 8
    // IFD0: no entries, next IFD at 14
    ..setUint16(8, 0)
    ..setUint32(10, 14)
    // IFD1 at 14: two entries (0x0201, 0x0202)
    ..setUint16(14, 2);
  var p = 16;
  void entry(int tag, int value) {
    v
      ..setUint16(p, tag)
      ..setUint16(p + 2, 4) // LONG
      ..setUint32(p + 4, 1)
      ..setUint32(p + 8, value);
    p += 12;
  }

  entry(0x0201, previewAt);
  entry(0x0202, previewLength);
  v.setUint32(p, 0);
  b[previewAt] = 0xFF;
  b[previewAt + 1] = 0xD8;
  return (bytes: b, previewLength: previewLength);
}
