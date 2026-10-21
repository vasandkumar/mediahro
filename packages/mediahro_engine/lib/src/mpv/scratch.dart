import 'dart:io';
import 'dart:isolate';

import 'package:mediahro_engine/src/api/media_source.dart';
import 'package:mediahro_engine/src/api/models.dart';
import 'package:meta/meta.dart';

/// URI schemes that mark a source as protected media even when its
/// `sensitive` flag is not set (the vault, IMG-011 / PRIV-007): a second
/// line of defence for a vault source built without the flag.
const Set<String> sensitiveSchemes = {'vault'};

/// Whether nothing decoded from [source] may be written to disk (ADR-043):
/// protected media, such as decrypted vault content. Analysis then keeps to
/// RAM-backed storage or is refused.
bool isSensitiveSource(MediaSource? source) =>
    source != null &&
    (source.sensitive ||
        switch (source) {
          VirtualFileSource(:final file) => sensitiveSchemes.contains(
            file.uri.scheme,
          ),
          UriSource(:final uri) => sensitiveSchemes.contains(uri.scheme),
        });

/// The error for work on a sensitive source that would need a disk file.
const EngineException sensitiveNeedsMemory = EngineException(
  EngineError(
    code: EngineErrorCode.notSupported,
    detail:
        'protected media is never written to disk, and this device has '
        'no RAM-backed storage for it',
  ),
);

const String _parentName = 'mediahro-scratch';

// Folders earlier versions made directly in the temporary directory.
const List<String> _legacyPrefixes = [
  'mediahro-pcm',
  'mediahro-subx',
  'mediahro-subimg',
  'mediahro-cast',
  'mediahro-shot',
  'mediahro-disc',
  'mh-subs',
];

// Folders of this process that are in use (never swept).
final Set<String> _active = {};
bool _swept = false;

/// Where scratch folders live: a folder of its own in the app-private
/// temporary directory (the app's cache on Android; per-user on desktop).
Directory get scratchParent => Directory(
  '${Directory.systemTemp.path}${Platform.pathSeparator}$_parentName',
);

/// A new private scratch folder (`0700` on POSIX, since `createTemp` makes it
/// so) for decoded media; remove it with [deleteScratch]. The first call
/// of a process also sweeps what earlier runs left behind.
Future<Directory> createScratch(String prefix) async {
  final parent = scratchParent;
  await parent.create(recursive: true);
  await sweepOnce();
  final dir = await parent.createTemp('$prefix-');
  _active.add(dir.path);
  return dir;
}

/// Removes [dir]; a file another process still holds (Windows) is retried.
Future<void> deleteScratch(Directory dir) async {
  _active.remove(dir.path);
  for (var attempt = 0; attempt < 5; attempt++) {
    try {
      if (!dir.existsSync()) return;
      await dir.delete(recursive: true);
      return;
    } on FileSystemException {
      await Future<void>.delayed(Duration(milliseconds: 40 * (attempt + 1)));
    }
  }
}

/// Sweeps once per process: the engine calls it at start-up, and the first
/// scratch folder made does too.
Future<void> sweepOnce() async {
  if (_swept) return;
  _swept = true;
  await sweepStaleScratch();
}

/// Deletes scratch folders of earlier runs (crash or kill before cleanup),
/// and the older per-feature folders that sat directly in the temporary
/// directory. A folder counts as stale when nothing in it changed for
/// [olderThan] and this process is not using it. The scan runs in an
/// isolate: it happens at start-up and a temporary directory can hold
/// thousands of entries.
Future<void> sweepStaleScratch({
  Duration olderThan = const Duration(hours: 1),
}) async {
  // Read here: the isolate has globals of its own.
  final parent = scratchParent.path;
  final temp = Directory.systemTemp.path;
  final active = _active.toList();
  try {
    await Isolate.run(() => _sweepNow(parent, temp, olderThan, active));
  } on Object {
    // A sweep that cannot run is not an error for the app.
  }
}

void _sweepNow(
  String parentPath,
  String tempPath,
  Duration olderThan,
  List<String> active,
) {
  final now = DateTime.now();
  final candidates = <Directory>[];
  try {
    final parent = Directory(parentPath);
    if (parent.existsSync()) {
      candidates.addAll(parent.listSync().whereType<Directory>());
    }
    candidates.addAll(
      Directory(tempPath).listSync().whereType<Directory>().where((d) {
        final name = d.uri.pathSegments.where((s) => s.isNotEmpty).last;
        return _legacyPrefixes.any(name.startsWith);
      }),
    );
  } on FileSystemException {
    return;
  }
  for (final dir in candidates) {
    if (active.contains(dir.path)) continue;
    if (now.difference(_newestChange(dir)) < olderThan) continue;
    try {
      dir.deleteSync(recursive: true);
    } on FileSystemException {
      // In use elsewhere; the next start tries again.
    }
  }
}

// The newest change to a file in [dir] (writes to a file do not touch the
// folder itself), or the folder's own time when it is empty.
DateTime _newestChange(Directory dir) {
  try {
    DateTime? newest;
    for (final e in dir.listSync(recursive: true)) {
      if (e is! File) continue;
      final m = e.statSync().modified;
      if (newest == null || m.isAfter(newest)) newest = m;
    }
    return newest ?? dir.statSync().modified;
  } on FileSystemException {
    return DateTime.now();
  }
}

/// Forgets that this process swept (tests).
@visibleForTesting
void resetScratchSweep() => _swept = false;
