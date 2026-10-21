import 'package:mediahro/features/music/books/book.dart';
import 'package:mediahro/features/music/player/music_prefs.dart';

/// What the listener told Mediahro about books: which folders are books or
/// music, where each book stands, and its bookmarks (POD-001). Kept in the
/// library's settings table, so it travels with backups.
final class BookStore {
  BookStore(this.prefs, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final MusicPrefs prefs;
  final DateTime Function() _clock;

  static const _marks = 'books.marks';
  static const _lastSpeed = 'books.lastSpeed';

  /// Book id → `book` or `music`: the listener's answer to "is this an
  /// audiobook?", which wins over what the tags say.
  Future<Map<String, String>> marks() async => {
    for (final e in (await prefs.readMap(_marks) ?? const {}).entries)
      if (e.value == 'book' || e.value == 'music') e.key: e.value! as String,
  };

  /// Sets or, with null, clears the mark of [bookId].
  Future<void> setMark(String bookId, String? mark) async {
    final m = {...await marks()};
    if (mark == null) {
      m.remove(bookId);
    } else {
      m[bookId] = mark;
    }
    await prefs.write(_marks, m);
  }

  Future<BookProgress?> progress(String bookId) async {
    final j = await prefs.readMap('book.p.$bookId');
    return j == null ? null : BookProgress.fromJson(j);
  }

  Future<Map<String, BookProgress>> allProgress() async => {
    for (final e in (await prefs.readPrefix('book.p.')).entries)
      if (e.value case final Map<String, Object?> j)
        e.key: BookProgress.fromJson(j),
  };

  Future<void> saveProgress(String bookId, BookProgress p) async {
    await prefs.write(
      'book.p.$bookId',
      p.copyWith(updatedAt: _clock().toUtc()).toJson(),
    );
    await prefs.write(_lastSpeed, p.speed);
  }

  /// The speed a book never listened to starts at: the last one used.
  Future<double> lastSpeed() async =>
      (jsonDouble(await prefs.read(_lastSpeed)) ?? 1).clamp(0.5, 3.0);

  Future<List<BookBookmark>> bookmarks(String bookId) async {
    final l = await prefs.readList('book.b.$bookId') ?? const [];
    final out = [
      for (final v in l)
        if (v case final Map<String, Object?> j) BookBookmark.fromJson(j),
    ]..sort((a, b) => a.at.compareTo(b.at));
    return out;
  }

  Future<void> _saveBookmarks(String bookId, List<BookBookmark> l) =>
      prefs.write('book.b.$bookId', [for (final b in l) b.toJson()]);

  Future<BookBookmark> addBookmark(
    String bookId,
    Duration at, {
    String note = '',
  }) async {
    final all = await bookmarks(bookId);
    final now = _clock().toUtc();
    final b = BookBookmark(
      id: '${now.microsecondsSinceEpoch}',
      at: at,
      createdAt: now,
      note: note,
    );
    await _saveBookmarks(bookId, [...all, b]);
    return b;
  }

  Future<void> editBookmark(String bookId, String id, String note) async {
    final all = await bookmarks(bookId);
    await _saveBookmarks(bookId, [
      for (final b in all)
        if (b.id == id) b.withNote(note) else b,
    ]);
  }

  Future<void> removeBookmark(String bookId, String id) async {
    final all = await bookmarks(bookId);
    await _saveBookmarks(bookId, [
      for (final b in all)
        if (b.id != id) b,
    ]);
  }
}
