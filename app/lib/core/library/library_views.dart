import 'package:drift/drift.dart';
import 'package:mediahro/core/db/library_database.dart';
import 'package:mediahro/core/rules/rule_sql.dart';
import 'package:meta/meta.dart';

/// The three modes of the shell (CORE-001); each has its own library view.
enum LibraryMode {
  video({ItemKind.video}),
  music({ItemKind.audio}),
  photos({ItemKind.image, ItemKind.video});

  const LibraryMode(this.kinds);

  final Set<ItemKind> kinds;
}

/// Folder tree or curated library view, persisted per mode (LIB-004).
enum ViewMode { folders, library }

/// An item with its resume state, for home rows (LIB-006).
@immutable
final class ResumeItem {
  const ResumeItem(this.item, this.position, this.duration);

  final ItemRow item;
  final Duration position;
  final Duration? duration;

  /// 0…1 for the resume bar, null when the duration is unknown.
  double? get fraction {
    final d =
        duration ??
        (item.durationMs == null
            ? null
            : Duration(milliseconds: item.durationMs!));
    if (d == null || d == Duration.zero) return null;
    return (position.inMilliseconds / d.inMilliseconds).clamp(0, 1).toDouble();
  }
}

/// A folder in folder mode with its media count.
@immutable
final class FolderEntry {
  const FolderEntry(this.sourceId, this.path, this.name, this.itemCount);

  final int sourceId;

  /// Relative path of the folder (`''` for the source root).
  final String path;
  final String name;
  final int itemCount;
}

/// A group in library mode (LIB-012).
@immutable
final class Collection {
  const Collection(
    this.key,
    this.title,
    this.itemCount, {
    this.coverItemId,
    this.year,
  });

  /// Stable key for navigation (`artist:<name>`, `series:<id>`, ...).
  final String key;
  final String title;
  final int itemCount;
  final int? coverItemId;
  final int? year;
}

enum CollectionKind {
  series,
  seasons,
  movieCollections,
  albums,
  artists,
  genres,
  years,
  composers,
  photoAlbums,
  people,
  places,
}

/// Statistics (LIB-015).
@immutable
final class LibraryStats {
  const LibraryStats({
    required this.playCount,
    required this.timePlayed,
    required this.topItems,
    required this.bytesByKind,
    required this.bytesBySource,
    required this.countByKind,
  });

  final int playCount;
  final Duration timePlayed;
  final List<(ItemRow, int)> topItems;
  final Map<ItemKind, int> bytesByKind;
  final Map<int, int> bytesBySource;
  final Map<ItemKind, int> countByKind;
}

