import 'package:mediahro/core/db/tables.dart';
import 'package:meta/meta.dart';

/// A file found by the walker. Plain values only, so it crosses isolates.
@immutable
final class FoundFile {
  const FoundFile({
    required this.relPath,
    required this.size,
    required this.mtimeMs,
    required this.kind,
  });

  /// `/`-separated path relative to the source root, no leading slash.
  final String relPath;
  final int size;
  final int mtimeMs;
  final ItemKind kind;

  String get name {
    final i = relPath.lastIndexOf('/');
    return i < 0 ? relPath : relPath.substring(i + 1);
  }

  String get parentPath {
    final i = relPath.lastIndexOf('/');
    return i < 0 ? '' : relPath.substring(0, i);
  }

  @override
  bool operator ==(Object other) =>
      other is FoundFile &&
      other.relPath == relPath &&
      other.size == size &&
      other.mtimeMs == mtimeMs &&
      other.kind == kind;

  @override
  int get hashCode => Object.hash(relPath, size, mtimeMs, kind);

  @override
  String toString() => 'FoundFile($relPath, $size, $mtimeMs)';
}

/// What the index already knows about a path (the stable item key,
/// docs/05 §6: source + relative path + size + mtime).
@immutable
final class KnownItem {
  const KnownItem({
    required this.id,
    required this.relPath,
    required this.size,
    required this.mtimeMs,
    this.contentHash,
    this.missing = false,
  });

  final int id;
  final String relPath;
  final int size;
  final int mtimeMs;
  final String? contentHash;
  final bool missing;
}

/// A file that moved: same content, new path (keeps progress, tags, ratings).
@immutable
final class MovedItem {
  const MovedItem(this.id, this.to, this.contentHash);

  final int id;
  final FoundFile to;
  final String? contentHash;
}

/// Result of comparing a walk with the index.
@immutable
final class ScanDiff {
  const ScanDiff({
    this.added = const [],
    this.changed = const [],
    this.moved = const [],
    this.missingIds = const [],
    this.reappearedIds = const [],
    this.unchanged = 0,
    this.addedHashes = const {},
  });

  final List<FoundFile> added;

  /// Same path, different size or mtime.
  final List<(int, FoundFile)> changed;
  final List<MovedItem> moved;

  /// Known items not seen in this walk.
  final List<int> missingIds;

  /// Items marked missing earlier and seen again unchanged.
  final List<int> reappearedIds;
  final int unchanged;

  /// Content hashes computed for added files during move detection.
  final Map<String, String> addedHashes;

  int get filesSeen =>
      added.length +
      changed.length +
      moved.length +
      reappearedIds.length +
      unchanged;

  bool get isEmpty =>
      added.isEmpty &&
      changed.isEmpty &&
      moved.isEmpty &&
      missingIds.isEmpty &&
      reappearedIds.isEmpty;
}

/// Progress of a running scan, streamed to the Sources UI (docs/06 §9).
@immutable
final class ScanProgress {
  const ScanProgress({
    required this.sourceId,
    required this.state,
    this.filesSeen = 0,
    this.directoriesSeen = 0,
    this.error,
  });

  final int sourceId;
  final ScanJobState state;
  final int filesSeen;
  final int directoriesSeen;
  final String? error;

  ScanProgress copyWith({
    ScanJobState? state,
    int? filesSeen,
    int? directoriesSeen,
    String? error,
  }) => ScanProgress(
    sourceId: sourceId,
    state: state ?? this.state,
    filesSeen: filesSeen ?? this.filesSeen,
    directoriesSeen: directoriesSeen ?? this.directoriesSeen,
    error: error ?? this.error,
  );
}

/// Walk options.
@immutable
final class ScanOptions {
  const ScanOptions({
    this.maxDepth = 64,
    this.skipHidden = true,
    this.honourNoMedia = true,
    this.excludedFolders = const {},
    this.includeKinds = const {
      ItemKind.video,
      ItemKind.audio,
      ItemKind.image,
      ItemKind.playlist,
      ItemKind.subtitle,
      ItemKind.archive,
    },
  });

  final int maxDepth;

  /// Skips dot-files and dot-folders (`.thumbnails`, `.Trash-1000`).
  final bool skipHidden;

  /// Skips folders that contain a `.nomedia` file (Android convention).
  final bool honourNoMedia;

  /// Relative folder paths never descended into.
  final Set<String> excludedFolders;
  final Set<ItemKind> includeKinds;
}
