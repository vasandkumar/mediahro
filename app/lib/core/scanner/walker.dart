import 'dart:async';

import 'package:mediahro/core/index/content_hash.dart';
import 'package:mediahro/core/index/media_kind.dart';
import 'package:mediahro/core/scanner/scan_model.dart';
import 'package:mediahro_ffi/mediahro_ffi.dart';

/// Cooperative pause/cancel for a walk (LIB-003: scans are pausable).
final class PauseToken {
  Completer<void>? _resume;
  bool _cancelled = false;

  bool get isPaused => _resume != null;
  bool get isCancelled => _cancelled;

  void pause() => _resume ??= Completer<void>();

  void resume() {
    _resume?.complete();
    _resume = null;
  }

  void cancel() {
    _cancelled = true;
    resume();
  }

  /// Waits while paused; throws [ScanCancelled] after [cancel].
  Future<void> checkpoint() async {
    final r = _resume;
    if (r != null) await r.future;
    if (_cancelled) throw const ScanCancelled();
  }
}

final class ScanCancelled implements Exception {
  const ScanCancelled();
}

/// Breadth-first walk of [root] on [fs], yielding batches of indexable files.
/// Never follows links; skips hidden and `.nomedia` folders per [options].
Stream<List<FoundFile>> walk(
  VirtualFileSystem fs,
  Uri root, {
  ScanOptions options = const ScanOptions(),
  PauseToken? token,
  int batchSize = 512,
  void Function(int directories)? onDirectory,
}) async* {
  final queue = <(Uri, String, int)>[(root, '', 0)];
  var batch = <FoundFile>[];
  var dirs = 0;
  while (queue.isNotEmpty) {
    await token?.checkpoint();
    final (uri, rel, depth) = queue.removeAt(0);
    final children = <VirtualEntry>[];
    try {
      children.addAll(await fs.list(uri).toList());
    } on VirtualFileException catch (e) {
      // An unreadable root is fatal; unreadable subfolders are skipped.
      if (rel.isEmpty) rethrow;
      if (e.error == VirtualFileError.unreachable) rethrow;
      continue;
    }
    dirs++;
    onDirectory?.call(dirs);
    if (options.honourNoMedia && children.any((c) => c.name == '.nomedia')) {
      continue;
    }
    for (final c in children) {
      if (options.skipHidden && c.name.startsWith('.')) continue;
      final childRel = rel.isEmpty ? c.name : '$rel/${c.name}';
      if (c.isDirectory) {
        if (depth + 1 > options.maxDepth) continue;
        if (options.excludedFolders.contains(childRel)) continue;
        queue.add((c.uri, childRel, depth + 1));
        continue;
      }
      final kind = MediaKinds.classify(c.name);
      if (!options.includeKinds.contains(kind)) continue;
      batch.add(
        FoundFile(
          relPath: childRel,
          size: c.size ?? 0,
          // The index keeps second precision (drift epoch seconds).
          mtimeMs: (c.modified?.millisecondsSinceEpoch ?? 0) ~/ 1000 * 1000,
          kind: kind,
        ),
      );
      if (batch.length >= batchSize) {
        yield batch;
        batch = <FoundFile>[];
      }
    }
  }
  if (batch.isNotEmpty) yield batch;
}

/// Compares a full walk with the index. Moves are detected by size and
/// confirmed by content hash ([hashOf]); without a stored hash, a file with
/// the same name, size and mtime counts as moved.
Future<ScanDiff> diffWalk(
  List<FoundFile> found,
  Map<String, KnownItem> known, {
  Future<String?> Function(FoundFile file)? hashOf,
  PauseToken? token,
}) async {
  final added = <FoundFile>[];
  final changed = <(int, FoundFile)>[];
  final reappeared = <int>[];
  var unchanged = 0;
  final seen = <String>{};
  for (final f in found) {
    seen.add(f.relPath);
    final k = known[f.relPath];
    if (k == null) {
      added.add(f);
    } else if (k.size != f.size || k.mtimeMs != f.mtimeMs) {
      changed.add((k.id, f));
    } else if (k.missing) {
      reappeared.add(k.id);
    } else {
      unchanged++;
    }
  }
  final gone = [
    for (final k in known.values)
      if (!seen.contains(k.relPath)) k,
  ];
  final moved = <MovedItem>[];
  final hashes = <String, String>{};
  if (gone.isNotEmpty && added.isNotEmpty) {
    final bySize = <int, List<KnownItem>>{};
    for (final g in gone) {
      (bySize[g.size] ??= []).add(g);
    }
    final stillAdded = <FoundFile>[];
    for (final f in added) {
      await token?.checkpoint();
      final candidates = bySize[f.size];
      KnownItem? match;
      String? hash;
      if (candidates != null && candidates.isNotEmpty) {
        if (candidates.any((c) => c.contentHash != null) && hashOf != null) {
          hash = await hashOf(f);
          if (hash != null) {
            hashes[f.relPath] = hash;
            match = candidates.where((c) => c.contentHash == hash).firstOrNull;
          }
        }
        match ??= candidates
            .where(
              (c) =>
                  c.contentHash == null &&
                  c.mtimeMs == f.mtimeMs &&
                  _name(c.relPath) == f.name,
            )
            .firstOrNull;
      }
      if (match != null) {
        candidates!.remove(match);
        moved.add(MovedItem(match.id, f, hash));
      } else {
        stillAdded.add(f);
      }
    }
    added
      ..clear()
      ..addAll(stillAdded);
  }
  final movedIds = {for (final m in moved) m.id};
  return ScanDiff(
    added: added,
    changed: changed,
    moved: moved,
    missingIds: [
      for (final g in gone)
        if (!g.missing && !movedIds.contains(g.id)) g.id,
    ],
    reappearedIds: reappeared,
    unchanged: unchanged,
    addedHashes: hashes,
  );
}

/// Hashes [file] under [root] on [fs] (move detection).
Future<String?> hashFound(
  VirtualFileSystem fs,
  Uri root,
  FoundFile file,
) async {
  final uri = childUri(root, file.relPath);
  try {
    final vf = await fs.open(uri);
    try {
      return await contentHash(vf, knownSize: file.size);
    } finally {
      await vf.close();
    }
  } on VirtualFileException {
    return null;
  }
}

/// URI of [relPath] below a directory URI [root] (segments percent-encoded).
Uri childUri(Uri root, String relPath) => root.replace(
  pathSegments: [
    ...root.pathSegments.where((s) => s.isNotEmpty),
    ...relPath.split('/'),
  ],
);

String _name(String relPath) {
  final i = relPath.lastIndexOf('/');
  return i < 0 ? relPath : relPath.substring(i + 1);
}
