import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:mediahro/core/db/library_database.dart';
import 'package:mediahro/features/photos/timeline/timeline_model.dart';
import 'package:mediahro/features/photos/viewer/photo_clips.dart';
import 'package:mediahro/images/pipeline/image_worker.dart';
import 'package:mediahro/images/pipeline/mediahro_image_pipeline.dart';
import 'package:mediahro/images/pipeline/thumbnail_cache.dart';
import 'package:mediahro/images/pipeline/worker_pool.dart';

import '../../core/seed.dart';
import '../../images/fixtures.dart';
import '../../images/pipeline_fakes.dart';
import 'disk_support.dart';
import 'photos_harness.dart';

Uint8List bytesOf(int n, [int seed = 1]) =>
    Uint8List.fromList(List.generate(n, (i) => (i * 31 + seed) & 0xFF));

void main() {
  group('IMG-001 a part of a file', () {
    late MemoryFile inner;

    setUp(() => inner = MemoryFile(Uri.parse('file:///a.jpg'), bytesOf(100)));

    test('IMG-001 reads are shifted and stop at the end of the part', () async {
      final r = RangeFile(inner, offset: 60, size: 30);
      expect(await r.length(), 30);
      expect(await r.read(0, 5), bytesOf(100).sublist(60, 65));
      expect(await r.read(25, 100), bytesOf(100).sublist(85, 90));
      expect(await r.read(30, 5), isEmpty);
      expect(await r.read(10, 0), isEmpty);
      expect(r.isSeekable, isTrue);
    });

    test('IMG-001 a negative read is refused', () async {
      final r = RangeFile(inner, offset: 0, size: 10);
      expect(() => r.read(-1, 5), throwsRangeError);
    });

    test(
      'IMG-001 the part has its own address, closing closes the file',
      () async {
        final r = RangeFile(inner, offset: 60, size: 30);
        expect(r.uri, isNot(inner.uri));
        await r.close();
      },
    );
  });

  group('IMG-001 finding the clip', () {
    late Directory dir;
    late LibraryDatabase db;
    late DiskIo io;
    late MediahroImagePipeline pipeline;
    late PhotoClipService clips;
    late Seed seed;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('mediahro-clips');
      db = LibraryDatabase.memory();
      seed = Seed(db);
      io = DiskIo();
      pipeline = MediahroImagePipeline(
        worker: ImageWorkerClient(
          IsolateWorkerPool(size: 1, factory: fakeWorker),
        ),
        cache: ThumbnailCache(db: db, directory: Directory('${dir.path}/t')),
        io: io,
        fallback: FakeUiFallback(),
      );
      clips = PhotoClipService(
        files: DiskFiles(dir, io),
        io: io,
        pipeline: pipeline,
        db: db,
      );
    });

    tearDown(() async {
      await pipeline.dispose();
      await db.close();
      try {
        dir.deleteSync(recursive: true);
      } on FileSystemException {
        // Best effort on Windows.
      }
    });

    Future<PhotoEntry> photo(
      String rel,
      Uint8List data, {
      bool live = false,
      bool motion = false,
    }) async {
      File('${dir.path}/$rel')
        ..createSync(recursive: true)
        ..writeAsBytesSync(data);
      final id = await seed.item(rel, kind: ItemKind.image, size: data.length);
      final base = fakeEntries(days: 1, perDay: 1, firstId: id).single;
      return PhotoEntry(
        id: id,
        sourceId: 1,
        relPath: rel,
        name: rel.split('/').last,
        ext: rel.split('.').last,
        isVideo: false,
        size: data.length,
        mtime: base.mtime,
        date: base.date,
        livePhoto: live,
        motionPhoto: motion,
      );
    }

    Uint8List motionJpeg(int videoLength, {int declared = -1}) {
      final xmp = xmpDoc(
        [
          '<GCamera:MotionPhoto>1</GCamera:MotionPhoto>',
          '<Container:Directory><rdf:Seq>',
          '<rdf:li><Container:Item Item:Semantic="Primary"/></rdf:li>',
          '<rdf:li><Container:Item Item:Semantic="MotionPhoto" ',
          'Item:Mime="video/mp4" Item:Length="${declared < 0 ? videoLength : declared}"/></rdf:li>',
          '</rdf:Seq></Container:Directory>',
        ].join(),
      );
      return sampleJpeg(xmp: xmp, trailer: bytesOf(videoLength, 9));
    }

    test(
      'IMG-001 a Motion Photo gives the video at the end of its file',
      () async {
        final jpeg = motionJpeg(500);
        final p = await photo('m/a.jpg', jpeg, motion: true);
        final clip = await clips.open(p);
        expect(clip, isNotNull);
        expect(clip!.motion, isTrue);
        expect(await clip.file.length(), 500);
        expect(await clip.file.read(0, 500), bytesOf(500, 9));
        await clip.file.close();
      },
    );

    test('IMG-001 a length that does not fit the file gives nothing', () async {
      final p = await photo(
        'm/b.jpg',
        motionJpeg(300, declared: 5000000),
        motion: true,
      );
      expect(await clips.open(p), isNull);
      final q = await photo('m/c.jpg', sampleJpeg(), motion: true);
      expect(await clips.open(q), isNull);
    });

    test('IMG-001 a Live Photo gives the MOV beside it', () async {
      final p = await photo('l/IMG_1.heic', bytesOf(50), live: true);
      File('${dir.path}/l/IMG_1.MOV').writeAsBytesSync(bytesOf(70, 3));
      await db
          .into(db.imageMeta)
          .insertOnConflictUpdate(
            ImageMetaCompanion.insert(
              itemId: Value(p.id),
              pairedVideoPath: const Value('IMG_1.MOV'),
            ),
          );
      final clip = await clips.open(p);
      expect(clip, isNotNull);
      expect(clip!.motion, isFalse);
      expect(await clip.file.read(0, 70), bytesOf(70, 3));
      await clip.file.close();
    });

    test('IMG-001 a Live Photo whose video is gone, or a plain photo, gives nothing', () async {
      final p = await photo('l/IMG_2.heic', bytesOf(50), live: true);
      await db
          .into(db.imageMeta)
          .insertOnConflictUpdate(
            ImageMetaCompanion.insert(
              itemId: Value(p.id),
              pairedVideoPath: const Value('IMG_2.MOV'),
            ),
          );
      expect(await clips.open(p), isNull);
      final plain = await photo('l/plain.jpg', sampleJpeg());
      expect(await clips.open(plain), isNull);
    });

    test('IMG-001 a path that tries to leave the folder is refused', () async {
      final p = await photo('l/IMG_3.heic', bytesOf(50), live: true);
      File('${dir.path}/secret.mov').writeAsBytesSync(bytesOf(10));
      await db
          .into(db.imageMeta)
          .insertOnConflictUpdate(
            ImageMetaCompanion.insert(
              itemId: Value(p.id),
              pairedVideoPath: const Value('../secret.mov'),
            ),
          );
      expect(await clips.open(p), isNull);
    });
  });
}
