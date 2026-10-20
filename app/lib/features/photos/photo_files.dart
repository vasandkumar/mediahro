import 'dart:async';

import 'package:mediahro/core/db/library_database.dart';
import 'package:mediahro/core/files/file_systems.dart';
import 'package:mediahro/core/scanner/walker.dart';
import 'package:mediahro/core/sources/source_access.dart';
import 'package:mediahro/features/photos/timeline/timeline_model.dart';
import 'package:mediahro/images/image_pipeline.dart';
import 'package:mediahro_ffi/mediahro_ffi.dart';

/// Opens photos by index entry; faked in tests.
abstract interface class PhotoFileOpener {
  /// URI of [e] inside its source.
  Future<Uri> uriOf(PhotoEntry e);

  /// The file, opened. The caller closes `source.file`.
  Future<ImageSource> open(PhotoEntry e);
}

/// Opens indexed photos through their source (local folder, SAF tree,
/// MediaStore, network share) and mounts the source so the image pipeline
/// can write metadata back through it (IMG-006).
final class PhotoFiles implements PhotoFileOpener {
  PhotoFiles(this.db, this.resolver, this.mounts);

  final LibraryDatabase db;
  final SourceResolver resolver;
  final MountedFileSystems mounts;
  final _access = <int, Future<(SourceAccess, VirtualFileSystem)>>{};

  Future<(SourceAccess, VirtualFileSystem)> _source(int sourceId) =>
      _access[sourceId] ??= () async {
        final row = await (db.select(
          db.sources,
        )..where((s) => s.id.equals(sourceId))).getSingle();
        final access = await resolver.resolve(row);
        final fs = access.fileSystem();
        mounts.mount(access.root, fs);
        return (access, fs);
      }();

  @override
  Future<Uri> uriOf(PhotoEntry e) async {
    final (access, _) = await _source(e.sourceId);
    return childUri(access.root, e.relPath);
  }

  @override
  Future<ImageSource> open(PhotoEntry e) async {
    try {
      final (access, fs) = await _source(e.sourceId);
      final file = await fs.open(childUri(access.root, e.relPath));
      return ImageSource(file, mtime: e.mtime, orientationHint: e.orientation);
    } on Object {
      // A revoked grant or a dropped share: resolve again next time.
      unawaited(_access.remove(e.sourceId)?.then((a) => a.$1.close()));
      rethrow;
    }
  }

  Future<void> close() async {
    final all = _access.values.toList();
    _access.clear();
    for (final a in all) {
      try {
        await (await a).$1.close();
      } on Object {
        // A source that failed to open has nothing to close.
      }
    }
  }
}
