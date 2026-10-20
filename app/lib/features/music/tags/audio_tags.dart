import 'dart:typed_data';

import 'package:mediahro/features/music/tags/byte_reader.dart';
import 'package:meta/meta.dart';

/// Where a tag block came from (MUS-002). The editor (MUS-003) writes back
/// to the same container.
enum TagContainer {
  id3v1,
  id3v2,
  vorbisComment,
  ape,
  mp4,
  asf,
  riffInfo,
  aiffText,
}

/// Picture role, ID3 APIC / FLAC PICTURE numbering.
enum PictureType {
  other,
  fileIcon,
  otherFileIcon,
  frontCover,
  backCover,
  leaflet,
  media,
  leadArtist,
  artist,
  conductor,
  band,
  composer,
  lyricist,
  recordingLocation,
  duringRecording,
  duringPerformance,
  screenCapture,
  brightFish,
  illustration,
  bandLogo,
  publisherLogo;

  static PictureType fromCode(int code) =>
      code >= 0 && code < values.length ? values[code] : other;
}

@immutable
final class EmbeddedPicture {
  const EmbeddedPicture({
    required this.type,
    required this.mimeType,
    required this.bytes,
    this.description = '',
  });

  final PictureType type;
  final String mimeType;
  final String description;
  final Uint8List bytes;
}

/// One time-stamped lyric line from an ID3 SYLT frame (MUS-005).
@immutable
final class SyncedLyricLine {
  const SyncedLyricLine(this.time, this.text);

  final Duration time;
  final String text;

  @override
  bool operator ==(Object other) =>
      other is SyncedLyricLine && other.time == time && other.text == text;

  @override
  int get hashCode => Object.hash(time, text);

  @override
  String toString() => 'SyncedLyricLine($time, $text)';
}

/// A chapter mark from the container (ID3 CHAP, Nero `chpl`, OverDrive
/// MediaMarkers) for audiobook mode (POD-001).
@immutable
final class TagChapter {
  const TagChapter(this.start, this.title, {this.end});

  final Duration start;
  final Duration? end;
  final String title;

  @override
  bool operator ==(Object other) =>
      other is TagChapter &&
      other.start == start &&
      other.end == end &&
      other.title == title;

  @override
  int get hashCode => Object.hash(start, end, title);

  @override
  String toString() => 'TagChapter($start, $title)';
}

/// Canonical field names (the Vorbis comment vocabulary, which every other
/// container maps onto). Values are lists: artists, genres and composers are
/// multi-valued (MUS-002).
abstract final class TagField {
  static const title = 'TITLE';
  static const artist = 'ARTIST';
  static const albumArtist = 'ALBUMARTIST';
  static const album = 'ALBUM';
  static const genre = 'GENRE';
  static const composer = 'COMPOSER';
  static const conductor = 'CONDUCTOR';
  static const lyricist = 'LYRICIST';
  static const date = 'DATE';
  static const originalDate = 'ORIGINALDATE';
  static const trackNumber = 'TRACKNUMBER';
  static const trackTotal = 'TRACKTOTAL';
  static const discNumber = 'DISCNUMBER';
  static const discTotal = 'DISCTOTAL';
  static const discSubtitle = 'DISCSUBTITLE';
  static const comment = 'COMMENT';
  static const lyrics = 'LYRICS';
  static const bpm = 'BPM';
  static const compilation = 'COMPILATION';
  static const label = 'LABEL';
  static const isrc = 'ISRC';
  static const copyright = 'COPYRIGHT';
  static const encoder = 'ENCODER';
  static const titleSort = 'TITLESORT';
  static const artistSort = 'ARTISTSORT';
  static const albumSort = 'ALBUMSORT';
  static const albumArtistSort = 'ALBUMARTISTSORT';
  static const grouping = 'GROUPING';
  static const rating = 'RATING';
  static const trackGain = 'REPLAYGAIN_TRACK_GAIN';
  static const trackPeak = 'REPLAYGAIN_TRACK_PEAK';
  static const albumGain = 'REPLAYGAIN_ALBUM_GAIN';
  static const albumPeak = 'REPLAYGAIN_ALBUM_PEAK';
  static const mbTrackId = 'MUSICBRAINZ_TRACKID';
  static const mbRecordingId = 'MUSICBRAINZ_RECORDINGID';
  static const mbAlbumId = 'MUSICBRAINZ_ALBUMID';
  static const mbArtistId = 'MUSICBRAINZ_ARTISTID';
  static const mbAlbumArtistId = 'MUSICBRAINZ_ALBUMARTISTID';
  static const mbReleaseGroupId = 'MUSICBRAINZ_RELEASEGROUPID';
  static const mbReleaseTrackId = 'MUSICBRAINZ_RELEASETRACKID';
  static const acoustIdId = 'ACOUSTID_ID';
  static const acoustIdFingerprint = 'ACOUSTID_FINGERPRINT';

