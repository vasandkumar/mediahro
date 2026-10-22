import 'dart:isolate';
import 'dart:typed_data';

import 'package:mediahro/core/parsers/playlist_parser.dart' show decodeText;
import 'package:mediahro/core/parsers/xml_lite.dart';
import 'package:meta/meta.dart';

/// Hard limits for untrusted feeds (PRIV-005): the parser runs off the UI
/// isolate and never reads more than this.
const int maxFeedBytes = 24 << 20;
const int maxFeedEpisodes = 5000;

const _limits = XmlLimits(maxLength: maxFeedBytes, maxNodes: 1500000);

/// A podcast feed as published (POD-002).
@immutable
final class ParsedFeed {
  const ParsedFeed({
    required this.title,
    required this.episodes,
    this.author,
    this.description,
    this.link,
    this.imageUrl,
    this.language,
  });

  final String title;
  final String? author;
  final String? description;
  final String? link;
  final String? imageUrl;
  final String? language;

  /// Newest first.
  final List<ParsedEpisode> episodes;
}

/// One episode of a feed.
@immutable
final class ParsedEpisode {
  const ParsedEpisode({
    required this.guid,
    required this.title,
    required this.url,
    this.published,
    this.duration,
    this.mimeType,
    this.size,
    this.description,
    this.imageUrl,
    this.episode,
    this.season,
    this.explicit = false,
  });

  /// Stable id: the feed's own guid, else the enclosure address.
  final String guid;
  final String title;

  /// The audio (or video) file.
  final String url;
  final DateTime? published;
  final Duration? duration;
  final String? mimeType;
  final int? size;

  /// Plain text, no markup.
  final String? description;
  final String? imageUrl;
  final int? episode;
  final int? season;
  final bool explicit;

  Map<String, Object?> toJson() => {
    'guid': guid,
    'title': title,
    'url': url,
    'at': published?.toUtc().millisecondsSinceEpoch,
    'ms': duration?.inMilliseconds,
    'type': mimeType,
    'size': size,
    'desc': description,
    'img': imageUrl,
    'ep': episode,
    'season': season,
    if (explicit) 'x': true,
  };

  static ParsedEpisode? fromJson(Map<String, Object?> j) {
    final guid = j['guid'];
    final title = j['title'];
    final url = j['url'];
    if (guid is! String || title is! String || url is! String) return null;
    return ParsedEpisode(
      guid: guid,
      title: title,
      url: url,
      published: j['at'] is int
          ? DateTime.fromMillisecondsSinceEpoch(j['at']! as int, isUtc: true)
          : null,
      duration: j['ms'] is int ? Duration(milliseconds: j['ms']! as int) : null,
      mimeType: j['type'] as String?,
      size: j['size'] as int?,
      description: j['desc'] as String?,
      imageUrl: j['img'] as String?,
      episode: j['ep'] as int?,
      season: j['season'] as int?,
      explicit: j['x'] == true,
    );
  }
}

final class FeedFormatException extends FormatException {
  const FeedFormatException(super.message);
}

/// Parses [bytes] (RSS 2.0 with the iTunes and Podcasting 2.0 tags, or Atom)
/// on a worker isolate. [base] resolves relative links.
Future<ParsedFeed> parseFeedIsolated(Uint8List bytes, {Uri? base}) {
  if (bytes.length > maxFeedBytes) {
    throw const FeedFormatException('feed too large');
  }
  return Isolate.run(() => parseFeed(decodeText(bytes), base: base));
}

ParsedFeed parseFeed(String text, {Uri? base}) {
  final XmlElement root;
  try {
    root = parseXml(text, limits: _limits);
  } on XmlFormatException catch (e) {
    throw FeedFormatException(e.message);
  }
  return switch (root.localName) {
    'rss' || 'RDF' => _rss(root, base),
    'feed' => _atom(root, base),
    _ => throw const FeedFormatException('not a feed'),
  };
}

// ----------------------------------------------------------------- RSS --

ParsedFeed _rss(XmlElement root, Uri? base) {
  final channel = root.child('channel') ?? root;
  final title = _clip(channel.childText('title'), 500);
  final items = [for (final item in channel.all('item')) ?_rssItem(item, base)];
  return ParsedFeed(
    title: title ?? '',
    author: _clip(
      channel.childText('author') ?? channel.child('author')?.text,
      300,
    ),
    description: _plain(
      channel.childText('description') ?? channel.childText('summary'),
      4000,
    ),
    link: _http(channel.childText('link'), base),
    imageUrl: _http(
      channel
          .all('image')
          .map((e) => e.attr('href') ?? e.childText('url'))
          .firstWhere((u) => u != null && u.isNotEmpty, orElse: () => null),
      base,
    ),
    language: channel.childText('language'),
    episodes: _newestFirst(items),
  );
}

