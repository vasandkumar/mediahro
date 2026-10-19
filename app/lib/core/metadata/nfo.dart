import 'package:mediahro/core/parsers/xml_lite.dart';
import 'package:meta/meta.dart';

/// Kodi-style `.nfo` sidecar (movie.nfo, tvshow.nfo, `<file>.nfo`), read
/// before any online lookup so curated libraries work offline (LIB-011).
@immutable
final class NfoInfo {
  const NfoInfo({
    this.title,
    this.year,
    this.plot,
    this.rating,
    this.tmdbId,
    this.tvdbId,
    this.imdbId,
    this.season,
    this.episode,
    this.showTitle,
    this.actors = const [],
    this.directors = const [],
    this.isEpisode = false,
  });

  final String? title;
  final int? year;
  final String? plot;
  final double? rating;
  final String? tmdbId;
  final String? tvdbId;
  final String? imdbId;
  final int? season;
  final int? episode;
  final String? showTitle;
  final List<(String, String?)> actors;
  final List<String> directors;
  final bool isEpisode;
}

/// Parses an NFO document, or returns null when it is not NFO XML (some
/// NFOs are just a URL line).
NfoInfo? parseNfo(String text) {
  final XmlElement root;
  try {
    root = parseXml(
      text,
      limits: const XmlLimits(maxLength: 1 << 20, maxNodes: 20000),
    );
  } on XmlFormatException {
    return null;
  }
  if (!const {'movie', 'tvshow', 'episodedetails'}.contains(root.localName)) {
    return null;
  }
  String? uid(String type) {
    for (final u in root.all('uniqueid')) {
      if (u.attr('type')?.toLowerCase() == type) return u.text;
    }
    return switch (type) {
      'tmdb' => root.childText('tmdbid'),
      'imdb' => root.childText('imdbid') ?? root.childText('id'),
      _ => null,
    };
  }

  final year =
      int.tryParse(root.childText('year') ?? '') ??
      int.tryParse(
        (root.childText('premiered') ?? root.childText('aired') ?? '')
            .split('-')
            .first,
      );
  return NfoInfo(
    title: root.childText('title'),
    year: year,
    plot: root.childText('plot'),
    rating: double.tryParse(root.childText('rating') ?? ''),
    tmdbId: uid('tmdb'),
    tvdbId: uid('tvdb'),
    imdbId: uid('imdb'),
    season: int.tryParse(root.childText('season') ?? ''),
    episode: int.tryParse(root.childText('episode') ?? ''),
    showTitle: root.childText('showtitle'),
    isEpisode: root.localName == 'episodedetails',
    actors: [
      for (final a in root.all('actor'))
        if (a.childText('name') case final String n when n.isNotEmpty)
          (n, a.childText('role')),
    ],
    directors: [
      for (final d in root.all('director'))
        if (d.text.isNotEmpty) d.text,
    ],
  );
}
