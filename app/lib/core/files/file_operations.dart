import 'dart:async';

import 'package:drift/drift.dart';
import 'package:mediahro/core/db/library_database.dart';
import 'package:mediahro/core/files/file_systems.dart';
import 'package:mediahro/core/files/sidecars.dart';
import 'package:mediahro/core/index/index_writer.dart';
import 'package:mediahro/core/library/item_locator.dart';
import 'package:mediahro/core/metadata/filename_parser.dart';
import 'package:mediahro/platform/storage.dart';
import 'package:mediahro_ffi/mediahro_ffi.dart';
import 'package:meta/meta.dart';

/// What [FileOperations.delete] did, for the undo snackbar (FILE-002).
@immutable
final class DeleteResult {
  const DeleteResult({
    this.trashed = const [],
    this.deleted = const [],
    this.trash,
  });

  /// Moved to the OS trash / Recycle Bin: undoable.
  final List<Uri> trashed;

  /// Permanently deleted (network shares without a trash; the UI confirmed).
  final List<Uri> deleted;
  final TrashResult? trash;

  bool get canUndo => trash != null && trashed.isNotEmpty;
}

/// Progress of a copy/move batch.
@immutable
final class TransferProgress {
  const TransferProgress(this.done, this.total, this.bytes, this.current);

  final int done;
  final int total;
  final int bytes;
  final Uri current;
}

/// File operations across every source (FILE-002, FILE-003, FILE-006):
/// rename (sidecars follow), move, copy (across sources), new folder,
/// delete to the OS trash with undo. The index follows every change so
/// positions, tags and ratings stay with the file.
final class FileOperations {
  FileOperations({
    required this.fileSystems,
    required this.db,
    this.storage,
    IndexWriter? writer,
    ItemLocator? locator,
  }) : _writer = writer ?? IndexWriter(db),
       _locator = locator ?? ItemLocator(db);

  final MountedFileSystems fileSystems;
  final LibraryDatabase db;

  /// OS trash on local files (Recycle Bin, Trash, MediaStore trash).
  final StorageFacade? storage;
  final IndexWriter _writer;
  final ItemLocator _locator;

  MutableFileSystem _mutable(Uri uri) {
    final fs = fileSystems.forUri(uri);
    if (fs is! MutableFileSystem) {
      throw VirtualFileException(
        VirtualFileError.unsupported,
        uri,
        'read-only source',
      );
    }
    return fs;
  }

  Future<Uri> newFolder(Uri parent, String name) =>
      _mutable(parent).createDirectory(parent, name);

  /// Renames [uri]; sidecars with the same base name are renamed too
  /// (`Movie.en.srt` follows `Movie.mkv`).
  Future<Uri> rename(
    Uri uri,
    String newName, {
    bool withSidecars = true,
  }) async {
    final fs = _mutable(uri);
    final oldName = uri.pathSegments.where((s) => s.isNotEmpty).last;
    final parent = _parent(uri);
    final sidecars = withSidecars && !uri.path.endsWith('/')
        ? renameSidecars(oldName, newName, [
            for (final e in await fs.list(parent).toList()) e.name,
          ])
        : const <String, String>{};
    final renamed = await fs.rename(uri, newName);
    await _reindex(uri, renamed);
    for (final MapEntry(key: from, value: to) in sidecars.entries) {
      final fromUri = parent.resolve(Uri.encodeComponent(from));
      final toUri = await fs.rename(fromUri, to);
      await _reindex(fromUri, toUri);
    }
    return renamed;
  }

  /// Moves [uris] into [directory]; across sources this is copy + delete.
  Stream<TransferProgress> move(List<Uri> uris, Uri directory) =>
      _transfer(uris, directory, deleteSource: true);

  Stream<TransferProgress> copy(List<Uri> uris, Uri directory) =>
      _transfer(uris, directory, deleteSource: false);

  Stream<TransferProgress> _transfer(
    List<Uri> uris,
    Uri directory, {
    required bool deleteSource,
  }) async* {
    final dst = _mutable(directory);
    var bytes = 0;
    for (var i = 0; i < uris.length; i++) {
      final src = uris[i];
      final srcFs = fileSystems.forUri(src);
      if (deleteSource && identical(srcFs, dst)) {
        final moved = await dst.move(src, directory);
        await _reindex(src, moved);
      } else {
        await _copyTree(srcFs, src, dst, directory, (n) => bytes += n);
        if (deleteSource) await _mutable(src).delete(src, recursive: true);
      }
      yield TransferProgress(i + 1, uris.length, bytes, src);
    }
  }

