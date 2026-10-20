import 'package:mediahro_subtitles/src/subtitle_parser.dart';

// Text-subtitle parsers and writers for the editor (SUB-030) and the
// on-device pipelines (SUB-040, 050, 051, 052, 053). Playback parsing is
// libass/FFmpeg's (B1); these are pure, bounded by [ParseLimits], and run in
// an isolate through `parseSubtitlesIsolated` (PRIV-005).

final _lines = RegExp(r'\r\n|\r|\n');

List<String> _splitLines(String text) =>
    text.replaceFirst('﻿', '').split(_lines);

void _checkCount(List<SubtitleCue> cues, ParseLimits limits) {
  if (cues.length > limits.maxCues) {
    throw SubtitleParseException('more than ${limits.maxCues} cues');
  }
}

void _checkSize(String text, ParseLimits limits) {
  // Characters, not bytes: a cheap upper bound before parsing.
  if (text.length > limits.maxBytes) {
    throw const SubtitleParseException('file too large');
  }
}

String _two(int v) => v.toString().padLeft(2, '0');
String _three(int v) => v.toString().padLeft(3, '0');

/// `01:02:03,456` (SRT) or `01:02:03.456` (WebVTT).
String formatClock(Duration d, {String separator = ','}) {
  final ms = d.inMilliseconds < 0 ? 0 : d.inMilliseconds;
  final h = ms ~/ 3600000;
  final m = ms ~/ 60000 % 60;
  final s = ms ~/ 1000 % 60;
  return '${_two(h)}:${_two(m)}:${_two(s)}$separator${_three(ms % 1000)}';
}

/// `1:02:03.45` (ASS centiseconds).
String formatAssClock(Duration d) {
  final cs = (d.inMilliseconds < 0 ? 0 : d.inMilliseconds) ~/ 10;
  final h = cs ~/ 360000;
  final m = cs ~/ 6000 % 60;
  final s = cs ~/ 100 % 60;
  return '$h:${_two(m)}:${_two(s)}.${_two(cs % 100)}';
}

final _clock = RegExp(
  r'^\s*(?:(\d+):)?(\d{1,2}):(\d{1,2})(?:[.,:](\d{1,3}))?\s*$',
);

/// Parses `h:mm:ss,ms`, `mm:ss.ms`, `h:mm:ss.cc` (fraction digits scale:
/// 1 → tenths, 2 → hundredths, 3 → ms). Null when malformed.
Duration? parseClock(String s) {
  final m = _clock.firstMatch(s);
  if (m == null) return null;
  final h = int.parse(m.group(1) ?? '0');
  final min = int.parse(m.group(2)!);
  final sec = int.parse(m.group(3)!);
  final frac = m.group(4);
  final ms = frac == null
      ? 0
      : int.parse(frac) *
            switch (frac.length) {
              1 => 100,
              2 => 10,
              _ => 1,
            };
  if (min > 59 || sec > 59) return null;
  return Duration(hours: h, minutes: min, seconds: sec, milliseconds: ms);
}

// ------------------------------------------------------------------ SRT

final class SrtParser implements SubtitleParser {
  const SrtParser();

  @override
  Set<SubtitleFormat> get formats => const {SubtitleFormat.srt};

  static final _arrow = RegExp(r'^(.+?)\s*-->\s*(\S+)');

  @override
  SubtitleDocument parse(
    String text, {
    ParseLimits limits = const ParseLimits(),
  }) {
    _checkSize(text, limits);
    final cues = <SubtitleCue>[];
    final lines = _splitLines(text);
    var i = 0;
    while (i < lines.length) {
      final m = _arrow.firstMatch(lines[i].trim());
      final start = m == null ? null : parseClock(m.group(1)!);
      final end = m == null ? null : parseClock(m.group(2)!);
      if (start == null || end == null) {
        i++;
        continue;
      }
      i++;
      final body = <String>[];
      while (i < lines.length && lines[i].trim().isNotEmpty) {
        // A following cue without a blank line in between.
        if (_arrow.hasMatch(lines[i].trim()) && body.isNotEmpty) break;
        body.add(lines[i].trimRight());
        i++;
      }
      // A bare index line before the next cue belongs to it, not to us.
      if (body.isNotEmpty &&
          i < lines.length &&
          RegExp(r'^\d+$').hasMatch(body.last.trim()) &&
          _arrow.hasMatch(lines[i].trim())) {
        body.removeLast();
      }
      cues.add(SubtitleCue(start: start, end: end, text: body.join('\n')));
      _checkCount(cues, limits);
    }
    return SubtitleDocument(format: SubtitleFormat.srt, cues: cues);
  }

