import 'package:meta/meta.dart';

/// Limits for untrusted XML (PRIV-005).
@immutable
final class XmlLimits {
  const XmlLimits({
    this.maxLength = 8 << 20,
    this.maxDepth = 64,
    this.maxNodes = 200000,
  });

  final int maxLength;
  final int maxDepth;
  final int maxNodes;
}

final class XmlFormatException extends FormatException {
  const XmlFormatException(super.message, [super.source, super.offset]);
}

/// An element of a parsed document. Names keep their prefix
/// (`d:response`); [localName] strips it. Namespaces are not resolved,
/// which is enough for WebDAV, DIDL-Lite, SSDP descriptions, XSPF and NFO.
final class XmlElement {
  XmlElement(this.name, this.attributes);

  final String name;
  final Map<String, String> attributes;
  final List<XmlElement> children = [];
  final StringBuffer _text = StringBuffer();

  String get localName {
    final i = name.indexOf(':');
    return i < 0 ? name : name.substring(i + 1);
  }

  /// Text directly inside this element (CDATA included), trimmed.
  String get text => _text.toString().trim();

  /// First child with [localName], ignoring prefixes.
  XmlElement? child(String localName) {
    for (final c in children) {
      if (c.localName == localName) return c;
    }
    return null;
  }

  Iterable<XmlElement> all(String localName) =>
      children.where((c) => c.localName == localName);

  /// Depth-first descendants with [localName].
  Iterable<XmlElement> descendants(String localName) sync* {
    for (final c in children) {
      if (c.localName == localName) yield c;
      yield* c.descendants(localName);
    }
  }

  String? childText(String localName) => child(localName)?.text;

  /// Attribute by local name, ignoring prefixes.
  String? attr(String localName) {
    for (final e in attributes.entries) {
      final k = e.key;
      final i = k.indexOf(':');
      if ((i < 0 ? k : k.substring(i + 1)) == localName) return e.value;
    }
    return null;
  }
}

/// A small non-validating XML parser. DOCTYPE declarations are skipped and
/// never expanded (no external entities, no entity bombs).
XmlElement parseXml(String input, {XmlLimits limits = const XmlLimits()}) {
  if (input.length > limits.maxLength) {
    throw const XmlFormatException('document too large');
  }
  return _Parser(input, limits).parse();
}

final class _Parser {
  _Parser(this.s, this.limits);

  final String s;
  final XmlLimits limits;
  int p = 0;
  int nodes = 0;

  XmlElement parse() {
    final stack = <XmlElement>[];
    XmlElement? root;
    if (s.startsWith('﻿')) p = 1;
    while (p < s.length) {
      final lt = s.indexOf('<', p);
      if (lt < 0) {
        if (stack.isNotEmpty) stack.last._text.write(_decode(s.substring(p)));
        break;
      }
      if (lt > p && stack.isNotEmpty) {
        stack.last._text.write(_decode(s.substring(p, lt)));
      }
      p = lt;
      if (s.startsWith('<!--', p)) {
        p = _after('-->', p + 4);
      } else if (s.startsWith('<![CDATA[', p)) {
        final end = s.indexOf(']]>', p + 9);
        if (end < 0) throw XmlFormatException('unterminated CDATA', s, p);
        stack.lastOrNull?._text.write(s.substring(p + 9, end));
        p = end + 3;
      } else if (s.startsWith('<?', p)) {
        p = _after('?>', p + 2);
      } else if (s.startsWith('<!', p)) {
        p = _skipDeclaration(p + 2);
      } else if (s.startsWith('</', p)) {
        final end = s.indexOf('>', p);
        if (end < 0) throw XmlFormatException('unterminated end tag', s, p);
        final name = s.substring(p + 2, end).trim();
        if (stack.isEmpty || stack.last.name != name) {
          throw XmlFormatException('mismatched </$name>', s, p);
        }
        stack.removeLast();
        p = end + 1;
      } else {
        final (el, selfClosing) = _startTag();
        if (++nodes > limits.maxNodes) {
          throw const XmlFormatException('too many nodes');
        }
        if (stack.isEmpty) {
          if (root != null) throw XmlFormatException('two roots', s, lt);
          root = el;
        } else {
          stack.last.children.add(el);
        }
        if (!selfClosing) {
          stack.add(el);
          if (stack.length > limits.maxDepth) {
            throw const XmlFormatException('nesting too deep');
          }
        }
      }
    }
    if (root == null) throw const XmlFormatException('no root element');
    if (stack.isNotEmpty) {
      throw XmlFormatException('unclosed <${stack.last.name}>');
    }
    return root;
  }

