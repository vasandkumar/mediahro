/// Which entries of an archive are pages, and in what order (IMG-017).
library;

const Set<String> _pageExt = {
  'jpg', 'jpeg', 'png', 'gif', 'webp', 'avif', 'heic', 'heif', 'jxl', 'bmp', //
  'tif', 'tiff',
};

/// True when [path] (an entry path inside an archive) is a page: a picture
/// that is not hidden, not in a `__MACOSX` folder and not a thumbnail cache.
bool isPagePath(String path) {
  final parts = path.split('/').where((p) => p.isNotEmpty).toList();
  if (parts.isEmpty) return false;
  for (final p in parts) {
    if (p.startsWith('.') || p == '__MACOSX') return false;
  }
  final name = parts.last;
  if (name.toLowerCase() == 'thumbs.db') return false;
  final dot = name.lastIndexOf('.');
  if (dot <= 0) return false;
  return _pageExt.contains(name.substring(dot + 1).toLowerCase());
}

/// Compares like a person: case does not matter and runs of digits compare as
/// numbers, so `page2` comes before `page10`. Folders sort by the same rule
/// as part of the path.
int naturalCompare(String a, String b) {
  final x = a.toLowerCase();
  final y = b.toLowerCase();
  var i = 0;
  var j = 0;
  while (i < x.length && j < y.length) {
    final cx = x.codeUnitAt(i);
    final cy = y.codeUnitAt(j);
    final dx = _isDigit(cx);
    final dy = _isDigit(cy);
    if (dx && dy) {
      var ei = i;
      while (ei < x.length && _isDigit(x.codeUnitAt(ei))) {
        ei++;
      }
      var ej = j;
      while (ej < y.length && _isDigit(y.codeUnitAt(ej))) {
        ej++;
      }
      // Leading zeros do not count; a longer number is larger.
      var si = i;
      while (si < ei - 1 && x.codeUnitAt(si) == 0x30) {
        si++;
      }
      var sj = j;
      while (sj < ej - 1 && y.codeUnitAt(sj) == 0x30) {
        sj++;
      }
      final nx = x.substring(si, ei);
      final ny = y.substring(sj, ej);
      if (nx.length != ny.length) return nx.length - ny.length;
      final c = nx.compareTo(ny);
      if (c != 0) return c;
      // Same value: fewer leading zeros first, then go on.
      if (ei - i != ej - j) return (ei - i) - (ej - j);
      i = ei;
      j = ej;
    } else {
      if (cx != cy) return cx - cy;
      i++;
      j++;
    }
  }
  return (x.length - i) - (y.length - j);
}

bool _isDigit(int c) => c >= 0x30 && c <= 0x39;

/// The pages among [paths], in reading order: folder by folder, then by
/// name, numbers as numbers.
List<String> orderedPages(Iterable<String> paths) {
  final pages = [
    for (final p in paths)
      if (isPagePath(p)) p,
  ]..sort(naturalCompare);
  return pages;
}
