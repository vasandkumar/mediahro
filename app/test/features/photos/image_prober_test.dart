import 'dart:io';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:mediahro/core/db/library_database.dart';
import 'package:mediahro/core/library/tags.dart';
import 'package:mediahro/features/photos/image_prober.dart';
import 'package:mediahro/features/photos/map/gazetteer.dart';
import 'package:mediahro/features/photos/map/place_resolver.dart';
import 'package:mediahro/images/metadata/bytes.dart';
import 'package:mediahro/images/metadata/tiff.dart';
import 'package:mediahro/images/pipeline/image_worker.dart';
import 'package:mediahro/images/pipeline/mediahro_image_pipeline.dart';
import 'package:mediahro/images/pipeline/thumbnail_cache.dart';
import 'package:mediahro/images/pipeline/worker_pool.dart';

import '../../core/seed.dart';
import '../../images/fixtures.dart';
import '../../images/pipeline_fakes.dart';

void main() {
  late LibraryDatabase db;
  late Seed seed;
  late MemoryIo io;
  late MediahroImagePipeline pipeline;
  late Directory dir;

  setUp(() {
    db = LibraryDatabase.memory();
    seed = Seed(db);
    io = MemoryIo();
    dir = Directory.systemTemp.createTempSync('mediahro-prober');
    pipeline = MediahroImagePipeline(
      worker: ImageWorkerClient(
        IsolateWorkerPool(size: 1, factory: fakeWorker),
      ),
      cache: ThumbnailCache(db: db, directory: dir),
      io: io,
      fallback: FakeUiFallback(),
    );
  });

  tearDown(() async {
    await pipeline.dispose();
    await db.close();
    dir.deleteSync(recursive: true);
  });

  Future<ItemRow> row(int id) =>
      (db.select(db.items)..where((i) => i.id.equals(id))).getSingle();

  Future<ImageMetaRow> metaOf(int id) =>
      (db.select(db.imageMeta)..where((m) => m.itemId.equals(id))).getSingle();

  ImageProber prober() => ImageProber(pipeline: pipeline, db: db, io: io);

  test(
    'IMG-003 the prober reads size, capture time, camera, GPS and orientation',
    () async {
      final id = await seed.item('a.jpg', kind: ItemKind.image);
      final f = io.add('a.jpg', sampleJpeg(exif: sampleExif()));
      final r = await prober().probe(f, await row(id));
      expect((r.width, r.height), (2, 4), reason: 'orientation 6 swaps 4×2');
      expect(r.takenAt, DateTime(2024, 5, 1, 10, 20, 30));
      expect(r.hdrType, isNull);
      final meta = await metaOf(id);
      expect(meta.camera, 'Samsung SM-M176B');
      expect(meta.lens, 'Main 5.4mm f/1.8');
      expect(meta.orientation, 6);
      expect(meta.latitude, closeTo(12.975, 1e-6));
      expect(meta.pairedVideoPath, isNull);
    },
  );

  test('IMG-007 a geotagged photo is given its place by the prober', () async {
    final gazetteer = Gazetteer.parse(
      File('assets/gazetteer/places.bin').readAsBytesSync(),
    );
    final id = await seed.item('a.jpg', kind: ItemKind.image);
    final f = io.add('a.jpg', sampleJpeg(exif: sampleExif()));
    final places = PlaceResolver(db, () async => gazetteer);
    await ImageProber(
      pipeline: pipeline,
      db: db,
      io: io,
      places: places,
    ).probe(f, await row(id));
    final meta = await metaOf(id);
    expect(meta.placeId, isNotNull);
    final place = await (db.select(
      db.places,
    )..where((p) => p.id.equals(meta.placeId!))).getSingle();
    expect(place.name, 'Bengaluru');
    expect(place.country, 'India');
  });

  test('IMG-003 the prober leaves phash and favourite alone', () async {
    final id = await seed.item('a.jpg', kind: ItemKind.image);
    await db
        .into(db.imageMeta)
        .insert(
          ImageMetaCompanion.insert(
            itemId: Value(id),
            phash: const Value('deadbeefdeadbeef'),
            favourite: const Value(true),
          ),
        );
    final f = io.add('a.jpg', sampleJpeg(exif: sampleExif()));
    await prober().probe(f, await row(id));
    final meta = await metaOf(id);
    expect(meta.phash, 'deadbeefdeadbeef');
    expect(meta.favourite, isTrue);
    expect(meta.camera, isNotNull);
  });

  test('IMG-001 an Apple Live Photo is paired with its MOV by name', () async {
    final id = await seed.item('IMG_1.jpg', kind: ItemKind.image);
    io.add('IMG_1.MOV', Uint8List(100));
    final e = TiffEditor(TiffStructure.parse(sampleExif()));
    // Apple MakerNote with ContentIdentifier (tag 0x0011), big-endian IFD at
    // 14; offsets are relative to the start of the note.
    const uuid = 'F6E6F5A6-0000-4000-8000-0123456789AB';
    final note = ByteSink()
      ..ascii('Apple iOS')
      ..u8(0)
      ..u16(1)
      ..ascii('MM')
      ..u16(1)
      ..u16(0x0011)
      ..u16(2)
      ..u32(uuid.length + 1)
      ..u32(14 + 2 + 12 + 4)
      ..u32(0)
      ..ascii(uuid)
      ..u8(0);
    e.set(IfdKind.exif, e.values.bytes(TiffTag.makerNote, note.take()));
    final f = io.add('IMG_1.jpg', sampleJpeg(exif: e.build()));
    final r = await prober().probe(f, await row(id));
    expect(r.width, isNotNull);
    expect((await metaOf(id)).pairedVideoPath, 'IMG_1.MOV');
  });

  test(
    'IMG-001 a same-named video does not make a plain photo a Live Photo',
    () async {
      final id = await seed.item('IMG_2.jpg', kind: ItemKind.image);
      io.add('IMG_2.MOV', Uint8List(100));
      final f = io.add('IMG_2.jpg', sampleJpeg(exif: sampleExif()));
      await prober().probe(f, await row(id));
      expect((await metaOf(id)).pairedVideoPath, isNull);
    },
  );

  test(
    'IMG-001 Motion Photo and gain-map HDR markers reach the index row',
    () async {
      final id = await seed.item('mp.jpg', kind: ItemKind.image);
      final xmp = xmpDoc(
        [
          '<GCamera:MicroVideo>1</GCamera:MicroVideo>',
          '<GCamera:MicroVideoOffset>5000</GCamera:MicroVideoOffset>',
          '<hdrgm:Version>1.0</hdrgm:Version>',
        ].join(),
      );
      final f = io.add('mp.jpg', sampleJpeg(xmp: xmp));
      final r = await prober().probe(f, await row(id));
      expect(r.videoCodec, 'mp4');
      expect(r.hdrType, 'gainmap');
    },
  );

  test('IMG-006 reprobe refreshes the item after an edit', () async {
    final id = await seed.item('a.jpg', kind: ItemKind.image);
    final f = io.add('a.jpg', sampleJpeg(exif: sampleExif()));
    await prober().reprobe(await row(id), f);
    final item = await row(id);
    expect(item.takenAt, DateTime(2024, 5, 1, 10, 20, 30));
    expect(item.probed, isTrue);
    expect(item.height, 4);
  });

  test('IMG-003 only images are probed here', () async {
    final id = await seed.item('v.mp4');
    await expectLater(
      prober().probe(io.add('v.mp4', Uint8List(10)), await row(id)),
      throwsArgumentError,
    );
  });

  group('IMG-005 organisation read from the file', () {
    final xmp = xmpDoc(
      [
        '<xmp:Rating>4</xmp:Rating>',
        '<xmp:Label>Green</xmp:Label>',
        '<dc:subject><rdf:Bag><rdf:li>lake</rdf:li><rdf:li>dawn</rdf:li></rdf:Bag></dc:subject>',
      ].join(),
    );

    test(
      'IMG-005 a first look imports the stars, label and keywords',
      () async {
        final id = await seed.item('a.jpg', kind: ItemKind.image);
        final f = io.add('a.jpg', sampleJpeg(xmp: xmp));
        await prober().probe(f, await row(id));
        expect((await db.select(db.ratings).getSingle()).value, 8);
        expect(
          (await db.select(db.labels).getSingle()).color,
          LabelColor.green,
        );
        expect((await TagRepository(db).tagsOf(id)).toSet(), {'lake', 'dawn'});
      },
    );

    test(
      'IMG-005 what the user set in the library wins over the file',
      () async {
        final id = await seed.item('a.jpg', kind: ItemKind.image);
        await db
            .into(db.ratings)
            .insert(RatingsCompanion.insert(itemId: Value(id), value: 2));
        await TagRepository(db).addTag([id], 'mine');
        final f = io.add('a.jpg', sampleJpeg(xmp: xmp));
        await prober().probe(f, await row(id));
        expect((await db.select(db.ratings).getSingle()).value, 2);
        expect(await TagRepository(db).tagsOf(id), ['mine']);
      },
    );

    test('IMG-005 re-reading an edited file does not re-import', () async {
      final id = await seed.item('a.jpg', kind: ItemKind.image);
      final f = io.add('a.jpg', sampleJpeg(xmp: xmp));
      await prober().reprobe(await row(id), f);
      await db.delete(db.ratings).go();
      await prober().reprobe(await row(id), f);
      expect(
        await db.select(db.ratings).get(),
        isEmpty,
        reason: 'the user cleared it',
      );
    });

    test('IMG-005 label names from photo programs map to library labels', () {
      expect(labelFromXmp('Red'), LabelColor.red);
      expect(labelFromXmp(' purple '), LabelColor.purple);
      expect(labelFromXmp('Gray'), LabelColor.grey);
      expect(labelFromXmp('Second'), isNull);
      expect(labelFromXmp(null), isNull);
    });
  });
}
