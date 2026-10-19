import 'package:meta/meta.dart';

/// What a video file name says about its content (LIB-011).
@immutable
final class ParsedName {
  const ParsedName({
    required this.title,
    this.year,
    this.season,
    this.episode,
    this.episodeEnd,
    this.absoluteEpisode,
    this.episodeTitle,
    this.releaseGroup,
  });

  final String title;
  final int? year;
  final int? season;
  final int? episode;

  /// Last episode of a multi-episode file (`S01E01E02`, `S01E01-E03`).
  final int? episodeEnd;

  /// Anime-style absolute numbering (`Title - 105`).
  final int? absoluteEpisode;
  final String? episodeTitle;

  /// Detected and ignored for matching (LIB-011).
  final String? releaseGroup;

  bool get isEpisode => episode != null || absoluteEpisode != null;

  @override
  bool operator ==(Object other) =>
      other is ParsedName &&
      other.title == title &&
      other.year == year &&
      other.season == season &&
      other.episode == episode &&
      other.episodeEnd == episodeEnd &&
      other.absoluteEpisode == absoluteEpisode &&
      other.episodeTitle == episodeTitle &&
      other.releaseGroup == releaseGroup;

  @override
  int get hashCode => Object.hash(
    title,
    year,
    season,
    episode,
    episodeEnd,
    absoluteEpisode,
    episodeTitle,
    releaseGroup,
  );

  @override
  String toString() =>
      'ParsedName($title, year: $year, S$season E$episode-$episodeEnd, '
      'abs: $absoluteEpisode, ep: $episodeTitle, group: $releaseGroup)';
}

/// Tokens that end the title part of a release name.
final RegExp _stop = RegExp(
  r'^(?:\d{3,4}[pi]|4k|8k|uhd|fhd|hd|sd|bluray|blu-ray|bdrip|brrip|bdremux|'
  'remux|web-?dl|web-?rip|web|hdtv|pdtv|dvdrip|dvdscr|dvd|hdrip|cam|ts|'
  r'x26[45]|h\.?26[45]|hevc|avc|av1|vp9|xvid|divx|10bit|8bit|hdr10\+?|hdr|'
  r'dv|dovi|sdr|aac\d?(?:\.\d)?|ac3|eac3|dd\+?p?\d?(?:\.\d)?|dts(?:-hd)?|'
  r'truehd|atmos|flac|opus|mp3|ma|5\.1|7\.1|2\.0|proper|repack|real|'
  'extended|unrated|uncut|remastered|imax|internal|limited|multi|dual|'
  r'subbed|dubbed|complete|nf|amzn|dsnp|hmax|atvp|hulu)$',
  caseSensitive: false,
);

final RegExp _sxe = RegExp(
  r'(?:^|[\s._\-\[(])s(\d{1,2})[\s._]?e(\d{1,4})(?:(?:[\s._-]?e|-)(\d{1,4}))?(?=$|[\s._\-\])])',
  caseSensitive: false,
);
final RegExp _nxn = RegExp(
  r'(?:^|[\s._\-\[(])(\d{1,2})x(\d{2,3})(?=$|[\s._\-\])])',
  caseSensitive: false,
);
final RegExp _seasonOnly = RegExp(
  r'(?:^|[\s._-])(?:season|series|staffel|saison|temporada)[\s._-]?(\d{1,2})(?=$|[\s._-])',
  caseSensitive: false,
);
final RegExp _year = RegExp(
  r'(?:^|[\s._\-\[(])((?:19|20)\d{2})(?=$|[\s._\-\])])',
);
final RegExp _bracketed = RegExp(r'\[[^\]]*\]|\{[^}]*\}');
final RegExp _absEpisode = RegExp(r'\s-\s(\d{1,4})(?:v\d)?(?:\s|$)');
final RegExp _trailingGroup = RegExp(r'-([A-Za-z0-9]{2,15})$');
final RegExp _leadingGroup = RegExp(r'^\[([^\]]+)\]');

