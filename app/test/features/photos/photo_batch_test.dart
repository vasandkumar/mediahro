import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mediahro/core/db/library_database.dart';
import 'package:mediahro/core/files/batch.dart';
import 'package:mediahro/core/files/file_operations.dart';
import 'package:mediahro/core/files/file_systems.dart';
import 'package:mediahro/features/photos/batch/photo_batch_service.dart';
import 'package:mediahro/features/photos/image_prober.dart';
import 'package:mediahro/features/photos/photo_files.dart';
import 'package:mediahro/features/photos/timeline/timeline_model.dart';
import 'package:mediahro/images/image_pipeline.dart';
import 'package:mediahro/images/metadata/jpeg.dart';
import 'package:mediahro/images/metadata/metadata_codec.dart';
import 'package:mediahro/images/pipeline/image_io.dart';
import 'package:mediahro/images/pipeline/image_worker.dart';
import 'package:mediahro/images/pipeline/mediahro_image_pipeline.dart';
import 'package:mediahro/images/pipeline/thumbnail_cache.dart';
import 'package:mediahro/images/pipeline/worker_pool.dart';
import 'package:mediahro/platform/imaging.dart';
import 'package:mediahro_ffi/mediahro_ffi.dart';

import '../../core/seed.dart';
import '../../images/fixtures.dart';
import '../../images/pipeline_fakes.dart';
import 'photos_harness.dart' show fakeEntries;

/// Real files in a temp folder, read as buffers (the fake codec reads
/// buffers, never paths).
final class _DiskIo implements ImageIo {
  final MountedFileSystems mounts = MountedFileSystems();
  final List<Uri> writes = [];

  @override
  String? localPath(Uri uri) => null;

  @override
  Future<VirtualFile> open(Uri uri) => mounts.forUri(uri).open(uri);

  @override
  Future<void> replace(Uri uri, Uint8List bytes) async {
    writes.add(uri);
    File.fromUri(uri).writeAsBytesSync(bytes);
  }

  @override
  Future<void> create(Uri uri, Uint8List bytes) async {
    if (File.fromUri(uri).existsSync()) {
      throw VirtualFileException(VirtualFileError.alreadyExists, uri);
    }
    writes.add(uri);
    File.fromUri(uri).writeAsBytesSync(bytes);
  }

  @override
  Future<bool> exists(Uri uri) async => File.fromUri(uri).existsSync();

  @override
  Future<void> delete(Uri uri) async => File.fromUri(uri).deleteSync();
}

final class _Files implements PhotoFileOpener {
  _Files(this.dir, this.io);

  final Directory dir;
  final _DiskIo io;

  @override
  Future<Uri> uriOf(PhotoEntry e) async => File('${dir.path}/${e.relPath}').uri;

  @override
  Future<ImageSource> open(PhotoEntry e) async => ImageSource(
    await io.open(await uriOf(e)),
    mtime: e.mtime,
    orientationHint: e.orientation,
  );
}

final class _AvifHeicImaging implements ImagingFacade {
  @override
  Future<ImagingSupport> support() async => const ImagingSupport(
    decodable: {'heic', 'avif'},
    encodable: {'heic', 'avif'},
  );