  @override
  String write(SubtitleDocument document) {
    final out = StringBuffer();
    var n = 1;
    for (final c in document.cues) {
      out
        ..writeln(n++)
        ..writeln('${formatClock(c.start)} --> ${formatClock(c.end)}')
        ..writeln(_asHtml(c.text, document.format))
        ..writeln();
    }
    return out.toString();
  }
}

/// ASS override tags to the HTML subset SRT/WebVTT players understand.
String _asHtml(String text, SubtitleFormat from) {
  if (from != SubtitleFormat.ass && from != SubtitleFormat.ssa) return text;
  return text
      .replaceAll(r'{\i1}', '<i>')
      .replaceAll(r'{\i0}', '</i>')
      .replaceAll(r'{\b1}', '<b>')
      .replaceAll(r'{\b0}', '</b>')
      .replaceAll(RegExp(r'\{[^}]*\}'), '')
      .replaceAll(r'\N', '\n')
      .replaceAll(r'\n', '\n')
      .replaceAll(r'\h', ' ');
}

// --------------------------------------------------------------- WebVTT

final class WebVttParser implements SubtitleParser {
  const WebVttParser();

  @override
  Set<SubtitleFormat> get formats => const {SubtitleFormat.webvtt};

  static final _arrow = RegExp(r'^(\S+)\s*-->\s*(\S+)(.*)$');

  @override
  SubtitleDocument parse(
    String text, {
    ParseLimits limits = const ParseLimits(),
  }) {
    _checkSize(text, limits);
    final lines = _splitLines(text);
    if (lines.isEmpty || !lines.first.trimLeft().startsWith('WEBVTT')) {
      throw const SubtitleParseException('missing WEBVTT header');
    }
    final cues = <SubtitleCue>[];
    var i = 1;
    while (i < lines.length) {
      final line = lines[i].trim();
      if (line.isEmpty) {
        i++;
        continue;
      }
      if (line.startsWith('NOTE') ||
          line.startsWith('STYLE') ||
          line.startsWith('REGION')) {
        while (i < lines.length && lines[i].trim().isNotEmpty) {
          i++;
        }
        continue;
      }
      String? id;
      var m = _arrow.firstMatch(line);
      if (m == null && i + 1 < lines.length) {
        id = line;
        i++;
        m = _arrow.firstMatch(lines[i].trim());
      }
      final start = m == null ? null : parseClock(m.group(1)!);
      final end = m == null ? null : parseClock(m.group(2)!);
      i++;
      final body = <String>[];
      while (i < lines.length && lines[i].trim().isNotEmpty) {
        body.add(lines[i].trimRight());
        i++;
      }
      if (start == null || end == null) continue;
      final settings = m!.group(3)!.trim();
      cues.add(
        SubtitleCue(
          start: start,
          end: end,
          text: body.join('\n'),
          extra: {'id': ?id, if (settings.isNotEmpty) 'settings': settings},
        ),
      );
      _checkCount(cues, limits);
    }
    return SubtitleDocument(format: SubtitleFormat.webvtt, cues: cues);
  }

  @override
  String write(SubtitleDocument document) {
    final out = StringBuffer('WEBVTT\n\n');
    for (final c in document.cues) {
      if (c.extra['id'] case final id?) out.writeln(id);
      final settings = c.extra['settings'];
      out
        ..writeln(
          '${formatClock(c.start, separator: '.')} --> '
          '${formatClock(c.end, separator: '.')}'
          '${settings == null ? '' : ' $settings'}',
        )
        ..writeln(_asHtml(c.text, document.format))
        ..writeln();
    }
    return out.toString();
  }
}

// -------------------------------------------------------------- ASS/SSA

final class AssParser implements SubtitleParser {
  const AssParser();

  @override
  Set<SubtitleFormat> get formats => const {
    SubtitleFormat.ass,
    SubtitleFormat.ssa,
  };

  static const _defaultFormat = [
    'Layer', 'Start', 'End', 'Style', 'Name', 'MarginL', 'MarginR', //
    'MarginV', 'Effect', 'Text',
  ];

