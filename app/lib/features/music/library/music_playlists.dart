import 'package:drift/drift.dart';
import 'package:mediahro/core/db/library_database.dart';
import 'package:mediahro/core/library/playlists.dart';
import 'package:mediahro/core/rules/rule_sql.dart';
import 'package:mediahro/core/rules/smart_rule.dart';
import 'package:mediahro/features/music/library/music_library.dart';
import 'package:meta/meta.dart';

/// Rule fields offered for music smart playlists (MUS-008): tags, play
/// statistics, rating, dates, length and path.
const List<RuleField> musicRuleFields = [
  RuleField.title,
  RuleField.artist,
  RuleField.albumArtist,
  RuleField.album,
  RuleField.genre,
  RuleField.composer,
  RuleField.year,
  RuleField.trackNumber,
  RuleField.discNumber,
  RuleField.playCount,
  RuleField.lastPlayed,
  RuleField.rating,
  RuleField.dateAdded,
  RuleField.durationMs,
  RuleField.path,
  RuleField.folder,
  RuleField.extension,
  RuleField.audioCodec,
  RuleField.tag,
];

/// A playlist row for the music views.
@immutable
final class MusicPlaylist {
  const MusicPlaylist({
    required this.id,
    required this.name,
    required this.rule,
    required this.count,
  });

  final int id;
  final String name;

  /// Null for a manual playlist.
  final SmartRule? rule;

  /// Songs in it (smart playlists are evaluated now).
  final int count;

  bool get smart => rule != null;
}

/// Music playlists (MUS-001 "playlists", MUS-008 smart playlists) over
/// B2's [PlaylistRepository]; smart rules are scoped to audio items.
final class MusicPlaylists {
  MusicPlaylists(this.db, this.repo, this.library);

  final LibraryDatabase db;
  final PlaylistRepository repo;
  final MusicLibrary library;

  Future<List<MusicPlaylist>> all({
    Visibility visibility = Visibility.standard,
  }) async {
    final rows =
        await (db.select(db.playlists)
              ..where((p) => p.mode.isIn(const ['audio', 'mixed']))
              ..orderBy([(p) => OrderingTerm.asc(p.name)]))
            .get();
    final out = <MusicPlaylist>[];
    for (final p in rows) {
      final rule = p.rule == null ? null : _decode(p.rule!);
      final count = rule != null
          ? (await repo.evaluate(rule, visibility: visibility)).length
          : await _manualCount(p.id);
      out.add(MusicPlaylist(id: p.id, name: p.name, rule: rule, count: count));
    }
    return out;
  }

  Future<int> _manualCount(int id) async {
    final r = await db
        .customSelect(
          'SELECT count(*) AS n FROM playlist_item pi JOIN item i ON i.id = pi.item_id '
          "WHERE pi.playlist_id = ? AND i.kind = 'audio' AND i.missing = 0",
          variables: [Variable.withInt(id)],
          readsFrom: {db.playlistItems, db.items},
        )
        .getSingle();
    return r.read<int>('n');
  }

  /// Songs of a playlist in its order (manual) or its rule's sort (smart).
  Future<List<MusicTrack>> tracks(
    int playlistId, {
    Visibility visibility = Visibility.standard,
  }) async {
    final entries = await repo.tracks(playlistId, visibility: visibility);
    return await library.tracksByIds([
      for (final e in entries)
        if (e.item case final ItemRow i when i.kind == ItemKind.audio) i.id,
    ], visibility: visibility);
  }

  /// How many songs [rule] matches now (live preview in the editor).
  Future<int> preview(SmartRule rule) async =>
      (await repo.evaluate(scoped(rule))).length;

  Future<int> createManual(String name) =>
      repo.createManual(name, mode: 'audio');

  Future<int> createSmart(String name, SmartRule rule) =>
      repo.createSmart(name, scoped(rule), mode: 'audio');

  Future<void> updateRule(int id, SmartRule rule) =>
      repo.updateRule(id, scoped(rule));

  Future<void> rename(int id, String name) => repo.rename(id, name);
  Future<void> delete(int id) => repo.delete(id);
  Future<void> move(int id, int from, int to) => repo.move(id, from, to);
  Future<void> removeAt(int id, int position) => repo.removeAt(id, position);
  Future<void> add(int id, List<MusicTrack> tracks) =>
      repo.addItems(id, [for (final t in tracks) t.itemId]);

  /// Smart rules made here only ever match songs.
  static SmartRule scoped(SmartRule r) => SmartRule(
    root: r.root,
    limit: r.limit,
    limitUnit: r.limitUnit,
    sort: r.sort,
    kinds: const {'audio'},
  );

  static SmartRule? _decode(String json) {
    try {
      return SmartRule.decode(json);
    } on FormatException {
      return null;
    }
  }
}
