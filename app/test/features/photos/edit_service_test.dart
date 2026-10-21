import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mediahro/core/db/library_database.dart';
import 'package:mediahro/features/photos/edit/edit_store.dart';
import 'package:mediahro/features/photos/edit/photo_editor_service.dart';
import 'package:mediahro/features/photos/image_prober.dart';
import 'package:mediahro/features/photos/photo_files.dart';
import 'package:mediahro/features/photos/timeline/timeline_model.dart';
import 'package:mediahro/images/edit/edit_recipe.dart';
import 'package:mediahro/images/image_pipeline.dart';
import 'package:mediahro/images/pipeline/image_io.dart';
import 'package:mediahro/images/pipeline/image_worker.dart';
import 'package:mediahro/images/pipeline/mediahro_image_pipeline.dart';
import 'package:mediahro/images/pipeline/pixel_codec.dart';
import 'package:mediahro/images/pipeline/thumbnail_cache.dart';
import 'package:mediahro/images/pipeline/worker_pool.dart';
import 'package:mediahro_ffi/mediahro_ffi.dart' show VirtualFile;

import '../../core/seed.dart';
import '../../images/fixtures.dart';
import '../../images/pipeline_fakes.dart';
import 'photos_harness.dart';

/// Files of one fake share; `open` reads them from [MemoryIo].
final class _Files implements PhotoFileOpener {
  _Files(this.io);

  final MemoryIo io;

  @override
  Future<Uri> uriOf(PhotoEntry e) async =>
      Uri.parse('smb://nas/photos/${e.relPath}');

  @override
  Future<ImageSource> open(PhotoEntry e) async {
    final uri = await uriOf(e);
    return ImageSource(
      MemoryFile(uri, io.files[uri]!),
      mtime: DateTime.utc(2026, 10, 21),
    );
  }
}