  Future<void> _copyTree(
    VirtualFileSystem srcFs,
    Uri src,
    MutableFileSystem dst,
    Uri directory,
    void Function(int) onBytes,
  ) async {
    final e = await srcFs.stat(src);
    if (e.isDirectory) {
      final made = await dst.createDirectory(directory, e.name);
      for (final c in await srcFs.list(src).toList()) {
        await _copyTree(srcFs, c.uri, dst, made, onBytes);
      }
      return;
    }
    final target = directory.resolve(Uri.encodeComponent(e.name));
    final w = await dst.create(target);
    final r = await srcFs.open(src);
    var off = 0;
    try {
      while (true) {
        final chunk = await r.read(off, 1 << 20);
        if (chunk.isEmpty) break;
        await w.write(chunk);
        off += chunk.length;
        onBytes(chunk.length);
      }
      await w.close();
    } on Object {
      await w.abort();
      rethrow;
    } finally {
      await r.close();
    }
  }

  /// Deletes to the OS trash where available (local files), with undo;
  /// otherwise permanently ([allowPermanent] must be set after the UI
  /// confirmed "Delete permanently?").
  Future<DeleteResult> delete(
    List<Uri> uris, {
    bool allowPermanent = false,
  }) async {
    final local = [
      for (final u in uris)
        if (u.scheme == 'file') u,
    ];
    final remote = [
      for (final u in uris)
        if (u.scheme != 'file') u,
    ];
    TrashResult? trash;
    final s = storage;
    if (local.isNotEmpty) {
      if (s != null) {
        trash = await s.moveToTrash(local);
      } else if (!allowPermanent) {
        throw VirtualFileException(
          VirtualFileError.unsupported,
          local.first,
          'no trash available',
        );
      } else {
        for (final u in local) {
          await _mutable(u).delete(u, recursive: true);
        }
      }
    }
    if (remote.isNotEmpty && !allowPermanent) {
      throw VirtualFileException(
        VirtualFileError.unsupported,
        remote.first,
        'this source has no trash',
      );
    }
    for (final u in remote) {
      await _mutable(u).delete(u, recursive: true);
    }
    await _markMissing([
      ...?trash?.trashed,
      ...remote,
      if (s == null) ...local,
    ]);
    return DeleteResult(
      trashed: trash?.trashed ?? const [],
      deleted: [...remote, if (s == null) ...local],
      trash: trash,
    );
  }

  Future<void> undoDelete(DeleteResult result) async {
    final t = result.trash;
    final s = storage;
    if (t == null || s == null) return;
    await s.restoreFromTrash(t);
    for (final u in t.trashed) {
      final item = await _locator.itemFor(u);
      if (item != null) {
        await (db.update(db.items)..where((i) => i.id.equals(item.id))).write(
          const ItemsCompanion(missing: Value(false)),
        );
      }
    }
  }

  Future<void> _markMissing(List<Uri> uris) async {
    for (final u in uris) {
      final item = await _locator.itemFor(u);
      if (item != null) {
        await (db.update(db.items)..where((i) => i.id.equals(item.id))).write(
          const ItemsCompanion(missing: Value(true)),
        );
      }
    }
  }

  /// Keeps the index row (and with it progress, tags, ratings) attached to
  /// a renamed or moved file.
  Future<void> _reindex(Uri from, Uri to) async {
    final item = await _locator.itemFor(from);
    if (item == null) return;
    final source = await (db.select(
      db.sources,
    )..where((s) => s.id.equals(item.sourceId))).getSingle();
    final root = Uri.parse(source.rootUri);
    final r = root.pathSegments.where((s) => s.isNotEmpty).toList();
    final t = to.pathSegments.where((s) => s.isNotEmpty).toList();
    if (t.length <= r.length) return;
    final rel = t.sublist(r.length).join('/');
    final name = t.last;
    final title = item.kind == ItemKind.video
        ? parseVideoFileName(name).title
        : cleanTitle(name);
    await (db.update(db.items)..where((i) => i.id.equals(item.id))).write(
      ItemsCompanion(
        relPath: Value(rel),
        parentPath: Value(
          rel.contains('/') ? rel.substring(0, rel.lastIndexOf('/')) : '',
        ),
        name: Value(name),
        title: Value(title),
        sortTitle: Value(sortTitle(title)),
      ),
    );
    await _writer.refreshFts([item.id]);
  }

  static Uri _parent(Uri uri) {
    final segs = uri.pathSegments.where((s) => s.isNotEmpty).toList()
      ..removeLast();
    return uri.replace(pathSegments: [...segs, '']);
  }
}
