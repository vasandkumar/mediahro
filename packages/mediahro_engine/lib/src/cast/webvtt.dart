/// WebVTT for cast receivers (CAST-005): subtitles are served as WebVTT
/// next to the media.
library;

import 'package:mediahro_engine/src/mpv/subtitle_convert.dart';

/// Renders [cues] as a WebVTT document.
String toWebVtt(List<Cue> cues) {
  final b = StringBuffer('WEBVTT\n\n');
  for (final c in cues) {
    b
      ..writeln('${_vttTime(c.start)} --> ${_vttTime(c.end)}')
      ..writeln(_escape(c.text))
      ..writeln();
  }
  return b.toString();
}

String _vttTime(Duration d) {
  final ms = d.inMilliseconds;
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(ms ~/ 3600000)}:${two(ms ~/ 60000 % 60)}:'
      '${two(ms ~/ 1000 % 60)}.${(ms % 1000).toString().padLeft(3, '0')}';
}

String _escape(String s) => s
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    // A blank line would end the cue.
    .replaceAll(RegExp(r'\n\s*\n'), '\n');

/// Parses SRT into cues (formatting tags removed).
List<Cue> parseSrt(String text) {
  final cues = <Cue>[];
  final block = RegExp(
    r'(\d{1,2}):(\d{2}):(\d{2})[,.](\d{1,3})\s*-->\s*'
    r'(\d{1,2}):(\d{2}):(\d{2})[,.](\d{1,3})[^\n]*\n([\s\S]*?)(?:\n\s*\n|$)',
  );
  Duration t(Match m, int i) => Duration(
    hours: int.parse(m.group(i)!),
    minutes: int.parse(m.group(i + 1)!),
    seconds: int.parse(m.group(i + 2)!),
    milliseconds: int.parse(m.group(i + 3)!.padRight(3, '0')),
  );
  for (final m in block.allMatches(text.replaceAll('\r\n', '\n'))) {
    final body = m
        .group(9)!
        .replaceAll(RegExp('<[^>]+>'), '')
        .replaceAll(RegExp(r'\{\\[^}]*\}'), '')
        .trim();
    if (body.isEmpty) continue;
    cues.add(Cue(t(m, 1), t(m, 5), body));
    if (cues.length >= maxCues) break;
  }
  return cues;
}

/// Strips ASS override tags and converts `\N` line breaks.
String assToPlain(String text) => text
    .replaceAll(RegExp(r'\{[^}]*\}'), '')
    .replaceAll(r'\N', '\n')
    .replaceAll(r'\n', '\n')
    .replaceAll(r'\h', ' ')
    .trim();
