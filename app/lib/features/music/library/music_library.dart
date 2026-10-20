import 'package:drift/drift.dart';
import 'package:mediahro/core/db/library_database.dart';
import 'package:mediahro/core/rules/rule_sql.dart';
import 'package:meta/meta.dart';

/// One song row of the music library (MUS-001).
@immutable
final class MusicTrack {
  const MusicTrack({
    required this.itemId,
    required this.sourceId,
    required this.relPath,
    required this.parentPath,
    required this.title,
    this.artist,
    this.albumArtist,
    this.album,
    this.genre,
    this.composer,
    this.year,
    this.trackNumber,
    this.discNumber,
    this.duration,
    this.trackGainDb,
    this.albumGainDb,
    this.loudnessLufs,
    this.addedAt,
    this.playCount = 0,
  });

  final int itemId;
  final int sourceId;
  final String relPath;
  final String parentPath;
  final String title;
  final String? artist;
  final String? albumArtist;
  final String? album;
  final String? genre;
  final String? composer;
  final int? year;
  final int? trackNumber;
  final int? discNumber;
  final Duration? duration;
  final double? trackGainDb;
  final double? albumGainDb;
  final double? loudnessLufs;
  final DateTime? addedAt;
  final int playCount;

  /// Album identity used for gapless-album detection and album views:
  /// album + album artist, or album + folder when no album artist is set
  /// (keeps compilations together).
  String? get albumKey => album == null
      ? null
      : '${album!.toLowerCase()}|${albumArtist?.toLowerCase() ?? '$sourceId:$parentPath'}';

  @override
  bool operator ==(Object other) =>
      other is MusicTrack && other.itemId == itemId && other.title == title;

  @override
  int get hashCode => Object.hash(itemId, title);
}

/// An album group (MUS-001).
@immutable
final class MusicAlbum {
  const MusicAlbum({
    required this.title,
    required this.groupKey,
    required this.trackCount,
    required this.coverItemId,
    this.albumArtist,
    this.artistCount = 1,
    this.firstArtist,
    this.year,
    this.duration,
  });

  final String title;

  /// `lower(album)|lower(album artist or source:folder)`; see
  /// [MusicTrack.albumKey].
  final String groupKey;
  final String? albumArtist;

  /// Distinct track artists; above one with no album artist shows as
  /// "Various artists".
  final int artistCount;
  final String? firstArtist;
  final int trackCount;
  final int coverItemId;
  final int? year;
  final Duration? duration;

  bool get isCompilation => albumArtist == null && artistCount > 1;

  /// The artist line to show, or null for "Various artists".
  String? get displayArtist =>
      albumArtist ?? (artistCount > 1 ? null : firstArtist);
}

/// A named group with a count: artists, genres, composers, years.
@immutable
final class MusicGroup {
  const MusicGroup(
    this.name,
    this.trackCount,
    this.coverItemId, {
    this.albumCount = 0,
  });

  final String name;
  final int trackCount;
  final int albumCount;
  final int coverItemId;
}

enum SongSort { title, artist, album, dateAdded, duration, playCount, year }

enum AlbumSort { title, artist, year, dateAdded }

enum GroupField { artist, albumArtist, genre, composer, year }

/// Read models for the music library views (MUS-001) over B2's index. All
/// queries honour [Visibility] (LIB-013) and exclude missing files.
final class MusicLibrary {
  MusicLibrary(this.db);

  final LibraryDatabase db;

  static const _albumGroup =
      "lower(a.album) || '|' || coalesce(lower(a.album_artist), i.source_id || ':' || i.parent_path)";

  static const _trackColumns =
      'i.id, i.source_id, i.rel_path, i.parent_path, i.title, i.duration_ms, '
      'i.added_at, i.play_count, a.artist, a.album_artist, a.album, a.genre, '
      'a.composer, a.year, a.track_number, a.disc_number, a.track_gain_db, '
      'a.album_gain_db, a.loudness_lufs';

  String _where(Visibility v) => "i.kind = 'audio' AND ${v.sql}";

  /// Every song, sorted.
  Future<List<MusicTrack>> songs({
    SongSort sort = SongSort.title,
    bool descending = false,
    Visibility visibility = Visibility.standard,
    int? limit,
  }) {
    final dir = descending ? 'DESC' : 'ASC';
    final order = switch (sort) {
      SongSort.title => 'i.sort_title $dir',
      SongSort.artist =>
        'lower(coalesce(a.artist, a.album_artist)) $dir NULLS LAST, lower(a.album), a.disc_number, a.track_number, i.sort_title',
      SongSort.album =>
        'lower(a.album) $dir NULLS LAST, a.disc_number, a.track_number, i.sort_title',
      SongSort.dateAdded => 'i.added_at $dir, i.id $dir',
      SongSort.duration => 'i.duration_ms $dir NULLS LAST, i.sort_title',
      SongSort.playCount => 'i.play_count $dir, i.sort_title',
      SongSort.year => 'a.year $dir NULLS LAST, lower(a.album), a.track_number',
    };
    return _tracks(
      'WHERE ${_where(visibility)} ORDER BY $order${limit == null ? '' : ' LIMIT $limit'}',
      const [],
    );
  }

