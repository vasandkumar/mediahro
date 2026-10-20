import 'package:mediahro/core/parsers/xml_lite.dart';

/// Namespaces the app writes.
const xmpNamespaces = {
  'x': 'adobe:ns:meta/',
  'rdf': 'http://www.w3.org/1999/02/22-rdf-syntax-ns#',
  'dc': 'http://purl.org/dc/elements/1.1/',
  'xmp': 'http://ns.adobe.com/xap/1.0/',
  'exif': 'http://ns.adobe.com/exif/1.0/',
  'photoshop': 'http://ns.adobe.com/photoshop/1.0/',
};

/// A mutable XML node for editing XMP (xml_lite elements are read-only).
final class XNode {
  XNode(this.name, [Map<String, String>? attrs, String? text])
    : attrs = attrs ?? {},
      text = text ?? '';

  factory XNode.from(XmlElement e) {
    final n = XNode(e.name, Map.of(e.attributes), e.text);
    for (final c in e.children) {
      n.children.add(XNode.from(c));
    }
    return n;
  }

  final String name;
  final Map<String, String> attrs;
  final List<XNode> children = [];
  String text;

  String get localName {
    final i = name.indexOf(':');
    return i < 0 ? name : name.substring(i + 1);
  }

  Iterable<XNode> descendants(String local) sync* {
    for (final c in children) {
      if (c.localName == local) yield c;
      yield* c.descendants(local);
    }
  }

  void write(StringBuffer b, int indent) {
    final pad = ' ' * indent;
    b
      ..write(pad)
      ..write('<')
      ..write(name);
    for (final a in attrs.entries) {
      b.write(' ${a.key}="${xmlEscape(a.value)}"');
    }
    if (children.isEmpty && text.isEmpty) {
      b.write('/>\n');
      return;
    }
    b.write('>');
    if (children.isEmpty) {
      b
        ..write(xmlEscape(text))
        ..write('</$name>\n');
      return;
    }
    b.write('\n');
    if (text.isNotEmpty) b.writeln('$pad ${xmlEscape(text)}');
    for (final c in children) {
      c.write(b, indent + 1);
    }
    b.write('$pad</$name>\n');
  }
}

/// An XMP packet: what the app reads, and edits that keep every property
/// it does not manage.
final class XmpPacket {
  XmpPacket._(this.root);

  /// Empty packet with one rdf:Description.
  factory XmpPacket.empty() {
    final root = XNode('x:xmpmeta', {'xmlns:x': xmpNamespaces['x']!});
    final rdf = XNode('rdf:RDF', {'xmlns:rdf': xmpNamespaces['rdf']!});
    root.children.add(rdf);
    rdf.children.add(XNode('rdf:Description', {'rdf:about': ''}));
    return XmpPacket._(root);
  }

  /// Parses an XMP string; throws [XmlFormatException] when malformed.
  factory XmpPacket.parse(String xml) {
    final root = XNode.from(
      parseXml(xml, limits: const XmlLimits(maxLength: 4 << 20)),
    );
    if (root.localName == 'RDF') {
      final meta = XNode('x:xmpmeta', {'xmlns:x': xmpNamespaces['x']!});
      meta.children.add(root);
      return XmpPacket._(meta);
    }
    final p = XmpPacket._(root);
    if (p._descriptions.isEmpty) {
      final rdf = root.descendants('RDF').firstOrNull;
      if (rdf == null) {
        throw const XmlFormatException('no rdf:RDF in XMP');
      }
      rdf.children.add(XNode('rdf:Description', {'rdf:about': ''}));
    }
    return p;
  }

  final XNode root;

  List<XNode> get _descriptions => root.descendants('Description').toList();

  /// First value of [prop] (`prefix:name`) as attribute, simple element,
  /// or first rdf:li of an Alt/Seq/Bag.
  String? get(String prop) {
    final list = getList(prop);
    return list.isEmpty ? null : list.first;
  }

