import 'dart:async';
import 'dart:collection';

import 'package:drift/drift.dart';
import 'package:mediahro/core/db/library_database.dart';
import 'package:mediahro/core/index/content_hash.dart';
import 'package:mediahro/core/index/index_writer.dart';
import 'package:mediahro/features/music/library/artwork_store.dart';
import 'package:mediahro/features/music/library/music_files.dart';
import 'package:mediahro/features/music/tags/audio_tags.dart';
import 'package:mediahro/features/music/tags/tag_reader.dart';
import 'package:mediahro_ffi/mediahro_ffi.dart';

/// Reads tags (MUS-002) and cover art (MUS-004) for audio items the scanner
/// added, in the background: newly indexed, unprobed audio items are read
/// with [TagReader] in an isolate and written through B2's [IndexWriter].
final class MusicIndexer {
  MusicIndexer({
    required this.db,
    required this.files,
    required this.art,
    IndexWriter? writer,
    this.concurrency = 2,
    Future<AudioTags> Function(VirtualFile file)? readTags,
  }) : _writer = writer ?? IndexWriter(db),
       _readTags = readTags ?? _defaultRead;

  final LibraryDatabase db;
  final MusicFiles files;
  final ArtworkStore art;
  final IndexWriter _writer;
  final int concurrency;
  final Future<AudioTags> Function(VirtualFile file) _readTags;

  final _queue = Queue<int>();
  final _seen = <int>{};
  final _idle = <Completer<void>>[];
  final _done = StreamController<int>.broadcast();
  StreamSubscription<List<int>>? _watch;
  int _active = 0;
  bool _disposed = false;
  (String, Uint8List, String)? _lastFolderArt;
  String? _lastFolderKey;

  /// Item ids as they finish.
  Stream<int> get completed => _done.stream;

  /// Items waiting or in progress.
  int get pending => _queue.length + _active;

  /// Starts following the index: every unprobed audio item is read once per
  /// app run.
  void start() {
    _watch ??=
        (db.selectOnly(db.items)
              ..addColumns([db.items.id])
              ..where(
                db.items.kind.equalsValue(ItemKind.audio) &
                    db.items.probed.equals(false) &
                    db.items.missing.equals(false),
              ))
            .map((r) => r.read(db.items.id)!)
            .watch()
            .listen(enqueue);
  }

  void enqueue(Iterable<int> ids) {
    for (final id in ids) {
      if (_seen.add(id)) _queue.add(id);
    }
    _pump();
  }

  /// Completes when nothing is queued or running.
  Future<void> idle() {
    if (_queue.isEmpty && _active == 0) return Future.value();
    final c = Completer<void>();
    _idle.add(c);
    return c.future;
  }

  Future<void> dispose() async {
    _disposed = true;
    await _watch?.cancel();
    await _done.close();
  }

  void _pump() {
    while (!_disposed && _active < concurrency && _queue.isNotEmpty) {
      final id = _queue.removeFirst();
      _active++;
      unawaited(
        _run(id).whenComplete(() {
          _active--;
          _pump();
        }),
      );
    }
    if (_queue.isEmpty && _active == 0) {
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
      if (item == null || item.missing || _disposed) return;
      final file = await files.open(item.sourceId, item.relPath);
      AudioTags tags;
      String? hash;
      try {
        hash =
            item.contentHash ?? await contentHash(file, knownSize: item.size);
        tags = await _readTags(file);
      } finally {
        await file.close();
      }
      if (_disposed) return;
      await _writer.applyProbe(
        id,
        ProbeResult(
          durationMs: tags.duration?.inMilliseconds,
          audioTracks: 1,
          contentHash: hash,
          title: tags.title,
          artist: tags.artist,
          albumArtist: tags.albumArtist,
          album: tags.album,
          genre: tags.genre,
          composer: tags.composer,
          year: tags.year,
          trackNumber: tags.trackNumber,
          discNumber: tags.discNumber,
        ),
      );
      // IndexWriter writes audio_meta only for artist/album-style tags; the
      // numbers and ReplayGain (AUD-004) are kept for every tagged file.
      if (tags.trackNumber != null ||
          tags.discNumber != null ||
          tags.year != null ||
          tags.trackGainDb != null ||
          tags.albumGainDb != null) {
        await db
            .into(db.audioMeta)
            .insertOnConflictUpdate(
              AudioMetaCompanion.insert(
                itemId: Value(id),
                year: Value(tags.year),
                trackNumber: Value(tags.trackNumber),
                discNumber: Value(tags.discNumber),
                trackGainDb: Value(tags.trackGainDb),
                albumGainDb: Value(tags.albumGainDb),
              ),
            );
      }
      if (await art.storeEmbedded(id, tags) == null) {
        await _folderArt(item);
      }
      if (!_done.isClosed) _done.add(id);
    } on Exception {
      // Unreachable file, revoked grant or dropped share: the item stays
      // unprobed and the next app run tries again.
    }
  }

  Future<void> _folderArt(ItemRow item) async {
    final key = '${item.sourceId}:${item.parentPath}';
    if (_lastFolderKey != key) {
      _lastFolderKey = key;
      _lastFolderArt = await _findFolderArt(item.sourceId, item.parentPath);
    }
    final found = _lastFolderArt;
    if (found == null) return;
    await art.store(
      item.id,
      found.$2,
      mimeType: found.$3,
      source: ArtSource.folder,
    );
  }

  Future<(String, Uint8List, String)?> _findFolderArt(
    int sourceId,
    String folder,
  ) async {
    // The index already lists the folder's images when photos are scanned.
    final siblings =
        await (db.selectOnly(db.items)
              ..addColumns([db.items.name])
              ..where(
                db.items.sourceId.equals(sourceId) &
                    db.items.parentPath.equals(folder),
              ))
            .map((r) => r.read(db.items.name)!)
            .get();
    var name = ArtworkStore.pickFolderArt(siblings);
    if (name == null) {
      try {
        final entries = await files.list(sourceId, folder);
        name = ArtworkStore.pickFolderArt(
          entries.where((e) => !e.isDirectory).map((e) => e.name),
        );
      } on Object {
        return null;
      }
    }
    if (name == null) return null;
    final rel = folder.isEmpty ? name : '$folder/$name';
    final f = await files.open(sourceId, rel);
    try {
      final size = await f.length() ?? 0;
      if (size <= 0 || size > 16 * 1024 * 1024) return null;
      final bytes = await f.read(0, size);
      final lower = name.toLowerCase();
      final mime = lower.endsWith('.png')
          ? 'image/png'
          : lower.endsWith('.webp')
          ? 'image/webp'
          : 'image/jpeg';
      return (name, bytes, mime);
    } finally {
      await f.close();
    }
  }

  static Future<AudioTags> _defaultRead(VirtualFile file) {
    final uri = file.uri;
    if (uri.scheme == 'file') return TagReader.readFile(uri.toFilePath());
    return TagReader.readVirtualFile(file);
  }
}
