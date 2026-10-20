import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:mediahro/core/db/library_database.dart';
import 'package:mediahro/core/index/index_writer.dart';
import 'package:mediahro/features/music/library/artwork_store.dart';
import 'package:mediahro/features/music/library/music_files.dart';
import 'package:mediahro/features/music/library/music_library.dart';
import 'package:mediahro/features/music/player/music_prefs.dart';
import 'package:mediahro/features/music/tags/audio_tags.dart';
import 'package:mediahro/features/music/tags/byte_reader.dart';
import 'package:mediahro/features/music/tags/tag_reader.dart';
import 'package:mediahro/features/music/tags/writer/tag_edit.dart';
import 'package:mediahro/features/music/tags/writer/tag_writer.dart';
import 'package:mediahro_ffi/mediahro_ffi.dart';
import 'package:meta/meta.dart';

/// Why one file of a batch was not changed.
enum TagEditFailure { readOnly, unsupported, verifyFailed, ioError }

@immutable
final class TagEditResult {
  const TagEditResult({required this.changed, required this.failed});

  final int changed;

  /// Item id → reason.
  final Map<int, TagEditFailure> failed;
}

/// Writes tag edits to music files (MUS-003), safely:
/// 1. the new file is built from the original (new tag + streamed audio)
///    into a temporary file next to it (local files) or in the app cache
///    (other sources);
/// 2. the temporary file is read back and must carry the edit, or nothing
///    happens;
/// 3. the original is renamed to a backup name, the new file takes its
///    name, then the backup is deleted. A failure in between puts the
///    original back.
/// The index (titles, albums, art) is refreshed, and the last batch can be
/// undone.
final class TagEditor {
  TagEditor({
    required this.db,
    required this.files,
    required this.art,
    required this.prefs,
    required this.cacheDir,
    IndexWriter? writer,
  }) : _writer = writer ?? IndexWriter(db);

  final LibraryDatabase db;
  final MusicFiles files;
  final ArtworkStore art;
  final MusicPrefs prefs;

  /// Scratch space for non-local sources.
  final Directory cacheDir;
  final IndexWriter _writer;

  /// Applies [editFor] to every track; returns what changed. The batch is
  /// recorded for [undoLast].
  Future<TagEditResult> apply(
    List<MusicTrack> tracks,
    TagEdit Function(MusicTrack track, AudioTags before) editFor, {
    void Function(int done, int total)? progress,
  }) async {
    var changed = 0;
    final failed = <int, TagEditFailure>{};
    final journal = <Map<String, Object?>>[];
    for (final (i, t) in tracks.indexed) {
      try {
        final undo = await _editOne(t, editFor);
        if (undo != null) {
          changed++;
          journal.add({'itemId': t.itemId, 'edit': undo.toJson()});
        }
      } on TagWriteUnsupported {
        failed[t.itemId] = TagEditFailure.unsupported;
      } on _ReadOnly {
        failed[t.itemId] = TagEditFailure.readOnly;
      } on _VerifyFailed {
        failed[t.itemId] = TagEditFailure.verifyFailed;
      } on TagFormatException {
        failed[t.itemId] = TagEditFailure.unsupported;
      } on Exception {
        failed[t.itemId] = TagEditFailure.ioError;
      }
      progress?.call(i + 1, tracks.length);
    }
    if (journal.isNotEmpty) await prefs.write('tagUndo', journal);
    return TagEditResult(changed: changed, failed: failed);
  }

  /// Whether a batch can be undone.
  Future<bool> canUndo() async =>
      (await prefs.readList('tagUndo'))?.isNotEmpty ?? false;

  /// Restores the fields the last batch changed.
  Future<TagEditResult> undoLast() async {
    final journal = await prefs.readList('tagUndo') ?? const [];
    final edits = <int, TagEdit>{
      for (final e in journal)
        if (e case {
          'itemId': final int id,
          'edit': final Map<String, Object?> j,
        })
          id: TagEdit.fromJson(j),
    };
    final tracks = await MusicLibrary(db).tracksByIds(edits.keys.toList());
    await prefs.write('tagUndo', const <Object?>[]);
    final result = await apply(tracks, (t, _) => edits[t.itemId]!);
    // An undo is not itself undoable.
    await prefs.write('tagUndo', const <Object?>[]);
    return result;
  }

