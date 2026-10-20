import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:typed_data';

import 'package:mediahro/features/photos/map/web_mercator.dart';

/// Source of map tile pictures (IMG-007).
abstract interface class MapTileSource {
  /// Whether new tiles may be requested from the network (the privacy
  /// dashboard's map-tile switch). Tiles already on disk are shown anyway.
  bool get enabled;

  /// The PNG of [id], or null when it is not available (switch off and not
  /// cached, offline, no such tile).
  Future<Uint8List?> load(TileId id);
}

/// Tiles from `tiles.mediahro.com` (OpenStreetMap data, © OpenStreetMap
/// contributors), cached on disk. The only network call of the map; it
/// carries the tile coordinates and nothing else (no photo, no account).
final class NetworkMapTileSource implements MapTileSource {
  NetworkMapTileSource({
    required this.directory,
    required this.isEnabled,
    required this.fetch,
    this.maxDiskBytes = 256 * 1024 * 1024,
    this.maxParallel = 6,
    this.trimEvery = 200,
    this.refreshAfter = const Duration(days: 30),
    this.retryAfter = const Duration(seconds: 30),
    DateTime Function()? clock,
    this.urlTemplate = 'https://tiles.mediahro.com/{z}/{x}/{y}.png',
  }) : _clock = clock ?? DateTime.now;

  final Directory directory;
  final bool Function() isEnabled;

  /// The HTTP GET, through the network gateway; null for any failure.
  final Future<Uint8List?> Function(Uri uri) fetch;
  final int maxDiskBytes;
  final int maxParallel;

  /// Check the cache size after this many new tiles.
  final int trimEvery;
  final Duration refreshAfter;
  final Duration retryAfter;
  final String urlTemplate;
  final DateTime Function() _clock;

  final Map<TileId, Future<Uint8List?>> _inFlight = {};
  final Map<TileId, DateTime> _failedAt = {};
  final Set<Future<void>> _stores = {};
  final Queue<Completer<void>> _waiting = Queue();
  int _running = 0;
  int _writes = 0;

  @override
  bool get enabled => isEnabled();

  File _file(TileId id) => File(
    '${directory.path}${Platform.pathSeparator}${id.z}'
    '${Platform.pathSeparator}${id.x}${Platform.pathSeparator}${id.y}.png',
  );

  Uri uriOf(TileId id) => Uri.parse(
    urlTemplate
        .replaceAll('{z}', '${id.z}')
        .replaceAll('{x}', '${id.x}')
        .replaceAll('{y}', '${id.y}'),
  );

  @override
  Future<Uint8List?> load(TileId id) => _inFlight[id] ??= _load(id);

  Future<Uint8List?> _load(TileId id) async {
    // Registered in _inFlight before anything below can finish.
    await Future<void>.value();
    try {
      return await _loadTile(id);
    } finally {
      unawaited(_inFlight.remove(id));
    }
  }

  Future<Uint8List?> _loadTile(TileId id) async {
    Uint8List? cached;
    var stale = false;
    final file = _file(id);
    try {
      if (file.existsSync()) {
        cached = await file.readAsBytes();
        stale = _clock().difference(file.lastModifiedSync()) > refreshAfter;
      }
    } on FileSystemException {
      cached = null;
    }
    if (cached != null && !stale) return cached;
    if (!enabled) return cached;
    final failed = _failedAt[id];
    if (failed != null && _clock().difference(failed) < retryAfter) {
      return cached;
    }
    await _slot();
    final Uint8List? bytes;
    try {
      // The switch may have been turned off while this waited.
      if (!enabled) return cached;
      bytes = await fetch(uriOf(id));
    } on Object {
      _failedAt[id] = _clock();
      return cached;
    } finally {
      _release();
    }
    if (bytes == null || !_looksLikePng(bytes)) {
      _failedAt[id] = _clock();
      return cached;
    }
    _failedAt.remove(id);
    final write = _store(file, bytes);
    _stores.add(write);
    unawaited(write.whenComplete(() => _stores.remove(write)));
    return bytes;
  }

  Future<void> _slot() {
    if (_running < maxParallel) {
      _running++;
      return Future.value();
    }
    final c = Completer<void>();
    _waiting.add(c);
    return c.future;
  }

  void _release() {
    if (_waiting.isNotEmpty) {
      _waiting.removeFirst().complete();
    } else {
      _running--;
    }
  }

  Future<void> _store(File file, Uint8List bytes) async {
    try {
      await file.parent.create(recursive: true);
      // Written beside and renamed, so a reader never sees half a tile.
      final part = File('${file.path}.part');
      await part.writeAsBytes(bytes, flush: true);
      await part.rename(file.path);
      if (++_writes % trimEvery == 0) await _trim();
    } on FileSystemException {
      // A full disk costs a cache hit later, not the map.
    }
  }

  /// Deletes the oldest tiles until the cache fits [maxDiskBytes].
  Future<void> _trim() async {
    if (!directory.existsSync()) return;
    final files = <(File, int, DateTime)>[];
    var total = 0;
    await for (final e in directory.list(recursive: true)) {
      if (e is! File) continue;
      final stat = e.statSync();
      total += stat.size;
      files.add((e, stat.size, stat.modified));
    }
    if (total <= maxDiskBytes) return;
    files.sort((a, b) => a.$3.compareTo(b.$3));
    for (final (f, size, _) in files) {
      if (total <= maxDiskBytes * 0.9) break;
      try {
        await f.delete();
        total -= size;
      } on FileSystemException {
        continue;
      }
    }
  }

  /// Completes when the tiles loaded so far are on disk.
  Future<void> settled() => Future.wait(_stores.toList());

  /// Removes every cached tile (Settings, privacy).
  Future<void> clear() async {
    await settled();
    if (directory.existsSync()) await directory.delete(recursive: true);
  }
}

bool _looksLikePng(Uint8List b) =>
    b.length > 8 &&
    b[0] == 0x89 &&
    b[1] == 0x50 &&
    b[2] == 0x4e &&
    b[3] == 0x47;
