import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mediahro/core/db/library_database.dart';
import 'package:mediahro/images/pipeline/thumbnail_cache.dart';

void main() {
  late LibraryDatabase db;
  late Directory dir;
  late DateTime now;
  late ThumbnailCache cache;

  ThumbnailCache make({int maxBytes = 1000}) => ThumbnailCache(
    db: db,
    directory: dir,
    maxBytes: maxBytes,
    clock: () => now,
    touchFlushInterval: const Duration(hours: 1),
  );

  setUp(() {
    db = LibraryDatabase.memory();
    dir = Directory.systemTemp.createTempSync('mediahro-thumbs');
    now = DateTime.utc(2026, 10, 21, 12);
    cache = make();
  });

  tearDown(() async {
    await cache.dispose();
    await db.close();
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  Uint8List bytes(int n) => Uint8List(n);

  test('IMG-003 the key changes with path, mtime, size, orientation, edge', () {
    final uri = Uri.parse('file:///photos/a.jpg');
    final base = ThumbnailCache.keyFor(
      uri: uri,
      edge: 256,
      mtime: DateTime.utc(2026),
      size: 100,
    );
    expect(base, hasLength(40));
    expect(
      ThumbnailCache.keyFor(
        uri: uri,
        edge: 256,
        mtime: DateTime.utc(2026),
        size: 100,
      ),
      base,
    );
    for (final other in [
      ThumbnailCache.keyFor(
        uri: Uri.parse('file:///photos/b.jpg'),
        edge: 256,
        mtime: DateTime.utc(2026),
        size: 100,
      ),
      ThumbnailCache.keyFor(
        uri: uri,
        edge: 512,
        mtime: DateTime.utc(2026),
        size: 100,
      ),
      ThumbnailCache.keyFor(
        uri: uri,
        edge: 256,
        mtime: DateTime.utc(2027),
        size: 100,
      ),
      ThumbnailCache.keyFor(
        uri: uri,
        edge: 256,
        mtime: DateTime.utc(2026),
        size: 101,
      ),
      ThumbnailCache.keyFor(
        uri: uri,
        edge: 256,
        mtime: DateTime.utc(2026),
        size: 100,
        orientation: 6,
      ),
    ]) {
      expect(other, isNot(base));
    }
  });

  test(
    'IMG-003 a stored thumbnail is found again and the bytes round-trip',
    () async {
      expect(await cache.lookup('ab'.padRight(40, '0')), isNull);
      final data = Uint8List.fromList([1, 2, 3, 4]);
      final f = await cache.store('ab'.padRight(40, '0'), data);
      expect(f.existsSync(), isTrue);
      final hit = await cache.lookup('ab'.padRight(40, '0'));
      expect(hit?.readAsBytesSync(), data);
      expect(await cache.totalBytes(), 4);
    },
  );

  test(
    'IMG-003 storing the same key again replaces it without double counting',
    () async {
      final k = 'cd'.padRight(40, '1');
      await cache.store(k, bytes(100));
      await cache.store(k, bytes(60));
      expect(await cache.totalBytes(), 60);
      expect((await cache.lookup(k))!.lengthSync(), 60);
    },
  );

  test('IMG-003 a row whose file vanished is a miss and is dropped', () async {
    final k = 'ef'.padRight(40, '2');
    final f = await cache.store(k, bytes(10));
    f.deleteSync();
    expect(await cache.lookup(k), isNull);
    expect(await cache.totalBytes(), 0);
  });

  test(
    'IMG-003 eviction removes the least recently used files first',
    () async {
      final keys = [for (var i = 0; i < 5; i++) '0$i'.padRight(40, '3')];
      for (final k in keys) {
        now = now.add(const Duration(minutes: 1));
        await cache.store(k, bytes(300)); // 1500 bytes against a 1000 limit
      }
      // The first stores already evicted the oldest; touch an old survivor and
      // add more so the touched one outlives its neighbours.
      final survivors = <String>[];
      for (final k in keys) {
        if (await cache.lookup(k) != null) survivors.add(k);
      }
      expect(survivors, isNotEmpty);
      expect(await cache.totalBytes(), lessThanOrEqualTo(1000));
      // Newest entries survive, oldest are gone.
      expect(survivors.last, keys.last);
      expect(survivors, isNot(contains(keys.first)));
    },
  );

  test(
    'IMG-003 lookups count as use: a touched entry outlives an untouched one',
    () async {
      final a = 'a0'.padRight(40, '4');
      final b = 'b0'.padRight(40, '4');
      final c = 'c0'.padRight(40, '4');
      cache = make(maxBytes: 700);
      now = now.add(const Duration(minutes: 1));
      await cache.store(a, bytes(300));
      now = now.add(const Duration(minutes: 1));
      await cache.store(b, bytes(300));
      now = now.add(const Duration(minutes: 1));
      expect(await cache.lookup(a), isNotNull); // a is now newer than b
      now = now.add(const Duration(minutes: 1));
      await cache.store(c, bytes(300)); // over the limit: evict the oldest
      expect(await cache.lookup(b), isNull);
      expect(await cache.lookup(a), isNotNull);
      expect(await cache.lookup(c), isNotNull);
    },
  );

  test(
    'IMG-003 a scroll of lookups does not write to the database until flushed',
    () async {
      final k = 'f0'.padRight(40, '5');
      await cache.store(k, bytes(10));
      final before = (await db.select(db.thumbCache).getSingle()).lastUsedAt;
      now = now.add(const Duration(hours: 2));
      for (var i = 0; i < 20; i++) {
        await cache.lookup(k);
      }
      expect((await db.select(db.thumbCache).getSingle()).lastUsedAt, before);
      await cache.flushTouches();
      expect(
        (await db.select(db.thumbCache).getSingle()).lastUsedAt,
        isNot(before),
      );
    },
  );

  test('IMG-003 clear removes the files and the rows', () async {
    await cache.store('aa'.padRight(40, '6'), bytes(10));
    await cache.clear();
    expect(await cache.totalBytes(), 0);
    expect(dir.existsSync(), isFalse);
  });
}