/// Read models for home rows, folder and library modes, collections and
/// statistics. Every query honours [Visibility] (LIB-013).
final class LibraryViews {
  LibraryViews(this.db, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final LibraryDatabase db;
  final DateTime Function() _clock;

  // ---- LIB-004 view mode, persisted per mode in the `setting` table.

  Future<ViewMode> viewMode(LibraryMode mode) async {
    final row =
        await (db.select(db.settingsTable)
              ..where((s) => s.key.equals('library.viewMode.${mode.name}')))
            .getSingleOrNull();
    return row == null ? ViewMode.library : ViewMode.values.byName(row.value);
  }

  Future<void> setViewMode(LibraryMode mode, ViewMode view) => db
      .into(db.settingsTable)
      .insertOnConflictUpdate(
        SettingsTableCompanion.insert(
          key: 'library.viewMode.${mode.name}',
          value: view.name,
        ),
      );

  // ---- LIB-006 home rows.

  /// Started but unfinished items, most recent first.
  Future<List<ResumeItem>> continueWatching(
    LibraryMode mode, {
    int limit = 20,
    Visibility visibility = Visibility.standard,
  }) async {
    final vars = <Variable<Object>>[];
    final rows = await db
        .customSelect(
          'SELECT i.*, pr.position_ms AS _pos, pr.duration_ms AS _dur $itemJoins '
          'WHERE ${visibility.sql} AND ${_kinds(mode, vars)} '
          'AND pr.position_ms > 0 AND pr.watched = 0 '
          'ORDER BY pr.updated_at DESC LIMIT $limit',
          variables: vars,
          readsFrom: {db.items, db.progress},
        )
        .get();
    return [
      for (final r in rows)
        ResumeItem(
          db.items.map(r.data),
          Duration(milliseconds: r.read<int>('_pos')),
          switch (r.readNullable<int>('_dur')) {
            final int ms => Duration(milliseconds: ms),
            null => null,
          },
        ),
    ];
  }

  Future<List<ItemRow>> recentlyAdded(
    LibraryMode mode, {
    int limit = 30,
    Visibility visibility = Visibility.standard,
  }) => _items(mode, 'ORDER BY i.added_at DESC, i.id DESC', limit, visibility);

  Future<List<ItemRow>> recentlyPlayed(
    LibraryMode mode, {
    int limit = 30,
    Visibility visibility = Visibility.standard,
  }) => _items(
    mode,
    'AND i.last_played_at IS NOT NULL ORDER BY i.last_played_at DESC',
    limit,
    visibility,
  );

  Future<List<ItemRow>> unwatched(
    LibraryMode mode, {
    int limit = 30,
    Visibility visibility = Visibility.standard,
  }) => _items(
    mode,
    'AND i.play_count = 0 AND coalesce(pr.watched, 0) = 0 '
    'AND coalesce(pr.position_ms, 0) = 0 ORDER BY i.added_at DESC',
    limit,
    visibility,
  );

  // ---- LIB-004 folder mode.

  /// Sub-folders of [path] in [sourceId] that contain media of [mode].
  Future<List<FolderEntry>> folders(
    int sourceId,
    String path,
    LibraryMode mode, {
    Visibility visibility = Visibility.standard,
  }) async {
    final vars = <Variable<Object>>[Variable.withInt(sourceId)];
    final prefix = path.isEmpty ? '' : '$path/';
    final kinds = _kinds(mode, vars);
    vars
      ..add(Variable.withString(prefix))
      ..add(Variable.withString(prefix));
    final rows = await db
        .customSelect(
          'SELECT i.rel_path FROM item i WHERE i.source_id = ? AND $kinds AND ${visibility.sql} '
          'AND substr(i.rel_path, 1, length(?)) = ? AND i.parent_path != ?',
          variables: [...vars, Variable.withString(path)],
          readsFrom: {db.items},
        )
        .get();
    final counts = <String, int>{};
    for (final r in rows) {
      final rest = r.read<String>('rel_path').substring(prefix.length);
      final slash = rest.indexOf('/');
      if (slash < 0) continue;
      final name = rest.substring(0, slash);
      counts[name] = (counts[name] ?? 0) + 1;
    }
    final names = counts.keys.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return [
      for (final n in names) FolderEntry(sourceId, '$prefix$n', n, counts[n]!),
    ];
  }

  /// Media directly inside [path].
  Future<List<ItemRow>> folderItems(
    int sourceId,
    String path,
    LibraryMode mode, {
    Visibility visibility = Visibility.standard,
  }) async {
    final vars = <Variable<Object>>[];
    final kinds = _kinds(mode, vars);
    final rows = await db
        .customSelect(
          'SELECT i.* FROM item i WHERE $kinds AND ${visibility.sql} '
          'AND i.source_id = ? AND i.parent_path = ? ORDER BY i.sort_title, i.name',
          variables: [
            ...vars,
            Variable.withInt(sourceId),
            Variable.withString(path),
          ],
          readsFrom: {db.items},
        )
        .get();
    return [for (final r in rows) db.items.map(r.data)];
  }

  // ---- LIB-012 collections.

  Future<List<Collection>> collections(
    CollectionKind kind, {
    String? within,
    Visibility visibility = Visibility.standard,
  }) async {
    final v = visibility.sql;
    final (sql, vars) = switch (kind) {
      CollectionKind.series => (
        'SELECT s.id AS k, s.title AS t, count(*) AS n, min(i.id) AS c, s.year AS y '
            '$itemJoins JOIN series s ON s.id = v.series_id WHERE $v GROUP BY s.id ORDER BY s.title',
        <Variable<Object>>[],
      ),
      CollectionKind.seasons => (
        'SELECT se.id AS k, se.title AS t, count(*) AS n, min(i.id) AS c, se.number AS y '
            '$itemJoins JOIN season se ON se.id = v.season_id WHERE $v AND se.series_id = ? '
            'GROUP BY se.id ORDER BY se.number',
        <Variable<Object>>[Variable.withInt(int.parse(within ?? '0'))],
      ),
      CollectionKind.movieCollections => (
        'SELECT co.id AS k, co.name AS t, count(*) AS n, min(i.id) AS c, NULL AS y '
            '$itemJoins JOIN collection co ON co.id = v.collection_id WHERE $v GROUP BY co.id ORDER BY co.name',
        <Variable<Object>>[],
      ),
      CollectionKind.albums => (
        'SELECT a.album AS k, a.album AS t, count(*) AS n, min(i.id) AS c, max(a.year) AS y '
            '$itemJoins WHERE $v AND a.album IS NOT NULL '
            "GROUP BY lower(a.album), lower(coalesce(a.album_artist, a.artist, '')) ORDER BY lower(a.album)",
        <Variable<Object>>[],
      ),
      CollectionKind.artists => _group('coalesce(a.album_artist, a.artist)', v),
      CollectionKind.genres => _group('a.genre', v),
      CollectionKind.composers => _group('a.composer', v),
      CollectionKind.years => (
        'SELECT coalesce(a.year, v.year) AS k, coalesce(a.year, v.year) AS t, count(*) AS n, '
            'min(i.id) AS c, coalesce(a.year, v.year) AS y $itemJoins '
            'WHERE $v AND coalesce(a.year, v.year) IS NOT NULL GROUP BY 1 ORDER BY 1 DESC',
        <Variable<Object>>[],
      ),
      // Photo albums are image playlists; smart albums are smart ones.
      CollectionKind.photoAlbums => (
        'SELECT p.id AS k, p.name AS t, count(pi.id) AS n, min(pi.item_id) AS c, NULL AS y '
            'FROM playlist p LEFT JOIN playlist_item pi ON pi.playlist_id = p.id '
            "WHERE p.mode = 'image' GROUP BY p.id ORDER BY p.name",
        <Variable<Object>>[],
      ),
      CollectionKind.people => (
        'SELECT p.id AS k, p.name AS t, count(*) AS n, min(i.id) AS c, NULL AS y '
            '$itemJoins JOIN item_person ip ON ip.item_id = i.id JOIN person p ON p.id = ip.person_id '
            'WHERE $v GROUP BY p.id ORDER BY count(*) DESC, p.name',
        <Variable<Object>>[],
      ),
      CollectionKind.places => (
        'SELECT pl.id AS k, pl.name AS t, count(*) AS n, min(i.id) AS c, NULL AS y '
            '$itemJoins JOIN place pl ON pl.id = im.place_id WHERE $v GROUP BY pl.id ORDER BY pl.name',
        <Variable<Object>>[],
      ),
    };
    final rows = await db.customSelect(sql, variables: vars).get();
    return [
      for (final r in rows)
        Collection(
          '${kind.name}:${r.data['k']}',
          '${r.data['t']}',
          r.read<int>('n'),
          coverItemId: r.readNullable<int>('c'),
          year: r.readNullable<int>('y'),
        ),
    ];
  }

  // ---- LIB-015 statistics.

  Future<LibraryStats> stats({DateTime? since, int top = 10}) async {
    final from =
        (since ?? DateTime.fromMillisecondsSinceEpoch(0))
            .millisecondsSinceEpoch ~/
        1000;
    final plays = await db
        .customSelect(
          'SELECT count(*) AS n, coalesce(sum(listened_ms), 0) AS ms FROM play_event WHERE at >= ?',
          variables: [Variable.withInt(from)],
        )
        .getSingle();
    final topRows = await db
        .customSelect(
          'SELECT i.*, count(*) AS _n FROM play_event e JOIN item i ON i.id = e.item_id '
          'WHERE e.at >= ? AND ${Visibility.standard.sql} GROUP BY i.id ORDER BY _n DESC, i.sort_title LIMIT $top',
          variables: [Variable.withInt(from)],
          readsFrom: {db.items},
        )
        .get();
    final byKind = await db
        .customSelect(
          'SELECT kind, coalesce(sum(size), 0) AS b, count(*) AS n FROM item WHERE missing = 0 GROUP BY kind',
        )
        .get();
    final bySource = await db
        .customSelect(
          'SELECT source_id, coalesce(sum(size), 0) AS b FROM item WHERE missing = 0 GROUP BY source_id',
        )
        .get();
    return LibraryStats(
      playCount: plays.read<int>('n'),
      timePlayed: Duration(milliseconds: plays.read<int>('ms')),
      topItems: [
        for (final r in topRows) (db.items.map(r.data), r.read<int>('_n')),
      ],
      bytesByKind: {
        for (final r in byKind)
          ItemKind.values.byName(r.read<String>('kind')): r.read<int>('b'),
      },
      countByKind: {
        for (final r in byKind)
          ItemKind.values.byName(r.read<String>('kind')): r.read<int>('n'),
      },
      bytesBySource: {
        for (final r in bySource) r.read<int>('source_id'): r.read<int>('b'),
      },
    );
  }

  Future<List<ItemRow>> _items(
    LibraryMode mode,
    String tail,
    int limit,
    Visibility visibility,
  ) async {
    final vars = <Variable<Object>>[];
    final kinds = _kinds(mode, vars);
    final rows = await db
        .customSelect(
          'SELECT i.* $itemJoins WHERE ${visibility.sql} AND $kinds $tail LIMIT $limit',
          variables: vars,
          readsFrom: {db.items},
        )
        .get();
    return [for (final r in rows) db.items.map(r.data)];
  }

  (String, List<Variable<Object>>) _group(String expr, String v) => (
    'SELECT $expr AS k, $expr AS t, count(*) AS n, min(i.id) AS c, NULL AS y '
        '$itemJoins WHERE $v AND $expr IS NOT NULL GROUP BY lower($expr) ORDER BY lower($expr)',
    <Variable<Object>>[],
  );

  String _kinds(LibraryMode mode, List<Variable<Object>> vars) {
    for (final k in mode.kinds) {
      vars.add(Variable.withString(k.name));
    }
    return 'i.kind IN (${List.filled(mode.kinds.length, '?').join(', ')})';
  }

  /// Exposed for tests of time-relative rows.
  DateTime get now => _clock();
}
