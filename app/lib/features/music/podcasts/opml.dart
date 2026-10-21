import 'package:mediahro/core/parsers/xml_lite.dart';
import 'package:meta/meta.dart';

/// One subscription in an OPML file.
@immutable
final class OpmlFeed {
  const OpmlFeed(this.url, {this.title, this.link});

  final String url;
  final String? title;
  final String? link;
}

const maxOpmlFeeds = 5000;

/// The feeds in an OPML subscription list (POD-002), from any app's export:
/// every `outline` with an `xmlUrl` at any depth (folders only group),
/// http(s) only, each address once, in file order.
List<OpmlFeed> parseOpml(String text) {
  final XmlElement root;
  try {
    root = parseXml(text);
  } on XmlFormatException {
    return const [];
  }
  if (root.localName != 'opml') return const [];
  final seen = <String>{};
  final out = <OpmlFeed>[];
  for (final o in root.descendants('outline')) {
    final raw = (o.attr('xmlUrl') ?? o.attr('xmlurl'))?.trim();
    final uri = raw == null ? null : Uri.tryParse(raw);
    if (uri == null ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.host.isEmpty) {
      continue;
    }
    if (!seen.add(uri.toString())) continue;
    final title = (o.attr('title') ?? o.attr('text'))?.trim();
    out.add(
      OpmlFeed(
        uri.toString(),
        title: title == null || title.isEmpty ? null : title,
        link: o.attr('htmlUrl')?.trim(),
      ),
    );
    if (out.length >= maxOpmlFeeds) break;
  }
  return out;
}

/// An OPML 2.0 list of [feeds], for export (POD-002).
String buildOpml(List<OpmlFeed> feeds, {String title = 'Mediahro podcasts'}) {
  final b = StringBuffer()
    ..writeln('<?xml version="1.0" encoding="UTF-8"?>')
    ..writeln('<opml version="2.0">')
    ..writeln('  <head><title>${xmlEscape(title)}</title></head>')
    ..writeln('  <body>');
  for (final f in feeds) {
    final t = xmlEscape(f.title ?? f.url);
    b.write(
      '    <outline type="rss" text="$t" title="$t" '
      'xmlUrl="${xmlEscape(f.url)}"',
    );
    if (f.link != null && f.link!.isNotEmpty) {
      b.write(' htmlUrl="${xmlEscape(f.link!)}"');
    }
    b.writeln('/>');
  }
  b
    ..writeln('  </body>')
    ..writeln('</opml>');
  return b.toString();
}