  /// Fields the batch editor shows (MUS-003), in display order.
  static const List<String> editable = [
    title,
    artist,
    albumArtist,
    album,
    trackNumber,
    trackTotal,
    discNumber,
    discTotal,
    date,
    genre,
    composer,
    conductor,
    lyricist,
    comment,
    bpm,
    compilation,
    label,
    isrc,
    copyright,
    grouping,
    lyrics,
  ];
}

/// Everything MUS-002 reads from one file. Field values are merged from
/// every tag block in the file in priority order (ID3v2/native first, then
/// APE, then ID3v1).
@immutable
final class AudioTags {
  const AudioTags({
    this.fields = const {},
    this.pictures = const [],
    this.syncedLyrics = const [],
    this.chapters = const [],
    this.containers = const {},
    this.duration,
  });

  static const empty = AudioTags();

  /// Canonical upper-case key → values (see [TagField]).
  final Map<String, List<String>> fields;
  final List<EmbeddedPicture> pictures;
  final List<SyncedLyricLine> syncedLyrics;
  final List<TagChapter> chapters;
  final Set<TagContainer> containers;

  /// Duration when the container states it cheaply (MP4 `mvhd`, FLAC
  /// STREAMINFO); the engine probe is authoritative otherwise.
  final Duration? duration;

  bool get isEmpty =>
      fields.isEmpty &&
      pictures.isEmpty &&
      syncedLyrics.isEmpty &&
      chapters.isEmpty;

  List<String> values(String key) => fields[key] ?? const [];

  String? first(String key) {
    final v = fields[key];
    return v == null || v.isEmpty ? null : v.first;
  }

  String? get title => first(TagField.title);
  List<String> get artists => values(TagField.artist);
  List<String> get albumArtists => values(TagField.albumArtist);
  String? get album => first(TagField.album);
  List<String> get genres => values(TagField.genre);
  List<String> get composers => values(TagField.composer);
  String? get lyrics => first(TagField.lyrics);
  String? get comment => first(TagField.comment);

  /// Display form of a multi-valued artist field.
  String? get artist => _joined(artists);
  String? get albumArtist => _joined(albumArtists);
  String? get genre => _joined(genres);
  String? get composer => _joined(composers);

  int? get year {
    final d = first(TagField.date) ?? first(TagField.originalDate);
    if (d == null) return null;
    final m = RegExp(r'(\d{4})').firstMatch(d);
    return m == null ? null : int.parse(m.group(1)!);
  }

  int? get trackNumber => _leadingInt(first(TagField.trackNumber));
  int? get trackTotal =>
      _leadingInt(first(TagField.trackTotal)) ??
      _afterSlash(first(TagField.trackNumber));
  int? get discNumber => _leadingInt(first(TagField.discNumber));
  int? get discTotal =>
      _leadingInt(first(TagField.discTotal)) ??
      _afterSlash(first(TagField.discNumber));

  bool get compilation {
    final c = first(TagField.compilation);
    return c == '1' || c?.toLowerCase() == 'true';
  }

  double? get trackGainDb => _gain(first(TagField.trackGain));
  double? get albumGainDb => _gain(first(TagField.albumGain));
  double? get trackPeak => double.tryParse(first(TagField.trackPeak) ?? '');
  double? get albumPeak => double.tryParse(first(TagField.albumPeak) ?? '');

  /// MusicBrainz identifiers present in the file.
  Map<String, String> get musicBrainzIds => {
    for (final k in fields.keys)
      if (k.startsWith('MUSICBRAINZ_') && first(k) != null) k: first(k)!,
  };

