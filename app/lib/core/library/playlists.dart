import 'package:drift/drift.dart';
import 'package:mediahro/core/db/library_database.dart';
import 'package:mediahro/core/library/item_locator.dart';
import 'package:mediahro/core/parsers/playlist_parser.dart';
import 'package:mediahro/core/rules/rule_sql.dart';
import 'package:mediahro/core/rules/smart_rule.dart';

/// One resolved playlist entry: an indexed item or an external URI.
final class PlaylistTrack {
  const PlaylistTrack({this.item, this.uri, this.title, this.duration});

  final ItemRow? item;
  final String? uri;
  final String? title;
  final Duration? duration;

  String get displayTitle => item?.title ?? title ?? uri ?? '';
}

/// Manual and smart playlists (LIB-007), cross-source; import/export
/// M3U/M3U8/PLS/XSPF.
final class PlaylistRepository {
  PlaylistRepository(
    this.db, {
    ItemLocator? locator,
    RuleCompiler? compiler,
    DateTime Function()? clock,
  }) : locator = locator ?? ItemLocator(db),
       _compiler = compiler ?? RuleCompiler(clock: clock),
       _clock = clock ?? DateTime.now;

  final LibraryDatabase db;
  final ItemLocator locator;
  final RuleCompiler _compiler;
  final DateTime Function() _clock;

  Future<int> createManual(String name, {String mode = 'mixed'}) {
    final now = _clock();
    return db
        .into(db.playlists)
        .insert(
          PlaylistsCompanion.insert(
            name: name,
            mode: Value(mode),
            createdAt: now,
            updatedAt: now,
          ),
        );
  }

  Future<int> createSmart(
    String name,
    SmartRule rule, {
    String mode = 'mixed',
  }) {
    final now = _clock();
    return db
        .into(db.playlists)
        .insert(
          PlaylistsCompanion.insert(
            name: name,
            rule: Value(rule.encode()),
            mode: Value(mode),
            createdAt: now,
            updatedAt: now,
          ),
        );
  }

  Future<void> updateRule(int playlistId, SmartRule rule) =>
      (db.update(db.playlists)..where((p) => p.id.equals(playlistId))).write(
        PlaylistsCompanion(
          rule: Value(rule.encode()),
          updatedAt: Value(_clock()),
        ),
      );

  Future<void> rename(int playlistId, String name) =>
      (db.update(db.playlists)..where((p) => p.id.equals(playlistId))).write(
        PlaylistsCompanion(name: Value(name), updatedAt: Value(_clock())),
      );

  Future<void> delete(int playlistId) =>
      (db.delete(db.playlists)..where((p) => p.id.equals(playlistId))).go();

  Future<List<PlaylistRow>> all() => (db.select(
    db.playlists,
  )..orderBy([(p) => OrderingTerm.asc(p.name)])).get();

  /// Appends indexed items to a manual playlist.
  Future<void> addItems(int playlistId, List<int> itemIds) =>
      db.transaction(() async {
        var pos = await _nextPosition(playlistId);
        await db.batch((b) {
          b.insertAll(db.playlistItems, [
            for (final id in itemIds)
              PlaylistItemsCompanion.insert(
                playlistId: playlistId,
                position: pos++,
                itemId: Value(id),
              ),
          ]);
        });
        await _touch(playlistId);
      });

  /// Appends an external URI (stream, file on an unindexed source).
  Future<void> addUri(
    int playlistId,
    String uri, {
    String? title,
    Duration? duration,
  }) => db.transaction(() async {
    await db
        .into(db.playlistItems)
        .insert(
          PlaylistItemsCompanion.insert(
            playlistId: playlistId,
            position: await _nextPosition(playlistId),
            uri: Value(uri),
            title: Value(title),
            durationMs: Value(duration?.inMilliseconds),
          ),
        );
    await _touch(playlistId);
  });

  /// Moves the entry at [from] to [to] (0-based positions).
  Future<void> move(int playlistId, int from, int to) =>
      db.transaction(() async {
        final rows = await _entries(playlistId);
        if (from < 0 || from >= rows.length || to < 0 || to >= rows.length) {
          throw RangeError('move $from → $to of ${rows.length}');
        }
        final moved = rows.removeAt(from);
        rows.insert(to, moved);
        await _renumber(rows);
        await _touch(playlistId);
      });

  Future<void> removeAt(int playlistId, int position) => db.transaction(
    () async {
      final rows = await _entries(playlistId);
      final r = rows.removeAt(position);
      await (db.delete(db.playlistItems)..where((p) => p.id.equals(r.id))).go();
      await _renumber(rows);
      await _touch(playlistId);
    },
  );