  Future<List<MusicTrack>> tracksByIds(List<int> ids) async {
    if (ids.isEmpty) return const [];
    final rows = await _tracks(
      'WHERE i.id IN (${List.filled(ids.length, '?').join(',')})',
      [for (final id in ids) Variable.withInt(id)],
    );
    final byId = {for (final t in rows) t.itemId: t};
    return [for (final id in ids) ?byId[id]];
  }

  Future<MusicTrack?> track(int itemId) async {
    final r = await tracksByIds([itemId]);
    return r.isEmpty ? null : r.first;
  }

  Future<List<MusicAlbum>> albums({
    AlbumSort sort = AlbumSort.title,
    bool descending = false,
    String? artist,
    Visibility visibility = Visibility.standard,
  }) async {
    final dir = descending ? 'DESC' : 'ASC';
    final order = switch (sort) {
      AlbumSort.title => 'lower(t) $dir',
      AlbumSort.artist =>
        'lower(coalesce(aa, fa)) $dir NULLS LAST, y, lower(t)',
      AlbumSort.year => 'y $dir NULLS LAST, lower(t)',
      AlbumSort.dateAdded => 'added $dir',
    };
    final vars = <Variable<Object>>[];
    var filter = '';
    if (artist != null) {
      filter = ' AND (lower(a.artist) = lower(?) OR lower(a.album_artist) = lower(?))';
      vars.addAll([Variable.withString(artist), Variable.withString(artist)]);
    }
    final rows = await db
        .customSelect(
          'SELECT $_albumGroup AS k, min(a.album) AS t, min(a.album_artist) AS aa, '
          'min(a.artist) AS fa, count(DISTINCT lower(a.artist)) AS ac, '
          'count(*) AS n, min(i.id) AS c, max(a.year) AS y, '
          'sum(i.duration_ms) AS d, max(i.added_at) AS added '
          '$itemJoins WHERE ${_where(visibility)} AND a.album IS NOT NULL$filter '
          'GROUP BY k ORDER BY $order',
          variables: vars,
          readsFrom: {db.items, db.audioMeta},
        )
        .get();
    return [
      for (final r in rows)
        MusicAlbum(
          title: r.read<String>('t'),
          groupKey: r.read<String>('k'),
          albumArtist: r.readNullable<String>('aa'),
          firstArtist: r.readNullable<String>('fa'),
          artistCount: r.read<int>('ac'),
          trackCount: r.read<int>('n'),
          coverItemId: r.read<int>('c'),
          year: r.readNullable<int>('y'),
          duration: switch (r.readNullable<int>('d')) {
            final int ms => Duration(milliseconds: ms),
            null => null,
          },
        ),
    ];
  }

  /// Tracks of one album in disc/track order.
  Future<List<MusicTrack>> albumTracks(
    String groupKey, {
    Visibility visibility = Visibility.standard,
  }) => _tracks(
    'WHERE ${_where(visibility)} AND $_albumGroup = ? '
    'ORDER BY coalesce(a.disc_number, 1), a.track_number NULLS LAST, i.sort_title',
    [Variable.withString(groupKey)],
  );

  /// Artists (track artists) or album artists, with counts.
  Future<List<MusicGroup>> groups(
    GroupField field, {
    Visibility visibility = Visibility.standard,
  }) async {
    final expr = switch (field) {
      GroupField.artist => 'a.artist',
      GroupField.albumArtist => 'coalesce(a.album_artist, a.artist)',
      GroupField.genre => 'a.genre',
      GroupField.composer => 'a.composer',
      GroupField.year => 'a.year',
    };
    final order = field == GroupField.year ? 'k DESC' : 'lower(k)';
    final rows = await db
        .customSelect(
          'SELECT $expr AS k, count(*) AS n, count(DISTINCT $_albumGroup) AS al, '
          'min(i.id) AS c $itemJoins WHERE ${_where(visibility)} AND $expr IS NOT NULL '
          "AND trim($expr) != '' GROUP BY ${field == GroupField.year ? 'k' : 'lower(k)'} ORDER BY $order",
          readsFrom: {db.items, db.audioMeta},
        )
        .get();
    return [
      for (final r in rows)
        MusicGroup(
          '${r.data['k']}',
          r.read<int>('n'),
          r.read<int>('c'),
          albumCount: r.read<int>('al'),
        ),
    ];
  }