ParsedEpisode? _rssItem(XmlElement item, Uri? base) {
  final enclosure = item.child('enclosure');
  final url = _http(enclosure?.attr('url'), base);
  if (url == null) return null;
  final type = enclosure?.attr('type')?.toLowerCase();
  if (!_playable(type)) return null;
  final guid = item.childText('guid');
  return ParsedEpisode(
    guid: guid == null || guid.isEmpty ? url : guid,
    title:
        _clip(item.childText('title'), 500) ??
        Uri.tryParse(url)?.pathSegments.lastOrNull ??
        url,
    url: url,
    published: parseFeedDate(
      item.childText('pubDate') ?? item.childText('date'),
    ),
    duration: parseFeedDuration(item.childText('duration')),
    mimeType: type,
    size: int.tryParse(enclosure?.attr('length') ?? ''),
    description: _plain(
      item.childText('encoded') ??
          item.childText('description') ??
          item.childText('summary'),
      4000,
    ),
    imageUrl: _http(
      item.all('image').map((e) => e.attr('href')).nonNulls.firstOrNull,
      base,
    ),
    episode: int.tryParse(item.childText('episode') ?? ''),
    season: int.tryParse(item.childText('season') ?? ''),
    explicit: _explicit(item.childText('explicit')),
  );
}

// ---------------------------------------------------------------- Atom --

ParsedFeed _atom(XmlElement root, Uri? base) {
  String? linkOf(XmlElement e, String rel) => e
      .all('link')
      .where((l) => (l.attr('rel') ?? 'alternate') == rel)
      .map((l) => l.attr('href'))
      .nonNulls
      .firstOrNull;
  final items = <ParsedEpisode>[];
  for (final entry in root.all('entry')) {
    final enclosure = entry
        .all('link')
        .where((l) => l.attr('rel') == 'enclosure')
        .firstOrNull;
    final url = _http(enclosure?.attr('href'), base);
    if (url == null) continue;
    final type = enclosure?.attr('type')?.toLowerCase();
    if (!_playable(type)) continue;
    final id = entry.childText('id');
    items.add(
      ParsedEpisode(
        guid: id == null || id.isEmpty ? url : id,
        title: _clip(entry.childText('title'), 500) ?? url,
        url: url,
        published: parseFeedDate(
          entry.childText('published') ?? entry.childText('updated'),
        ),
        duration: parseFeedDuration(entry.childText('duration')),
        mimeType: type,
        size: int.tryParse(enclosure?.attr('length') ?? ''),
        description: _plain(
          entry.childText('content') ?? entry.childText('summary'),
          4000,
        ),
        imageUrl: _http(
          entry.all('image').map((e) => e.attr('href')).nonNulls.firstOrNull,
          base,
        ),
        episode: int.tryParse(entry.childText('episode') ?? ''),
        season: int.tryParse(entry.childText('season') ?? ''),
        explicit: _explicit(entry.childText('explicit')),
      ),
    );
  }
  return ParsedFeed(
    title: _clip(root.childText('title'), 500) ?? '',
    author: _clip(root.child('author')?.childText('name'), 300),
    description: _plain(
      root.childText('subtitle') ?? root.childText('summary'),
      4000,
    ),
    link: _http(linkOf(root, 'alternate'), base),
    imageUrl: _http(
      root.childText('logo') ??
          root.childText('icon') ??
          root.all('image').map((e) => e.attr('href')).nonNulls.firstOrNull,
      base,
    ),
    episodes: _newestFirst(items),
  );
}

// ------------------------------------------------------------- helpers --

/// Newest first; undated episodes keep their place after the dated ones; at
/// most [maxFeedEpisodes].
List<ParsedEpisode> _newestFirst(List<ParsedEpisode> items) {
  final dated = items.where((e) => e.published != null).toList()
    ..sort((a, b) => b.published!.compareTo(a.published!));
  final undated = items.where((e) => e.published == null);
  return [...dated, ...undated].take(maxFeedEpisodes).toList();
}

bool _playable(String? type) =>
    type == null ||
    type.isEmpty ||
    type.startsWith('audio/') ||
    type.startsWith('video/') ||
    type == 'application/octet-stream' ||
    type == 'application/ogg';

bool _explicit(String? v) {
  final t = v?.toLowerCase();
  return t == 'yes' || t == 'true' || t == 'explicit';
}

/// An absolute http(s) address, or null (file:, data:, javascript: and
/// anything else is never followed).
String? _http(String? raw, Uri? base) {
  final t = raw?.trim();
  if (t == null || t.isEmpty) return null;
  var uri = Uri.tryParse(t);
  if (uri == null) return null;
  if (!uri.hasScheme && base != null) uri = base.resolveUri(uri);
  if ((uri.scheme != 'http' && uri.scheme != 'https') || uri.host.isEmpty) {
    return null;
  }
  return uri.toString();
}

String? _clip(String? s, int max) {
  final t = s?.trim();
  if (t == null || t.isEmpty) return null;
  final one = t.replaceAll(RegExp(r'\s+'), ' ');
  return one.length <= max ? one : one.substring(0, max);
}

final RegExp _tag = RegExp('<[^>]*>');
final RegExp _htmlEntity = RegExp('&(#x[0-9a-fA-F]+|#[0-9]+|[a-zA-Z]+);');

