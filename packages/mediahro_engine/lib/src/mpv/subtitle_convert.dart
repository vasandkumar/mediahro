/// Converts subtitle formats libmpv/FFmpeg cannot read into SRT for the
/// engine's renderer (SUB-010): TTML/DFXP, LRC (music videos) and plain-text
/// timestamp lists. SRT, WebVTT, ASS/SSA, SAMI and MicroDVD are read by
/// mpv directly.
///
/// Parsers are bounded (docs/13 parser limits): at most [maxCues] cues and
/// [maxInputChars] characters are read.
library;

const int maxCues = 100000;
const int maxInputChars = 20 * 1024 * 1024;

/// Subtitle file kinds the engine converts before loading.
enum ConvertedSubtitle { ttml, lrc, text, microDvd }

/// The conversion needed for [path], or null when mpv reads it natively.
ConvertedSubtitle? conversionFor(String path, {String? head}) {
  final p = path.toLowerCase();
  if (p.endsWith('.ttml') || p.endsWith('.dfxp')) return ConvertedSubtitle.ttml;
  if (p.endsWith('.xml') && head != null && head.contains('<tt')) {
    return ConvertedSubtitle.ttml;
  }
  if (p.endsWith('.lrc')) return ConvertedSubtitle.lrc;
  // MicroDVD shares `.sub` with VobSub; mpv probes it as the latter.
  if ((p.endsWith('.sub') || p.endsWith('.txt')) &&
      head != null &&
      RegExp('^\uFEFF?\\{\\d+\\}\\{\\d*\\}').hasMatch(head)) {
    return ConvertedSubtitle.microDvd;
  }
  if (p.endsWith('.txt')) return ConvertedSubtitle.text;
  return null;
}

/// One cue.
final class Cue {
  const Cue(this.start, this.end, this.text);
  final Duration start;
  final Duration end;
  final String text;
}

String convertToSrt(ConvertedSubtitle kind, String input, {double? videoFps}) {
  final text = input.length > maxInputChars
      ? input.substring(0, maxInputChars)
      : input;
  final cues = switch (kind) {
    ConvertedSubtitle.ttml => parseTtml(text),
    ConvertedSubtitle.lrc => parseLrc(text),
    ConvertedSubtitle.text => parseTimestampText(text),
    ConvertedSubtitle.microDvd => parseMicroDvd(text, videoFps: videoFps),
  };
  return toSrt(cues);
}

String toSrt(List<Cue> cues) {
  final b = StringBuffer();
  for (var i = 0; i < cues.length; i++) {
    final c = cues[i];
    b
      ..writeln(i + 1)
      ..writeln('${_srtTime(c.start)} --> ${_srtTime(c.end)}')
      ..writeln(c.text)
      ..writeln();
  }
  return b.toString();
}

String _srtTime(Duration d) {
  final ms = d.inMilliseconds;
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(ms ~/ 3600000)}:${two(ms ~/ 60000 % 60)}:'
      '${two(ms ~/ 1000 % 60)},${(ms % 1000).toString().padLeft(3, '0')}';
}

// ------------------------------------------------------------------ TTML --

/// TTML / DFXP `<p begin end|dur>` cues; `<br/>` becomes a line break, other
/// markup is stripped. Supports clock times (`hh:mm:ss.fff`, `hh:mm:ss:ff`
/// with `ttp:frameRate`) and offset times (`12.5s`, `500ms`, `30f`, `2t`).
List<Cue> parseTtml(String xml) {
  final frameRate =
      double.tryParse(
        RegExp(r'ttp:frameRate="(\d+(?:\.\d+)?)"').firstMatch(xml)?.group(1) ??
            '',
      ) ??
      30;
  final tickRate =
      double.tryParse(
        RegExp(r'ttp:tickRate="(\d+)"').firstMatch(xml)?.group(1) ?? '',
      ) ??
      10000000;
  Duration? time(String? v) =>
      v == null ? null : _ttmlTime(v, frameRate: frameRate, tickRate: tickRate);
  final cues = <Cue>[];
  final p = RegExp(r'<(?:\w+:)?p\b([^>]*)>(.*?)</(?:\w+:)?p>', dotAll: true);
  for (final m in p.allMatches(xml)) {
    final attrs = m.group(1)!;
    String? attr(String name) =>
        RegExp('\\b$name="([^"]*)"').firstMatch(attrs)?.group(1);
    final begin = time(attr('begin'));
    if (begin == null) continue;
    final end =
        time(attr('end')) ?? (begin + (time(attr('dur')) ?? Duration.zero));
    final body = m
        .group(2)!
        .replaceAll(RegExp(r'<(?:\w+:)?br\s*/?>'), '\n')
        .replaceAll(RegExp('<[^>]+>'), '')
        .split('\n')
        .map((l) => _xmlUnescape(l.trim()))
        .where((l) => l.isNotEmpty)
        .join('\n');
    if (body.isEmpty) continue;
    cues.add(Cue(begin, end, body));
    if (cues.length >= maxCues) break;
  }
  return cues;
}

Duration? _ttmlTime(
  String v, {
  required double frameRate,
  required double tickRate,
}) {
  final s = v.trim();
  final clock = RegExp(r'^(\d+):(\d{2}):(\d{2})(?:([.:])(\d+))?$')
      .firstMatch(s);
  if (clock != null) {
    final h = int.parse(clock.group(1)!);
    final m = int.parse(clock.group(2)!);
    final sec = int.parse(clock.group(3)!);
    var micros = (h * 3600 + m * 60 + sec) * 1000000;
    final frac = clock.group(5);
    if (frac != null) {
      micros += clock.group(4) == ':'
          ? (int.parse(frac) / frameRate * 1e6).round()
          : (double.parse('0.$frac') * 1e6).round();
    }
    return Duration(microseconds: micros);
  }
  final offset = RegExp(r'^(\d+(?:\.\d+)?)(h|m|s|ms|f|t)$').firstMatch(s);
  if (offset == null) return null;
  final n = double.parse(offset.group(1)!);
  final seconds = switch (offset.group(2)) {
    'h' => n * 3600,
    'm' => n * 60,
    's' => n,
    'ms' => n / 1000,
    'f' => n / frameRate,
    _ => n / tickRate,
  };
  return Duration(microseconds: (seconds * 1e6).round());
}