  /// Edits one file; returns the inverse edit, or null when nothing
  /// changed.
  Future<TagEdit?> _editOne(
    MusicTrack t,
    TagEdit Function(MusicTrack, AudioTags) editFor,
  ) async {
    final target = await files.writable(t.sourceId, t.relPath);
    if (target == null) throw const _ReadOnly();
    final (fs, uri) = target;
    final local = uri.scheme == 'file';
    final work = await cacheDir.create(recursive: true);
    final stamp =
        '${DateTime.now().microsecondsSinceEpoch}-${math.Random().nextInt(1 << 30)}';
    String srcPath;
    String outPath;
    final dir = local ? File(uri.toFilePath()).parent.path : work.path;
    final name = t.relPath.split('/').last;
    if (local) {
      srcPath = uri.toFilePath();
      outPath = '$dir${Platform.pathSeparator}.$name.mediahro-$stamp.tmp';
    } else {
      srcPath = '${work.path}${Platform.pathSeparator}$stamp.src';
      outPath = '${work.path}${Platform.pathSeparator}$stamp.out';
      await _download(await files.open(t.sourceId, t.relPath), srcPath);
    }
    try {
      // Read, plan, write and verify in an isolate (CLAUDE.md §1.10).
      final before = await TagReader.readFile(srcPath);
      final edit = editFor(t, before);
      if (edit.isEmpty) return null;
      final ok = await _buildAndVerify(srcPath, outPath, before, edit);
      if (!ok) throw const _VerifyFailed();
      if (local) {
        await _swapLocal(srcPath, outPath);
      } else {
        await _swapRemote(fs, uri, outPath);
      }
      await _reindex(t, edit.applyTo(before), pictures: edit.pictures != null);
      return edit.inverse(before);
    } finally {
      for (final p in [if (!local) srcPath, outPath]) {
        final f = File(p);
        if (f.existsSync()) await f.delete();
      }
    }
  }

  static Future<bool> _buildAndVerify(
    String src,
    String out,
    AudioTags before,
    TagEdit edit,
  ) => Isolate.run(() {
    final raf = File(src).openSync();
    try {
      final r = FileByteReader(raf);
      final plan = TagWriter.plan(r, before, edit);
      final w = File(out).openSync(mode: FileMode.writeOnly);
      try {
        for (final p in plan.parts) {
          switch (p) {
            case BytesPart(:final bytes):
              w.writeFromSync(bytes);
            case RangePart(:final offset, :final length):
              var pos = offset;
              final end = offset + length;
              while (pos < end) {
                final n = math.min(1 << 20, end - pos);
                w.writeFromSync(r.read(pos, n));
                pos += n;
              }
          }
        }
        w.flushSync();
      } finally {
        w.closeSync();
      }
      // Verify: the new file reads back with the edit applied.
      final check = File(out).openSync();
      try {
        final got = TagReader.read(FileByteReader(check));
        final want = edit.applyTo(before);
        for (final k in edit.fields.keys) {
          if (!_sameValues(got.values(k), want.values(k), k)) return false;
        }
        if (edit.pictures != null &&
            got.pictures.length != want.pictures.length) {
          return false;
        }
        return File(out).lengthSync() == plan.length;
      } finally {
        check.closeSync();
      }
    } finally {
      raf.closeSync();
    }
  });

  static bool _sameValues(List<String> got, List<String> want, String key) {
    // Track/disc totals may be folded into "n/total" and read back either
    // way; compare by value.
    if (got.length != want.length) {
      return (key == TagField.trackTotal || key == TagField.discTotal) &&
          got.isNotEmpty == want.isNotEmpty;
    }
    for (var i = 0; i < got.length; i++) {
      if (got[i].trim() != want[i].trim()) return false;
    }
    return true;
  }

  Future<void> _swapLocal(String original, String tmp) async {
    final bak = '$original.mediahro-bak';
    await File(original).rename(bak);
    try {
      await File(tmp).rename(original);
    } on Exception {
      await File(bak).rename(original);
      rethrow;
    }
    await File(bak).delete();
  }

  Future<void> _swapRemote(MutableFileSystem fs, Uri uri, String out) async {
    final name = uri.pathSegments.where((s) => s.isNotEmpty).last;
    final dir = uri.replace(
      path: uri.path.substring(
        0,
        uri.path.length - Uri.encodeComponent(name).length,
      ),
    );
    final tmpUri = dir.resolve(Uri.encodeComponent('.$name.mediahro.tmp'));
    final w = await fs.create(tmpUri);
    try {
      final raf = await File(out).open();
      try {
        while (true) {
          final chunk = await raf.read(1 << 20);
          if (chunk.isEmpty) break;
          await w.write(chunk);
        }
      } finally {
        await raf.close();
      }
      await w.close();
    } on Exception {
      await w.abort();
      rethrow;
    }
    final bakUri = await fs.rename(uri, '$name.mediahro-bak');
    try {
      await fs.rename(tmpUri, name);
    } on Exception {
      await fs.rename(bakUri, name);
      rethrow;
    }
    await fs.delete(bakUri);
  }