  int _after(String marker, int from) {
    final i = s.indexOf(marker, from);
    if (i < 0) throw XmlFormatException('unterminated $marker', s, from);
    return i + marker.length;
  }

  int _skipDeclaration(int from) {
    // <!DOCTYPE ... [ ... ]> : skip balanced brackets without interpreting.
    var depth = 0;
    for (var i = from; i < s.length; i++) {
      final c = s.codeUnitAt(i);
      if (c == 0x5B) depth++;
      if (c == 0x5D) depth--;
      if (c == 0x3E && depth <= 0) return i + 1;
    }
    throw XmlFormatException('unterminated declaration', s, from);
  }

  (XmlElement, bool) _startTag() {
    var i = p + 1;
    final nameStart = i;
    while (i < s.length &&
        !_isSpace(s.codeUnitAt(i)) &&
        s[i] != '>' &&
        s[i] != '/') {
      i++;
    }
    final name = s.substring(nameStart, i);
    if (name.isEmpty) throw XmlFormatException('empty tag name', s, p);
    final attrs = <String, String>{};
    while (true) {
      while (i < s.length && _isSpace(s.codeUnitAt(i))) {
        i++;
      }
      if (i >= s.length) throw XmlFormatException('unterminated tag', s, p);
      if (s[i] == '>') {
        p = i + 1;
        return (XmlElement(name, attrs), false);
      }
      if (s.startsWith('/>', i)) {
        p = i + 2;
        return (XmlElement(name, attrs), true);
      }
      final eq = s.indexOf('=', i);
      if (eq < 0) throw XmlFormatException('bad attribute', s, i);
      final key = s.substring(i, eq).trim();
      var q = eq + 1;
      while (q < s.length && _isSpace(s.codeUnitAt(q))) {
        q++;
      }
      if (q >= s.length || (s[q] != '"' && s[q] != "'")) {
        throw XmlFormatException('unquoted attribute', s, q);
      }
      final close = s.indexOf(s[q], q + 1);
      if (close < 0) throw XmlFormatException('unterminated attribute', s, q);
      attrs[key] = _decode(s.substring(q + 1, close));
      i = close + 1;
    }
  }

  static bool _isSpace(int c) =>
      c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0D;
}

final RegExp _entity = RegExp('&(#x[0-9a-fA-F]+|#[0-9]+|[a-zA-Z]+);');

/// Decodes the five predefined entities and character references.
String _decode(String t) {
  if (!t.contains('&')) return t;
  return t.replaceAllMapped(_entity, (m) {
    final e = m.group(1)!;
    switch (e) {
      case 'lt':
        return '<';
      case 'gt':
        return '>';
      case 'amp':
        return '&';
      case 'quot':
        return '"';
      case 'apos':
        return "'";
    }
    final code = e.startsWith('#x')
        ? int.tryParse(e.substring(2), radix: 16)
        : e.startsWith('#')
        ? int.tryParse(e.substring(1))
        : null;
    if (code == null || code <= 0 || code > 0x10FFFF) return m.group(0)!;
    return String.fromCharCode(code);
  });
}

/// Escapes text for XML output (playlist export, SOAP bodies).
String xmlEscape(String t) => t
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&apos;');