String _xmlUnescape(String s) => s
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"')
    .replaceAll('&apos;', "'")
    .replaceAll('&nbsp;', ' ')
    .replaceAll('&amp;', '&');

// ------------------------------------------------------------------- LRC --

/// LRC lyrics: `[mm:ss.xx]` lines (several stamps per line allowed),
/// `[offset:+/-ms]`; each line lasts until the next stamp (or 5 s).
/// Enhanced word stamps `<mm:ss.xx>` are stripped.
List<Cue> parseLrc(String text) {
  var offsetMs = 0;
  final stamped = <(Duration, String)>[];
  final stamp = RegExp(r'\[(\d+):(\d{1,2})(?:[.:](\d{1,3}))?\]');
  for (final raw in text.split(RegExp(r'\r?\n'))) {
    final line = raw.trim();
    final off = RegExp(
      r'^\[offset:\s*([+-]?\d+)\]',
      caseSensitive: false,
    ).firstMatch(line);
    if (off != null) {
      offsetMs = int.parse(off.group(1)!);
      continue;
    }
    final stamps = stamp.allMatches(line).toList();
    if (stamps.isEmpty || stamps.first.start != 0) continue;
    final lyric = line
        .substring(stamps.last.end)
        .replaceAll(RegExp(r'<\d+:\d{1,2}(?:[.:]\d{1,3})?>'), '')
        .trim();
    for (final m in stamps) {
      final frac = m.group(3) ?? '0';
      final ms =
          int.parse(m.group(1)!) * 60000 +
          int.parse(m.group(2)!) * 1000 +
          (int.parse(frac.padRight(3, '0').substring(0, 3)));
      // LRC offset: positive values make lyrics appear sooner.
      stamped.add((
        Duration(milliseconds: (ms - offsetMs).clamp(0, 1 << 40)),
        lyric,
      ));
    }
  }
  stamped.sort((a, b) => a.$1.compareTo(b.$1));
  final cues = <Cue>[];
  for (var i = 0; i < stamped.length && cues.length < maxCues; i++) {
    final (start, lyric) = stamped[i];
    if (lyric.isEmpty) continue;
    final end = i + 1 < stamped.length
        ? stamped[i + 1].$1
        : start + const Duration(seconds: 5);
    cues.add(Cue(start, end, lyric));
  }
  return cues;
}

// -------------------------------------------------------------- MicroDVD --

/// MicroDVD `{start}{end}text` frame-based cues; `|` separates lines. The
/// frame rate comes from a `{1}{1}fps` header, else [videoFps], else
/// 23.976.
List<Cue> parseMicroDvd(String text, {double? videoFps}) {
  final line = RegExp(r'^\{(\d+)\}\{(\d*)\}(.*)$');
  var fps = videoFps ?? 23.976;
  final cues = <Cue>[];
  for (final raw in text.split(RegExp(r'\r?\n'))) {
    final m = line.firstMatch(raw.trim().replaceFirst('\uFEFF', ''));
    if (m == null) continue;
    final start = int.parse(m.group(1)!);
    final end = int.tryParse(m.group(2)!) ?? start;
    final body = m.group(3)!;
    final header = double.tryParse(body.trim());
    if (start <= 1 && end <= 1 && header != null && header > 0) {
      fps = header;
      continue;
    }
    Duration at(int frame) =>
        Duration(microseconds: (frame / fps * 1e6).round());
    cues.add(
      Cue(
        at(start),
        at(end > start ? end : start + (fps * 3).round()),
        body.replaceAll(RegExp(r'\{[^}]*\}'), '').replaceAll('|', '\n'),
      ),
    );
    if (cues.length >= maxCues) break;
  }
  return cues;
}

// ------------------------------------------------------------------- TXT --

/// Plain text with a leading timestamp per line (`00:01:02 text`,
/// `1:02.5 text`, `[00:01:02] text`): the "TXT heuristics" of SUB-010.
/// Each line lasts until the next (at most 6 s).
List<Cue> parseTimestampText(String text) {
  final line = RegExp(
    r'^\[?(?:(\d+):)?(\d{1,2}):(\d{2})(?:[.,](\d{1,3}))?\]?\s+(.+)$',
  );
  final stamped = <(Duration, String)>[];
  for (final raw in text.split(RegExp(r'\r?\n'))) {
    final m = line.firstMatch(raw.trim());
    if (m == null) continue;
    final ms =
        int.parse(m.group(1) ?? '0') * 3600000 +
        int.parse(m.group(2)!) * 60000 +
        int.parse(m.group(3)!) * 1000 +
        int.parse((m.group(4) ?? '0').padRight(3, '0').substring(0, 3));
    stamped.add((
      Duration(milliseconds: ms),
      m.group(5)!.trim().replaceAll('|', '\n'),
    ));
  }
  final cues = <Cue>[];
  for (var i = 0; i < stamped.length && cues.length < maxCues; i++) {
    final (start, t) = stamped[i];
    var end = i + 1 < stamped.length
        ? stamped[i + 1].$1
        : start + const Duration(seconds: 6);
    if (end - start > const Duration(seconds: 6)) {
      end = start + const Duration(seconds: 6);
    }
    cues.add(Cue(start, end, t));
  }
  return cues;
}
