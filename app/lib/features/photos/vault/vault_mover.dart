import 'dart:async';

import 'package:drift/drift.dart';
import 'package:mediahro/core/db/library_database.dart';
import 'package:mediahro/features/photos/photo_files.dart';
import 'package:mediahro/features/photos/timeline/timeline_model.dart';
import 'package:mediahro/features/photos/vault/vault_store.dart';
import 'package:mediahro/images/pipeline/image_io.dart';
import 'package:mediahro/images/pipeline/mediahro_image_pipeline.dart';
import 'package:meta/meta.dart';

/// How moving photos into the vault went.
@immutable
final class VaultMoveReport {
  const VaultMoveReport({
    this.moved = 0,
    this.failed = const [],
    this.stopped = false,
  });

  final int moved;

  /// Photos left where they were (read-only source, unreadable file).
  final List<String> failed;
  final bool stopped;
}

/// Moves photos from the library into the vault (IMG-011): each is encrypted,
/// then removed from where it was (for good, never to a trash that would keep
/// a readable copy) and forgotten by the library, its cached thumbnails
/// included. A photo whose original cannot be removed is not kept in the
/// vault either: it stays as it was.
final class VaultMover {
  VaultMover({
    required this.files,
    required this.io,
    required this.db,
    required this.pipeline,
  });

  final PhotoFileOpener files;
  final ImageIo io;
  final LibraryDatabase db;
  final MediahroImagePipeline pipeline;

  Stream<List<int>> _read(PhotoEntry p, int length) async* {
    final src = await files.open(p);
    try {
      for (var at = 0; at < length; at += 1 << 20) {
        yield await src.file.read(at, (length - at).clamp(0, 1 << 20));
      }
    } finally {
      await src.file.close();
    }
  }

  Future<VaultMoveReport> moveIn(
    VaultStore store,
    List<PhotoEntry> photos, {
    void Function(int done)? onProgress,
    bool Function()? cancelled,
  }) async {
    var moved = 0;
    var n = 0;
    final failed = <String>[];
    for (final p in photos) {
      if (cancelled?.call() ?? false) {
        return VaultMoveReport(moved: moved, failed: failed, stopped: true);
      }
      VaultItem? item;
      try {
        final origin = await files.uriOf(p);
        final probe = await files.open(p);
        final int length;
        try {
          length = await probe.file.length() ?? p.size;
        } finally {
          await probe.file.close();
        }
        item = await store.add(
          name: p.name,
          kind: p.isVideo ? 'video' : 'image',
          content: _read(p, length),
          size: length,
          takenAt: p.date,
          width: p.width,
          height: p.height,
        );
        await io.delete(origin);
        await pipeline.forgetThumbnails(
          uri: origin,
          size: p.size,
          mtime: p.mtime,
          orientation: p.orientation ?? 1,
        );
        await (db.update(db.items)..where((i) => i.id.equals(p.id))).write(
          const ItemsCompanion(missing: Value(true)),
        );
        moved++;
      } on Object {
        if (item != null) {
          // The original is still there: the vault copy must not be.
          try {
            await store.remove(item.id);
          } on Object {
            // Nothing more to do; the next open lists it.
          }
        }
        failed.add(p.name);
      }
      onProgress?.call(++n);
    }
    return VaultMoveReport(moved: moved, failed: failed);
  }
}

/// Reads a vault item's bytes in 1 MiB pieces, for saving it out.
Stream<List<int>> vaultContent(VaultStore store, VaultItem item) async* {
  final f = await store.openFile(item.id);
  try {
    final length = await f.length() ?? 0;
    for (var at = 0; at < length; at += 1 << 20) {
      yield await f.read(at, 1 << 20);
    }
  } finally {
    await f.close();
  }
}