  @override
  Object? noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late Directory dir;
  late LibraryDatabase db;
  late _DiskIo io;
  late MediahroImagePipeline pipeline;
  late PhotoBatchService batch;
  late Seed seed;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('mediahro-batch');
    db = LibraryDatabase.memory();
    seed = Seed(db);
    io = _DiskIo();
    pipeline = MediahroImagePipeline(
      worker: ImageWorkerClient(
        IsolateWorkerPool(size: 1, factory: fakeWorker),
      ),
      cache: ThumbnailCache(db: db, directory: Directory('${dir.path}/.t')),
      io: io,
      fallback: FakeUiFallback(),
    );
    batch = PhotoBatchService(
      files: _Files(dir, io),
      pipeline: pipeline,
      io: io,
      operations: FileOperations(fileSystems: io.mounts, db: db),
      db: db,
      prober: ImageProber(pipeline: pipeline, db: db, io: io),
    );
  });

  tearDown(() async {
    await pipeline.dispose();
    await db.close();
    dir.deleteSync(recursive: true);
  });

  File add(String rel, Uint8List bytes) => File('${dir.path}/$rel')
    ..createSync(recursive: true)
    ..writeAsBytesSync(bytes);

  PhotoEntry entry(
    String rel, {
    int id = 1,
    int? orientation,
    bool video = false,
    DateTime? date,
    int? width,
    int? height,
  }) {
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
      date: date ?? DateTime(2026, 10, 21, 9, 30),
      width: width,
      height: height,
      orientation: orientation,
    );
  }

  group('IMG-010 rename', () {
    test('IMG-010 names come from tokens, in order, with a counter', () {
      final photos = [
        entry('a/IMG_1.jpg', date: DateTime(2026, 5, 1, 8)),
        entry('a/IMG_2.jpg', id: 2, date: DateTime(2026, 5, 2, 8)),
      ];
      final plan = batch.previewRename(photos, '{date:yyyy-MM-dd}_{n:3}');
      expect(
        [for (final p in plan) p.to],
        ['2026-05-01_001.jpg', '2026-05-02_002.jpg'],
      );
      expect(plan.every((p) => !p.conflict), isTrue);
    });

    test('IMG-010 the size tokens use the photo, the extension is kept', () {
      final plan = batch.previewRename([
        entry('x.png', width: 4000, height: 3000),
      ], '{name}-{width}x{height}');
      expect(plan.single.to, 'x-4000x3000.png');
    });

    test('IMG-010 two photos with one name are a conflict', () {
      final plan = batch.previewRename([
        entry('a.jpg'),
        entry('b.jpg', id: 2),
      ], 'holiday');
      expect(plan.every((p) => p.conflict), isTrue);
    });

    test('IMG-010 an unknown token is an error', () {
      expect(
        () => batch.previewRename([entry('a.jpg')], '{nope}'),
        throwsA(isA<PatternError>()),
      );
    });

    test('IMG-010 files are renamed on disk', () async {
      add('t/a.jpg', sampleJpeg());
      add('t/b.jpg', sampleJpeg());
      final progress = <int>[];
      final report = await batch.rename(
        [entry('t/a.jpg'), entry('t/b.jpg', id: 2)],
        'trip_{n:2}',
        onProgress: progress.add,
      );
      expect(report.done, 2);
      expect(File('${dir.path}/t/trip_01.jpg').existsSync(), isTrue);
      expect(File('${dir.path}/t/trip_02.jpg').existsSync(), isTrue);
      expect(File('${dir.path}/t/a.jpg').existsSync(), isFalse);
      expect(progress, [1, 2]);
    });

    test('IMG-010 a name that does not change is left alone', () async {
      add('a.jpg', sampleJpeg());
      final report = await batch.rename([entry('a.jpg')], '{name}');
      expect(report.done, 0);
      expect(report.skipped, 1);
    });

    test(
      'IMG-010 conflicts stop the batch before anything is renamed',
      () async {
        add('a.jpg', sampleJpeg());
        add('b.jpg', sampleJpeg());
        await expectLater(
          batch.rename([entry('a.jpg'), entry('b.jpg', id: 2)], 'same'),
          throwsA(isA<PatternError>()),
        );
        expect(File('${dir.path}/a.jpg').existsSync(), isTrue);
      },
    );
  });

  group('IMG-010 convert and resize', () {
    test(
      'IMG-010 a copy in the new format is written next to the original',
      () async {
        add('a.jpg', fakeImage(8, 4));
        final report = await batch.convert([
          entry('a.jpg'),
        ], const ConvertOptions(format: EncodeFormat.png, stripMetadata: true));
        expect(report.done, 1);
        expect(File('${dir.path}/a.png').existsSync(), isTrue);
        expect(File('${dir.path}/a.jpg').existsSync(), isTrue);
      },
    );

    test('IMG-010 the same format never overwrites the original', () async {
      add('a.png', fakeImage(8, 4));
      await batch.convert([entry('a.png')], const ConvertOptions());
      await batch.convert([entry('a.png')], const ConvertOptions());
      expect(File('${dir.path}/a_converted.png').existsSync(), isTrue);
      expect(File('${dir.path}/a_converted_2.png').existsSync(), isTrue);
      expect(File('${dir.path}/a.png').readAsBytesSync(), fakeImage(8, 4));
    });

    test('IMG-010 photos are made smaller, never larger', () async {
      add('big.png', fakeImage(8, 4));
      add('small.png', fakeImage(2, 1));
      await batch.convert([
        entry('big.png'),
        entry('small.png', id: 2),
      ], const ConvertOptions(maxEdge: 4, stripMetadata: true));
      final big = File('${dir.path}/big_converted.png').readAsBytesSync();
      expect((big[1], big[2]), (4, 2));
      final small = File('${dir.path}/small_converted.png').readAsBytesSync();
      expect((small[1], small[2]), (2, 1));
    });

    test('IMG-010 metadata can be dropped while converting', () async {
      add('a.jpg', sampleJpeg(exif: sampleExif()));
      add('b.jpg', sampleJpeg(exif: sampleExif()));
      await batch.convert([
        entry('a.jpg'),
      ], const ConvertOptions(format: EncodeFormat.jpeg));
      await batch.convert([
        entry('b.jpg', id: 2),
      ], const ConvertOptions(format: EncodeFormat.jpeg, stripMetadata: true));
      expect(
        JpegFile.parse(File('${dir.path}/a_converted.jpg').readAsBytesSync())
            .exif,
        isNotNull,
      );
      expect(
        JpegFile.parse(File('${dir.path}/b_converted.jpg').readAsBytesSync())
            .exif,
        isNull,
      );
    });

    test(
      'IMG-010 videos are skipped, bad files reported, the rest go on',
      () async {
        add('good.png', fakeImage(4, 2));
        final report = await batch.convert([
          entry('good.png'),
          entry('clip.mp4', id: 2, video: true),
          entry('missing.png', id: 3),
        ], const ConvertOptions(stripMetadata: true));
        expect(report.done, 1);
        expect(report.skipped, 1);
        expect(report.failed, ['missing.png']);
      },
    );

    test('IMG-010 a batch can be stopped', () async {
      add('a.png', fakeImage(4, 2));
      add('b.png', fakeImage(4, 2));
      add('c.png', fakeImage(4, 2));
      var seen = 0;
      final report = await batch.convert(
        [entry('a.png'), entry('b.png', id: 2), entry('c.png', id: 3)],
        const ConvertOptions(stripMetadata: true),
        onProgress: (n) => seen = n,
        cancelled: () => seen >= 1,
      );
      expect(report.stopped, isTrue);
      expect(report.done, 1);
    });

    test(
      'IMG-010 the formats offered are the ones this device can write',
      () async {
        expect(await batch.formats(), {
          EncodeFormat.jpeg,
          EncodeFormat.png,
          EncodeFormat.webp,
          EncodeFormat.jxl,
        });
        final withOs = MediahroImagePipeline(
          worker: ImageWorkerClient(
            IsolateWorkerPool(size: 1, factory: fakeWorker),
          ),
          cache: ThumbnailCache(
            db: db,
            directory: Directory('${dir.path}/.t2'),
          ),
          io: io,
          imaging: _AvifHeicImaging(),
          fallback: FakeUiFallback(),
        );
        addTearDown(withOs.dispose);
        expect(
          await withOs.encodableFormats(),
          containsAll([EncodeFormat.avif, EncodeFormat.heic]),
        );
      },
    );

    test('IMG-010 without libjxl JPEG XL is not offered', () async {
      final none = MediahroImagePipeline(
        worker: ImageWorkerClient(
          IsolateWorkerPool(size: 1, factory: emptyWorker),
        ),
        cache: ThumbnailCache(db: db, directory: Directory('${dir.path}/.t3')),
        io: io,
        fallback: FakeUiFallback(),
      );
      addTearDown(none.dispose);
      expect(await none.encodableFormats(), isNot(contains(EncodeFormat.jxl)));
    });
  });

  group('IMG-010 upright by EXIF', () {
    test('IMG-010 only photos stored sideways are saved again', () async {
      final id = await seed.item('a.jpg', kind: ItemKind.image);
      add('a.jpg', sampleJpeg(exif: sampleExif()));
      add('b.jpg', sampleJpeg());
      final report = await batch.uprightByExif([
        entry('a.jpg', id: id, orientation: 6),
        entry('b.jpg', id: 2, orientation: 1),
        entry('c.jpg', id: 3),
      ]);
      expect(report.done, 1);
      expect(report.skipped, 2);
      expect(io.writes.map((u) => u.pathSegments.last), ['a.jpg']);
    });

    test('IMG-010 the saved file says it is upright', () async {
      final id = await seed.item('a.jpg', kind: ItemKind.image);
      add('a.jpg', sampleJpeg(exif: sampleExif()));
      await batch.uprightByExif([entry('a.jpg', id: id, orientation: 6)]);
      final parsed = parseMetadata(File('${dir.path}/a.jpg').readAsBytesSync());
      expect(parsed.orientation, 1);
      expect(parsed.metadata.cameraModel, 'SM-M176B');
    });

    test('IMG-010 a format that cannot be rewritten is reported', () async {
      add('h.heic', fakeImage(4, 2));
      final report = await batch.uprightByExif([
        entry('h.heic', orientation: 6),
      ]);
      expect(report.failed, ['h.heic']);
    });
  });

  group('IMG-010 strip metadata', () {
    test('IMG-010 removing the location keeps the rest', () async {
      add('a.jpg', sampleJpeg(exif: sampleExif()));
      final id = await seed.item('a.jpg', kind: ItemKind.image);
      final report = await batch.strip([
        entry('a.jpg', id: id),
      ], StripScope.location);
      expect(report.done, 1);
      final m = parseMetadata(File('${dir.path}/a.jpg').readAsBytesSync())
          .metadata;
      expect(m.latitude, isNull);
      expect(m.cameraModel, 'SM-M176B');
    });

    test(
      'IMG-010 removing everything leaves orientation and nothing else',
      () async {
        add('a.jpg', sampleJpeg(exif: sampleExif()));
        final id = await seed.item('a.jpg', kind: ItemKind.image);
        await batch.strip([entry('a.jpg', id: id)], StripScope.everything);
        final p = parseMetadata(File('${dir.path}/a.jpg').readAsBytesSync());
        expect(p.metadata.latitude, isNull);
        expect(p.metadata.cameraModel, isNull);
        expect(p.orientation, 6);
      },
    );

    test(
      'IMG-010 the capture date stays in the library after a strip',
      () async {
        final taken = DateTime.utc(2026, 5, 1, 10);
        final id = await seed.item('a.jpg', kind: ItemKind.image);
        await db.customStatement('UPDATE item SET taken_at = ? WHERE id = ?', [
          taken.millisecondsSinceEpoch ~/ 1000,
          id,
        ]);
        add('a.jpg', sampleJpeg(exif: sampleExif()));
        await batch.strip([entry('a.jpg', id: id)], StripScope.everything);
        final row = await (db.select(
          db.items,
        )..where((i) => i.id.equals(id))).getSingle();
        expect(row.takenAt, isNotNull);
      },
    );

    test(
      'IMG-010 a format that cannot be cleaned in place is reported',
      () async {
        add('h.heic', fakeImage(4, 2));
        final report = await batch.strip([
          entry('h.heic'),
        ], StripScope.everything);
        expect(report.failed, ['h.heic']);
      },
    );

    test('IMG-010 videos are left alone', () async {
      final report = await batch.strip([
        entry('v.mp4', video: true),
      ], StripScope.everything);
      expect(report.skipped, 1);
    });
  });
}
