import 'dart:math' as math;
import 'dart:typed_data';

import 'package:drift/drift.dart';
import 'package:mediahro/core/db/library_database.dart';
import 'package:mediahro/core/index/content_hash.dart';
import 'package:mediahro/core/library/duplicates.dart';
import 'package:mediahro/features/photos/photo_files.dart';
import 'package:mediahro/features/photos/timeline/timeline_model.dart';
import 'package:mediahro/images/image_pipeline.dart';
import 'package:mediahro/images/pipeline/mediahro_image_pipeline.dart';

/// A 32 × 32 greyscale picture of [d] (box averages of the luma, the shape
/// is stretched), the input of the perceptual hash (LIB-014, IMG-013).
Uint8List grey32Of(DecodedImage d) {
  const n = 32;
  final out = Uint8List(n * n);
  final w = d.width;
  final h = d.height;
  if (w == 0 || h == 0) return out;
  final p = d.pixels;
  for (var cy = 0; cy < n; cy++) {
    final y0 = cy * h ~/ n;
    final y1 = math.max(y0 + 1, (cy + 1) * h ~/ n);
    for (var cx = 0; cx < n; cx++) {
      final x0 = cx * w ~/ n;
      final x1 = math.max(x0 + 1, (cx + 1) * w ~/ n);
      var sum = 0;
      var count = 0;
      for (var y = y0; y < y1 && y < h; y++) {
        for (var x = x0; x < x1 && x < w; x++) {
          final o = (y * w + x) * 4;
          // Rec. 601 luma, integer.
          sum += (p[o] * 299 + p[o + 1] * 587 + p[o + 2] * 114) ~/ 1000;
          count++;
        }
      }
      out[cy * n + cx] = count == 0 ? 0 : sum ~/ count;
    }
  }
  return out;
}

/// A library row as a photo entry (the light shape the photo screens use).
PhotoEntry photoEntryOfItem(ItemRow i) => PhotoEntry(
  id: i.id,
  sourceId: i.sourceId,
  relPath: i.relPath,
  name: i.name,
  ext: i.ext.toLowerCase(),
  isVideo: i.kind == ItemKind.video,
  size: i.size,
  mtime: i.mtime,
  date: i.takenAt ?? i.mtime,
  width: i.width,
  height: i.height,
);

/// Feeds the duplicate finder from the photo pipeline: content hashes read
/// two mebibytes at most, greyscale thumbnails decoded at reduced size.
final class PhotoDuplicateInputs implements DuplicateInputs {
  PhotoDuplicateInputs({
    required this.files,
    required this.pipeline,
    this.onThumbnail,
  });

  final PhotoFileOpener files;
  final MediahroImagePipeline pipeline;

  /// Called before each thumbnail is made; may throw to stop the scan.
  final void Function()? onThumbnail;

  @override
  Future<String?> contentHash(ItemRow item) async {
    try {
      final src = await files.open(photoEntryOfItem(item));
      try {
        return await contentHashOf64(src, item.size);
      } finally {
        await src.file.close();
      }
    } on Object {
      return null;
    }
  }

  @override
  Future<Uint8List?> grey32(ItemRow item) async {
    onThumbnail?.call();
    if (item.kind != ItemKind.image) return null;
    try {
      final src = await files.open(photoEntryOfItem(item));
      try {
        final info = await pipeline.info(src);
        final longest = math.max(info.width, info.height);
        final scale = longest <= 64 ? 1.0 : 64 / longest;
        return grey32Of(await pipeline.decode(src, scale: scale));
      } finally {
        await src.file.close();
      }
    } on StopScan {
      rethrow;
    } on Object {
      return null;
    }
  }

  @override
  Future<Uint32List?> fingerprint(ItemRow item) async => null;
}

/// Reads like [contentHash] on an opened photo.
Future<String> contentHashOf64(ImageSource src, int size) =>
    contentHash(src.file, knownSize: size);

/// Thrown by the scan's hook when the user stopped it.
final class StopScan implements Exception {
  const StopScan();
}

/// What a scan found.
final class DuplicateScan {
  const DuplicateScan(this.groups, {this.stopped = false});

  final List<DuplicateGroup> groups;
  final bool stopped;
}

/// The scan as the screen sees it; faked in widget tests.
abstract interface class DuplicateScanner {
  Future<DuplicateScan> scan({
    required bool exact,
    required bool similar,
    void Function(int done, int total)? onProgress,
    bool Function()? cancelled,
  });
}

/// Looks for exact copies and visually similar photos (IMG-013). Never
/// deletes anything: the groups go to a review screen.
final class PhotoDuplicateScanner implements DuplicateScanner {
  PhotoDuplicateScanner({
    required this.db,
    required this.files,
    required this.pipeline,
    this.maxPhashDistance = 6,
  });

  final LibraryDatabase db;
  final PhotoFileOpener files;
  final MediahroImagePipeline pipeline;
  final int maxPhashDistance;

  /// Photos whose perceptual hash is not computed yet.
  Future<int> pending() async {
    final row = await db
        .customSelect(
          'SELECT count(*) AS n FROM item i LEFT JOIN image_meta im '
          'ON im.item_id = i.id WHERE i.kind = ? AND i.missing = 0 '
          'AND i.vault = 0 AND im.phash IS NULL',
          variables: [Variable.withString(ItemKind.image.name)],
          readsFrom: {db.items, db.imageMeta},
        )
        .getSingle();
    return row.read<int>('n');
  }

  @override
  Future<DuplicateScan> scan({
    required bool exact,
    required bool similar,
    void Function(int done, int total)? onProgress,
    bool Function()? cancelled,
  }) async {
    final total = similar ? await pending() : 0;
    var done = 0;
    final finder = DuplicateFinder(
      db,
      maxPhashDistance: maxPhashDistance,
      inputs: PhotoDuplicateInputs(
        files: files,
        pipeline: pipeline,
        onThumbnail: () {
          if (cancelled?.call() ?? false) throw const StopScan();
          onProgress?.call(done++, total);
        },
      ),
    );
    final groups = <DuplicateGroup>[];
    try {
      if (exact) groups.addAll(await finder.exact());
      if (similar) groups.addAll(await finder.images());
    } on StopScan {
      return DuplicateScan(_photosOnly(groups), stopped: true);
    }
    return DuplicateScan(_photosOnly(groups));
  }

  /// Photos and videos only (exact matches can include other media), and a
  /// perceptual group that repeats an exact one is dropped.
  List<DuplicateGroup> _photosOnly(List<DuplicateGroup> all) {
    final seen = <String>{};
    final out = <DuplicateGroup>[];
    for (final g in all) {
      final items = [
        for (final i in g.items)
          if ((i.kind == ItemKind.image || i.kind == ItemKind.video) &&
              !i.vault)
            i,
      ];
      if (items.length < 2) continue;
      final key = ([for (final i in items) i.id]..sort()).join(',');
      if (!seen.add(key)) continue;
      out.add(DuplicateGroup(g.kind, items, similarity: g.similarity));
    }
    return out;
  }
}