  List<String> getList(String prop) {
    final local = prop.substring(prop.indexOf(':') + 1);
    for (final d in _descriptions) {
      for (final a in d.attrs.entries) {
        if (_local(a.key) == local && _prefixMatches(a.key, prop)) {
          return [a.value];
        }
      }
      for (final c in d.children) {
        if (c.localName != local || !_prefixMatches(c.name, prop)) continue;
        final lis = c.descendants('li').toList();
        if (lis.isNotEmpty) {
          // Prefer x-default in a language alternative.
          final def = lis.where((l) => l.attrs['xml:lang'] == 'x-default');
          final ordered = [...def, ...lis.where((l) => !def.contains(l))];
          return [
            for (final l in ordered)
              if (l.text.isNotEmpty) l.text,
          ];
        }
        final r = c.attrs['rdf:resource'];
        if (r != null) return [r];
        return c.text.isEmpty ? const [] : [c.text];
      }
    }
    return const [];
  }

  static String _local(String n) => n.substring(n.indexOf(':') + 1);

  // Prefixes vary between writers; match on the namespace's usual prefix
  // or ignore when the document uses another one for the same local name.
  static bool _prefixMatches(String name, String prop) {
    final i = name.indexOf(':');
    if (i < 0) return false;
    final want = prop.substring(0, prop.indexOf(':'));
    return name.substring(0, i) == want;
  }

  /// Removes [prop] wherever it appears.
  void remove(String prop) {
    for (final d in _descriptions) {
      d.attrs.removeWhere((k, _) => k == prop);
      d.children.removeWhere((c) => c.name == prop);
    }
  }

  XNode _target(String prop) {
    final prefix = prop.substring(0, prop.indexOf(':'));
    final d = _descriptions.first;
    final ns = xmpNamespaces[prefix];
    if (ns != null && !d.attrs.containsKey('xmlns:$prefix')) {
      // Declared on an ancestor counts too.
      final declared = _declared(prefix);
      if (!declared) d.attrs['xmlns:$prefix'] = ns;
    }
    return d;
  }

  bool _declared(String prefix) {
    bool walk(XNode n) =>
        n.attrs.containsKey('xmlns:$prefix') ||
        n.children.any((c) => c.localName != 'Description' && walk(c));
    return walk(root) ||
        _descriptions.any((d) => d.attrs.containsKey('xmlns:$prefix'));
  }

  void setSimple(String prop, String? value) {
    remove(prop);
    if (value == null) return;
    _target(prop).children.add(XNode(prop, null, value));
  }

  /// rdf:Alt with an x-default entry (dc:title, dc:description).
  void setAlt(String prop, String? value) {
    remove(prop);
    if (value == null) return;
    final alt = XNode('rdf:Alt')
      ..children.add(XNode('rdf:li', {'xml:lang': 'x-default'}, value));
    _target(prop).children.add(XNode(prop)..children.add(alt));
  }

  /// rdf:Bag (dc:subject).
  void setBag(String prop, List<String>? values) {
    remove(prop);
    if (values == null || values.isEmpty) return;
    final bag = XNode('rdf:Bag');
    for (final v in values) {
      bag.children.add(XNode('rdf:li', null, v));
    }
    _target(prop).children.add(XNode(prop)..children.add(bag));
  }

  /// The serialised packet with an xpacket wrapper and [padding] bytes of
  /// whitespace so later in-place edits fit (XMP spec part 1 §7.3.2).
  String serialize({int padding = 2048}) {
    final b = StringBuffer()
      ..write('<?xpacket begin="﻿" id="W5M0MpCehiHzreSzNTczkc9d"?>\n');
    root.write(b, 0);
    for (var i = 0; i < padding ~/ 100; i++) {
      b.writeln(' ' * 99);
    }
    b.write('<?xpacket end="w"?>');
    return b.toString();
  }

  // ---- typed readers ----

  String? get title => get('dc:title');
  String? get description => get('dc:description');
  List<String> get keywords => getList('dc:subject');

  int? get rating => int.tryParse(get('xmp:Rating') ?? '');

  String? get label => get('xmp:Label');

  DateTime? get captured => parseXmpDate(
    get('exif:DateTimeOriginal') ??
        get('photoshop:DateCreated') ??
        get('xmp:CreateDate'),
  );

  (double, double)? get location {
    final lat = parseXmpGps(get('exif:GPSLatitude'));
    final lon = parseXmpGps(get('exif:GPSLongitude'));
    return lat == null || lon == null ? null : (lat, lon);
  }

  /// Google Photo Sphere / panorama (IMG-001).
  bool get isPanorama {
    final p = get('GPano:ProjectionType');
    return p != null || get('GPano:UsePanoramaViewer') == 'True';
  }