/// Show notes as plain text: tags dropped (paragraph and line breaks kept),
/// character references decoded.
String? _plain(String? html, int max) {
  var t = html;
  if (t == null || t.trim().isEmpty) return null;
  t = t
      .replaceAll(RegExp(r'<\s*br\s*/?\s*>', caseSensitive: false), '\n')
      .replaceAll(
        RegExp(r'</\s*(p|div|li|h[1-6])\s*>', caseSensitive: false),
        '\n',
      )
      .replaceAll(_tag, '')
      .replaceAllMapped(_htmlEntity, (m) {
        final e = m.group(1)!;
        const named = {
          'amp': '&',
          'lt': '<',
          'gt': '>',
          'quot': '"',
          'apos': "'",
          'nbsp': ' ',
          'ndash': '–',
          'mdash': '—',
          'hellip': '…',
          'rsquo': '’',
          'lsquo': '‘',
          'rdquo': '”',
          'ldquo': '“',
        };
        if (named.containsKey(e)) return named[e]!;
        final code = e.startsWith('#x')
            ? int.tryParse(e.substring(2), radix: 16)
            : e.startsWith('#')
            ? int.tryParse(e.substring(1))
            : null;
        if (code == null || code <= 0 || code > 0x10FFFF) return m.group(0)!;
        return String.fromCharCode(code);
      });
  t = t
      .split('\n')
      .map((l) => l.trim())
      .join('\n')
      .replaceAll(RegExp(r'\n{3,}'), '\n\n')
      .trim();
  if (t.isEmpty) return null;
  return t.length <= max ? t : t.substring(0, max);
}

const _months = {
  'jan': 1,
  'feb': 2,
  'mar': 3,
  'apr': 4,
  'may': 5,
  'jun': 6,
  'jul': 7,
  'aug': 8,
  'sep': 9,
  'oct': 10,
  'nov': 11,
  'dec': 12,
};

const _zones = {
  'gmt': 0,
  'ut': 0,
  'utc': 0,
  'z': 0,
  'est': -5,
  'edt': -4,
  'cst': -6,
  'cdt': -5,
  'mst': -7,
  'mdt': -6,
  'pst': -8,
  'pdt': -7,
};

/// RFC 822 (`Tue, 10 Jun 2025 04:00:00 +0200`, as RSS writes it) or
/// ISO 8601 (as Atom writes it); null when neither fits.
DateTime? parseFeedDate(String? raw) {
  final s = raw?.trim();
  if (s == null || s.isEmpty) return null;
  final iso = DateTime.tryParse(s);
  if (iso != null) {
    // A date or time with no zone is UTC, not this device's time zone.
    return iso.isUtc || RegExp(r'[+-]\d{2}:?\d{2}$').hasMatch(s)
        ? iso.toUtc()
        : DateTime.utc(
            iso.year,
            iso.month,
            iso.day,
            iso.hour,
            iso.minute,
            iso.second,
            iso.millisecond,
          );
  }
  final m = RegExp(
    r'^(?:[A-Za-z]{3,9},?\s+)?(\d{1,2})\s+([A-Za-z]{3})[A-Za-z]*\s+(\d{2,4})'
    r'(?:\s+(\d{1,2}):(\d{2})(?::(\d{2}))?)?\s*([+-]\d{4}|[A-Za-z]{1,4})?$',
  ).firstMatch(s);
  if (m == null) return null;
  final month = _months[m.group(2)!.toLowerCase()];
  if (month == null) return null;
  var year = int.parse(m.group(3)!);
  if (year < 50) {
    year += 2000;
  } else if (year < 100) {
    year += 1900;
  }
  var offset = Duration.zero;
  final z = m.group(7);
  if (z != null) {
    if (z.startsWith('+') || z.startsWith('-')) {
      final sign = z.startsWith('-') ? -1 : 1;
      offset = Duration(
        hours: sign * int.parse(z.substring(1, 3)),
        minutes: sign * int.parse(z.substring(3, 5)),
      );
    } else {
      offset = Duration(hours: _zones[z.toLowerCase()] ?? 0);
    }
  }
  try {
    final utc = DateTime.utc(
      year,
      month,
      int.parse(m.group(1)!),
      int.tryParse(m.group(4) ?? '') ?? 0,
      int.tryParse(m.group(5) ?? '') ?? 0,
      int.tryParse(m.group(6) ?? '') ?? 0,
    );
    return utc.subtract(offset);
  } on Object {
    return null;
  }
}

/// `1:02:03`, `45:10` or plain seconds (`3723`, `3723.5`), as the iTunes
/// duration tag has them.
Duration? parseFeedDuration(String? raw) {
  final s = raw?.trim();
  if (s == null || s.isEmpty) return null;
  final parts = s.split(':');
  if (parts.length > 3) return null;
  var seconds = 0.0;
  for (final p in parts) {
    final v = double.tryParse(p);
    if (v == null || v < 0) return null;
    seconds = seconds * 60 + v;
  }
  if (seconds <= 0) return null;
  return Duration(milliseconds: (seconds * 1000).round());
}
