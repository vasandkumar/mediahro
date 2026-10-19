import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:mediahro/core/db/library_database.dart';
import 'package:mediahro/core/index/content_hash.dart' as ch;
import 'package:mediahro/core/index/index_writer.dart';
import 'package:mediahro/core/scanner/scan_service.dart';
import 'package:mediahro/core/sources/source_access.dart';
import 'package:mediahro_ffi/mediahro_ffi.dart';

import '../fakes.dart';

Future<int> addSource(
  LibraryDatabase db,
  Uri root, {
  SourceKind kind = SourceKind.local,
  ScanSchedule schedule = ScanSchedule.manual,
}) => db
    .into(db.sources)
    .insert(
      SourcesCompanion.insert(
        kind: kind,
        name: 'src',
        rootUri: root.toString(),
        addedAt: DateTime.utc(2026),
        schedule: Value(schedule),
      ),
    );

DefaultSourceResolver localResolver([
  Map<SourceKind, FileSystemBuilder>? extra,
]) => DefaultSourceResolver(
  builders: {SourceKind.local: (_) => const LocalFileSystem(), ...?extra},
);

Future<void> touch(Directory dir, String rel, [String body = 'x']) async {
  final f = File('${dir.path}/$rel');
  await f.parent.create(recursive: true);
  await f.writeAsString(body);
}