  /// The front cover, or the first picture when none is marked front.
  EmbeddedPicture? get cover {
    for (final p in pictures) {
      if (p.type == PictureType.frontCover) return p;
    }
    return pictures.isEmpty ? null : pictures.first;
  }

  AudioTags copyWith({
    Map<String, List<String>>? fields,
    List<EmbeddedPicture>? pictures,
    List<SyncedLyricLine>? syncedLyrics,
    List<TagChapter>? chapters,
    Set<TagContainer>? containers,
    Duration? duration,
  }) => AudioTags(
    fields: fields ?? this.fields,
    pictures: pictures ?? this.pictures,
    syncedLyrics: syncedLyrics ?? this.syncedLyrics,
    chapters: chapters ?? this.chapters,
    containers: containers ?? this.containers,
    duration: duration ?? this.duration,
  );

  static String? _joined(List<String> v) => v.isEmpty ? null : v.join('; ');

  static int? _leadingInt(String? s) {
    if (s == null) return null;
    final m = RegExp(r'^\s*(\d+)').firstMatch(s);
    return m == null ? null : int.tryParse(m.group(1)!);
  }

  static int? _afterSlash(String? s) {
    if (s == null) return null;
    final m = RegExp(r'/\s*(\d+)').firstMatch(s);
    return m == null ? null : int.tryParse(m.group(1)!);
  }

  static double? _gain(String? s) {
    if (s == null) return null;
    final m = RegExp(r'([-+]?\d+(?:[.,]\d+)?)').firstMatch(s);
    return m == null ? null : double.tryParse(m.group(1)!.replaceAll(',', '.'));
  }
}

/// Accumulates fields while parsing; the first container to set a key wins
/// unless the key is cleared first.
final class TagBuilder {
  final Map<String, List<String>> fields = {};
  final List<EmbeddedPicture> pictures = [];
  final List<SyncedLyricLine> syncedLyrics = [];
  final List<TagChapter> chapters = [];
  final Set<TagContainer> containers = {};
  Duration? duration;
  int _count = 0;

  /// Adds values under [key] (upper-cased). Blank values are dropped.
  void add(String key, Iterable<String> values) {
    if (++_count > _maxFieldsTotal) return;
    final k = key.toUpperCase();
    final clean = [
      for (final v in values)
        if (_trim(v).isNotEmpty) _cap(_trim(v)),
    ];
    if (clean.isEmpty) return;
    final list = fields[k] ??= [];
    for (final v in clean) {
      if (!list.contains(v)) list.add(v);
    }
  }

  void addOne(String key, String value) => add(key, [value]);

  void addPicture(EmbeddedPicture p) {
    if (pictures.length >= TagLimits.maxPictures || p.bytes.isEmpty) return;
    pictures.add(p);
  }

  void addChapter(TagChapter c) {
    if (chapters.length < TagLimits.maxChapters) chapters.add(c);
  }

  /// Merges a lower-priority block: only keys not yet set are taken.
  void mergeMissing(TagBuilder other) {
    other.fields.forEach((k, v) => fields.putIfAbsent(k, () => v));
    if (pictures.isEmpty) pictures.addAll(other.pictures);
    if (syncedLyrics.isEmpty) syncedLyrics.addAll(other.syncedLyrics);
    if (chapters.isEmpty) chapters.addAll(other.chapters);
    containers.addAll(other.containers);
    duration ??= other.duration;
  }

  AudioTags build() {
    chapters.sort((a, b) => a.start.compareTo(b.start));
    syncedLyrics.sort((a, b) => a.time.compareTo(b.time));
    return AudioTags(
      fields: {
        for (final e in fields.entries) e.key: List.unmodifiable(e.value),
      },
      pictures: List.unmodifiable(pictures),
      syncedLyrics: List.unmodifiable(syncedLyrics),
      chapters: List.unmodifiable(chapters),
      containers: Set.unmodifiable(containers),
      duration: duration,
    );
  }

  static const int _maxFieldsTotal = TagLimits.maxFields * 4;

  static String _trim(String v) =>
      v.replaceAll('\u0000', '').replaceAll('﻿', '').trim();

  static String _cap(String v) => v.length > TagLimits.maxTextBytes
      ? v.substring(0, TagLimits.maxTextBytes)
      : v;
}
