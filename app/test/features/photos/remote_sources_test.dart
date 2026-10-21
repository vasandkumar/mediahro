import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mediahro/core/db/library_database.dart';
import 'package:mediahro/core/files/file_systems.dart';
import 'package:mediahro/core/rules/rule_sql.dart' as rules;
import 'package:mediahro/core/scanner/scan_service.dart';
import 'package:mediahro/core/sources/source_access.dart';
import 'package:mediahro/core/sources/source_builders.dart';
import 'package:mediahro/core/sources/source_repository.dart';
import 'package:mediahro/features/photos/photo_files.dart';
import 'package:mediahro/features/photos/photos_providers.dart';
import 'package:mediahro/features/photos/timeline/thumbnail_controller.dart';
import 'package:mediahro/images/image_pipeline.dart';
import 'package:mediahro/images/pipeline/image_io.dart';
import 'package:mediahro/images/pipeline/image_worker.dart';
import 'package:mediahro/images/pipeline/mediahro_image_pipeline.dart';
import 'package:mediahro/images/pipeline/thumbnail_cache.dart';
import 'package:mediahro/images/pipeline/worker_pool.dart';
import 'package:mediahro_ffi/mediahro_ffi.dart';

import '../../core/sources/dav_server.dart';
import '../../images/fixtures.dart';
import '../../images/pipeline_fakes.dart';

