import 'package:mediahro/features/music/library/music_library.dart';
import 'package:meta/meta.dart';

/// An audiobook (POD-001): one M4B/M4A/MP3 file, or a folder of files played
/// in order. Positions inside a book are "global": the time since the start
/// of the book, across its files.
@immutable
final class Book {
  const Book({
    required this.id,
    required this.title,
    required this.tracks,
    this.author,
    this.narrator,
  });

  /// `i:<item id>` for a single file, `d:<source id>:<folder>` for a folder.
  final String id;
  final String title;
  final String? author;
  final String? narrator;

  /// In playing order; never empty.
  final List<MusicTrack> tracks;

  bool get singleFile => tracks.length == 1;
  int get coverItemId => tracks.first.itemId;

  /// Where each file starts, by the lengths the library knows.
  List<Duration> get offsets {
    var at = Duration.zero;
    return [
      for (final t in tracks)
        () {
          final start = at;
          at += t.duration ?? Duration.zero;
          return start;
        }(),
    ];
  }

  Duration get duration =>
      tracks.fold(Duration.zero, (a, t) => a + (t.duration ?? Duration.zero));

  /// The file and the time inside it for a global [position].
  (int, Duration) locate(Duration position) {
    final starts = offsets;
    var i = starts.length - 1;
    while (i > 0 && starts[i] > position) {
      i--;
    }
    return (i, position - starts[i]);
  }

  /// Global time of [position] inside file [index].
  Duration globalOf(int index, Duration position) =>
      offsets[index.clamp(0, tracks.length - 1)] + position;
}

/// A chapter of a book, from the file (MP4 chapters, ID3 CHAP, OverDrive
/// markers), a CUE sheet, or the files of a folder book.
@immutable
final class BookChapter {
  const BookChapter(this.start, this.title);

  final Duration start;
  final String title;

  @override
  bool operator ==(Object other) =>
      other is BookChapter && other.start == start && other.title == title;

  @override
  int get hashCode => Object.hash(start, title);

  @override
  String toString() => 'BookChapter($start, $title)';
}

/// The listener's place in a book, remembered per book.
@immutable
final class BookProgress {
  const BookProgress({
    this.trackIndex = 0,
    this.position = Duration.zero,
    this.speed = 1,
    this.skipSilence = false,
    this.finished = false,
    this.updatedAt,
  });

  factory BookProgress.fromJson(Map<String, Object?> j) => BookProgress(
    trackIndex: (j['track'] as num?)?.toInt() ?? 0,
    position: Duration(milliseconds: (j['ms'] as num?)?.toInt() ?? 0),
    speed: ((j['speed'] as num?)?.toDouble() ?? 1).clamp(0.5, 3.0),
    skipSilence: j['skip'] == true,
    finished: j['done'] == true,
    updatedAt: j['at'] is int
        ? DateTime.fromMillisecondsSinceEpoch(j['at']! as int, isUtc: true)
        : null,
  );

  /// The file of the book and the time inside it.
  final int trackIndex;
  final Duration position;
  final double speed;
  final bool skipSilence;
  final bool finished;
  final DateTime? updatedAt;

  bool get started => trackIndex > 0 || position > Duration.zero;

  BookProgress copyWith({
    int? trackIndex,
    Duration? position,
    double? speed,
    bool? skipSilence,
    bool? finished,
    DateTime? updatedAt,
  }) => BookProgress(
    trackIndex: trackIndex ?? this.trackIndex,
    position: position ?? this.position,
    speed: speed ?? this.speed,
    skipSilence: skipSilence ?? this.skipSilence,
    finished: finished ?? this.finished,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  Map<String, Object?> toJson() => {
    'track': trackIndex,
    'ms': position.inMilliseconds,
    'speed': speed,
    'skip': skipSilence,
    'done': finished,
    'at': updatedAt?.toUtc().millisecondsSinceEpoch,
  };
}

/// A place the listener marked, with an optional note (POD-001).
@immutable
final class BookBookmark {
  const BookBookmark({
    required this.id,
    required this.at,
    required this.createdAt,
    this.note = '',
  });

  factory BookBookmark.fromJson(Map<String, Object?> j) => BookBookmark(
    id: '${j['id']}',
    at: Duration(milliseconds: (j['ms'] as num?)?.toInt() ?? 0),
    note: j['note'] is String ? j['note']! as String : '',
    createdAt: DateTime.fromMillisecondsSinceEpoch(
      (j['created'] as num?)?.toInt() ?? 0,
      isUtc: true,
    ),
  );

  final String id;

  /// Global position in the book.
  final Duration at;
  final String note;
  final DateTime createdAt;

  BookBookmark withNote(String note) =>
      BookBookmark(id: id, at: at, createdAt: createdAt, note: note);

  Map<String, Object?> toJson() => {
    'id': id,
    'ms': at.inMilliseconds,
    'note': note,
    'created': createdAt.toUtc().millisecondsSinceEpoch,
  };
}
