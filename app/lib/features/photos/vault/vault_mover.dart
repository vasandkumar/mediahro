import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:drift/drift.dart';
import 'package:mediahro/core/db/library_database.dart';
import 'package:mediahro/core/library/tags.dart';
import 'package:mediahro/features/photos/organise/write_back.dart'
    show xmpLabel;
import 'package:mediahro/features/photos/photo_files.dart';
import 'package:mediahro/features/photos/timeline/timeline_model.dart';
import 'package:mediahro/features/photos/vault/vault_container.dart';
import 'package:mediahro/images/image_pipeline.dart';
import 'package:mediahro/images/metadata/metadata_codec.dart';
import 'package:mediahro/images/pipeline/image_io.dart';
import 'package:mediahro/images/pipeline/mediahro_image_pipeline.dart';
import 'package:meta/meta.dart';

/// How moving photos into the vault went.
@immutable
final class VaultMoveReport {
  const VaultMoveReport({
    this.moved = 0,
    this.failed = const [],
    this.leftInLibrary = const [],
    this.stopped = false,
  });

  final int moved;

  /// Photos left where they were (read-only source, unreadable file).
  final List<String> failed;

  /// Photos that are in the vault and gone from their folder but whose
  /// library entry or cached pictures could not be cleaned up completely.
  /// They are safe in the vault; the entry goes with the next library scan.
  final List<String> leftInLibrary;
  final bool stopped;
}

/// Moves photos from the library into the vault (IMG-011): each is encrypted
/// and read back, then removed from where it was (for good, never to a trash
/// that would keep a readable copy), and then forgotten by the library in one
/// transaction: its entry, tags, ratings, places, albums and search entry,
/// and its cached thumbnails. A photo whose original cannot be removed is
/// not kept in the vault either: it stays as it was. Once the original is
/// gone the vault copy is never removed again, whatever the clean-up does.
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

  /// Longest edge of the stored picture of an item.
  static const int thumbnailEdge = 384;

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

  Future<Uint8List?> _thumbnailOf(PhotoEntry p) async {
    if (p.isVideo) return null;
    try {
      final src = await files.open(p);
      try {
        final info = await pipeline.info(src);
        final longest = math.max(info.width, info.height);
        final scale = longest <= thumbnailEdge ? 1.0 : thumbnailEdge / longest;
        final d = await pipeline.decode(src, scale: scale);
        return await pipeline.encode(
          d,
          const EncodeOptions(format: EncodeFormat.webp, quality: 80),
        );
      } finally {
        await src.file.close();
      }
    } on Object {
      // The grid shows a placeholder until the picture is decoded.
      return null;
    }
  }

  /// Everything the library knows of a photo that the vault should keep.
  Future<
    ({List<String> tags, int? halfStars, bool favourite, LabelColor? label})
  >
  _facts(int itemId) async {
    final tags = TagRepository(db);
    final rating = await (db.select(
      db.ratings,
    )..where((r) => r.itemId.equals(itemId))).getSingleOrNull();
    final meta = await (db.select(
      db.imageMeta,
    )..where((m) => m.itemId.equals(itemId))).getSingleOrNull();
    return (
      tags: await tags.tagsOf(itemId),
      halfStars: rating != null && rating.value > 0 ? rating.value : null,
      favourite: meta?.favourite ?? false,
      label: await tags.labelOf(itemId),
    );
  }

  /// Removes the photo from the library in one transaction. The playlist
  /// rows go first: they would only lose their link and keep a title.
  Future<void> _scrubLibrary(PhotoEntry p) async {
    try {
      // Freed pages are overwritten, best effort (not every build allows it).
      await db.customStatement('PRAGMA secure_delete = ON');
    } on Object {
      // A pragma the build does not know.
    }
    await db.transaction(() async {
      await (db.delete(
        db.playlistItems,
      )..where((r) => r.itemId.equals(p.id))).go();
      await (db.delete(db.items)..where((i) => i.id.equals(p.id))).go();
    });
  }

  Future<VaultMoveReport> moveIn(
    VaultContainer container,
    List<PhotoEntry> photos, {
    void Function(int done)? onProgress,
    bool Function()? cancelled,
  }) async {
    var moved = 0;
    var n = 0;
    final failed = <String>[];
    final leftInLibrary = <String>[];
    for (final p in photos) {
      if (cancelled?.call() ?? false) {
        return VaultMoveReport(
          moved: moved,
          failed: failed,
          leftInLibrary: leftInLibrary,
          stopped: true,
        );
      }
      VaultItem? item;
      var originalDeleted = false;
      try {
        final origin = await files.uriOf(p);
        final probe = await files.open(p);
        final int length;
        try {
          length = await probe.file.length() ?? p.size;
        } finally {
          await probe.file.close();
        }
        final facts = await _facts(p.id);
        item = await container.add(
          name: p.name,
          kind: p.isVideo ? 'video' : 'image',
          content: _read(p, length),
          size: length,
          takenAt: p.date,
          width: p.width,
          height: p.height,
          tags: facts.tags,
          halfStars: facts.halfStars,
          favourite: facts.favourite,
          label: facts.label?.name,
        );
        final thumb = await _thumbnailOf(p);
        if (thumb != null) {
          try {
            await container.putThumbnail(item.id, thumb);
          } on Object {
            // The grid decodes the item instead.
          }
        }
        await io.delete(origin);
        originalDeleted = true;
        // From here the vault holds the only copy: nothing below may touch it.
        try {
          await _scrubLibrary(p);
          await pipeline.forgetThumbnails(
            uri: origin,
            size: p.size,
            mtime: p.mtime,
            orientation: p.orientation ?? 1,
          );
        } on Object {
          leftInLibrary.add(p.name);
        }
        moved++;
      } on Object {
        if (item != null && !originalDeleted) {
          // The original is still there: the vault copy must not be.
          try {
            await container.remove(item.id);
          } on Object {
            // Nothing more to do; the next open lists it.
          }
        }
        if (!originalDeleted) failed.add(p.name);
      }
      onProgress?.call(++n);
    }
    return VaultMoveReport(
      moved: moved,
      failed: failed,
      leftInLibrary: leftInLibrary,
    );
  }
}

