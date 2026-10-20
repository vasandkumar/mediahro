import 'package:meta/meta.dart';

/// One timed word of an enhanced LRC line (`<mm:ss.xx>word`).
@immutable
final class LyricWord {
  const LyricWord(this.time, this.text);

  final Duration time;
  final String text;

  @override
  bool operator ==(Object other) =>
      other is LyricWord && other.time == time && other.text == text;

  @override
  int get hashCode => Object.hash(time, text);
}

/// One lyric line; [time] is null for unsynced lyrics.
@immutable
final class LyricLine {
  const LyricLine(this.text, {this.time, this.words = const []});

  final Duration? time;
  final String text;

  /// Word timings (enhanced LRC, karaoke); empty when not word-synced.
  final List<LyricWord> words;

  LyricLine withTime(Duration? t) => LyricLine(text, time: t, words: words);

  @override
  bool operator ==(Object other) =>
      other is LyricLine &&
      other.time == time &&
      other.text == text &&
      _listEq(other.words, words);

  @override
  int get hashCode => Object.hash(time, text, Object.hashAll(words));

  @override
  String toString() => 'LyricLine($time, $text)';
}

/// Where lyrics came from (shown in the lyrics view).
enum LyricsOrigin { edited, sidecar, embedded, online }

/// Lyrics of a song (MUS-005).
@immutable
final class Lyrics {
  const Lyrics(
    this.lines, {
    this.origin = LyricsOrigin.embedded,
    this.title,
    this.artist,
    this.album,
  });

  final List<LyricLine> lines;
  final LyricsOrigin origin;
  final String? title;
  final String? artist;
  final String? album;

  /// True when every line with text has a time.
  bool get synced =>
      lines.isNotEmpty && lines.every((l) => l.time != null || l.text.isEmpty);

  bool get wordSynced => lines.any((l) => l.words.isNotEmpty);

  bool get isEmpty => lines.every((l) => l.text.trim().isEmpty);

  /// Index of the line playing at [position], or -1 before the first.
  int lineAt(Duration position) {
    var found = -1;
    for (var i = 0; i < lines.length; i++) {
      final t = lines[i].time;
      if (t == null) continue;
      if (t <= position) {
        found = i;
      } else {
        break;
      }
    }
    return found;
  }

  Lyrics copyWith({List<LyricLine>? lines, LyricsOrigin? origin}) => Lyrics(
    lines ?? this.lines,
    origin: origin ?? this.origin,
    title: title,
    artist: artist,
    album: album,
  );

  /// Plain text, one line per lyric line.
  String toPlainText() => lines.map((l) => l.text).join('\n');
}

final _stamp = RegExp(r'\[(\d{1,3}):(\d{1,2})(?:[.:](\d{1,3}))?\]');
final _wordStamp = RegExp(r'<(\d{1,3}):(\d{1,2})(?:[.:](\d{1,3}))?>');
final _meta = RegExp(r'^\[([a-zA-Z]+):(.*)\]\s*$');

Duration _clock(String m, String s, String? frac) {
  var ms = 0;
  if (frac != null) {
    // .x = tenths, .xx = hundredths, .xxx = thousandths.
    ms = int.parse(frac.padRight(3, '0').substring(0, 3));
  }
  return Duration(
    minutes: int.parse(m),
    seconds: int.parse(s),
    milliseconds: ms,
  );
}

/// Parses LRC (simple and enhanced) or plain text. Lines with several
/// timestamps are repeated; `[offset:+/-ms]` is applied (positive offset =
/// lyrics earlier, per the LRC convention). Limits: 20 000 lines.
Lyrics parseLyrics(String text, {LyricsOrigin origin = LyricsOrigin.embedded}) {
  final out = <LyricLine>[];
  var offset = Duration.zero;
  String? title;
  String? artist;
  String? album;
  var anyStamp = false;
  final rawLines = text
      .replaceAll('\r\n', '\n')
      .replaceAll('\r', '\n')
      .split('\n');
  for (final raw in rawLines.take(20000)) {
    final line = raw.trimRight();
    final meta = _meta.firstMatch(line.trim());
    if (meta != null && !_stamp.hasMatch(line)) {
      final key = meta.group(1)!.toLowerCase();
      final value = meta.group(2)!.trim();
      switch (key) {
        case 'offset':
          offset = Duration(milliseconds: int.tryParse(value) ?? 0);
        case 'ti':
          title = value;
        case 'ar':
          artist = value;
        case 'al':
          album = value;
      }
      continue;
    }
    final stamps = <Duration>[];
    var rest = line.trimLeft();
    while (true) {
      final m = _stamp.matchAsPrefix(rest);
      if (m == null) break;
      stamps.add(_clock(m.group(1)!, m.group(2)!, m.group(3)));
      rest = rest.substring(m.end).trimLeft();
    }
    final (lyric, words) = _words(rest);
    if (stamps.isEmpty) {
      out.add(LyricLine(lyric, words: words));
    } else {
      anyStamp = true;
      for (final s in stamps) {
        out.add(LyricLine(lyric, time: s, words: words));
      }
    }
  }
  var lines = out;
  if (anyStamp) {
    // Synced: drop untimed lines (comments, blanks) and sort; apply offset.
    lines = [
      for (final l in out)
        if (l.time != null)
          LyricLine(
            l.text,
            time: _nonNegative(l.time! - offset),
            words: [
              for (final w in l.words)
                LyricWord(_nonNegative(w.time - offset), w.text),
            ],
          ),
    ]..sort((a, b) => a.time!.compareTo(b.time!));
  } else {
    // Plain: trim leading and trailing blank lines.
    while (lines.isNotEmpty && lines.first.text.trim().isEmpty) {
      lines = lines.sublist(1);
    }
    while (lines.isNotEmpty && lines.last.text.trim().isEmpty) {
      lines = lines.sublist(0, lines.length - 1);
    }
  }
  return Lyrics(
    List.unmodifiable(lines),
    origin: origin,
    title: title,
    artist: artist,
    album: album,
  );
}

