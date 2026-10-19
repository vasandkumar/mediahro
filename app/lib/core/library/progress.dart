import 'package:drift/drift.dart';
import 'package:mediahro/core/db/library_database.dart';
import 'package:meta/meta.dart';

/// A server or tracker that mirrors watched state and positions (LIB-010):
/// Jellyfin, Emby and Plex (lane C4 adapters over `ServerLibrary`) and
/// Trakt. Each is opt-in per account.
abstract interface class ProgressSyncTarget {
  String get id;

  /// Whether [itemId] is known to this target (server item map, Trakt ids).
  Future<bool> handles(int itemId);
  Future<void> push(ProgressUpdate update);

  /// Remote state changed since [since] (pulled on sync).
  Future<List<ProgressUpdate>> pull({DateTime? since});
}

@immutable
final class ProgressUpdate {
  const ProgressUpdate({
    required this.itemId,
    required this.position,
    required this.watched,
    required this.at,
    this.duration,
  });

  final int itemId;
  final Duration position;
  final Duration? duration;
  final bool watched;
  final DateTime at;
}

/// Per-item watched state and resume position (LIB-010), play counts and
/// play events for statistics (LIB-015).
final class ProgressRepository {
  ProgressRepository(
    this.db, {
    DateTime Function()? clock,
    this.watchedThreshold = 0.9,
    this.minResume = const Duration(seconds: 30),
  }) : _clock = clock ?? DateTime.now;

  final LibraryDatabase db;
  final DateTime Function() _clock;

  /// Fraction after which an item counts as watched.
  final double watchedThreshold;

  /// Positions earlier than this don't create a resume point.
  final Duration minResume;

  /// Saves the play head (the player calls this every 5 s, CORE-011).
  /// Crossing [watchedThreshold] marks the item watched and resets the
  /// resume point.
  Future<void> savePosition(
    int itemId,
    Duration position, {
    Duration? duration,
  }) async {
    final d = duration;
    final watched =
        d != null &&
        d > Duration.zero &&
        position.inMilliseconds >= d.inMilliseconds * watchedThreshold;
    if (watched) {
      await markWatched([itemId], watched: true);
      return;
    }
    if (position < minResume) return;
    await db
        .into(db.progress)
        .insertOnConflictUpdate(
          ProgressCompanion.insert(
            itemId: Value(itemId),
            positionMs: position.inMilliseconds,
            durationMs: Value(d?.inMilliseconds),
            updatedAt: _clock(),
            dirty: const Value(true),
          ),
        );
  }

  Future<void> markWatched(Iterable<int> itemIds, {required bool watched}) =>
      db.batch((b) {
        b.insertAllOnConflictUpdate(db.progress, [
          for (final id in itemIds)
            ProgressCompanion.insert(
              itemId: Value(id),
              positionMs: 0,
              watched: Value(watched),
              updatedAt: _clock(),
              dirty: const Value(true),
            ),
        ]);
      });

  Future<ProgressRow?> of(int itemId) => (db.select(
    db.progress,
  )..where((p) => p.itemId.equals(itemId))).getSingleOrNull();

  /// Records a finished or stopped play: play count, last played and a
  /// play event with the time actually listened/watched.
  Future<void> recordPlay(int itemId, Duration listened) =>
      db.transaction(() async {
        final now = _clock();
        await db.customStatement(
          'UPDATE item SET play_count = play_count + 1, last_played_at = ? WHERE id = ?',
          [now.millisecondsSinceEpoch ~/ 1000, itemId],
        );
        await db
            .into(db.playEvents)
            .insert(
              PlayEventsCompanion.insert(
                itemId: itemId,
                at: now,
                listenedMs: listened.inMilliseconds,
              ),
            );
      });

  /// Pushes dirty rows to every target that knows the item, then applies
  /// newer remote state (last writer wins by timestamp).
  Future<int> sync(List<ProgressSyncTarget> targets, {DateTime? since}) async {
    var pushed = 0;
    final dirty = await (db.select(
      db.progress,
    )..where((p) => p.dirty.equals(true))).get();
    for (final row in dirty) {
      final update = ProgressUpdate(
        itemId: row.itemId,
        position: Duration(milliseconds: row.positionMs),
        duration: row.durationMs == null
            ? null
            : Duration(milliseconds: row.durationMs!),
        watched: row.watched,
        at: row.updatedAt,
      );
      var ok = true;
      for (final t in targets) {
        if (!await t.handles(row.itemId)) continue;
        try {
          await t.push(update);
          pushed++;
        } on Object {
          ok = false;
        }
      }
      if (ok) {
        await (db.update(db.progress)
              ..where((p) => p.itemId.equals(row.itemId)))
            .write(const ProgressCompanion(dirty: Value(false)));
      }
    }
    for (final t in targets) {
      for (final u in await t.pull(since: since)) {
        final local = await of(u.itemId);
        if (local != null && !local.updatedAt.isBefore(u.at)) continue;
        await db
            .into(db.progress)
            .insertOnConflictUpdate(
              ProgressCompanion.insert(
                itemId: Value(u.itemId),
                positionMs: u.position.inMilliseconds,
                durationMs: Value(u.duration?.inMilliseconds),
                watched: Value(u.watched),
                updatedAt: u.at,
              ),
            );
      }
    }
    return pushed;
  }
}
