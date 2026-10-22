import 'dart:async';
import 'dart:math' as math;

import 'package:mediahro/core/library/queues.dart' show RepeatMode;
import 'package:mediahro/features/music/books/book.dart';
import 'package:mediahro/features/music/books/book_library.dart';
import 'package:mediahro/features/music/books/book_store.dart';
import 'package:mediahro/features/music/player/music_dsp.dart';
import 'package:mediahro/features/music/player/music_player.dart';
import 'package:mediahro/features/music/player/spoken_mode.dart';
import 'package:mediahro_engine/mediahro_engine.dart';
import 'package:meta/meta.dart';

/// What a book player shows (POD-001). Positions are global: the time since
/// the start of the book, across its files.
@immutable
final class BookPlayerState {
  const BookPlayerState({
    this.book,
    this.chapters = const [],
    this.bookmarks = const [],
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.speed = 1,
    this.skipSilence = false,
    this.playing = false,
    this.stopAtChapterEnd = false,
    this.finished = false,
  });

  final Book? book;
  final List<BookChapter> chapters;
  final List<BookBookmark> bookmarks;
  final Duration position;
  final Duration duration;
  final double speed;
  final bool skipSilence;
  final bool playing;

  /// Pause when the current chapter ends (the book's sleep timer).
  final bool stopAtChapterEnd;
  final bool finished;

  bool get active => book != null;

  /// The chapter the position is in, or -1 for a book without chapters.
  int get chapterIndex {
    var i = -1;
    for (final (n, c) in chapters.indexed) {
      if (c.start <= position) i = n;
    }
    return i;
  }

  BookChapter? get chapter => chapterIndex < 0 ? null : chapters[chapterIndex];

  Duration get chapterStart => chapter?.start ?? Duration.zero;

  Duration get chapterEnd {
    final next = chapterIndex + 1;
    return chapterIndex >= 0 && next < chapters.length
        ? chapters[next].start
        : duration;
  }

  /// Time left in the book at the current speed.
  Duration get remaining => Duration(
    microseconds: ((duration - position).inMicroseconds / speed).round().clamp(
      0,
      1 << 62,
    ),
  );

  BookPlayerState copyWith({
    Book? book,
    List<BookChapter>? chapters,
    List<BookBookmark>? bookmarks,
    Duration? position,
    Duration? duration,
    double? speed,
    bool? skipSilence,
    bool? playing,
    bool? stopAtChapterEnd,
    bool? finished,
  }) => BookPlayerState(
    book: book ?? this.book,
    chapters: chapters ?? this.chapters,
    bookmarks: bookmarks ?? this.bookmarks,
    position: position ?? this.position,
    duration: duration ?? this.duration,
    speed: speed ?? this.speed,
    skipSilence: skipSilence ?? this.skipSilence,
    playing: playing ?? this.playing,
    stopAtChapterEnd: stopAtChapterEnd ?? this.stopAtChapterEnd,
    finished: finished ?? this.finished,
  );
}

