import 'package:meta/meta.dart';

/// One line of an FTP `LIST` or SFTP long listing.
@immutable
final class ListedEntry {
  const ListedEntry(
    this.name, {
    required this.isDirectory,
    this.size,
    this.modified,
    this.linkTarget,
  });

  final String name;
  final bool isDirectory;
  final int? size;
  final DateTime? modified;
  final String? linkTarget;
}

const _months = {
  'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4, 'may': 5, 'jun': 6, //
  'jul': 7, 'aug': 8, 'sep': 9, 'oct': 10, 'nov': 11, 'dec': 12,
};

final RegExp _unix = RegExp(
  r'^([\-dlbcps])[rwxsStTl\-]{9}[+@.]?\s+\d+\s+\S+\s+(?:\S+\s+)?(\d+)\s+'
  r'([A-Za-z]{3})\s+(\d{1,2})\s+(\d{1,2}:\d{2}|\d{4})\s(.+)$',
);
final RegExp _dos = RegExp(
  r'^(\d{2})-(\d{2})-(\d{2,4})\s+(\d{1,2}):(\d{2})(AM|PM)?\s+(<DIR>|\d+)\s+(.+)$',
  caseSensitive: false,
);

/// Parses a listing (Unix `ls -l` style from most FTP servers and SFTP,
/// or MS-DOS style from IIS). Unparseable lines are skipped. [now] decides
/// the year of recent Unix entries that carry a time instead of a year.
List<ListedEntry> parseListing(String text, {DateTime? now}) {
  final at = now ?? DateTime.now().toUtc();
  final out = <ListedEntry>[];
  for (final raw in text.split(RegExp('\r?\n'))) {
    final line = raw.trimRight();
    if (line.isEmpty || line.startsWith('total ')) continue;
    final u = _unix.firstMatch(line);
    if (u != null) {
      final type = u.group(1)!;
      var name = u.group(6)!;
      String? target;
      if (type == 'l') {
        final arrow = name.indexOf(' -> ');
        if (arrow > 0) {
          target = name.substring(arrow + 4);
          name = name.substring(0, arrow);
        }
      }
      if (name == '.' || name == '..') continue;
      out.add(
        ListedEntry(
          name,
          isDirectory: type == 'd',
          size: type == 'd' ? null : int.tryParse(u.group(2)!),
          modified: _unixDate(u.group(3)!, u.group(4)!, u.group(5)!, at),
          linkTarget: target,
        ),
      );
      continue;
    }
    final d = _dos.firstMatch(line);
    if (d != null) {
      var year = int.parse(d.group(3)!);
      if (year < 100) year += year < 70 ? 2000 : 1900;
      var hour = int.parse(d.group(4)!);
      final ampm = d.group(6)?.toUpperCase();
      if (ampm == 'PM' && hour < 12) hour += 12;
      if (ampm == 'AM' && hour == 12) hour = 0;
      final dir = d.group(7)!.toUpperCase() == '<DIR>';
      out.add(
        ListedEntry(
          d.group(8)!,
          isDirectory: dir,
          size: dir ? null : int.tryParse(d.group(7)!),
          modified: DateTime.utc(
            year,
            int.parse(d.group(1)!),
            int.parse(d.group(2)!),
            hour,
            int.parse(d.group(5)!),
          ),
        ),
      );
    }
  }
  return out;
}

DateTime? _unixDate(String mon, String day, String timeOrYear, DateTime now) {
  final m = _months[mon.toLowerCase()];
  final dd = int.tryParse(day);
  if (m == null || dd == null) return null;
  if (timeOrYear.contains(':')) {
    final p = timeOrYear.split(':');
    var d = DateTime.utc(now.year, m, dd, int.parse(p[0]), int.parse(p[1]));
    // Recent entries omit the year; a date "in the future" is last year's.
    if (d.isAfter(now.add(const Duration(days: 2)))) {
      d = DateTime.utc(now.year - 1, m, dd, d.hour, d.minute);
    }
    return d;
  }
  return DateTime.utc(int.parse(timeOrYear), m, dd);
}