  Future<void> _download(VirtualFile f, String path) async {
    final out = await File(path).open(mode: FileMode.writeOnly);
    try {
      final len = await f.length() ?? 0;
      var pos = 0;
      while (pos < len) {
        final chunk = await f.read(pos, math.min(1 << 20, len - pos));
        if (chunk.isEmpty) break;
        await out.writeFrom(chunk);
        pos += chunk.length;
      }
    } finally {
      await out.close();
      await f.close();
    }
  }

  Future<void> _reindex(
    MusicTrack t,
    AudioTags after, {
    required bool pictures,
  }) async {
    await _writer.applyProbe(
      t.itemId,
      ProbeResult(
        durationMs: t.duration?.inMilliseconds,
        audioTracks: 1,
        title: after.title ?? t.relPath.split('/').last,
        artist: after.artist,
        albumArtist: after.albumArtist,
        album: after.album,
        genre: after.genre,
        composer: after.composer,
        year: after.year,
        trackNumber: after.trackNumber,
        discNumber: after.discNumber,
      ),
    );
    if (pictures) {
      art.forget(t.itemId);
      if (after.cover != null) await art.storeEmbedded(t.itemId, after);
    }
  }
}

final class _ReadOnly implements Exception {
  const _ReadOnly();
}

final class _VerifyFailed implements Exception {
  const _VerifyFailed();
}

// ------------------------------------------------------------- patterns --

/// Placeholders for rename-from-tags and tags-from-filename (MUS-003).
const Map<String, String> patternFields = {
  'title': TagField.title,
  'artist': TagField.artist,
  'albumartist': TagField.albumArtist,
  'album': TagField.album,
  'track': TagField.trackNumber,
  'disc': TagField.discNumber,
  'year': TagField.date,
  'genre': TagField.genre,
  'composer': TagField.composer,
};

/// A file name (without extension) from [pattern], e.g.
/// `%track% - %artist% - %title%`. Track numbers are zero-padded to two
/// digits; characters not allowed in file names become `_`. Null when a
/// placeholder has no value.
String? nameFromTags(String pattern, AudioTags t) {
  var missing = false;
  final out = pattern.replaceAllMapped(RegExp(r'%(\w+)%'), (m) {
    final key = patternFields[m.group(1)!.toLowerCase()];
    if (key == null) return m.group(0)!;
    var v = switch (key) {
      TagField.trackNumber => t.trackNumber?.toString().padLeft(2, '0'),
      TagField.discNumber => t.discNumber?.toString(),
      TagField.date => t.year?.toString(),
      TagField.artist => t.artist,
      TagField.genre => t.genre,
      _ => t.first(key),
    };
    if (v == null || v.trim().isEmpty) {
      missing = true;
      v = '';
    }
    return v;
  });
  if (missing) return null;
  final clean = out
      .replaceAll(RegExp(r'[<>:"/\\|?*\u0000-\u001F]'), '_')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  return clean.isEmpty || clean == '.' || clean == '..' ? null : clean;
}

/// Fields read from a file name (without extension) by [pattern], e.g.
/// `%track% - %artist% - %title%`; null when the name doesn't match.
Map<String, List<String>>? tagsFromName(String pattern, String stem) {
  final keys = <String>[];
  final regex = StringBuffer('^');
  var last = 0;
  for (final m in RegExp(r'%(\w+)%').allMatches(pattern)) {
    regex.write(RegExp.escape(pattern.substring(last, m.start)));
    final key = patternFields[m.group(1)!.toLowerCase()];
    if (key == null) {
      regex.write(RegExp.escape(m.group(0)!));
    } else {
      keys.add(key);
      regex.write(
        key == TagField.trackNumber ||
                key == TagField.discNumber ||
                key == TagField.date
            ? r'(\d+)'
            : '(.+?)',
      );
    }
    last = m.end;
  }
  regex
    ..write(RegExp.escape(pattern.substring(last)))
    ..write(r'$');
  final match = RegExp(regex.toString()).firstMatch(stem.trim());
  if (match == null) return null;
  return {
    for (var i = 0; i < keys.length; i++)
      keys[i]: [
        if (keys[i] == TagField.trackNumber || keys[i] == TagField.discNumber)
          '${int.parse(match.group(i + 1)!)}'
        else
          match.group(i + 1)!.trim(),
      ],
  };
}

/// Bytes helper for tests and tools.
Uint8List planBytes(Uint8List original, WritePlan plan) {
  final b = BytesBuilder(copy: false);
  for (final p in plan.parts) {
    switch (p) {
      case BytesPart(:final bytes):
        b.add(bytes);
      case RangePart(:final offset, :final length):
        b.add(Uint8List.sublistView(original, offset, offset + length));
    }
  }
  return b.toBytes();
}