/// IMG-016: the gallery over a source that is not a local folder. A WebDAV
/// share served from this machine is scanned, listed, opened and given
/// thumbnails exactly like a folder on the phone, and a share that goes away
/// costs the photos nothing the library already knows.
void main() {
  late TestDavServer server;
  late LibraryDatabase db;
  late Directory dir;
  late ScanService scanner;
  late PhotoFiles files;
  late MediahroImagePipeline pipeline;
  late int sourceId;
  late DefaultSourceResolver resolver;
  final jpeg = sampleJpeg();

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('mediahro-remote');
    server = (await TestDavServer.start())
      ..put('Holiday/IMG_0001.jpg', jpeg)
      ..put('Holiday/My trip 2.jpg', jpeg)
      ..put('Holiday/ünï côdé.jpg', jpeg)
      ..put('Holiday/notes.txt', [1, 2, 3]);
    db = LibraryDatabase.memory();
    resolver = DefaultSourceResolver(builders: defaultFileSystemBuilders());
    scanner = ScanService(db: db, resolver: resolver);
    sourceId = await db
        .into(db.sources)
        .insert(
          SourcesCompanion.insert(
            kind: SourceKind.webdav,
            name: 'NAS',
            rootUri: '${server.root}',
            addedAt: DateTime.now().toUtc(),
          ),
        );
    files = PhotoFiles(db, resolver, MountedFileSystems());
    pipeline = MediahroImagePipeline(
      worker: ImageWorkerClient(
        IsolateWorkerPool(size: 1, factory: fakeWorker),
      ),
      cache: ThumbnailCache(db: db, directory: Directory('${dir.path}/t')),
      io: _NoWrites(),
      fallback: FakeUiFallback(),
    );
  });

  tearDown(() async {
    await pipeline.dispose();
    await files.close();
    await server.close();
    await db.close();
    try {
      dir.deleteSync(recursive: true);
    } on FileSystemException {
      // Best effort on Windows.
    }
  });

  Future<List<PhotoEntryRow>> entries() async {
    final q = db.customSelect(
      photoEntriesSql(const rules.Visibility(unlocked: true)),
      readsFrom: {db.items, db.imageMeta, db.ratings, db.sources},
    );
    return [
      for (final e in await loadPhotoEntries(q))
        (id: e.id, source: e.sourceId, name: e.name, rel: e.relPath),
    ];
  }

  test('IMG-016 the photos of a WebDAV share are indexed and listed', () async {
    final out = await scanner.scan(sourceId);
    expect(out.state, ScanJobState.done, reason: '${out.error}');
    final list = await entries();
    expect(list.map((e) => e.name).toSet(), {
      'IMG_0001.jpg',
      'My trip 2.jpg',
      'ünï côdé.jpg',
    });
    expect(list.every((e) => e.source == sourceId), isTrue);
    expect(list.map((e) => e.rel), everyElement(startsWith('Holiday/')));
  });

  test('IMG-016 a photo opens from the share, read in pieces', () async {
    await scanner.scan(sourceId);
    final e = (await loadPhotoEntries(
      db.customSelect(
        photoEntriesSql(const rules.Visibility(unlocked: true)),
        readsFrom: {db.items},
      ),
    )).firstWhere((p) => p.name == 'My trip 2.jpg');
    final src = await files.open(e);
    try {
      expect(await src.file.length(), jpeg.length);
      expect(await src.file.read(0, 2), [0xFF, 0xD8]);
      final tail = await src.file.read(jpeg.length - 2, 10);
      expect(tail, jpeg.sublist(jpeg.length - 2));
    } finally {
      await src.file.close();
    }
    expect(server.requests.where((r) => r.startsWith('GET')), isNotEmpty);
  });

  test('IMG-016 a thumbnail is made from what the share sends', () async {
    await scanner.scan(sourceId);
    final e = (await loadPhotoEntries(
      db.customSelect(
        photoEntriesSql(const rules.Visibility(unlocked: true)),
        readsFrom: {db.items},
      ),
    )).firstWhere((p) => p.name == 'IMG_0001.jpg');
    final thumbs = PipelineThumbnailSource(pipeline, files);
    final file = await thumbs.load(e, ThumbnailPriority.visible, (_) {});
    expect(file.existsSync(), isTrue);
    expect(file.lengthSync(), greaterThan(0));
    // The second time it is on disk: the share is not asked again.
    final gets = server.requests.where((r) => r.startsWith('GET')).length;
    final again = await thumbs.load(e, ThumbnailPriority.visible, (_) {});
    expect(again.path, file.path);
    expect(server.requests.where((r) => r.startsWith('GET')).length, gets);
  });

  group('IMG-016 a share that cannot be reached', () {
    test(
      'IMG-016 the photos stay listed and opening one fails cleanly',
      () async {
        await scanner.scan(sourceId);
        final before = await entries();
        expect(before, hasLength(3));
        final e = (await loadPhotoEntries(
          db.customSelect(
            photoEntriesSql(const rules.Visibility(unlocked: true)),
            readsFrom: {db.items},
          ),
        )).firstWhere((p) => p.name == 'IMG_0001.jpg');
        await files.close();
        await server.close();

        // A rescan reports the failure and forgets nothing.
        final out = await scanner.scan(sourceId);
        expect(out.state, ScanJobState.failed);
        expect(await entries(), hasLength(3));

        // The source says it could not be reached.
        final summary = (await SourceRepository(
          db: db,
          resolver: resolver,
        ).summaries()).single;
        expect(summary.health, SourceHealth.unreachable);

        // Opening a photo is an error to show, not a hang.
        await expectLater(
          files.open(e).timeout(const Duration(seconds: 20)),
          throwsA(isA<Object>()),
        );
        // A thumbnail not yet made fails the same way, and the tile keeps its
        // placeholder.
        final thumbs = PipelineThumbnailSource(pipeline, files);
        await expectLater(
          thumbs
              .load(e, ThumbnailPriority.visible, (_) {})
              .timeout(const Duration(seconds: 20)),
          throwsA(isA<Object>()),
        );
      },
    );

    test('IMG-016 when the share is back, the photos open again', () async {
      await scanner.scan(sourceId);
      final e = (await loadPhotoEntries(
        db.customSelect(
          photoEntriesSql(const rules.Visibility(unlocked: true)),
          readsFrom: {db.items},
        ),
      )).firstWhere((p) => p.name == 'IMG_0001.jpg');
      final src = await files.open(e);
      expect(await src.file.length(), jpeg.length);
      await src.file.close();
      // The same share, a new connection: a stale one is not kept forever.
      await files.close();
      final again = await files.open(e);
      expect(await again.file.read(0, 2), [0xFF, 0xD8]);
      await again.file.close();
    });
  });
}

typedef PhotoEntryRow = ({int id, int source, String name, String rel});

/// The pipeline writes thumbnails to the cache folder, never to the share.
final class _NoWrites implements ImageIo {
  @override
  String? localPath(Uri uri) => null;

  @override
  Future<VirtualFile> open(Uri uri) => throw UnimplementedError();

  @override
  Future<void> replace(Uri uri, Uint8List bytes) =>
      throw StateError('a share is read only here');

  @override
  Future<void> create(Uri uri, Uint8List bytes) =>
      throw StateError('a share is read only here');

  @override
  Future<bool> exists(Uri uri) async => false;

  @override
  Future<void> delete(Uri uri) => throw StateError('a share is read only here');
}
