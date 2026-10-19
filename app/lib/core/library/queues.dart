import 'dart:math';

import 'package:drift/drift.dart';
import 'package:mediahro/core/db/library_database.dart';

enum QueueMode { audio, video }

enum RepeatMode { off, one, all }

/// A queue with its entries in play order.
final class PlayQueue {
  const PlayQueue(this.row, this.entries);

  final QueueRow row;
  final List<QueueItemRow> entries;

  int get currentIndex => row.currentIndex;
  QueueItemRow? get current =>
      currentIndex >= 0 && currentIndex < entries.length
      ? entries[currentIndex]
      : null;
}

/// Named audio queues (Musicolet pattern) and the single video queue
/// (LIB-008). Everything is persisted, so queues survive restarts and
/// engine faults (CORE-011).
final class QueueRepository {
  QueueRepository(this.db, {DateTime Function()? clock, Random? random})
    : _clock = clock ?? DateTime.now,
      _random = random ?? Random();

  final LibraryDatabase db;
  final DateTime Function() _clock;
  final Random _random;

  /// The one video queue, created on first use.
  Future<int> videoQueue() async {
    final existing = await (db.select(
      db.queues,
    )..where((q) => q.mode.equals(QueueMode.video.name))).getSingleOrNull();
    if (existing != null) return existing.id;
    return await db
        .into(db.queues)
        .insert(
          QueuesCompanion.insert(
            name: 'video',
            mode: QueueMode.video.name,
            active: const Value(true),
            updatedAt: _clock(),
          ),
        );
  }

  /// A new named audio queue; becomes active when it is the first one.
  Future<int> createAudioQueue(String name) async {
    final count = await _audioQueues().get();
    return await db
        .into(db.queues)
        .insert(
          QueuesCompanion.insert(
            name: name,
            mode: QueueMode.audio.name,
            active: Value(count.isEmpty),
            updatedAt: _clock(),
          ),
        );
  }

  Future<List<QueueRow>> audioQueues() => _audioQueues().get();

  Stream<List<QueueRow>> watchAudioQueues() => _audioQueues().watch();

  SimpleSelectStatement<$QueuesTable, QueueRow> _audioQueues() =>
      db.select(db.queues)
        ..where((q) => q.mode.equals(QueueMode.audio.name))
        ..orderBy([(q) => OrderingTerm.asc(q.id)]);

  Future<void> rename(int queueId, String name) =>
      _write(queueId, QueuesCompanion(name: Value(name)));

  /// Deletes an audio queue; another one becomes active if needed.
  Future<void> delete(int queueId) => db.transaction(() async {
    final q = await _queue(queueId);
    if (q.mode == QueueMode.video.name) {
      throw StateError('the video queue cannot be deleted');
    }
    await (db.delete(db.queues)..where((r) => r.id.equals(queueId))).go();
    if (q.active) {
      final next = await _audioQueues().get();
      if (next.isNotEmpty) await activate(next.first.id);
    }
  });

  /// Only one audio queue is active at a time.
  Future<void> activate(int queueId) => db.transaction(() async {
    final q = await _queue(queueId);
    await (db.update(db.queues)..where((r) => r.mode.equals(q.mode))).write(
      const QueuesCompanion(active: Value(false)),
    );
    await _write(queueId, const QueuesCompanion(active: Value(true)));
  });

  Future<QueueRow?> active(QueueMode mode) =>
      (db.select(db.queues)
            ..where((q) => q.mode.equals(mode.name) & q.active.equals(true)))
          .getSingleOrNull();

  Future<PlayQueue> load(int queueId) async {
    final row = await _queue(queueId);
    return PlayQueue(row, await _entries(queueId));
  }

  /// Replaces the queue with [itemIds] and starts at [startIndex].
  Future<void> replace(int queueId, List<int> itemIds, {int startIndex = 0}) =>
      db.transaction(() async {
        await (db.delete(
          db.queueItems,
        )..where((q) => q.queueId.equals(queueId))).go();
        await _insertItems(queueId, itemIds, 0);
        await _write(
          queueId,
          QueuesCompanion(
            currentIndex: Value(startIndex),
            positionMs: const Value(0),
          ),
        );
      });

  /// Appends to the end ("add to queue").
  Future<void> append(int queueId, List<int> itemIds) =>
      db.transaction(() async {
        final n = (await _entries(queueId)).length;
        await _insertItems(queueId, itemIds, n);
        await _touch(queueId);
      });

  /// Inserts right after the current entry ("play next").
  Future<void> playNext(int queueId, List<int> itemIds) => db.transaction(
    () async {
      final q = await _queue(queueId);
      final entries = await _entries(queueId);
      final at = entries.isEmpty ? 0 : q.currentIndex + 1;
      for (final e in entries.where((e) => e.position >= at)) {
        await (db.update(db.queueItems)..where((r) => r.id.equals(e.id))).write(
          QueueItemsCompanion(position: Value(e.position + itemIds.length)),
        );
      }
      await _insertItems(queueId, itemIds, at);
      await _touch(queueId);
    },
  );

