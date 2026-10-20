import 'dart:async';

import 'package:mediahro/core/db/library_database.dart';
import 'package:mediahro/core/scanner/walker.dart';
import 'package:mediahro/core/sources/source_access.dart';
import 'package:mediahro_engine/mediahro_engine.dart';
import 'package:mediahro_ffi/mediahro_ffi.dart';

/// Opens indexed music files through their source (local folder, SAF tree,
/// MediaStore, network share) and turns them into engine sources.
final class MusicFiles {
  MusicFiles(this.db, this.resolver);

  final LibraryDatabase db;
  final SourceResolver resolver;
  final _access = <int, Future<(SourceAccess, VirtualFileSystem)>>{};

  Future<(SourceAccess, VirtualFileSystem)> _source(int sourceId) =>
      _access[sourceId] ??= () async {
        final row = await (db.select(
          db.sources,
        )..where((s) => s.id.equals(sourceId))).getSingle();
        final access = await resolver.resolve(row);
        return (access, access.fileSystem());
      }();

  /// URI of an item inside its source.
  Future<Uri> uriOf(int sourceId, String relPath) async {
    final (access, _) = await _source(sourceId);
    return childUri(access.root, relPath);
  }

  Future<VirtualFile> open(int sourceId, String relPath) async {
    try {
      final (access, fs) = await _source(sourceId);
      return await fs.open(childUri(access.root, relPath));
    } on Object {
      // A revoked grant or a dropped share: resolve again next time.
      unawaited(_access.remove(sourceId)?.then((a) => a.$1.close()));
      rethrow;
    }
  }

  /// Lists a folder of a source (folder art lookup).
  Future<List<VirtualEntry>> list(int sourceId, String folder) async {
    final (access, fs) = await _source(sourceId);
    final dir = folder.isEmpty
        ? access.root
        : childUri(access.root, '$folder/');
    return await fs.list(dir).take(500).toList();
  }

  /// What the engine plays for an item: a plain `file:` URI that mpv opens
  /// itself, or a [VirtualFileSource] for everything else.
  Future<MediaSource> mediaSource(
    int sourceId,
    String relPath, {
    String? title,
  }) async {
    final (access, _) = await _source(sourceId);
    final uri = childUri(access.root, relPath);
    if (uri.scheme == 'file') return UriSource(uri, title: title);
    return VirtualFileSource(await open(sourceId, relPath), title: title);
  }

  Future<void> close() async {
    final all = _access.values.toList();
    _access.clear();
    for (final a in all) {
      try {
        await (await a).$1.close();
      } on Object {
        // Already gone.
      }
    }
  }
}