/// Audiobook mode on the music player (POD-001): a book plays as the queue
/// of its files, and this keeps what makes it a book. Where the listener
/// stands in it, its speed and skip-silence setting (remembered per book),
/// chapter navigation, bookmarks with notes, and "pause at the end of this
/// chapter".
///
/// The book is released, with the speed back to normal, as soon as the
/// player moves on to something that is not part of it.
final class BookPlayer {
  BookPlayer({
    required this.player,
    required this.engine,
    required this.dsp,
    required this.library,
    required this.store,
    this.saveEvery = const Duration(seconds: 5),
    SpokenMode? mode,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now,
       _mode = mode ?? SpokenMode();

  final MusicPlayer player;
  final PlaybackEngine engine;
  final MusicDsp dsp;
  final BookLibrary library;
  final BookStore store;
  final Duration saveEvery;
  final DateTime Function() _clock;
  final SpokenMode _mode;

  /// Less than this left counts as the end of the book.
  static const endMargin = Duration(seconds: 2);

  /// Pressing "previous chapter" this far into a chapter restarts it.
  static const restartAfter = Duration(seconds: 3);

  final _states = StreamController<BookPlayerState>.broadcast();
  BookPlayerState _state = const BookPlayerState();
  StreamSubscription<MusicPlayerState>? _sub;
  Future<void> _ops = Future.value();
  bool _opening = false;
  bool _wasPlaying = false;
  DateTime? _lastSave;
  int _lastIndex = -1;
  bool _disposed = false;

  BookPlayerState get state => _state;

  Stream<BookPlayerState> get states => Stream.multi((l) {
    l.add(_state);
    final s = _states.stream.listen(l.add, onDone: l.close);
    l.onCancel = s.cancel;
  });

  /// Plays [book] from where the listener left it, or from [at] when given.
  /// A finished book starts again from the beginning. With [autoplay] false
  /// it opens paused.
  Future<void> open(Book book, {Duration? at, bool autoplay = true}) =>
      _serial(() async {
        if (_state.active && _state.book!.id != book.id) await _release();
        _mode.claim(this);
        final stored = await store.progress(book.id);
        final speed = stored?.speed ?? await store.lastSpeed();
        var progress = (stored ?? BookProgress(speed: speed)).copyWith(
          speed: speed,
        );
        if (progress.finished) {
          progress = progress.copyWith(
            trackIndex: 0,
            position: Duration.zero,
            finished: false,
          );
        }
        var index = progress.trackIndex.clamp(0, book.tracks.length - 1);
        var local = progress.position;
        if (at != null) (index, local) = book.locate(at);
        final chapters = await library.chapters(book);
        final bookmarks = await store.bookmarks(book.id);
        _opening = true;
        try {
          _lastIndex = index;
          _set(
            BookPlayerState(
              book: book,
              chapters: chapters,
              bookmarks: bookmarks,
              position: book.globalOf(index, local),
              duration: book.duration,
              speed: progress.speed,
              skipSilence: progress.skipSilence,
            ),
          );
          await dsp.setSkipSilence(enabled: progress.skipSilence);
          await player.playTracks(
            book.tracks,
            start: index,
            startPosition: local,
            autoplay: autoplay,
          );
          if (player.state.repeat != RepeatMode.off) {
            await player.setRepeat(RepeatMode.off);
          }
          await engine.setRate(progress.speed);
        } finally {
          _opening = false;
        }
        _sub ??= player.states.listen(_onPlayer);
        await _save(force: true);
        _set(_state.copyWith(playing: autoplay));
      });

  Future<void> play() => _serial(() async {
    if (!_state.active) return;
    if (_state.finished) {
      await _seek(Duration.zero);
    }
    await player.play();
  });

  Future<void> pause() => _serial(() async {
    if (_state.active) await player.pause();
  });

  Future<void> togglePlayPause() => _state.playing ? pause() : play();

  Future<void> seek(Duration position) => _serial(() => _seek(position));

  /// Forwards or, negative, back by [by] (the 30 s buttons).
  Future<void> skip(Duration by) => _serial(() => _seek(_state.position + by));

  Future<void> nextChapter() => _serial(() async {
    final i = _state.chapterIndex + 1;
    if (i > 0 && i < _state.chapters.length) {
      await _seek(_state.chapters[i].start);
    }
  });

  /// Restarts the chapter after a few seconds of it, else goes to the
  /// previous one.
  Future<void> previousChapter() => _serial(() async {
    final i = _state.chapterIndex;
    if (i < 0) return;
    final into = _state.position - _state.chapterStart;
    // A few seconds of the recording, whatever the speed.
    final threshold = Duration(
      microseconds: (restartAfter.inMicroseconds * _state.speed).round(),
    );
    if (into > threshold || i == 0) {
      await _seek(_state.chapterStart);
    } else {
      await _seek(_state.chapters[i - 1].start);
    }
  });

  Future<void> toChapter(int index) => _serial(() async {
    if (index >= 0 && index < _state.chapters.length) {
      await _seek(_state.chapters[index].start);
    }
  });

  /// 0.5 to 3, remembered for this book and offered to the next new one.
  Future<void> setSpeed(double speed) => _serial(() async {
    final book = _state.book;
    if (book == null) return;
    final s = speed.clamp(0.5, 3.0);
    // The wanted speed first: the engine's own report of it must not look
    // like a speed that fell back.
    _set(_state.copyWith(speed: s));
    await engine.setRate(s);
    await _save(force: true);
  });

  Future<void> setSkipSilence({required bool enabled}) => _serial(() async {
    if (!_state.active) return;
    await dsp.setSkipSilence(enabled: enabled);
    _set(_state.copyWith(skipSilence: enabled));
    await _save(force: true);
  });

  /// Pauses when the current chapter ends (once).
  Future<void> setStopAtChapterEnd({required bool enabled}) async {
    if (!_state.active) return;
    _set(_state.copyWith(stopAtChapterEnd: enabled));
  }

  /// Marks the current place; [note] is optional.
  Future<BookBookmark?> addBookmark({String note = ''}) async {
    final book = _state.book;
    if (book == null) return null;
    final b = await store.addBookmark(book.id, _state.position, note: note);
    _set(_state.copyWith(bookmarks: await store.bookmarks(book.id)));
    return b;
  }

  Future<void> editBookmark(String id, String note) async {
    final book = _state.book;
    if (book == null) return;
    await store.editBookmark(book.id, id, note);
    _set(_state.copyWith(bookmarks: await store.bookmarks(book.id)));
  }

  Future<void> removeBookmark(String id) async {
    final book = _state.book;
    if (book == null) return;
    await store.removeBookmark(book.id, id);
    _set(_state.copyWith(bookmarks: await store.bookmarks(book.id)));
  }

  Future<void> goToBookmark(BookBookmark b) => seek(b.at);

  Future<void> dispose() async {
    _disposed = true;
    await _sub?.cancel();
    if (_state.active) await _save(force: true);
    await _states.close();
  }

  // ------------------------------------------------------------ internals --

  Future<void> _seek(Duration to) async {
    final book = _state.book;
    if (book == null) return;
    final total = _state.duration;
    final target = Duration(
      microseconds: to.inMicroseconds.clamp(
        0,
        math.max(0, total.inMicroseconds - 1),
      ),
    );
    final (index, local) = book.locate(target);
    final wasPlaying = _state.playing;
    if (index == player.state.index) {
      await player.seek(local);
    } else {
      _lastIndex = index;
      await player.jumpTo(index);
      await player.seek(local);
      if (!wasPlaying) await player.pause();
    }
    _set(_state.copyWith(position: target, finished: false));
    await _save(force: true);
  }

  void _onPlayer(MusicPlayerState s) {
    final book = _state.book;
    if (book == null || _opening || _disposed) return;
    final current = s.current;
    // A station or an episode plays: the queue (the book) is waiting.
    if (s.live ||
        s.spoken ||
        current == null ||
        !book.tracks.any((t) => t.itemId == current.itemId)) {
      unawaited(_serial(_release));
      return;
    }
    final index = book.tracks.indexWhere((t) => t.itemId == current.itemId);
    final global = book.globalOf(index, s.position);
    final playing = s.playing;
    final ended =
        s.playback.status == PlaybackStatus.ended &&
        index == book.tracks.length - 1;
    final finished =
        ended ||
        (_state.duration > Duration.zero &&
            global >= _state.duration - endMargin &&
            !playing);
    _set(
      _state.copyWith(
        position: finished ? _state.duration : global,
        playing: playing,
        finished: finished,
        duration: _state.duration == Duration.zero
            ? (s.playback.duration ?? Duration.zero)
            : null,
      ),
    );
    // The speed belongs to the book: the engine may have reset it on a new
    // item.
    if (engine.current.rate != _state.speed &&
        s.playback.status != PlaybackStatus.idle) {
      unawaited(engine.setRate(_state.speed));
    }
    if (_state.stopAtChapterEnd &&
        playing &&
        _state.chapterIndex >= 0 &&
        global >= _state.chapterEnd - const Duration(milliseconds: 300)) {
      _set(_state.copyWith(stopAtChapterEnd: false));
      unawaited(player.pause());
    }
    final moved = index != _lastIndex;
    _lastIndex = index;
    if (moved || (_wasPlaying && !playing) || finished) {
      unawaited(_save(force: true));
    } else if (playing) {
      unawaited(_save());
    }
    _wasPlaying = playing;
  }

  /// Writes the place, and the settings that go with it, when [force] or
  /// [saveEvery] has passed.
  Future<void> _save({bool force = false}) async {
    final book = _state.book;
    if (book == null) return;
    final now = _clock();
    final last = _lastSave;
    if (!force && last != null && now.difference(last) < saveEvery) return;
    _lastSave = now;
    final (index, local) = book.locate(
      _state.finished ? Duration.zero : _state.position,
    );
    await store.saveProgress(
      book.id,
      BookProgress(
        trackIndex: index,
        position: local,
        speed: _state.speed,
        skipSilence: _state.skipSilence,
        finished: _state.finished,
      ),
    );
  }

  /// Leaves book mode: saves, and gives the music player its normal speed
  /// and silences back.
  Future<void> _release() async {
    if (!_state.active) return;
    await _save(force: true);
    _lastSave = null;
    _wasPlaying = false;
    _set(const BookPlayerState());
    if (_mode.release(this)) {
      await dsp.setSkipSilence(enabled: false);
      await engine.setRate(1);
    }
  }

  Future<void> _serial(Future<void> Function() op) {
    final f = _ops.then((_) => op());
    _ops = f.catchError((Object _) {});
    return f;
  }

  void _set(BookPlayerState s) {
    _state = s;
    if (!_states.isClosed) _states.add(s);
  }
}
