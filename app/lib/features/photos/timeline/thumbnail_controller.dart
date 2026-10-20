import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:mediahro/features/photos/photo_files.dart';
import 'package:mediahro/features/photos/timeline/timeline_model.dart';
import 'package:mediahro/images/image_pipeline.dart';
import 'package:mediahro/images/pipeline/mediahro_image_pipeline.dart';
import 'package:mediahro/images/pipeline/worker_pool.dart';

/// Where thumbnails come from; the controller only schedules.
abstract interface class ThumbnailSource {
  Future<File> load(
    PhotoEntry entry,
    ThumbnailPriority priority,
    void Function(JobHandle) onQueued,
  );

  void reprioritise(int entryId, ThumbnailPriority priority);

  void cancel(int entryId);
}

/// [ThumbnailSource] over the image pipeline.
final class PipelineThumbnailSource implements ThumbnailSource {
  PipelineThumbnailSource(this.pipeline, this.files, {this.edge = 256});

  final MediahroImagePipeline pipeline;
  final PhotoFiles files;
  final int edge;

  @override
  Future<File> load(
    PhotoEntry entry,
    ThumbnailPriority priority,
    void Function(JobHandle) onQueued,
  ) async => await pipeline.thumbnailFor(
    uri: await files.uriOf(entry),
    size: entry.size,
    mtime: entry.mtime,
    orientation: entry.orientation ?? 1,
    edge: edge,
    open: () => files.open(entry),
    closeSource: true,
    priority: priority,
    group: entry.id,
    onQueued: onQueued,
  );

  @override
  void reprioritise(int entryId, ThumbnailPriority priority) =>
      pipeline.reprioritise(entryId, priority);

  @override
  void cancel(int entryId) => pipeline.cancelGroup(entryId);
}

/// Thumbnail scheduling for one timeline (IMG-003): tiles ask for their
/// thumbnail when built; as the viewport moves, the controller keeps the
/// jobs of what is on screen at the front of the queue, what is within a
/// screen next, the prefetch band (±2 screens) last, and drops queued work
/// for tiles that were scrolled far away. Resolved files are remembered so a
/// tile that is rebuilt while scrolling back does not touch the database.
final class ThumbnailController {
  ThumbnailController(this.source, {this.memory = 4000});

  final ThumbnailSource source;

  /// How many resolved files stay in memory.
  final int memory;

  final LinkedHashMap<int, File> _resolved = LinkedHashMap();
  final Map<int, Future<File?>> _pending = {};
  final Map<int, int> _indexOf = {};
  final Set<int> _failed = {};
  int _first = 0;
  int _last = -1;
  int _span = 30;
  bool _viewportKnown = false;
  bool _disposed = false;

  /// The file for [id] if it is already known.
  File? resolved(int id) {
    final f = _resolved.remove(id);
    if (f != null) _resolved[id] = f; // most recently used last
    return f;
  }

  bool failed(int id) => _failed.contains(id);

  /// Entries with a request in flight (tests, diagnostics).
  int get pending => _pending.length;

  ThumbnailPriority _priorityFor(int index) {
    if (!_viewportKnown) return ThumbnailPriority.visible;
    if (index >= _first && index <= _last) return ThumbnailPriority.visible;
    if (index >= _first - _span && index <= _last + _span) {
      return ThumbnailPriority.nearby;
    }
    return ThumbnailPriority.prefetch;
  }

  /// Starts (or joins) the load of [entry], shown at [index] of the
  /// timeline. Completes with null when the load was dropped or failed.
  Future<File?> request(PhotoEntry entry, int index) {
    final done = _resolved[entry.id];
    if (done != null) return Future.value(done);
    _indexOf[entry.id] = index;
    return _pending[entry.id] ??= _load(entry, index);
  }

  Future<File?> _load(PhotoEntry entry, int index) async {
    try {
      final file = await source.load(entry, _priorityFor(index), (_) {});
      if (!_disposed) {
        _failed.remove(entry.id);
        _resolved[entry.id] = file;
        while (_resolved.length > memory) {
          _resolved.remove(_resolved.keys.first);
        }
      }
      return file;
    } on JobCancelled {
      return null;
    } on Object {
      // Unreadable file, dropped share, no worker: the tile shows a broken
      // image and the user can retry.
      _failed.add(entry.id);
      return null;
    } finally {
      unawaited(_pending.remove(entry.id));
    }
  }

  /// Forgets a tile that was disposed: its queued job is dropped.
  void release(int id) {
    if (_pending.containsKey(id)) source.cancel(id);
    _indexOf.remove(id);
  }

  /// Retries a failed thumbnail (the user tapped the broken tile).
  void retry(int id) => _failed.remove(id);

  /// The visible entry range changed. [screenItems] is how many tiles fit
  /// on a screen, for the nearby and prefetch bands.
  void viewport(int first, int last, {required int screenItems}) {
    _viewportKnown = true;
    _first = first;
    _last = last;
    _span = screenItems;
    for (final e in _indexOf.entries.toList()) {
      final index = e.value;
      if (!_pending.containsKey(e.key)) continue;
      if (index < first - 3 * screenItems || index > last + 3 * screenItems) {
        source.cancel(e.key);
      } else {
        source.reprioritise(e.key, _priorityFor(index));
      }
    }
  }

  void dispose() {
    _disposed = true;
    _pending.keys.toList().forEach(source.cancel);
    _pending.clear();
    _resolved.clear();
  }
}