  @override
  SubtitleDocument parse(
    String text, {
    ParseLimits limits = const ParseLimits(),
  }) {
    _checkSize(text, limits);
    final lines = _splitLines(text);
    final header = StringBuffer();
    final cues = <SubtitleCue>[];
    var inEvents = false;
    var ssa = false;
    var fields = _defaultFormat;
    for (final raw in lines) {
      final line = raw.trimRight();
      final t = line.trim();
      if (t.startsWith('[') && t.endsWith(']')) {
        inEvents = t.toLowerCase() == '[events]';
        if (!inEvents) header.writeln(line);
        continue;
      }
      if (!inEvents) {
        if (t.toLowerCase().startsWith('scripttype:') &&
            t.toLowerCase().contains('v4.00') &&
            !t.contains('+')) {
          ssa = true;
        }
        header.writeln(line);
        continue;
      }
      final colon = t.indexOf(':');
      if (colon < 0) continue;
      final kind = t.substring(0, colon).trim().toLowerCase();
      final value = t.substring(colon + 1).trimLeft();
      if (kind == 'format') {
        fields = [for (final f in value.split(',')) f.trim()];
        continue;
      }
      if (kind != 'dialogue') continue;
      final parts = _splitFields(value, fields.length);
      String field(String name) {
        final i = fields.indexWhere(
          (f) => f.toLowerCase() == name.toLowerCase(),
        );
        return i < 0 || i >= parts.length ? '' : parts[i];
      }

      final start = parseClock(field('Start'));
      final end = parseClock(field('End'));
      if (start == null || end == null) continue;
      cues.add(
        SubtitleCue(
          start: start,
          end: end,
          text: field('Text'),
          style: field('Style'),
          extra: {
            for (final f in fields)
              if (!const {
                'start',
                'end',
                'style',
                'text',
              }.contains(f.toLowerCase()))
                f: field(f),
          },
        ),
      );
      _checkCount(cues, limits);
    }
    return SubtitleDocument(
      format: ssa ? SubtitleFormat.ssa : SubtitleFormat.ass,
      cues: cues,
      header: header.toString().trimRight(),
    );
  }

  /// Splits on the first `count - 1` commas: the text keeps its commas.
  static List<String> _splitFields(String value, int count) {
    final out = <String>[];
    var rest = value;
    for (var i = 0; i < count - 1; i++) {
      final c = rest.indexOf(',');
      if (c < 0) break;
      out.add(rest.substring(0, c).trim());
      rest = rest.substring(c + 1);
    }
    out.add(rest);
    return out;
  }

  static const defaultHeader =
      '[Script Info]\n'
      'ScriptType: v4.00+\n'
      'PlayResX: 1920\n'
      'PlayResY: 1080\n'
      'WrapStyle: 0\n'
      'ScaledBorderAndShadow: yes\n'
      '\n'
      '[V4+ Styles]\n'
      'Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, '
      'OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, '
      'ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, '
      'Alignment, MarginL, MarginR, MarginV, Encoding\n'
      // The style line is one comma-separated record.
      // ignore: missing_whitespace_between_adjacent_strings
      'Style: Default,Arial,64,&H00FFFFFF,&H000000FF,&H00000000,&H64000000,'
      '0,0,0,0,100,100,0,0,1,3,1,2,60,60,50,1';

  @override
  String write(SubtitleDocument document) {
    final ass =
        document.format == SubtitleFormat.ass ||
        document.format == SubtitleFormat.ssa;
    final out = StringBuffer()
      ..writeln(
        ass && document.header != null ? document.header : defaultHeader,
      )
      ..writeln()
      ..writeln('[Events]')
      ..writeln(
        'Format: Layer, Start, End, Style, Name, MarginL, MarginR, '
        'MarginV, Effect, Text',
      );
    for (final c in document.cues) {
      final e = c.extra;
      final text = ass ? c.text : _asAss(c.text);
      out.writeln(
        'Dialogue: ${e['Layer'] ?? '0'},${formatAssClock(c.start)},'
        '${formatAssClock(c.end)},${c.style ?? 'Default'},${e['Name'] ?? ''},'
        '${e['MarginL'] ?? '0'},${e['MarginR'] ?? '0'},${e['MarginV'] ?? '0'},'
        '${e['Effect'] ?? ''},$text',
      );
    }
    return out.toString();
  }
}

/// SRT/WebVTT text to ASS: line breaks and the common HTML tags.
String _asAss(String text) => text
    .replaceAll('<i>', r'{\i1}')
    .replaceAll('</i>', r'{\i0}')
    .replaceAll('<b>', r'{\b1}')
    .replaceAll('</b>', r'{\b0}')
    .replaceAll(RegExp('</?[a-zA-Z][^>]*>'), '')
    .replaceAll('\n', r'\N');

// ------------------------------------------------------------- MicroDVD

/// `{start}{end}text` in frames; `|` breaks lines. A first cue
/// `{1}{1}23.976` sets the frame rate, else [fps].
final class MicroDvdParser implements SubtitleParser {
  const MicroDvdParser({this.fps = 23.976});

  final double fps;

