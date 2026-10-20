import 'package:drift/drift.dart';
import 'package:mediahro/core/db/library_database.dart';
import 'package:mediahro/core/files/batch.dart';
import 'package:mediahro/core/files/file_operations.dart';
import 'package:mediahro/features/photos/edit/photo_editor_service.dart';
import 'package:mediahro/features/photos/image_prober.dart';
import 'package:mediahro/features/photos/photo_files.dart';
import 'package:mediahro/features/photos/timeline/timeline_model.dart';
import 'package:mediahro/images/edit/edit_recipe.dart';
import 'package:mediahro/images/image_pipeline.dart';
import 'package:mediahro/images/pipeline/image_io.dart';
import 'package:mediahro/images/pipeline/mediahro_image_pipeline.dart';
import 'package:meta/meta.dart';

/// How a batch went (IMG-010).
@immutable
final class BatchReport {
  const BatchReport({
    this.done = 0,
    this.skipped = 0,
    this.failed = const [],
    this.stopped = false,
  });

  /// Files changed or written.
  final int done;

  /// Files that needed nothing (already upright, a video, ...).
  final int skipped;

  /// Names of the files that could not be processed.
  final List<String> failed;

  /// The user stopped the batch before the end.
  final bool stopped;
}

/// What the convert step writes.
@immutable
final class ConvertOptions {
  const ConvertOptions({
    this.format,
    this.quality = 90,
    this.maxEdge,
    this.stripMetadata = false,
  });

  /// Null keeps each photo's own format where this app can write it, JPEG
  /// otherwise.
  final EncodeFormat? format;
  final int quality;

  /// Longest side in pixels; null keeps the size. Never enlarges.
  final int? maxEdge;
  final bool stripMetadata;
}

/// What the strip step removes.
enum StripScope { location, everything }

/// Batch operations on photos (IMG-010): rename with tokens, convert and
/// resize, turn upright by the EXIF orientation, strip metadata. Faked in
/// widget tests.
abstract interface class PhotoBatch {
  /// Formats this device can write.
  Future<Set<EncodeFormat>> formats();

  /// The names [pattern] would give, conflicts marked; nothing is changed.
  List<RenamePlan> previewRename(List<PhotoEntry> photos, String pattern);

  Future<BatchReport> rename(
    List<PhotoEntry> photos,
    String pattern, {
    void Function(int done)? onProgress,
    bool Function()? cancelled,
  });

  Future<BatchReport> convert(
    List<PhotoEntry> photos,
    ConvertOptions options, {
    void Function(int done)? onProgress,
    bool Function()? cancelled,
  });

  /// Re-saves photos whose EXIF orientation is not "normal" with upright
  /// pixels and orientation 1.
  Future<BatchReport> uprightByExif(
    List<PhotoEntry> photos, {
    void Function(int done)? onProgress,
    bool Function()? cancelled,
  });

  Future<BatchReport> strip(
    List<PhotoEntry> photos,
    StripScope scope, {
    void Function(int done)? onProgress,
    bool Function()? cancelled,
  });
}

/// Photos the app can rewrite in place.
const _rewritable = {'jpg', 'jpeg', 'png', 'webp', 'jxl'};

final class PhotoBatchService implements PhotoBatch {
  PhotoBatchService({
    required this.files,
    required this.pipeline,
    required this.io,
    required this.operations,
    required this.db,
    required this.prober,
  });

  final PhotoFileOpener files;
  final MediahroImagePipeline pipeline;
  final ImageIo io;
  final FileOperations operations;
  final LibraryDatabase db;
  final ImageProber prober;

  /// Reads a rewritten file again so the library matches it. The capture
  /// date stays when the file no longer carries one (metadata stripped).
  Future<void> _reprobe(PhotoEntry p) async {
    final item = await (db.select(
      db.items,
    )..where((i) => i.id.equals(p.id))).getSingleOrNull();
    if (item == null) return;
    final fresh = await files.open(p);
    try {
      await prober.reprobe(item, fresh.file);
    } finally {
      await fresh.file.close();
    }
    if (item.takenAt != null) {
      await (db.update(db.items)
            ..where((i) => i.id.equals(p.id) & i.takenAt.isNull()))
          .write(ItemsCompanion(takenAt: Value(item.takenAt)));
    }
  }

  @override
  Future<Set<EncodeFormat>> formats() => pipeline.encodableFormats();

  RenameFacts _facts(PhotoEntry e) => RenameFacts(
    name: e.name,
    modified: e.date,
    width: e.width,
    height: e.height,
  );

  @override
  List<RenamePlan> previewRename(List<PhotoEntry> photos, String pattern) =>
      planRename([for (final p in photos) _facts(p)], pattern);

