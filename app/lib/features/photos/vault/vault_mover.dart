import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

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
    this.listFolder,
  });

  /// The files in the folder of `file`, as their own URIs (one listing). Null
  /// where the source cannot list; the sidecars are then probed by name.
  final Future<List<Uri>> Function(Uri file)? listFolder;

  final PhotoFileOpener files;
  final ImageIo io;
  final LibraryDatabase db;
  final MediahroImagePipeline pipeline;

  /// Longest edge of the stored picture of an item.
  static const int thumbnailEdge = 384;

  Stream<List<int>> _read(
    PhotoEntry p,
    int length,
    void Function(double)? onFraction,
  ) async* {
    final src = await files.open(p);
    try {
      for (var at = 0; at < length; at += 1 << 20) {
        yield await src.file.read(at, (length - at).clamp(0, 1 << 20));
        onFraction?.call(length == 0 ? 1 : (at + (1 << 20)) / length);
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
  Future<void> _scrubLibrary(PhotoEntry p, Uri origin) async {
    try {
      // Freed pages are overwritten, best effort (not every build allows it).
      await db.customStatement('PRAGMA secure_delete = ON');
    } on Object {
      // A pragma the build does not know.
    }
    // Files the library cached for the item (artwork a scraper fetched,
    // subtitles downloaded for it) go first, then the rows that name them.
    final artwork = await (db.select(
      db.artworks,
    )..where((a) => a.ownerType.equals('item') & a.ownerId.equals(p.id))).get();
    final subtitles = await (db.select(
      db.subtitleCache,
    )..where((s) => s.itemId.equals(p.id))).get();
    for (final path in [
      for (final a in artwork)
        if (a.cachePath != null) a.cachePath!,
      for (final s in subtitles) s.path,
    ]) {
      try {
        final f = File(path);
        if (f.existsSync()) f.deleteSync();
      } on FileSystemException {
        // Left for a cache clean-up; the row below no longer points at it.
      }
    }
    final uri = '$origin';
    final local = origin.scheme == 'file' ? origin.toFilePath() : uri;
    await db.transaction(() async {
      await (db.delete(
        db.playlistItems,
      )..where((r) => r.itemId.equals(p.id) | r.uri.equals(uri))).go();
      // A download keeps a title and the place it was saved.
      await (db.delete(db.downloads)..where(
            (d) =>
                d.itemId.equals(p.id) |
                d.remoteUri.equals(uri) |
                d.localPath.equals(local),
          ))
          .go();
      await (db.delete(db.artworks)
            ..where((a) => a.ownerType.equals('item') & a.ownerId.equals(p.id)))
          .go();
      // Queues remember a title and a place by themselves; scrobbles remember
      // a payload.
      await (db.delete(
        db.queueItems,
      )..where((q) => q.itemId.equals(p.id) | q.uri.equals(uri))).go();
      await (db.delete(
        db.scrobbleQueue,
      )..where((q) => q.itemId.equals(p.id))).go();
      await (db.delete(db.items)..where((i) => i.id.equals(p.id))).go();
    });
  }

  /// Names of files that sit beside a video and belong to it: subtitles,
  /// artwork and an info file, with the video's own name.
  static List<String> sidecarNames(String videoName) {
    final dot = videoName.lastIndexOf('.');
    final base = dot <= 0 ? videoName : videoName.substring(0, dot);
    const subtitle = ['srt', 'ass', 'ssa', 'sub', 'idx', 'vtt', 'sup'];
    const languages = [
      'en', 'nl', 'fr', 'de', 'es', 'it', 'pt', 'ru', 'ja', 'ko', 'zh', 'ar', //
      'hi', 'tr', 'pl', 'sv', 'da', 'fi', 'no', 'he', 'cs', 'el', 'hu', 'ro', //
      'uk', 'id', 'th', 'vi', 'forced',
    ];
    return [
      for (final e in subtitle) '$base.$e',
      for (final l in languages)
        for (final e in subtitle) '$base.$l.$e',
      '$base.nfo',
      for (final k in [
        'poster', 'fanart', 'thumb', 'landscape', 'banner', 'clearlogo', //
        'backdrop', 'cover',
      ])
        for (final e in ['jpg', 'jpeg', 'png', 'webp']) '$base-$k.$e',
      // Not '$base.jpg' or '.png': a picture with the video's name is as
      // likely a photo of its own (a Live Photo pair, a screenshot of it).
      '$base.tbn',
    ];
  }

  /// Deletes the sidecars of a video that has just moved in (the flow told
  /// the user it would). A sidecar that is itself in the library is left
  /// alone. Returns how many could not be deleted.
  Future<int> _deleteSidecars(PhotoEntry p, Uri origin) async {
    final wanted = {for (final n in sidecarNames(p.name)) n.toLowerCase()};
    final lister = listFolder;
    final List<Uri> found;
    if (lister != null) {
      final listed = await lister(origin);
      found = [
        for (final u in listed)
          if (u != origin &&
              u.pathSegments.isNotEmpty &&
              wanted.contains(u.pathSegments.last.toLowerCase()))
            u,
      ];
    } else {
      // No listing: ask for each name, with the URI built from segments
      // (not from a decoded string).
      final dir = origin.pathSegments.sublist(
        0,
        origin.pathSegments.length - 1,
      );
      found = [];
      for (final n in sidecarNames(p.name)) {
        final u = origin.replace(pathSegments: [...dir, n]);
        try {
          if (await io.exists(u)) found.add(u);
        } on Object {
          // Cannot tell: leave it.
        }
      }
    }
    if (found.isEmpty) return 0;
    // What the library lists as a file of its own is not a sidecar.
    final slash = p.relPath.lastIndexOf('/');
    final parent = slash < 0 ? '' : p.relPath.substring(0, slash);
    final own = {
      for (final i
          in await (db.select(db.items)..where(
                (i) =>
                    i.sourceId.equals(p.sourceId) & i.parentPath.equals(parent),
              ))
              .get())
        i.name.toLowerCase(),
    };
    var failed = 0;
    for (final u in found) {
      if (own.contains(u.pathSegments.last.toLowerCase())) continue;
      try {
        await io.delete(u);
      } on Object {
        failed++;
      }
    }
    return failed;
  }

  Future<VaultMoveReport> moveIn(
    VaultContainer container,
    List<PhotoEntry> photos, {
    void Function(int done)? onProgress,
    void Function(double fraction)? onItemProgress,
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
      Uri? origin;
      try {
        origin = await files.uriOf(p);
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
          content: _read(p, length, onItemProgress),
          size: length,
          takenAt: p.date,
          width: p.width,
          height: p.height,
          tags: facts.tags,
          halfStars: facts.halfStars,
          favourite: facts.favourite,
          label: facts.label?.name,
        );
        // Every chunk must read back before the only other copy goes (the
        // add above checked the first and last).
        await container.verify(item.id);
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
        if (p.isVideo) {
          try {
            await _deleteSidecars(p, origin);
          } on Object {
            // Beside the video, not in the vault: not worth failing for.
          }
        }
        try {
          await _scrubLibrary(p, origin);
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
        if (item != null && !originalDeleted && origin != null) {
          // Did the delete fail, or fail after it had done its work? Look
          // before taking the vault copy away: if the original is gone the
          // vault copy is the only one.
          bool? stillThere;
          try {
            stillThere = await io.exists(origin);
          } on Object {
            stillThere = null;
          }
          if (stillThere ?? false) {
            // The original is still there: the vault copy must not be.
            try {
              await container.remove(item.id);
            } on Object {
              // Nothing more to do; the next open lists it.
            }
            failed.add(p.name);
          } else if (stillThere == null) {
            // Cannot tell: keep both rather than risk the only copy.
            leftInLibrary.add(p.name);
          } else {
            try {
              await _scrubLibrary(p, origin);
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
          }
        } else if (!originalDeleted) {
          failed.add(p.name);
        }
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