  /// HDR gain map (Adobe / ISO 21496 hdrgm namespace, IMG-002).
  bool get hasGainMap =>
      get('hdrgm:Version') != null ||
      root
          .descendants('Item')
          .any(
            (i) => i.attrs.entries.any(
              (a) => _local(a.key) == 'Semantic' && a.value == 'GainMap',
            ),
          );

  /// Motion Photo: offset of the trailing MP4 from the end of the file
  /// (GCamera MicroVideoOffset, or Container directory item length).
  int? get motionPhotoVideoLength {
    final legacy = int.tryParse(get('GCamera:MicroVideoOffset') ?? '');
    if (legacy != null && legacy > 0) return legacy;
    if (get('GCamera:MotionPhoto') != '1' && get('GCamera:MicroVideo') != '1') {
      return null;
    }
    for (final item in root.descendants('Item')) {
      String? attr(String local) {
        for (final a in item.attrs.entries) {
          if (_local(a.key) == local) return a.value;
        }
        for (final c in item.children) {
          if (c.localName == local) return c.text;
        }
        return null;
      }

      if (attr('Semantic') == 'MotionPhoto') {
        return int.tryParse(attr('Length') ?? '');
      }
    }
    return null;
  }

  Map<String, String> displayMap() {
    final out = <String, String>{};
    for (final d in _descriptions) {
      for (final a in d.attrs.entries) {
        if (a.key.startsWith('xmlns') || a.key.startsWith('rdf:')) continue;
        out['XMP:${a.key}'] = a.value;
      }
      for (final c in d.children) {
        final lis = c.descendants('li').map((l) => l.text).toList();
        final v = lis.isNotEmpty ? lis.join(', ') : c.text;
        if (v.isNotEmpty) out['XMP:${c.name}'] = v;
      }
    }
    return out;
  }
}

/// ISO 8601 / XMP date (`2024-05-01T10:20:30+02:00`, also `2024:05:01 …`).
DateTime? parseXmpDate(String? s) {
  if (s == null || s.isEmpty) return null;
  var t = s.trim();
  if (RegExp(r'^\d{4}:\d{2}:\d{2}').hasMatch(t)) {
    t = '${t.substring(0, 4)}-${t.substring(5, 7)}-${t.substring(8)}';
  }
  t = t.replaceFirst(' ', 'T');
  if (RegExp(r'^\d{4}$').hasMatch(t)) t = '$t-01-01';
  if (RegExp(r'^\d{4}-\d{2}$').hasMatch(t)) t = '$t-01';
  return DateTime.tryParse(t);
}

/// XMP GPS coordinate `DDD,MM.mmmmK` or `DDD,MM,SSK` (K = N/S/E/W).
double? parseXmpGps(String? s) {
  if (s == null) return null;
  final m = RegExp(
    r'^\s*(\d+(?:\.\d+)?)(?:,(\d+(?:\.\d+)?))?(?:,(\d+(?:\.\d+)?))?\s*([NSEW])\s*$',
  ).firstMatch(s);
  if (m == null) return double.tryParse(s.trim());
  var v = double.parse(m.group(1)!);
  if (m.group(2) != null) v += double.parse(m.group(2)!) / 60;
  if (m.group(3) != null) v += double.parse(m.group(3)!) / 3600;
  final k = m.group(4)!;
  return k == 'S' || k == 'W' ? -v : v;
}

/// Formats [v] as XMP GPS `DDD,MM.mmmmmmK`.
String formatXmpGps(double v, {required bool latitude}) {
  final ref = latitude ? (v < 0 ? 'S' : 'N') : (v < 0 ? 'W' : 'E');
  final a = v.abs();
  final deg = a.floor();
  final min = (a - deg) * 60;
  return '$deg,${min.toStringAsFixed(6)}$ref';
}

/// `YYYY-MM-DDTHH:MM:SS` plus the offset when known.
String formatXmpDate(DateTime d) {
  String two(int v) => v.toString().padLeft(2, '0');
  final base =
      '${d.year.toString().padLeft(4, '0')}-${two(d.month)}-${two(d.day)}'
      'T${two(d.hour)}:${two(d.minute)}:${two(d.second)}';
  if (d.isUtc) return '${base}Z';
  final off = d.timeZoneOffset;
  final sign = off.isNegative ? '-' : '+';
  final m = off.inMinutes.abs();
  return '$base$sign${two(m ~/ 60)}:${two(m % 60)}';
}
