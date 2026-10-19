import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:mediahro/core/db/library_database.dart';
import 'package:mediahro_ffi/mediahro_ffi.dart';
import 'package:meta/meta.dart';

/// Opens the remote file to mirror (any source: shares, WebDAV, cloud,
/// server download URLs through NetworkGateway).
typedef RemoteOpener = Future<VirtualFile> Function(Uri remote);

@immutable
final class DownloadProgress {
  const DownloadProgress(
    this.id,
    this.state,
    this.received,
    this.total, {
    this.error,
  });

  final int id;
  final DownloadState state;
  final int received;
  final int? total;
  final String? error;

  double? get fraction =>
      total == null || total == 0 ? null : received / total!;
}

final class QuotaExceeded implements Exception {
  const QuotaExceeded(this.needed, this.available);

  final int needed;
  final int available;

  @override
  String toString() => 'QuotaExceeded(needed $needed, available $available)';
}

/// Offline downloads for any server or share item (NET-018): resumable
/// (the `.part` file's length is the resume offset), size quota, expiry,
/// pause/resume/cancel, at most [concurrency] at once.
final class DownloadManager {
  DownloadManager({
    required this.db,
    required this.directory,
    required this.opener,
    this.quotaBytes = 32 << 30,
    this.concurrency = 2,
    this.chunk = 1 << 20,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final LibraryDatabase db;

  /// App-private downloads directory.
  final Directory directory;
  final RemoteOpener opener;
  final int quotaBytes;
  final int concurrency;
  final int chunk;
  final DateTime Function() _clock;

  final _progress = StreamController<DownloadProgress>.broadcast();
  final _running = <int, _Job>{};

  Stream<DownloadProgress> get progress => _progress.stream;

  /// Queues [remote]. Throws [QuotaExceeded] when the known size does not
  /// fit next to existing downloads.
  Future<int> enqueue(
    Uri remote, {
    required String title,
    int? sourceId,
    int? itemId,
    int? knownSize,
    Duration? keepFor,
  }) async {
    final existing = await (db.select(
      db.downloads,
    )..where((d) => d.remoteUri.equals(remote.toString()))).getSingleOrNull();
    if (existing != null &&
        existing.state != DownloadState.expired &&
        existing.state != DownloadState.failed) {
      return existing.id;
    }
    final used = await usedBytes();
    if (knownSize != null && used + knownSize > quotaBytes) {
      throw QuotaExceeded(knownSize, quotaBytes - used);
    }
    await directory.create(recursive: true);
    final now = _clock();
    final id = await db
        .into(db.downloads)
        .insert(
          DownloadsCompanion.insert(
            remoteUri: remote.toString(),
            sourceId: Value(sourceId),
            itemId: Value(itemId),
            title: title,
            localPath: '',
            totalBytes: Value(knownSize),
            createdAt: now,
            expiresAt: Value(keepFor == null ? null : now.add(keepFor)),
          ),
        );
    final name = _safeName(
      remote.pathSegments.where((s) => s.isNotEmpty).lastOrNull ?? title,
    );
    await (db.update(db.downloads)..where((d) => d.id.equals(id))).write(
      DownloadsCompanion(
        localPath: Value('${directory.path}${Platform.pathSeparator}$id-$name'),
      ),
    );
    _pump();
    return id;
  }

  Future<List<DownloadRow>> all() => (db.select(
    db.downloads,
  )..orderBy([(d) => OrderingTerm.desc(d.createdAt)])).get();

  /// The finished local copy of [remote], for offline playback.
  Future<File?> localFor(Uri remote) async {
    final d =
        await (db.select(db.downloads)..where(
              (x) =>
                  x.remoteUri.equals(remote.toString()) &
                  x.state.equalsValue(DownloadState.done),
            ))
            .getSingleOrNull();
    if (d == null) return null;
    final f = File(d.localPath);
    return f.existsSync() ? f : null;
  }

  Future<void> pause(int id) async {
    _running.remove(id)?.cancelled = true;
    await _setState(id, DownloadState.paused);
  }

  Future<void> resume(int id) async {
    await _setState(id, DownloadState.queued);
    _pump();
  }

  /// Cancels and deletes the partial or finished file.
  Future<void> remove(int id) async {
    _running.remove(id)?.cancelled = true;
    final d = await (db.select(
      db.downloads,
    )..where((x) => x.id.equals(id))).getSingleOrNull();
    if (d == null) return;
    for (final p in [d.localPath, '${d.localPath}.part']) {
      final f = File(p);
      if (f.existsSync()) await f.delete();
    }
    await (db.delete(db.downloads)..where((x) => x.id.equals(id))).go();
  }

  /// Deletes downloads past their expiry; returns how many.
  Future<int> sweepExpired() async {
    final now = _clock();
    final rows =
        await (db.select(db.downloads)..where(
              (d) =>
                  d.expiresAt.isSmallerThanValue(now) &
                  d.state.equalsValue(DownloadState.expired).not(),
            ))
            .get();
    for (final d in rows) {
      _running.remove(d.id)?.cancelled = true;
      for (final p in [d.localPath, '${d.localPath}.part']) {
        final f = File(p);
        if (f.existsSync()) await f.delete();
      }
      await _setState(d.id, DownloadState.expired);
    }
    return rows.length;
  }

  Future<int> usedBytes() async {
    final r = await db
        .customSelect(
          "SELECT coalesce(sum(coalesce(total_bytes, received_bytes)), 0) AS b FROM download WHERE state != 'expired' AND state != 'failed'",
        )
        .getSingle();
    return r.read<int>('b');
  }

  /// Restarts queued work (call once at app start: interrupted downloads
  /// resume from their `.part` files).
  Future<void> start() async {
    await (db.update(db.downloads)
          ..where((d) => d.state.equalsValue(DownloadState.running)))
        .write(const DownloadsCompanion(state: Value(DownloadState.queued)));
    _pump();
  }

  Future<void> dispose() async {
    for (final j in _running.values) {
      j.cancelled = true;
    }
    await _progress.close();
  }

  bool _pumping = false;

  void _pump() {
    if (_pumping) return;
    _pumping = true;
    unawaited(() async {
      try {
        while (_running.length < concurrency) {
          final next =
              await (db.select(db.downloads)
                    ..where((d) => d.state.equalsValue(DownloadState.queued))
                    ..orderBy([(d) => OrderingTerm.asc(d.createdAt)])
                    ..limit(1))
                  .getSingleOrNull();
          if (next == null || _running.containsKey(next.id)) break;
          final job = _Job();
          _running[next.id] = job;
          await _setState(next.id, DownloadState.running);
          unawaited(_run(next, job));
        }
      } finally {
        _pumping = false;
      }
    }());
  }

  Future<void> _run(DownloadRow d, _Job job) async {
    final part = File('${d.localPath}.part');
    RandomAccessFile? out;
    VirtualFile? src;
    try {
      src = await opener(Uri.parse(d.remoteUri));
      final total = await src.length() ?? d.totalBytes;
      if (total != null) {
        final others = await usedBytes() - (d.totalBytes ?? d.receivedBytes);
        if (others + total > quotaBytes) {
          throw QuotaExceeded(total, quotaBytes - others);
        }
      }
      out = await part.open(mode: FileMode.append);
      var received = await out.length();
      if (received > 0 && !src.isSeekable) {
        await out.truncate(0);
        received = 0;
      }
      await (db.update(db.downloads)..where((x) => x.id.equals(d.id))).write(
        DownloadsCompanion(
          totalBytes: Value(total),
          receivedBytes: Value(received),
        ),
      );
      var lastReport = DateTime.fromMillisecondsSinceEpoch(0);
      while (!job.cancelled) {
        final bytes = await src.read(received, chunk);
        if (bytes.isEmpty) break;
        await out.writeFrom(bytes);
        received += bytes.length;
        final now = _clock();
        if (now.difference(lastReport).inMilliseconds >= 250) {
          lastReport = now;
          await (db.update(db.downloads)..where((x) => x.id.equals(d.id)))
              .write(DownloadsCompanion(receivedBytes: Value(received)));
          _emit(DownloadProgress(d.id, DownloadState.running, received, total));
        }
        if (total != null && received >= total) break;
      }
      await out.flush();
      await out.close();
      out = null;
      if (job.cancelled) return;
      if (total != null && received != total) {
        throw VirtualFileException(
          VirtualFileError.io,
          Uri.parse(d.remoteUri),
          'short download',
        );
      }
      final target = File(d.localPath);
      if (target.existsSync()) await target.delete();
      await part.rename(d.localPath);
      await (db.update(db.downloads)..where((x) => x.id.equals(d.id))).write(
        DownloadsCompanion(
          state: const Value(DownloadState.done),
          receivedBytes: Value(received),
          totalBytes: Value(total ?? received),
        ),
      );
      _emit(
        DownloadProgress(d.id, DownloadState.done, received, total ?? received),
      );
    } on Object catch (e) {
      await (db.update(db.downloads)..where((x) => x.id.equals(d.id))).write(
        DownloadsCompanion(
          state: const Value(DownloadState.failed),
          error: Value('$e'),
        ),
      );
      _emit(DownloadProgress(d.id, DownloadState.failed, 0, null, error: '$e'));
    } finally {
      await out?.close();
      await src?.close();
      _running.remove(d.id);
      _pump();
    }
  }

  void _emit(DownloadProgress p) {
    if (!_progress.isClosed) _progress.add(p);
  }

  Future<void> _setState(int id, DownloadState s) async {
    await (db.update(db.downloads)..where((d) => d.id.equals(id))).write(
      DownloadsCompanion(state: Value(s)),
    );
    _emit(DownloadProgress(id, s, 0, null));
  }

  static String _safeName(String s) {
    final n = Uri.decodeComponent(s)
        .replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1f]'), '_');
    return n.length > 120 ? n.substring(n.length - 120) : n;
  }
}

final class _Job {
  bool cancelled = false;
}
