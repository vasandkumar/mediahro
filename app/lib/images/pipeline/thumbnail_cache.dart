import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:mediahro/core/db/library_database.dart';

/// On-disk LRU of generated thumbnails (IMG-003, docs/05 §5): small WebP
/// files named by a hash of (path, mtime, size, orientation, edge), tracked
/// in the `thumb_cache` table. Looking a thumbnail up never writes to the
/// database during a scroll: last-used times are batched and flushed later.
final class ThumbnailCache {
  ThumbnailCache({
    required this.db,
    required this.directory,
    this.maxBytes = 512 << 20,
    DateTime Function()? clock,
    this.touchFlushInterval = const Duration(seconds: 20),
  }) : _clock = clock ?? DateTime.now;

  final LibraryDatabase db;
  final Directory directory;

  /// Upper bound on the cache size; eviction removes the least recently used
  /// files down to 90 % of it.
  final int maxBytes;
  final Duration touchFlushInterval;
  final DateTime Function() _clock;

  final Map<String, DateTime> _touched = {};
  Timer? _flushTimer;
  int? _total;

  /// The cache key for one rendition of one image.
  static String keyFor({
    required Uri uri,
    required int edge,
    DateTime? mtime,
    int? size,
    int orientation = 1,
  }) {
    final raw =
        '$uri|${mtime?.millisecondsSinceEpoch ?? 0}|${size ?? 0}|$orientation|$edge';
    return sha1.convert(utf8.encode(raw)).toString();
  }

  File _fileFor(String key, String ext) => File(
    '${directory.path}${Platform.pathSeparator}${key.substring(0, 2)}'
    '${Platform.pathSeparator}$key.$ext',
  );

  /// The cached file for [key], or null on a miss (also when the row is
  /// there but the file vanished: the row is dropped).
  Future<File?> lookup(String key) async {
    final row = await (db.select(
      db.thumbCache,
    )..where((t) => t.key.equals(key))).getSingleOrNull();
    if (row == null) return null;
    final f = File(row.path);
    if (!f.existsSync()) {
      await _drop(row.key, row.bytes);
      return null;
    }
    _touch(key);
    return f;
  }

  void _touch(String key) {
    _touched[key] = _clock();
    _flushTimer ??= Timer(touchFlushInterval, () {
      _flushTimer = null;
      unawaited(flushTouches());
    });
  }

  /// Writes the batched last-used times.
  Future<void> flushTouches() async {
    if (_touched.isEmpty) return;
    final batch = Map.of(_touched);
    _touched.clear();
    await db.batch((b) {
      for (final e in batch.entries) {
        b.update(
          db.thumbCache,
          ThumbCacheCompanion(lastUsedAt: Value(e.value)),
          where: (t) => t.key.equals(e.key),
        );
      }
    });
  }

  /// Stores [data] under [key] (replacing an older rendition) and evicts to
  /// stay under [maxBytes].
  Future<File> store(String key, Uint8List data, {String ext = 'webp'}) async {
    final file = _fileFor(key, ext);
    await file.parent.create(recursive: true);
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsBytes(data, flush: true);
    await tmp.rename(file.path);
    final existing = await (db.select(
      db.thumbCache,
    )..where((t) => t.key.equals(key))).getSingleOrNull();
    await db
        .into(db.thumbCache)
        .insertOnConflictUpdate(
          ThumbCacheCompanion.insert(
            key: key,
            path: file.path,
            bytes: data.length,
            lastUsedAt: _clock(),
          ),
        );
    _total =
        (_total ?? await totalBytes()) + data.length - (existing?.bytes ?? 0);
    if (_total! > maxBytes) await evict();
    return file;
  }

  Future<int> totalBytes() async {
    final r = await db
        .customSelect(
          'SELECT coalesce(sum(bytes), 0) AS b FROM thumb_cache',
          readsFrom: {db.thumbCache},
        )
        .getSingle();
    return _total = r.read<int>('b');
  }

  /// Removes least recently used entries until the cache is at 90 % of its
  /// limit.
  Future<void> evict() async {
    await flushTouches();
    var total = await totalBytes();
    if (total <= maxBytes) return;
    final target = (maxBytes * 0.9).floor();
    final rows = await (db.select(
      db.thumbCache,
    )..orderBy([(t) => OrderingTerm.asc(t.lastUsedAt)])).get();
    for (final r in rows) {
      if (total <= target) break;
      await _drop(r.key, r.bytes);
      total -= r.bytes;
    }
    _total = total;
  }

  Future<void> _drop(String key, int bytes) async {
    final row = await (db.select(
      db.thumbCache,
    )..where((t) => t.key.equals(key))).getSingleOrNull();
    if (row != null) {
      final f = File(row.path);
      if (f.existsSync()) {
        try {
          f.deleteSync();
        } on FileSystemException {
          // A locked file is retried by the next eviction pass.
        }
      }
    }
    await (db.delete(db.thumbCache)..where((t) => t.key.equals(key))).go();
    if (_total != null) _total = _total! - bytes;
  }

  /// Removes the entries for [keys] (a photo that left the library).
  Future<void> forget(Iterable<String> keys) async {
    for (final key in keys) {
      final row = await (db.select(
        db.thumbCache,
      )..where((t) => t.key.equals(key))).getSingleOrNull();
      if (row != null) await _drop(row.key, row.bytes);
    }
  }

  /// Removes everything (Settings → clear thumbnail cache).
  Future<void> clear() async {
    _touched.clear();
    await db.delete(db.thumbCache).go();
    if (directory.existsSync()) {
      await directory.delete(recursive: true);
    }
    _total = 0;
  }

  Future<void> dispose() async {
    _flushTimer?.cancel();
    _flushTimer = null;
    await flushTouches();
  }
}