  @override
  Set<SubtitleFormat> get formats => const {SubtitleFormat.microDvd};

  static final _cue = RegExp(r'^\{(\d+)\}\{(\d*)\}(.*)$');

  @override
  SubtitleDocument parse(
    String text, {
    ParseLimits limits = const ParseLimits(),
  }) {
    _checkSize(text, limits);
    var rate = fps;
    final cues = <SubtitleCue>[];
    var first = true;
    for (final raw in _splitLines(text)) {
      final m = _cue.firstMatch(raw.trim());
      if (m == null) continue;
      final a = int.parse(m.group(1)!);
      final b = int.tryParse(m.group(2)!) ?? a;
      final body = m.group(3)!;
      if (first) {
        first = false;
        final r = double.tryParse(body.trim());
        if (a <= 1 && b <= 1 && r != null && r > 1 && r < 200) {
          rate = r;
          continue;
        }
      }
      Duration at(int frame) =>
          Duration(microseconds: (frame / rate * 1e6).round());
      cues.add(
        SubtitleCue(start: at(a), end: at(b), text: body.split('|').join('\n')),
      );
      _checkCount(cues, limits);
    }
    return SubtitleDocument(format: SubtitleFormat.microDvd, cues: cues);
  }

  @override
  String write(SubtitleDocument document) {
    final out = StringBuffer('{1}{1}${fps.toStringAsFixed(3)}\n');
    int frame(Duration d) => (d.inMicroseconds / 1e6 * fps).round();
    for (final c in document.cues) {
      out.writeln(
        '{${frame(c.start)}}{${frame(c.end)}}'
        '${stripMarkup(c.text).replaceAll('\n', '|')}',
      );
    }
    return out.toString();
  }
}

// ------------------------------------------------------------------ LRC

/// `[mm:ss.xx]line`; several stamps may share a line. Each line lasts
/// until the next starts (the last one [lastDuration]).
final class LrcParser implements SubtitleParser {
  const LrcParser({this.lastDuration = const Duration(seconds: 5)});

  final Duration lastDuration;

  @override
  Set<SubtitleFormat> get formats => const {SubtitleFormat.lrc};

  static final _stamp = RegExp(r'\[(\d{1,3}):(\d{1,2})(?:[.:](\d{1,3}))?\]');

  @override
  SubtitleDocument parse(
    String text, {
    ParseLimits limits = const ParseLimits(),
  }) {
    _checkSize(text, limits);
    final timed = <(Duration, String)>[];
    for (final raw in _splitLines(text)) {
      final stamps = _stamp.allMatches(raw).toList();
      if (stamps.isEmpty) continue;
      final body = raw.substring(stamps.last.end).trim();
      for (final m in stamps) {
        final frac = m.group(3);
        final ms = frac == null
            ? 0
            : int.parse(frac) *
                  (frac.length == 1
                      ? 100
                      : frac.length == 2
                      ? 10
                      : 1);
        timed.add((
          Duration(
            minutes: int.parse(m.group(1)!),
            seconds: int.parse(m.group(2)!),
            milliseconds: ms,
          ),
          body,
        ));
        if (timed.length > limits.maxCues) {
          throw SubtitleParseException('more than ${limits.maxCues} cues');
        }
      }
    }
    timed.sort((a, b) => a.$1.compareTo(b.$1));
    final cues = <SubtitleCue>[
      for (var i = 0; i < timed.length; i++)
        if (timed[i].$2.isNotEmpty)
          SubtitleCue(
            start: timed[i].$1,
            end: i + 1 < timed.length
                ? timed[i + 1].$1
                : timed[i].$1 + lastDuration,
            text: timed[i].$2,
          ),
    ];
    return SubtitleDocument(format: SubtitleFormat.lrc, cues: cues);
  }

  @override
  String write(SubtitleDocument document) {
    final out = StringBuffer();
    for (final c in document.cues) {
      final cs = c.start.inMilliseconds ~/ 10;
      out.writeln(
        '[${_two(cs ~/ 6000)}:${_two(cs ~/ 100 % 60)}.${_two(cs % 100)}]'
        '${stripMarkup(c.text).replaceAll('\n', ' ')}',
      );
    }
    return out.toString();
  }
}

// ----------------------------------------------------------------- SAMI

/// `<SYNC Start=ms><P Class=..>text`; a sync with only `&nbsp;` ends the
/// previous one. One language class (the first) is read.
final class SamiParser implements SubtitleParser {
  const SamiParser();

  @override
  Set<SubtitleFormat> get formats => const {SubtitleFormat.smi};