void main() {
  group('IMG-009 saved edits', () {
    late Directory dir;
    late EditStore store;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('mediahro-edits');
      store = EditStore(Directory('${dir.path}/edits'));
    });

    tearDown(() => dir.deleteSync(recursive: true));

    test('IMG-009 an edit is kept for next time', () async {
      const r = EditRecipe(
        turns: 1,
        adjust: {AdjustKind.exposure: 0.4},
        crop: NormRect(0.1, 0.1, 0.5, 0.5),
      );
      await store.save(7, r);
      final back = await store.load(7);
      expect(back.turns, 1);
      expect(back.amount(AdjustKind.exposure), 0.4);
      expect(back.crop, r.crop);
      expect((await store.load(8)).isIdentity, isTrue);
    });

    test('IMG-009 an empty edit leaves no file', () async {
      await store.save(7, const EditRecipe(turns: 2));
      expect(File('${dir.path}/edits/7.json').existsSync(), isTrue);
      await store.save(7, EditRecipe.none);
      expect(File('${dir.path}/edits/7.json').existsSync(), isFalse);
    });

    test('IMG-009 a damaged file counts as no edit', () async {
      await Directory('${dir.path}/edits').create(recursive: true);
      File('${dir.path}/edits/3.json').writeAsStringSync('{ not json');
      expect((await store.load(3)).isIdentity, isTrue);
    });

    test('IMG-009 deleting what is not there is fine', () async {
      await store.delete(99);
    });
  });

  group('IMG-009 formats', () {
    test('IMG-009 formats the app can write are kept, others become JPEG', () {
      expect(editFormatFor('png'), EncodeFormat.png);
      expect(editFormatFor('WEBP'), EncodeFormat.webp);
      expect(editFormatFor('jxl'), EncodeFormat.jxl);
      expect(editFormatFor('jpg'), EncodeFormat.jpeg);
      for (final e in ['heic', 'avif', 'cr2', 'tiff', 'gif', 'bmp']) {
        expect(editFormatFor(e), EncodeFormat.jpeg, reason: e);
      }
      expect(extensionOf(EncodeFormat.jpeg), 'jpg');
      expect(extensionOf(EncodeFormat.png), 'png');
    });
  });

  group('IMG-009 saving', () {
    late LibraryDatabase db;
    late Directory dir;
    late MemoryIo io;
    late MediahroImagePipeline pipeline;
    late EditStore store;
    late PhotoEditService service;
    late Seed seed;

    setUp(() {
      db = LibraryDatabase.memory();
      seed = Seed(db);
      dir = Directory.systemTemp.createTempSync('mediahro-edit-service');
      io = MemoryIo();
      pipeline = MediahroImagePipeline(
        worker: ImageWorkerClient(
          IsolateWorkerPool(size: 1, factory: fakeWorker),
        ),
        cache: ThumbnailCache(db: db, directory: Directory('${dir.path}/t')),
        io: io,
        fallback: FakeUiFallback(),
      );
      store = EditStore(Directory('${dir.path}/edits'));
      service = PhotoEditService(
        files: _Files(io),
        pipeline: pipeline,
        io: io,
        prober: ImageProber(pipeline: pipeline, db: db, io: io),
        db: db,
        store: store,
      );
    });

    tearDown(() async {
      await pipeline.dispose();
      await db.close();
      dir.deleteSync(recursive: true);
    });

    PhotoEntry entry(int id, String path) {
      final e = fakeEntries(days: 1, perDay: 1, firstId: id).single;
      return PhotoEntry(
        id: id,
        sourceId: 1,
        relPath: path,
        name: path.split('/').last,
        ext: path.split('.').last.toLowerCase(),
        isVideo: false,
        size: 1,
        mtime: e.mtime,
        date: e.date,
      );
    }

    const warm = EditRecipe(adjust: {AdjustKind.temperature: 0.8});

    test(
      'IMG-009 a copy is written next to the original, which is untouched',
      () async {
        final original = sampleJpeg(exif: sampleExif());
        io.add('trip/a.jpg', original);
        final name = await service.saveCopy(entry(1, 'trip/a.jpg'), warm);
        expect(name, 'a_edited.jpg');
        final copy = io.files[Uri.parse('smb://nas/photos/trip/a_edited.jpg')];
        expect(copy, isNotNull);
        expect(io.files[Uri.parse('smb://nas/photos/trip/a.jpg')], original);
      },
    );

    test('IMG-009 a second copy gets its own name', () async {
      io.add('a.jpg', sampleJpeg());
      final e = entry(1, 'a.jpg');
      expect(await service.saveCopy(e, warm), 'a_edited.jpg');
      expect(await service.saveCopy(e, warm), 'a_edited_2.jpg');
      expect(await service.saveCopy(e, warm), 'a_edited_3.jpg');
    });

    test(
      'IMG-009 a PNG stays a PNG, a format we cannot write becomes JPEG',
      () async {
        io.add('p.png', fakeImage(4, 2));
        expect(await service.saveCopy(entry(1, 'p.png'), warm), 'p_edited.png');
        io.add('h.heic', fakeImage(4, 2));
        expect(
          await service.saveCopy(entry(2, 'h.heic'), warm),
          'h_edited.jpg',
        );
      },
    );

    test('IMG-009 the copy carries the original metadata', () async {
      io.add('a.jpg', sampleJpeg(exif: sampleExif()));
      await service.saveCopy(entry(1, 'a.jpg'), warm);
      final copy = io.files[Uri.parse('smb://nas/photos/a_edited.jpg')]!;
      expect(copy.length, greaterThan(100));
    });

    test(
      'IMG-009 replacing rewrites the original and forgets the edit',
      () async {
        final id = await seed.item('a.jpg', kind: ItemKind.image);
        io.add('a.jpg', sampleJpeg(exif: sampleExif()));
        final e = entry(id, 'a.jpg');
        await store.save(id, warm);
        await service.replaceOriginal(e, warm);
        expect(io.writes, contains(Uri.parse('smb://nas/photos/a.jpg')));
        expect((await store.load(id)).isIdentity, isTrue);
      },
    );

    test('IMG-009 a RAW or HEIC original is never replaced', () async {
      io.add('r.cr2', fakeImage(4, 2));
      final e = entry(1, 'r.cr2');
      expect(service.canReplace(e), isFalse);
      await expectLater(
        service.replaceOriginal(e, warm),
        throwsUnsupportedError,
      );
      expect(service.canReplace(entry(2, 'x.jpg')), isTrue);
      expect(service.canReplace(entry(3, 'x.heic')), isFalse);
    });

    test('IMG-009 a read-only share reports the failure', () async {
      io.add('a.jpg', sampleJpeg());
      final ro = PhotoEditService(
        files: _Files(io),
        pipeline: pipeline,
        io: _ReadOnlyIo(io),
        prober: ImageProber(pipeline: pipeline, db: db, io: io),
        db: db,
        store: store,
      );
      await expectLater(
        ro.saveCopy(entry(1, 'a.jpg'), warm),
        throwsA(isA<FileSystemException>()),
      );
    });

    test(
      'IMG-009 the preview is a reduced copy with the edit applied',
      () async {
        io.add('a.png', fakeImage(8, 4));
        final proxy = await service.loadProxy(entry(1, 'a.png'));
        expect((proxy.width, proxy.height), (8, 4));
        final out = await service.render(
          proxy,
          const EditRecipe(adjust: {AdjustKind.exposure: 0.5}),
        );
        expect(out.rgba[2], greaterThan(proxy.rgba[2]));
      },
    );
  });

  group('IMG-009 batch apply', () {
    const recipe = EditRecipe(turns: 1, adjust: {AdjustKind.saturation: 0.5});

    test('IMG-009 only the look goes to other photos', () async {
      final seen = <EditRecipe>[];
      final editor = _RecordingEditor(onSave: (e, r) => seen.add(r));
      final out = await applyLookToPhotos(
        editor,
        fakeEntries(days: 1, perDay: 3, firstId: 1),
        recipe,
      );
      expect(out, (saved: 3, failed: 0));
      expect(seen.every((r) => !r.hasGeometry), isTrue);
      expect(seen.every((r) => r.amount(AdjustKind.saturation) == 0.5), isTrue);
    });

    test(
      'IMG-009 videos are skipped and one bad file does not stop the rest',
      () async {
        final editor = _RecordingEditor(failIds: {2});
        final progress = <int>[];
        final out = await applyLookToPhotos(
          editor,
          fakeEntries(days: 1, perDay: 4, firstId: 1, videos: {3}),
          recipe,
          onProgress: progress.add,
        );
        expect(out, (saved: 2, failed: 1));
        expect(editor.copies.map((e) => e.id), [1, 4]);
        expect(progress, [1, 2, 3]);
      },
    );

    test('IMG-009 replacing falls back to copies for formats that cannot be replaced', () async {
      final editor = _RecordingEditor(replaceable: {1});
      await applyLookToPhotos(
        editor,
        fakeEntries(days: 1, perDay: 3, firstId: 1),
        recipe,
        replace: true,
      );
      expect(editor.replaced.map((e) => e.id), [1]);
      expect(editor.copies.map((e) => e.id), [2, 3]);
    });
  });
}

