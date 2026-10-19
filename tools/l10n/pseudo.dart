// Pseudo-localisation for ARB messages (CORE-008, docs/11 §1 localisation
// row). ICU-aware: placeholders (`{name}`), plural/select selectors and `#`
// are kept; only literal text changes.
//
//   en-XA  accented, ~40 % longer, wrapped in [ ] so truncation shows.
//   ar-XB  every word forced right-to-left, for RTL layout checks.
//
// Uses only dart:core so `merge_arb.dart` can run before `pub get`.

/// Accented, expanded variant of [message].
String pseudoExpand(String message) {
  final body = _transform(message, _accent);
  final literal = _literalLength(message);
  final pad = (literal * 0.4).ceil();
  return '[$body${pad > 0 ? ' ${'·' * pad}' : ''}]';
}

/// Right-to-left variant of [message]: each word wrapped in RLO … PDF.
String pseudoRtl(String message) => _transform(
  message,
  (text) =>
      text.replaceAllMapped(RegExp(r'[^\s]+'), (m) => '\u202E${m[0]}\u202C'),
);

/// Placeholder names used in [message], including plural/select arguments.
Set<String> placeholdersOf(String message) {
  final names = <String>{};
  _walk(message, onArgument: names.add);
  return names;
}

/// Null when braces balance and every argument is well formed, otherwise a
/// short description of the first problem.
String? icuError(String message) {
  try {
    _walk(message, onArgument: (_) {});
    return null;
  } on FormatException catch (e) {
    return e.message;
  }
}

int _literalLength(String message) {
  var n = 0;
  _transform(message, (t) {
    n += t.length;
    return t;
  });
  return n;
}

String _transform(String message, String Function(String literal) f) {
  final out = StringBuffer();
  final end = _Parser(message, out, f).message(0, inPlural: false);
  if (end < message.length) throw FormatException('unmatched } at $end');
  return out.toString();
}

void _walk(String message, {required void Function(String) onArgument}) {
  final end = _Parser(
    message,
    StringBuffer(),
    (s) => s,
    onArgument: onArgument,
  ).message(0, inPlural: false);
  if (end < message.length) throw FormatException('unmatched } at $end');
}

final class _Parser {
  _Parser(this.s, this.out, this.literal, {this.onArgument});

  final String s;
  final StringBuffer out;
  final String Function(String) literal;
  final void Function(String)? onArgument;

  /// Parses literal text and arguments from `i` until an unmatched `}` or
  /// the end; returns the index of that `}` (or `s.length`).
  int message(int from, {required bool inPlural}) {
    var i = from;
    final text = StringBuffer();
    void flush() {
      if (text.isEmpty) return;
      out.write(literal(text.toString()));
      text.clear();
    }

    while (i < s.length) {
      final c = s[i];
      if (c == '}') {
        flush();
        return i;
      }
      if (c == '{') {
        flush();
        i = argument(i);
        continue;
      }
      if (c == '#' && inPlural) {
        flush();
        out.write('#');
        i++;
        continue;
      }
      if (c == "'" &&
          i + 1 < s.length &&
          (s[i + 1] == '{' || s[i + 1] == '}')) {
        // ICU quoting: '{' is a literal brace.
        final end = s.indexOf("'", i + 1);
        if (end < 0) throw const FormatException('unterminated quote');
        flush();
        out.write(s.substring(i, end + 1));
        i = end + 1;
        continue;
      }
      text.write(c);
      i++;
    }
    flush();
    return i;
  }

  /// `{name}` or `{name, plural|select|selectordinal, sel{msg} …}`.
  int argument(int start) {
    var i = start + 1;
    final nameEnd = _indexOfAny(i, const ['}', ',']);
    if (nameEnd < 0) throw FormatException('unclosed { at $start');
    final name = s.substring(i, nameEnd).trim();
    if (name.isEmpty) throw FormatException('empty argument at $start');
    onArgument?.call(name);
    if (s[nameEnd] == '}') {
      out.write(s.substring(start, nameEnd + 1));
      return nameEnd + 1;
    }
    final typeEnd = _indexOfAny(nameEnd + 1, const [',', '}']);
    if (typeEnd < 0) throw FormatException('unclosed { at $start');
    final type = s.substring(nameEnd + 1, typeEnd).trim();
    if (s[typeEnd] == '}') {
      // {name, number} style: copy verbatim.
      out.write(s.substring(start, typeEnd + 1));
      return typeEnd + 1;
    }
    if (!const {'plural', 'select', 'selectordinal'}.contains(type)) {
      throw FormatException('unknown argument type "$type" at $start');
    }
    out.write(s.substring(start, typeEnd + 1));
    i = typeEnd + 1;
    var cases = 0;
    while (i < s.length) {
      while (i < s.length && s[i].trim().isEmpty) {
        out.write(s[i]);
        i++;
      }
      if (i >= s.length) break;
      if (s[i] == '}') {
        if (cases == 0) throw FormatException('no cases at $start');
        out.write('}');
        return i + 1;
      }
      final open = s.indexOf('{', i);
      if (open < 0) throw FormatException('case without message at $i');
      out.write(s.substring(i, open + 1));
      final close = message(open + 1, inPlural: type != 'select');
      if (close >= s.length) throw FormatException('unclosed case at $open');
      out.write('}');
      cases++;
      i = close + 1;
    }
    throw FormatException('unclosed { at $start');
  }

  int _indexOfAny(int from, List<String> chars) {
    for (var i = from; i < s.length; i++) {
      if (chars.contains(s[i])) return i;
      if (s[i] == '{') return -1;
    }
    return -1;
  }
}

const _accents = {
  'a': 'á',
  'b': 'ƀ',
  'c': 'ç',
  'd': 'ð',
  'e': 'é',
  'f': 'ƒ',
  'g': 'ĝ',
  'h': 'ĥ',
  'i': 'î',
  'j': 'ĵ',
  'k': 'ķ',
  'l': 'ļ',
  'm': 'ɱ',
  'n': 'ñ',
  'o': 'ö',
  'p': 'þ',
  'q': 'ǫ',
  'r': 'ŕ',
  's': 'š',
  't': 'ţ',
  'u': 'û',
  'v': 'ṽ',
  'w': 'ŵ',
  'x': 'ẋ',
  'y': 'ý',
  'z': 'ž',
  'A': 'Å',
  'B': 'Ɓ',
  'C': 'Ç',
  'D': 'Ð',
  'E': 'É',
  'F': 'Ƒ',
  'G': 'Ĝ',
  'H': 'Ĥ',
  'I': 'Î',
  'J': 'Ĵ',
  'K': 'Ķ',
  'L': 'Ļ',
  'M': 'Ṁ',
  'N': 'Ñ',
  'O': 'Ö',
  'P': 'Þ',
  'Q': 'Ǫ',
  'R': 'Ŕ',
  'S': 'Š',
  'T': 'Ţ',
  'U': 'Û',
  'V': 'Ṽ',
  'W': 'Ŵ',
  'X': 'Ẋ',
  'Y': 'Ý',
  'Z': 'Ž',
};

String _accent(String text) {
  final b = StringBuffer();
  for (final ch in text.split('')) {
    b.write(_accents[ch] ?? ch);
  }
  return b.toString();
}