/// Parses release-style video file names into title, year and episode
/// numbers. Release groups, resolutions, sources and codecs are ignored.
/// [parentFolders] (nearest first) fill in a series title when the file
/// name carries only episode numbers (`Show/Season 1/S01E02.mkv`).
ParsedName parseVideoFileName(
  String fileName, {
  List<String> parentFolders = const [],
}) {
  var name = _stripExtension(fileName).trim();
  String? group;
  final lead = _leadingGroup.firstMatch(name);
  if (lead != null) {
    group = lead.group(1);
    name = name.substring(lead.end).trim();
  }

  // Season/episode markers win over years for splitting the title.
  int? season;
  int? episode;
  int? episodeEnd;
  int? absolute;
  var cut = -1;
  var after = '';
  final sxe = _sxe.firstMatch(name) ?? _nxn.firstMatch(name);
  if (sxe != null) {
    season = int.parse(sxe.group(1)!);
    episode = int.parse(sxe.group(2)!);
    final end = sxe.groupCount >= 3 ? sxe.group(3) : null;
    episodeEnd = end == null ? null : int.parse(end);
    cut = sxe.start;
    after = name.substring(sxe.end);
  }

  final cleaned = name.replaceAll(_bracketed, ' ');
  if (sxe == null) {
    final abs = _absEpisode.firstMatch(cleaned);
    if (abs != null && lead != null) {
      absolute = int.parse(abs.group(1)!);
      cut = -2;
      name = cleaned.substring(0, abs.start);
    }
  }

  int? year;
  final head = cut >= 0 ? name.substring(0, cut) : name;
  // The last year-looking token is the release year ("2001 A Space Odyssey 1968").
  final years = _year.allMatches(head.replaceAll(_bracketed, ' ')).toList();
  var titlePart = head.replaceAll(_bracketed, ' ');
  if (years.isNotEmpty) {
    final m = years.length > 1 || years.first.start > 0 ? years.last : null;
    if (m != null) {
      year = int.parse(m.group(1)!);
      titlePart = titlePart.substring(0, m.start);
    }
  }
  if (sxe == null && years.isEmpty) {
    final g = _trailingGroup.firstMatch(titlePart.trim());
    if (g != null && _looksLikeRelease(titlePart)) {
      group ??= g.group(1);
    }
  }

  final tokens = _tokens(titlePart);
  final kept = <String>[];
  for (final t in tokens) {
    if (_stop.hasMatch(t) && kept.isNotEmpty) break;
    kept.add(t);
  }
  var title = _titleCase(kept.join(' '));
  if (group == null) {
    final g = _trailingGroup.firstMatch(_stripExtension(fileName));
    if (g != null &&
        (sxe != null || year != null || _looksLikeRelease(fileName))) {
      group = g.group(1);
    }
  }

  String? episodeTitle;
  if (sxe != null) {
    final rest = _tokens(after.replaceAll(_bracketed, ' '));
    final epWords = <String>[];
    for (final t in rest) {
      if (_stop.hasMatch(t) || _year.hasMatch(' $t')) break;
      epWords.add(t);
    }
    if (epWords.isNotEmpty && epWords.length <= 12) {
      var et = epWords.join(' ');
      if (group != null && et.endsWith(group)) {
        et = et.substring(0, et.length - group.length).trim();
      }
      if (et.isNotEmpty) episodeTitle = et;
    }
  }

  if (title.isEmpty && (season != null || absolute != null)) {
    title = _seriesFromFolders(parentFolders) ?? '';
  }
  if (season == null && episode != null) season = 1;
  if (episode != null && season == null) {
    for (final f in parentFolders) {
      final s = _seasonOnly.firstMatch(f);
      if (s != null) season = int.parse(s.group(1)!);
    }
  }
  if (title.isEmpty) {
    title = _titleCase(_tokens(_stripExtension(fileName)).join(' '));
  }

  return ParsedName(
    title: title,
    year: year,
    season: season,
    episode: episode,
    episodeEnd: episodeEnd,
    absoluteEpisode: absolute,
    episodeTitle: episodeTitle,
    releaseGroup: group,
  );
}

/// Display title for any file: extension and separators removed.
String cleanTitle(String fileName) {
  final t = _tokens(_stripExtension(fileName)).join(' ');
  return t.isEmpty ? fileName : t;
}

/// Sort key: case-folded, leading articles moved out of the way.
String sortTitle(String title) {
  final lower = title.toLowerCase().trim();
  for (final article in const ['the ', 'a ', 'an ']) {
    if (lower.startsWith(article) && lower.length > article.length) {
      return lower.substring(article.length);
    }
  }
  return lower;
}

String? _seriesFromFolders(List<String> folders) {
  for (final f in folders) {
    if (_seasonOnly.hasMatch(f) ||
        RegExp(r'^s\d{1,2}$', caseSensitive: false).hasMatch(f)) {
      continue;
    }
    final p = parseVideoFileName('$f.x');
    if (p.title.isNotEmpty) return p.title;
  }
  return null;
}

bool _looksLikeRelease(String s) =>
    _tokens(s).any(_stop.hasMatch) || s.contains('.');

String _stripExtension(String name) {
  final dot = name.lastIndexOf('.');
  if (dot <= 0) return name;
  final ext = name.substring(dot + 1);
  return ext.length <= 5 &&
          !ext.contains(' ') &&
          RegExp(r'^[A-Za-z0-9]+$').hasMatch(ext)
      ? name.substring(0, dot)
      : name;
}

List<String> _tokens(String s) => s
    .replaceAll(RegExp('[._]+'), ' ')
    .replaceAll(RegExp('[()]'), ' ')
    .split(RegExp(r'\s+'))
    .map((t) => t.replaceAll(RegExp(r'^-+|-+$'), ''))
    .where((t) => t.isNotEmpty)
    .toList();

String _titleCase(String s) => s.trim();
