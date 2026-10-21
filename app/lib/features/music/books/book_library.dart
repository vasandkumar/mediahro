import 'dart:convert';

import 'package:mediahro/features/music/books/book.dart';
import 'package:mediahro/features/music/books/book_store.dart';
import 'package:mediahro/features/music/books/cue_sheet.dart';
import 'package:mediahro/features/music/library/music_files.dart';
import 'package:mediahro/features/music/library/music_library.dart';
import 'package:mediahro/features/music/tags/audio_tags.dart';
import 'package:mediahro_ffi/mediahro_ffi.dart';
import 'package:meta/meta.dart';

/// A book with where the listener stands, for the list.
@immutable
final class BookEntry {
  const BookEntry(this.book, this.progress);

  final Book book;
  final BookProgress? progress;

  bool get finished => progress?.finished ?? false;
  bool get started => progress?.started ?? false;

  /// 0…1 through the book.
  double get fraction {
    final p = progress;
    final total = book.duration.inMilliseconds;
    if (p == null) return 0;
    if (p.finished) return 1;
    if (total <= 0) return 0;
    return (book.globalOf(p.trackIndex, p.position).inMilliseconds / total)
        .clamp(0.0, 1.0);
  }
}

/// Audiobooks over the music index (POD-001): an M4B/M4A file, or a folder
/// of MP3s, is a book when it is an `.m4b`, carries a spoken-word genre
/// (Audiobook, Spoken Word, Speech), or the listener says so. The listener's
/// answer always wins over the tags.
final class BookLibrary {
  BookLibrary({
    required this.library,
    required this.store,
    required this.files,
    required this.readTags,
  });

  final MusicLibrary library;
  final BookStore store;
  final MusicFiles files;

  /// Tag reader for chapters (MUS-002).
  final Future<AudioTags> Function(VirtualFile file) readTags;

  static const int maxCueBytes = 1024 * 1024;

  /// Every book, by title.
  Future<List<Book>> books() async {
    final marks = await store.marks();
    final groups = <String, List<MusicTrack>>{};
    for (final t in await library.audiobookCandidates()) {
      final id = t.relPath.toLowerCase().endsWith('.m4b')
          ? singleId(t.itemId)
          : folderId(t.sourceId, t.parentPath);
      if (marks[id] == 'music') continue;
      (groups[id] ??= []).add(t);
    }
    for (final e in marks.entries) {
      if (e.value != 'book') continue;
      final folder = _parseFolder(e.key);
      if (folder != null) {
        final all = await library.folderTracks(folder.$1, folder.$2);
        if (all.isNotEmpty) groups[e.key] = all;
      } else if (e.key.startsWith('i:') && !groups.containsKey(e.key)) {
        final t = await library.track(int.tryParse(e.key.substring(2)) ?? -1);
        if (t != null) groups[e.key] = [t];
      }
    }
    return [for (final e in groups.entries) _book(e.key, e.value)]
      ..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
  }

  Future<Book?> byId(String id) async =>
      (await books()).where((b) => b.id == id).firstOrNull;

  /// The list: every book with its progress, the ones in progress first
  /// (most recently listened first), then the rest by title, finished last.
  Future<List<BookEntry>> entries() async {
    final progress = await store.allProgress();
    final all = [for (final b in await books()) BookEntry(b, progress[b.id])];
    int rank(BookEntry e) => e.finished ? 2 : (e.started ? 0 : 1);
    final ranked = all.indexed.toList()
      ..sort((a, b) {
        final r = rank(a.$2).compareTo(rank(b.$2));
        if (r != 0) return r;
        if (rank(a.$2) == 0) {
          final t = (b.$2.progress?.updatedAt ?? DateTime(0)).compareTo(
            a.$2.progress?.updatedAt ?? DateTime(0),
          );
          if (t != 0) return t;
        }
        return a.$1.compareTo(b.$1);
      });
    return [for (final e in ranked) e.$2];
  }

  /// The chapters of [b], in time order. A folder of files has one per file;
  /// a single file has its own marks, else its CUE sheet's, else none.
  Future<List<BookChapter>> chapters(Book b) async {
    if (!b.singleFile) {
      final starts = b.offsets;
      return [
        for (final (i, t) in b.tracks.indexed) BookChapter(starts[i], t.title),
      ];
    }
    final t = b.tracks.single;
    var marks = const <TagChapter>[];
    try {
      final file = await files.open(t.sourceId, t.relPath);
      try {
        marks = (await readTags(file)).chapters;
      } finally {
        await file.close();
      }
    } on Exception {
      // Unreadable tags: fall through to the CUE sheet.
    }
    if (marks.isEmpty) marks = await _cue(t);
    final total = b.duration;
    return [
      for (final m in marks)
        if (total == Duration.zero || m.start < total)
          BookChapter(m.start, m.title.trim()),
    ];
  }

  Future<List<TagChapter>> _cue(MusicTrack t) async {
    final dot = t.relPath.lastIndexOf('.');
    final stem = dot > t.relPath.lastIndexOf('/')
        ? t.relPath.substring(0, dot)
        : t.relPath;
    for (final ext in const ['cue', 'CUE']) {
      VirtualFile? f;
      try {
        f = await files.open(t.sourceId, '$stem.$ext');
        final size = await f.length() ?? maxCueBytes;
        final bytes = await f.read(0, size.clamp(0, maxCueBytes));
        final text = utf8.decode(bytes, allowMalformed: true);
        final marks = parseCueSheet(text);
        if (marks.isNotEmpty) return marks;
      } on Exception {
        // No sheet with that name.
      } finally {
        await f?.close();
      }
    }
    return const [];
  }

  static String singleId(int itemId) => 'i:$itemId';
  static String folderId(int sourceId, String folder) => 'd:$sourceId:$folder';

  static (int, String)? _parseFolder(String id) {
    if (!id.startsWith('d:')) return null;
    final rest = id.substring(2);
    final colon = rest.indexOf(':');
    final source = int.tryParse(colon < 0 ? rest : rest.substring(0, colon));
    if (source == null || colon < 0) return null;
    return (source, rest.substring(colon + 1));
  }

  static Book _book(String id, List<MusicTrack> tracks) {
    final first = tracks.first;
    final folderName = first.parentPath.isEmpty
        ? null
        : first.parentPath.split('/').last;
    final title = first.album?.trim().isNotEmpty ?? false
        ? first.album!.trim()
        : (tracks.length > 1 && folderName != null ? folderName : first.title);
    return Book(
      id: id,
      title: title,
      author: first.albumArtist ?? first.artist,
      narrator: first.composer,
      tracks: tracks,
    );
  }
}