final class _ReadOnlyIo implements ImageIo {
  _ReadOnlyIo(this.inner);

  final MemoryIo inner;

  @override
  String? localPath(Uri uri) => inner.localPath(uri);

  @override
  Future<VirtualFile> open(Uri uri) => inner.open(uri);

  @override
  Future<void> delete(Uri uri) => inner.delete(uri);

  @override
  Future<void> create(Uri uri, Uint8List bytes) =>
      throw const FileSystemException('read-only');

  @override
  Future<void> replace(Uri uri, Uint8List bytes) =>
      throw const FileSystemException('read-only');

  @override
  Future<bool> exists(Uri uri) => inner.exists(uri);
}

final class _RecordingEditor implements PhotoEditor {
  _RecordingEditor({
    this.failIds = const {},
    this.replaceable = const {},
    this.onSave,
  });

  final Set<int> failIds;
  final Set<int> replaceable;
  final void Function(PhotoEntry, EditRecipe)? onSave;
  final List<PhotoEntry> copies = [];
  final List<PhotoEntry> replaced = [];

  @override
  bool canReplace(PhotoEntry entry) => replaceable.contains(entry.id);

  @override
  Future<String> saveCopy(PhotoEntry entry, EditRecipe recipe) async {
    if (failIds.contains(entry.id)) throw StateError('no');
    onSave?.call(entry, recipe);
    copies.add(entry);
    return 'x';
  }

  @override
  Future<void> replaceOriginal(PhotoEntry entry, EditRecipe recipe) async {
    if (failIds.contains(entry.id)) throw StateError('no');
    onSave?.call(entry, recipe);
    replaced.add(entry);
  }

  @override
  Future<PixelFrame> loadProxy(
    PhotoEntry entry, {
    int edge = editPreviewEdge,
  }) => throw UnimplementedError();

  @override
  Future<PixelFrame> render(PixelFrame proxy, EditRecipe recipe) =>
      throw UnimplementedError();

  @override
  Future<EditRecipe> savedRecipe(PhotoEntry entry) async => EditRecipe.none;

  @override
  Future<void> storeRecipe(PhotoEntry entry, EditRecipe recipe) async {}
}