/// Reads a vault item's bytes in 1 MiB pieces, for saving it out.
Stream<List<int>> vaultContent(VaultContainer c, VaultItem item) async* {
  final f = await c.openFile(item.id);
  try {
    final length = await f.length() ?? 0;
    for (var at = 0; at < length; at += 1 << 20) {
      yield await f.read(at, 1 << 20);
    }
  } finally {
    await f.close();
  }
}

/// Largest photo whose metadata is put back in when it is taken out.
const int restoreMetadataLimit = 64 << 20;

/// What taking [item] out writes: its bytes, with the rating, label and tags
/// the library had put back into the file (so the next library scan reads
/// them again) when the format holds them.
Stream<List<int>> restoredContent(VaultContainer c, VaultItem item) async* {
  final wants =
      item.kind == 'image' &&
      item.size <= restoreMetadataLimit &&
      (item.tags.isNotEmpty || item.halfStars != null || item.label != null);
  if (!wants) {
    yield* vaultContent(c, item);
    return;
  }
  final bytes = await c.readAll(item.id);
  LabelColor? color;
  for (final l in LabelColor.values) {
    if (l.name == item.label) color = l;
  }
  final r = writeMetadata(
    bytes,
    ImageMetadataEdit(
      rating: item.halfStars == null ? null : (item.halfStars! / 2).ceil(),
      keywords: item.tags.isEmpty ? null : item.tags,
      label: color == null ? null : xmpLabel(color),
    ),
    extension: item.ext,
  );
  yield r.file ?? bytes;
}
