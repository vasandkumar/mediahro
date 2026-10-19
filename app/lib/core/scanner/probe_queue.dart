import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:mediahro/core/db/library_database.dart';
import 'package:mediahro/core/index/content_hash.dart';
import 'package:mediahro/core/index/index_writer.dart';
import 'package:mediahro_ffi/mediahro_ffi.dart';

/// Reads media facts (duration, codecs, resolution, HDR, tracks, tags) from
/// a file. The playback engine implements it (lane B1, mpv probe); images
/// come from the image pipeline (lane C3).
abstract interface class MediaProber {
  Future<ProbeResult> probe(VirtualFile file, ItemRow item);
}

/// Opens an indexed item's file (source resolution + mounts).
typedef ItemOpener = Future<VirtualFile> Function(ItemRow item);

/// Background probing and hashing of newly indexed items with
/// viewport-priority scheduling (docs/05 §7: queues keyed to the visible
/// viewport). Items the UI shows jump ahead of the backlog; work runs at
/// most [concurrency] at a time and pauses with the scanner.
final class ProbeQueue {
  ProbeQueue({
    required this.db,
    required this.opener,
    this.prober,
    IndexWriter? writer,
    int? concurrency,
  }) : _writer = writer ?? IndexWriter(db),
       concurrency =
           concurrency ?? (Platform.numberOfProcessors ~/ 2).clamp(1, 8);

  final LibraryDatabase db;
  final ItemOpener opener;
  final MediaProber? prober;
  final IndexWriter _writer;
  final int concurrency;

  final _backlog = Queue<int>();
  final _queued = <int>{};
  Set<int> _visible = {};
  int _active = 0;
  bool _paused = false;
  final _done = StreamController<int>.broadcast();
  final _idle = <Completer<void>>[];

  /// Item ids as they finish (lists refresh their rows).
  Stream<int> get completed => _done.stream;

  int get pending => _queued.length;

  void enqueue(Iterable<int> itemIds) {
    for (final id in itemIds) {
      if (_queued.add(id)) _backlog.add(id);
    }
    _pump();
  }

  /// Ids currently on screen; they are probed first.
  void prioritize(Set<int> visibleIds) {
    _visible = visibleIds;
    _pump();
  }

  void pause() => _paused = true;

  void resume() {
    _paused = false;
    _pump();
  }

  /// Completes when nothing is queued or running.
  Future<void> idle() {
    if (_queued.isEmpty && _active == 0) return Future.value();
    final c = Completer<void>();
    _idle.add(c);
    return c.future;
  }

  Future<void> dispose() async {
    _paused = true;
    await _done.close();
  }

  int? _next() {
    for (final id in _visible) {
      if (_queued.contains(id) && _backlog.remove(id)) return id;
    }
    return _backlog.isEmpty ? null : _backlog.removeFirst();
  }

  void _pump() {
    while (!_paused && _active < concurrency) {
      final id = _next();
      if (id == null) break;
      _active++;
      unawaited(_run(id));
    }
    if (_queued.isEmpty && _active == 0) {
      for (final c in _idle) {
        c.complete();
      }
      _idle.clear();
    }
  }

  Future<void> _run(int id) async {
    try {
      final item = await (db.select(
        db.items,
      )..where((i) => i.id.equals(id))).getSingleOrNull();
      if (item == null || item.missing) return;
      final file = await opener(item);
      try {
        final hash =
            item.contentHash ?? await contentHash(file, knownSize: item.size);
        final facts = await prober?.probe(file, item);
        await _writer.applyProbe(
          id,
          facts == null
              ? ProbeResult(contentHash: hash)
              : ProbeResult(
                  durationMs: facts.durationMs,
                  width: facts.width,
                  height: facts.height,
                  videoCodec: facts.videoCodec,
                  audioCodec: facts.audioCodec,
                  hdrType: facts.hdrType,
                  audioLayout: facts.audioLayout,
                  audioTracks: facts.audioTracks,
                  subtitleTracks: facts.subtitleTracks,
                  contentHash: hash,
                  title: facts.title,
                  takenAt: facts.takenAt,
                  artist: facts.artist,
                  albumArtist: facts.albumArtist,
                  album: facts.album,
                  genre: facts.genre,
                  composer: facts.composer,
                  year: facts.year,
                  trackNumber: facts.trackNumber,
                  discNumber: facts.discNumber,
                  frameRate: facts.frameRate,
                ),
        );
      } finally {
        await file.close();
      }
      if (!_done.isClosed) _done.add(id);
    } on VirtualFileException {
      // Unreachable file: stays unprobed; the next scan re-queues it.
    } finally {
      _queued.remove(id);
      _active--;
      _pump();
    }
  }
}