  /// The loop shared by every operation: one file at a time, so a bad file
  /// is reported and the rest go on.
  Future<BatchReport> _each(
    List<PhotoEntry> photos,
    Future<bool> Function(PhotoEntry) work, {
    void Function(int done)? onProgress,
    bool Function()? cancelled,
  }) async {
    var done = 0;
    var skipped = 0;
    var n = 0;
    final failed = <String>[];
    for (final p in photos) {
      if (cancelled?.call() ?? false) {
        return BatchReport(
          done: done,
          skipped: skipped,
          failed: failed,
          stopped: true,
        );
      }
      try {
        if (await work(p)) {
          done++;
        } else {
          skipped++;
        }
      } on Object {
        failed.add(p.name);
      }
      onProgress?.call(++n);
    }
    return BatchReport(done: done, skipped: skipped, failed: failed);
  }

  @override
  Future<BatchReport> rename(
    List<PhotoEntry> photos,
    String pattern, {
    void Function(int done)? onProgress,
    bool Function()? cancelled,
  }) async {
    final plan = previewRename(photos, pattern);
    if (plan.any((p) => p.conflict)) throw const PatternError('conflict');
    final byName = <PhotoEntry, RenamePlan>{
      for (var i = 0; i < photos.length; i++) photos[i]: plan[i],
    };
    return await _each(
      photos,
      (p) async {
        final to = byName[p]!.to;
        if (to == p.name) return false;
        await operations.rename(await files.uriOf(p), to);
        return true;
      },
      onProgress: onProgress,
      cancelled: cancelled,
    );
  }

  @override
  Future<BatchReport> convert(
    List<PhotoEntry> photos,
    ConvertOptions options, {
    void Function(int done)? onProgress,
    bool Function()? cancelled,
  }) => _each(
    photos,
    (p) async {
      if (p.isVideo) return false;
      final format = options.format ?? editFormatFor(p.ext);
      final src = await files.open(p);
      try {
        final bytes = await pipeline.renderEdited(
          src,
          EditRecipe.none,
          EncodeOptions(
            format: format,
            quality: options.quality,
            maxEdge: options.maxEdge,
            stripMetadata: options.stripMetadata,
          ),
        );
        final original = await files.uriOf(p);
        final segments = [...original.pathSegments];
        final name = Uri.decodeComponent(segments.removeLast());
        final dot = name.lastIndexOf('.');
        final stem = dot <= 0 ? name : name.substring(0, dot);
        final ext = extensionOf(format);
        for (var n = 0; ; n++) {
          final suffix = n == 0
              ? ''
              : (n == 1 ? '_converted' : '_converted_$n');
          final candidate = '$stem$suffix.$ext';
          // A plain re-save of the same name would overwrite the original.
          if (candidate.toLowerCase() == name.toLowerCase()) continue;
          final target = original.replace(
            pathSegments: [...segments, candidate],
          );
          if (await io.exists(target)) continue;
          await io.create(target, bytes);
          return true;
        }
      } finally {
        await src.file.close();
      }
    },
    onProgress: onProgress,
    cancelled: cancelled,
  );

  @override
  Future<BatchReport> uprightByExif(
    List<PhotoEntry> photos, {
    void Function(int done)? onProgress,
    bool Function()? cancelled,
  }) => _each(
    photos,
    (p) async {
      if (p.isVideo || (p.orientation ?? 1) <= 1) return false;
      if (!_rewritable.contains(p.ext)) {
        throw UnsupportedError('${p.ext} cannot be rewritten');
      }
      final src = await files.open(p);
      try {
        final bytes = await pipeline.renderEdited(
          src,
          EditRecipe.none,
          EncodeOptions(format: editFormatFor(p.ext), quality: 95),
        );
        await io.replace(await files.uriOf(p), bytes);
      } finally {
        await src.file.close();
      }
      await _reprobe(p);
      return true;
    },
    onProgress: onProgress,
    cancelled: cancelled,
  );

  @override
  Future<BatchReport> strip(
    List<PhotoEntry> photos,
    StripScope scope, {
    void Function(int done)? onProgress,
    bool Function()? cancelled,
  }) => _each(
    photos,
    (p) async {
      if (p.isVideo) return false;
      final src = await files.open(p);
      try {
        switch (scope) {
          case StripScope.everything:
            await pipeline.stripMetadataFile(src);
          case StripScope.location:
            await pipeline.applyMetadataEdit(
              src,
              const ImageMetadataEdit(clearLocation: true),
            );
        }
      } finally {
        await src.file.close();
      }
      await _reprobe(p);
      return true;
    },
    onProgress: onProgress,
    cancelled: cancelled,
  );
}