  /// Tracks of a playlist: manual entries in order, or the smart rule
  /// evaluated now (smart playlists are always live).
  Future<List<PlaylistTrack>> tracks(
    int playlistId, {
    Visibility visibility = Visibility.standard,
  }) async {
    final p = await (db.select(
      db.playlists,
    )..where((p) => p.id.equals(playlistId))).getSingle();
    final rule = p.rule;
    if (rule != null) {
      return [
        for (final i in await evaluate(
          SmartRule.decode(rule),
          visibility: visibility,
        ))
          PlaylistTrack(item: i),
      ];
    }
    final rows =
        await (db.select(db.playlistItems).join([
                leftOuterJoin(
                  db.items,
                  db.items.id.equalsExp(db.playlistItems.itemId),
                ),
              ])
              ..where(db.playlistItems.playlistId.equals(playlistId))
              ..orderBy([OrderingTerm.asc(db.playlistItems.position)]))
            .get();
    return [
      for (final r in rows)
        PlaylistTrack(
          item: r.readTableOrNull(db.items),
          uri: r.readTable(db.playlistItems).uri,
          title: r.readTable(db.playlistItems).title,
          duration: switch (r.readTable(db.playlistItems).durationMs) {
            final int ms => Duration(milliseconds: ms),
            null => null,
          },
        ),
    ];
  }

  /// Runs a smart rule (also used by smart albums and MUS-008).
  Future<List<ItemRow>> evaluate(
    SmartRule rule, {
    Visibility visibility = Visibility.standard,
  }) async {
    final q = _compiler.select(rule, visibility: visibility);
    final rows = await db
        .customSelect(q.sql, variables: q.variables, readsFrom: {db.items})
        .get();
    return [for (final r in rows) db.items.map(r.data)];
  }

  /// Imports a playlist file; entries on indexed sources become item links,
  /// the rest stay as URIs (cross-source). Parsing runs on an isolate.
  Future<int> import(
    String name,
    Uint8List bytes,
    PlaylistFormat format, {
    Uri? base,
  }) async {
    final parsed = await parsePlaylistIsolated(bytes, format, base: base);
    if (parsed.isHlsStream && base != null) {
      final id = await createManual(name);
      await addUri(id, base.toString(), title: name);
      return id;
    }
    final id = await createManual(parsed.title ?? name);
    await db.transaction(() async {
      var pos = 0;
      final companions = <PlaylistItemsCompanion>[];
      for (final e in parsed.entries) {
        final uri = Uri.tryParse(e.location);
        final item = uri == null ? null : await locator.itemFor(uri);
        companions.add(
          PlaylistItemsCompanion.insert(
            playlistId: id,
            position: pos++,
            itemId: Value(item?.id),
            uri: Value(item == null ? e.location : null),
            title: Value(e.title),
            durationMs: Value(e.duration?.inMilliseconds),
          ),
        );
      }
      await db.batch((b) => b.insertAll(db.playlistItems, companions));
    });
    return id;
  }

  /// Exports any playlist (manual or smart) in [format] with absolute URIs.
  Future<String> export(int playlistId, PlaylistFormat format) async {
    final p = await (db.select(
      db.playlists,
    )..where((p) => p.id.equals(playlistId))).getSingle();
    final entries = <PlaylistEntry>[];
    for (final t in await tracks(playlistId)) {
      final item = t.item;
      final loc = item != null ? '${await locator.uriOf(item)}' : t.uri;
      if (loc == null) continue;
      entries.add(
        PlaylistEntry(
          loc,
          title: t.displayTitle,
          duration:
              t.duration ??
              (item?.durationMs == null
                  ? null
                  : Duration(milliseconds: item!.durationMs!)),
        ),
      );
    }
    return switch (format) {
      PlaylistFormat.m3u => writeM3u(entries, title: p.name),
      PlaylistFormat.pls => writePls(entries),
      PlaylistFormat.xspf => writeXspf(entries, title: p.name),
      PlaylistFormat.cue => throw UnsupportedError('CUE export'),
    };
  }

  Future<int> _nextPosition(int playlistId) async {
    final r = await db
        .customSelect(
          'SELECT coalesce(max(position) + 1, 0) AS n FROM playlist_item WHERE playlist_id = ?',
          variables: [Variable.withInt(playlistId)],
        )
        .getSingle();
    return r.read<int>('n');
  }

  Future<List<PlaylistItemRow>> _entries(int playlistId) =>
      (db.select(db.playlistItems)
            ..where((p) => p.playlistId.equals(playlistId))
            ..orderBy([(p) => OrderingTerm.asc(p.position)]))
          .get();

  Future<void> _renumber(List<PlaylistItemRow> rows) async {
    for (var i = 0; i < rows.length; i++) {
      if (rows[i].position == i) continue;
      await (db.update(db.playlistItems)..where((p) => p.id.equals(rows[i].id)))
          .write(PlaylistItemsCompanion(position: Value(i)));
    }
  }

  Future<void> _touch(int playlistId) =>
      (db.update(db.playlists)..where((p) => p.id.equals(playlistId))).write(
        PlaylistsCompanion(updatedAt: Value(_clock())),
      );
}
