import 'package:mediahro/features/music/tags/audio_tags.dart';

/// Byte order mark some editors put at the start of a text file.
final String _bom = String.fromCharCode(0xFEFF);

/// Chapter marks from a CUE sheet that sits next to a single-file audiobook
/// (POD-001): each `TRACK` with its `TITLE` and `INDEX 01 mm:ss:ff` (75
/// frames to the second). A sheet that names more than one audio file does
/// not describe one continuous file, so it gives no chapters.
List<TagChapter> parseCueSheet(String text) {
  final marks = <TagChapter>[];
  var files = 0;
  var inTrack = false;
  String? title;
  Duration? start;

  void close() {
    if (inTrack && start != null) {
      marks.add(
        TagChapter(
          start!,
          (title ?? '').isEmpty ? '${marks.length + 1}' : title!,
        ),
      );
    }
    title = null;
    start = null;
  }

  for (final raw in text.replaceFirst(_bom, '').split(RegExp(r'\r\n|\r|\n'))) {
    final line = raw.trim();
    final upper = line.toUpperCase();
    if (upper.startsWith('FILE ')) {
      files++;
    } else if (upper.startsWith('TRACK ')) {
      close();
      inTrack = true;
    } else if (inTrack && upper.startsWith('TITLE ')) {
      title = _unquote(line.substring(6));
    } else if (inTrack && upper.startsWith('INDEX 01 ')) {
      start = _time(line.substring(9).trim());
    }
  }
  close();
  if (files > 1) return const [];
  marks.sort((a, b) => a.start.compareTo(b.start));
  return marks;
}

String _unquote(String s) {
  final t = s.trim();
  return t.length >= 2 && t.startsWith('"') && t.endsWith('"')
      ? t.substring(1, t.length - 1)
      : t;
}

Duration? _time(String s) {
  final m = RegExp(r'^(\d+):(\d{1,2}):(\d{1,2})$').firstMatch(s);
  if (m == null) return null;
  final minutes = int.parse(m[1]!);
  final seconds = int.parse(m[2]!);
  final frames = int.parse(m[3]!);
  return Duration(
    milliseconds: ((minutes * 60 + seconds) * 1000 + frames * 1000 / 75)
        .round(),
  );
}