  /// Tracks of one artist, genre, composer or year.
  Future<List<MusicTrack>> groupTracks(
    GroupField field,
    String value, {
    Visibility visibility = Visibility.standard,
  }) {
    final (cond, v) = switch (field) {
      GroupField.artist => (
        'lower(a.artist) = lower(?)',
        Variable.withString(value),
      ),
      GroupField.albumArtist => (
        'lower(coalesce(a.album_artist, a.artist)) = lower(?)',
        Variable.withString(value),
      ),
      GroupField.genre => (
        'lower(a.genre) = lower(?)',
        Variable.withString(value),
      ),
      GroupField.composer => (
        'lower(a.composer) = lower(?)',
        Variable.withString(value),
      ),
      GroupField.year => (
        'a.year = ?',
        Variable<Object>(int.tryParse(value) ?? -1),
      ),
    };
    return _tracks(
      'WHERE ${_where(visibility)} AND $cond '
      'ORDER BY a.year NULLS LAST, lower(a.album), coalesce(a.disc_number, 1), '
      'a.track_number NULLS LAST, i.sort_title',
      [v],
    );
  }

  /// Audio tracks directly inside a folder (folder view, MUS-001).
  Future<List<MusicTrack>> folderTracks(
    int sourceId,
    String path, {
    Visibility visibility = Visibility.standard,
  }) => _tracks(
    'WHERE ${_where(visibility)} AND i.source_id = ? AND i.parent_path = ? '
    'ORDER BY coalesce(a.disc_number, 1), a.track_number NULLS LAST, i.sort_title',
    [Variable.withInt(sourceId), Variable.withString(path)],
  );

  /// Recently played songs, newest first (MUS-007 history, LIB-015 events).
  Future<List<(MusicTrack, DateTime)>> history({
    int limit = 100,
    Visibility visibility = Visibility.standard,
  }) async {
    final rows = await db
        .customSelect(
          'SELECT $_trackColumns, e.at AS played_at $itemJoins '
          'JOIN play_event e ON e.item_id = i.id '
          'WHERE ${_where(visibility)} ORDER BY e.at DESC, e.id DESC LIMIT $limit',
          readsFrom: {db.items, db.audioMeta, db.playEvents},
        )
        .get();
    return [for (final r in rows) (_track(r), r.read<DateTime>('played_at'))];
  }

  /// Number of songs, for the empty state and headers.
  Future<int> songCount({Visibility visibility = Visibility.standard}) async {
    final r = await db
        .customSelect(
          'SELECT count(*) AS n FROM item i WHERE ${_where(visibility)}',
          readsFrom: {db.items},
        )
        .getSingle();
    return r.read<int>('n');
  }

  /// Fires when the music part of the index changes.
  Stream<void> changes() => db
      .tableUpdates(
        TableUpdateQuery.onAllTables([db.items, db.audioMeta, db.artworks]),
      )
      .map((_) {});

  Future<List<MusicTrack>> _tracks(
    String tail,
    List<Variable<Object>> vars,
  ) async {
    final rows = await db
        .customSelect(
          'SELECT $_trackColumns $itemJoins $tail',
          variables: vars,
          readsFrom: {db.items, db.audioMeta},
        )
        .get();
    return [for (final r in rows) _track(r)];
  }

  static MusicTrack _track(QueryRow r) => MusicTrack(
    itemId: r.read<int>('id'),
    sourceId: r.read<int>('source_id'),
    relPath: r.read<String>('rel_path'),
    parentPath: r.read<String>('parent_path'),
    title: r.read<String>('title'),
    artist: r.readNullable<String>('artist'),
    albumArtist: r.readNullable<String>('album_artist'),
    album: r.readNullable<String>('album'),
    genre: r.readNullable<String>('genre'),
    composer: r.readNullable<String>('composer'),
    year: r.readNullable<int>('year'),
    trackNumber: r.readNullable<int>('track_number'),
    discNumber: r.readNullable<int>('disc_number'),
    duration: switch (r.readNullable<int>('duration_ms')) {
      final int ms => Duration(milliseconds: ms),
      null => null,
    },
    trackGainDb: r.readNullable<double>('track_gain_db'),
    albumGainDb: r.readNullable<double>('album_gain_db'),
    loudnessLufs: r.readNullable<double>('loudness_lufs'),
    addedAt: r.readNullable<DateTime>('added_at'),
    playCount: r.read<int>('play_count'),
  );
}