(String, List<LyricWord>) _words(String rest) {
  if (!_wordStamp.hasMatch(rest)) return (rest, const []);
  final words = <LyricWord>[];
  final text = StringBuffer();
  final matches = _wordStamp.allMatches(rest).toList();
  if (matches.first.start > 0) {
    text.write(rest.substring(0, matches.first.start));
  }
  for (var i = 0; i < matches.length; i++) {
    final m = matches[i];
    final end = i + 1 < matches.length ? matches[i + 1].start : rest.length;
    final word = rest.substring(m.end, end);
    text.write(word);
    if (word.trim().isNotEmpty) {
      words.add(LyricWord(_clock(m.group(1)!, m.group(2)!, m.group(3)), word));
    }
  }
  return (text.toString().replaceAll(RegExp(r'\s+'), ' ').trim(), words);
}

Duration _nonNegative(Duration d) => d.isNegative ? Duration.zero : d;

/// Serialises synced lyrics as LRC (enhanced when word timings exist), or
/// plain text when unsynced.
String toLrc(Lyrics l) {
  final b = StringBuffer();
  if (l.title != null) b.writeln('[ti:${l.title}]');
  if (l.artist != null) b.writeln('[ar:${l.artist}]');
  if (l.album != null) b.writeln('[al:${l.album}]');
  for (final line in l.lines) {
    final t = line.time;
    if (t != null) b.write('[${_fmt(t)}]');
    if (line.words.isNotEmpty) {
      for (final w in line.words) {
        b.write('<${_fmt(w.time)}>${w.text}');
      }
      b.writeln();
    } else {
      b.writeln(line.text);
    }
  }
  return b.toString();
}

String _fmt(Duration d) {
  final m = d.inMinutes.toString().padLeft(2, '0');
  final s = (d.inSeconds % 60).toString().padLeft(2, '0');
  final cs = ((d.inMilliseconds % 1000) ~/ 10).toString().padLeft(2, '0');
  return '$m:$s.$cs';
}

bool _listEq<T>(List<T> a, List<T> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// Tap-to-time LRC creation (MUS-005 "LRC editor/creator"): each tap stamps
/// the next line with the current playback position.
final class LrcEditorModel {
  LrcEditorModel(Lyrics source)
    : lines = [for (final l in source.lines) l],
      meta = source;

  final List<LyricLine> lines;
  final Lyrics meta;

  /// The next line to stamp.
  int cursor = 0;

  bool get done => cursor >= lines.length;

  /// Stamps the current line with [position] and moves on; blank lines are
  /// skipped.
  void tap(Duration position) {
    while (!done && lines[cursor].text.trim().isEmpty) {
      cursor++;
    }
    if (done) return;
    lines[cursor] = LyricLine(lines[cursor].text, time: position);
    cursor++;
  }

  /// Steps back one line and clears its time (undo).
  void back() {
    if (cursor == 0) return;
    cursor--;
    lines[cursor] = lines[cursor].withTime(null);
  }

  /// Nudges one line's time by [by].
  void nudge(int index, Duration by) {
    final t = lines[index].time;
    if (t == null) return;
    final n = t + by;
    lines[index] = lines[index].withTime(n.isNegative ? Duration.zero : n);
  }

  void editText(int index, String text) =>
      lines[index] = LyricLine(text, time: lines[index].time);

  Lyrics result() => Lyrics(
    [
      for (final l in lines)
        if (l.text.trim().isNotEmpty || l.time != null) l,
    ],
    origin: LyricsOrigin.edited,
    title: meta.title,
    artist: meta.artist,
    album: meta.album,
  );
}