  static final _sync = RegExp(
    r'<sync\s+start\s*=\s*"?(\d+)"?[^>]*>',
    caseSensitive: false,
  );

  @override
  SubtitleDocument parse(
    String text, {
    ParseLimits limits = const ParseLimits(),
  }) {
    _checkSize(text, limits);
    final syncs = _sync.allMatches(text).toList();
    final timed = <(Duration, String)>[];
    for (var i = 0; i < syncs.length; i++) {
      final end = i + 1 < syncs.length ? syncs[i + 1].start : text.length;
      final body = text
          .substring(syncs[i].end, end)
          .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
          .replaceAll(RegExp('<[^>]*>'), '')
          .replaceAll(RegExp('&nbsp;', caseSensitive: false), ' ')
          .replaceAll('&amp;', '&')
          .replaceAll('&lt;', '<')
          .replaceAll('&gt;', '>')
          .split('\n')
          .map((l) => l.trim())
          .where((l) => l.isNotEmpty)
          .join('\n');
      timed.add((Duration(milliseconds: int.parse(syncs[i].group(1)!)), body));
      if (timed.length > limits.maxCues) {
        throw SubtitleParseException('more than ${limits.maxCues} cues');
      }
    }
    final cues = <SubtitleCue>[
      for (var i = 0; i < timed.length; i++)
        if (timed[i].$2.isNotEmpty)
          SubtitleCue(
            start: timed[i].$1,
            end: i + 1 < timed.length
                ? timed[i + 1].$1
                : timed[i].$1 + const Duration(seconds: 5),
            text: timed[i].$2,
          ),
    ];
    return SubtitleDocument(format: SubtitleFormat.smi, cues: cues);
  }

  @override
  String write(SubtitleDocument document) {
    final out = StringBuffer(
      '<SAMI>\n<HEAD>\n<STYLE TYPE="text/css"><!--\n'
      'P { margin-left: 8pt; margin-right: 8pt; text-align: center; }\n'
      '.SUBTTL { Name: Subtitles; lang: und; }\n--></STYLE>\n</HEAD>\n<BODY>\n',
    );
    String esc(String s) => s
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('\n', '<br>');
    for (final c in document.cues) {
      out
        ..writeln(
          '<SYNC Start=${c.start.inMilliseconds}><P Class=SUBTTL>'
          '${esc(stripMarkup(c.text))}',
        )
        ..writeln('<SYNC Start=${c.end.inMilliseconds}><P Class=SUBTTL>&nbsp;');
    }
    out.writeln('</BODY>\n</SAMI>');
    return out.toString();
  }
}

/// The parser for [format]; null for image formats (OCR, SUB-051) and
/// formats without an editor parser yet.
SubtitleParser? parserFor(SubtitleFormat format, {double? fps}) =>
    switch (format) {
      SubtitleFormat.srt => const SrtParser(),
      SubtitleFormat.webvtt => const WebVttParser(),
      SubtitleFormat.ass || SubtitleFormat.ssa => const AssParser(),
      SubtitleFormat.microDvd =>
        fps == null ? const MicroDvdParser() : MicroDvdParser(fps: fps),
      SubtitleFormat.lrc => const LrcParser(),
      SubtitleFormat.smi => const SamiParser(),
      SubtitleFormat.ttml ||
      SubtitleFormat.txt ||
      SubtitleFormat.pgs ||
      SubtitleFormat.vobSub ||
      SubtitleFormat.dvb => null,
    };

/// Guesses the format of [text] from its first lines (pasted or
/// mis-named files).
SubtitleFormat? sniffSubtitleFormat(String text) {
  final head = text.replaceFirst('﻿', '').trimLeft();
  final start = head.length > 2000 ? head.substring(0, 2000) : head;
  if (start.startsWith('WEBVTT')) return SubtitleFormat.webvtt;
  if (start.startsWith('[Script Info]') ||
      start.contains('\n[Events]') ||
      start.contains('Dialogue:')) {
    return start.contains('v4.00+') || !start.contains('ScriptType')
        ? SubtitleFormat.ass
        : SubtitleFormat.ssa;
  }
  if (RegExp('<sami', caseSensitive: false).hasMatch(start)) {
    return SubtitleFormat.smi;
  }
  if (RegExp(r'^\{\d+\}\{\d*\}', multiLine: true).hasMatch(start)) {
    return SubtitleFormat.microDvd;
  }
  if (RegExp('-->', multiLine: true).hasMatch(start)) {
    return SubtitleFormat.srt;
  }
  if (RegExp(r'^\[\d{1,3}:\d{2}', multiLine: true).hasMatch(start)) {
    return SubtitleFormat.lrc;
  }
  return null;
}