  Future<void> appendUri(int queueId, String uri, {String? title}) =>
      db.transaction(() async {
        final n = (await _entries(queueId)).length;
        await db
            .into(db.queueItems)
            .insert(
              QueueItemsCompanion.insert(
                queueId: queueId,
                position: n,
                uri: Value(uri),
                title: Value(title),
              ),
            );
        await _touch(queueId);
      });

  Future<void> move(int queueId, int from, int to) => db.transaction(() async {
    final q = await _queue(queueId);
    final entries = await _entries(queueId);
    final current = q.currentIndex;
    final e = entries.removeAt(from);
    entries.insert(to, e);
    await _renumber(entries);
    // The playing entry keeps playing.
    var newCurrent = current;
    if (from == current) {
      newCurrent = to;
    } else if (from < current && to >= current) {
      newCurrent = current - 1;
    } else if (from > current && to <= current) {
      newCurrent = current + 1;
    }
    await _write(queueId, QueuesCompanion(currentIndex: Value(newCurrent)));
  });

  Future<void> removeAt(int queueId, int index) => db.transaction(() async {
    final q = await _queue(queueId);
    final entries = await _entries(queueId);
    final e = entries.removeAt(index);
    await (db.delete(db.queueItems)..where((r) => r.id.equals(e.id))).go();
    await _renumber(entries);
    var current = q.currentIndex;
    if (index < current || (index == current && current >= entries.length)) {
      current = max(0, current - 1);
    }
    await _write(queueId, QueuesCompanion(currentIndex: Value(current)));
  });

  Future<void> clear(int queueId) => db.transaction(() async {
    await (db.delete(
      db.queueItems,
    )..where((q) => q.queueId.equals(queueId))).go();
    await _write(
      queueId,
      const QueuesCompanion(currentIndex: Value(0), positionMs: Value(0)),
    );
  });

  /// Persists the play head (called every few seconds by the player).
  Future<void> savePosition(int queueId, int index, Duration position) =>
      _write(
        queueId,
        QueuesCompanion(
          currentIndex: Value(index),
          positionMs: Value(position.inMilliseconds),
        ),
      );

  /// Advances per repeat mode; returns the new index or null at the end.
  Future<int?> next(int queueId) async {
    final q = await load(queueId);
    final repeat = RepeatMode.values.byName(q.row.repeat);
    if (q.entries.isEmpty) return null;
    int? n;
    if (repeat == RepeatMode.one) {
      n = q.currentIndex;
    } else if (q.currentIndex + 1 < q.entries.length) {
      n = q.currentIndex + 1;
    } else if (repeat == RepeatMode.all) {
      n = 0;
    }
    if (n != null) await savePosition(queueId, n, Duration.zero);
    return n;
  }

  Future<int?> previous(int queueId) async {
    final q = await load(queueId);
    if (q.entries.isEmpty) return null;
    final n = q.currentIndex > 0 ? q.currentIndex - 1 : 0;
    await savePosition(queueId, n, Duration.zero);
    return n;
  }

  Future<void> setRepeat(int queueId, RepeatMode mode) =>
      _write(queueId, QueuesCompanion(repeat: Value(mode.name)));

  /// Shuffles the entries after the current one; the current stays first.
  Future<void> shuffle(int queueId, {required bool enabled}) => db.transaction(
    () async {
      if (enabled) {
        final q = await _queue(queueId);
        final entries = await _entries(queueId);
        if (entries.isNotEmpty) {
          final cur = entries.removeAt(q.currentIndex);
          entries
            ..shuffle(_random)
            ..insert(0, cur);
          await _renumber(entries);
          await _write(queueId, const QueuesCompanion(currentIndex: Value(0)));
        }
      }
      await _write(queueId, QueuesCompanion(shuffle: Value(enabled)));
    },
  );

  Future<void> _insertItems(int queueId, List<int> itemIds, int from) async {
    var pos = from;
    await db.batch((b) {
      b.insertAll(db.queueItems, [
        for (final id in itemIds)
          QueueItemsCompanion.insert(
            queueId: queueId,
            position: pos++,
            itemId: Value(id),
          ),
      ]);
    });
  }

  Future<QueueRow> _queue(int id) =>
      (db.select(db.queues)..where((q) => q.id.equals(id))).getSingle();

  Future<List<QueueItemRow>> _entries(int queueId) =>
      (db.select(db.queueItems)
            ..where((q) => q.queueId.equals(queueId))
            ..orderBy([(q) => OrderingTerm.asc(q.position)]))
          .get();

  Future<void> _renumber(List<QueueItemRow> entries) async {
    for (var i = 0; i < entries.length; i++) {
      if (entries[i].position == i) continue;
      await (db.update(db.queueItems)..where((r) => r.id.equals(entries[i].id)))
          .write(QueueItemsCompanion(position: Value(i)));
    }
  }

  Future<void> _touch(int queueId) => _write(queueId, const QueuesCompanion());

  Future<void> _write(int queueId, QueuesCompanion c) =>
      (db.update(db.queues)..where((q) => q.id.equals(queueId))).write(
        c.copyWith(updatedAt: Value(_clock())),
      );
}