void main() {
  late LibraryDatabase db;
  late Directory dir;

  setUp(() async {
    db = LibraryDatabase.memory();
    dir = await Directory.systemTemp.createTemp('mediahro_scan');
  });
  tearDown(() async {
    await db.close();
    await dir.delete(recursive: true);
  });

  test('LIB-002 local folder source indexes media by kind and skips hidden and .nomedia folders', () async {
    await touch(dir, 'Films/The.Matrix.1999.1080p.mkv');
    await touch(dir, 'Music/Album/01 Song.flac');
    await touch(dir, 'Photos/IMG_0001.JPG');
    await touch(dir, 'Films/The.Matrix.1999.1080p.en.srt');
    await touch(dir, 'notes.txt');
    await touch(dir, '.thumbnails/t.jpg');
    await touch(dir, 'Private/.nomedia');
    await touch(dir, 'Private/secret.mp4');
    final sid = await addSource(db, dir.uri);
    final svc = ScanService(
      db: db,
      resolver: localResolver(),
      useIsolates: false,
    );
    final out = await svc.scan(sid);
    expect(out.state, ScanJobState.done, reason: '${out.error}');
    final items = await db.select(db.items).get();
    expect(
      {for (final i in items) i.relPath: i.kind},
      {
        'Films/The.Matrix.1999.1080p.mkv': ItemKind.video,
        'Films/The.Matrix.1999.1080p.en.srt': ItemKind.subtitle,
        'Music/Album/01 Song.flac': ItemKind.audio,
        'Photos/IMG_0001.JPG': ItemKind.image,
      },
    );
    final film = items.firstWhere((i) => i.kind == ItemKind.video);
    expect(film.title, 'The Matrix');
    expect(film.parentPath, 'Films');
    final meta = await db.select(db.videoMeta).getSingle();
    expect(meta.year, 1999);
    final job = await db.select(db.scanJobs).getSingle();
    expect(job.state, ScanJobState.done);
    expect(job.added, 4);
  });

  test('LIB-003 incremental rescan applies adds, changes and removals and keeps item ids', () async {
    await touch(dir, 'a.mkv');
    await touch(dir, 'b.mkv');
    await touch(dir, 'c.mkv');
    final sid = await addSource(db, dir.uri);
    final svc = ScanService(
      db: db,
      resolver: localResolver(),
      useIsolates: false,
    );
    await svc.scan(sid);
    final before = {
      for (final i in await db.select(db.items).get()) i.relPath: i.id,
    };

    await File('${dir.path}/b.mkv').writeAsString('longer content');
    await File('${dir.path}/c.mkv').delete();
    await touch(dir, 'd.mkv');
    final out = await svc.scan(sid);
    expect(out.result.added, 1);
    expect(out.result.updated, 1);
    expect(out.result.removed, 1);
    final after = await db.select(db.items).get();
    final byPath = {for (final i in after) i.relPath: i};
    expect(byPath['a.mkv']!.id, before['a.mkv']);
    expect(byPath['b.mkv']!.id, before['b.mkv']);
    expect(byPath['b.mkv']!.size, 14);
    expect(byPath['c.mkv']!.missing, isTrue);
    expect(byPath['d.mkv']!.missing, isFalse);

    // Nothing changed: an empty diff.
    final again = await svc.scan(sid);
    expect(again.result.added + again.result.updated + again.result.removed, 0);
  });

  test(
    'LIB-001 a moved and renamed file keeps its id and progress (content hash)',
    () async {
      await touch(dir, 'old/Movie.mkv', 'movie bytes');
      final sid = await addSource(db, dir.uri);
      final svc = ScanService(
        db: db,
        resolver: localResolver(),
        useIsolates: false,
      );
      await svc.scan(sid);
      final item = await db.select(db.items).getSingle();
      // The probe queue stores a content hash for every file.
      final f = await const LocalFileSystem().open(
        File('${dir.path}/old/Movie.mkv').uri,
      );
      final hash = await ch.contentHash(f);
      await f.close();
      await IndexWriter(db).applyProbe(item.id, ProbeResult(contentHash: hash));
      await db
          .into(db.progress)
          .insert(
            ProgressCompanion.insert(
              itemId: Value(item.id),
              positionMs: 42000,
              updatedAt: DateTime.utc(2026),
            ),
          );
      await Directory('${dir.path}/new').create();
      await File('${dir.path}/old/Movie.mkv')
          .rename('${dir.path}/new/Renamed film.mkv');
      final out = await svc.scan(sid);
      expect(out.result.moved, 1);
      final moved = await db.select(db.items).getSingle();
      expect(moved.id, item.id);
      expect(moved.relPath, 'new/Renamed film.mkv');
      expect((await db.select(db.progress).getSingle()).positionMs, 42000);
    },
  );

  test('LIB-003 scans run on an isolate and report progress', () async {
    for (var i = 0; i < 50; i++) {
      await touch(dir, 'f$i.mp3');
    }
    final sid = await addSource(db, dir.uri);
    final svc = ScanService(db: db, resolver: localResolver());
    final states = <ScanJobState>[];
    final sub = svc.progress.listen((p) => states.add(p.state));
    final out = await svc.scan(sid);
    await Future<void>.delayed(Duration.zero);
    await sub.cancel();
    expect(out.state, ScanJobState.done, reason: '${out.error}');
    expect(await db.select(db.items).get(), hasLength(50));
    expect(states.first, ScanJobState.queued);
    expect(states, contains(ScanJobState.running));
    expect(states.last, ScanJobState.done);
  });

  test('LIB-003 scanning is pausable and cancellable', () async {
    final files = {
      for (var i = 0; i < 3000; i++) 'd${i ~/ 10}/f$i.mkv': bytesOf('x'),
    };
    final mem = MemoryFileSystem(files);
    final sid = await addSource(
      db,
      MemoryFileSystem.root,
      kind: SourceKind.smb,
    );
    final svc = ScanService(
      db: db,
      resolver: localResolver({SourceKind.smb: (_) => mem}),
      useIsolates: false,
    );
    final states = <ScanJobState>[];
    svc.progress.listen((p) => states.add(p.state));
    final job = svc.scan(sid);
    svc.pause(sid);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(await db.select(db.items).get(), isEmpty);
    expect(states, contains(ScanJobState.paused));
    svc.resume(sid);
    final done = await job;
    expect(done.state, ScanJobState.done, reason: '${done.error}');
    expect(await db.select(db.items).get(), hasLength(3000));

    final second = svc.scan(sid);
    svc.cancel(sid);
    expect((await second).state, ScanJobState.cancelled);
  });

  test('LIB-003 per-source schedule: on open scans only onOpen sources; watch rescans on change', () async {
    await touch(dir, 'a.mkv');
    final open = await addSource(db, dir.uri, schedule: ScanSchedule.onOpen);
    final manual = await addSource(db, dir.uri);
    final watched = await addSource(db, dir.uri, schedule: ScanSchedule.watch);
    final svc = ScanService(
      db: db,
      resolver: localResolver(),
      useIsolates: false,
      watchDebounce: const Duration(milliseconds: 10),
    );
    await svc.onAppOpen();
    Future<int> count(int sid) async => (await (db.select(
      db.items,
    )..where((i) => i.sourceId.equals(sid))).get()).length;
    expect(await count(open), 1);
    expect(await count(manual), 0);
    expect(await count(watched), 0);

    final changes = StreamController<void>.broadcast();
    await svc.startWatching((_) => changes.stream);
    changes
      ..add(null)
      ..add(null);
    await Future<void>.delayed(const Duration(milliseconds: 100));
    while (svc.isScanning(watched)) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(await count(watched), 1);
    expect(await db.select(db.scanJobs).get(), hasLength(2));
    await changes.close();
    await svc.dispose();
  });

  test(
    'LIB-003 an unreachable root fails the job without touching the index',
    () async {
      final sid = await addSource(db, Uri.directory('${dir.path}/missing'));
      final svc = ScanService(
        db: db,
        resolver: localResolver(),
        useIsolates: false,
      );
      final out = await svc.scan(sid);
      expect(out.state, ScanJobState.failed);
      expect((await db.select(db.scanJobs).getSingle()).error, isNotNull);
      expect(await db.select(db.items).get(), isEmpty);
    },
  );
}
