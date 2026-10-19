import 'package:drift/drift.dart';
import 'package:mediahro/core/db/library_database.dart';
import 'package:mediahro/core/rules/rule_sql.dart';
import 'package:mediahro/core/rules/smart_rule.dart';
import 'package:meta/meta.dart';

/// Resolution classes for the search filter (LIB-005).
enum ResolutionClass {
  sd(0, 719),
  hd(720, 1079),
  fullHd(1080, 1439),
  qhd(1440, 2159),
  uhd(2160, 4319),
  uhd8k(4320, 1 << 30);

  const ResolutionClass(this.minHeight, this.maxHeight);

  final int minHeight;
  final int maxHeight;
}

/// Filters of the search screen (LIB-005). Every field is optional.
@immutable
final class SearchFilters {
  const SearchFilters({
    this.kinds = const {},
    this.sourceIds = const {},
    this.resolutions = const {},
    this.videoCodecs = const {},
    this.audioCodecs = const {},
    this.hdrTypes = const {},
    this.minDuration,
    this.maxDuration,
    this.addedAfter,
    this.addedBefore,
    this.minRating,
    this.unplayedOnly = false,
  });

  final Set<ItemKind> kinds;
  final Set<int> sourceIds;
  final Set<ResolutionClass> resolutions;
  final Set<String> videoCodecs;
  final Set<String> audioCodecs;
  final Set<String> hdrTypes;
  final Duration? minDuration;
  final Duration? maxDuration;
  final DateTime? addedAfter;
  final DateTime? addedBefore;

  /// 0…10 (half stars).
  final int? minRating;
  final bool unplayedOnly;

  bool get isEmpty =>
      kinds.isEmpty &&
      sourceIds.isEmpty &&
      resolutions.isEmpty &&
      videoCodecs.isEmpty &&
      audioCodecs.isEmpty &&
      hdrTypes.isEmpty &&
      minDuration == null &&
      maxDuration == null &&
      addedAfter == null &&
      addedBefore == null &&
      minRating == null &&
      !unplayedOnly;

  /// The same filters as a rule tree (shared compiler with LIB-007).
  RuleGroup toRule() => RuleGroup(
    children: [
      if (sourceIds.isNotEmpty)
        RuleCondition(RuleField.source, RuleOp.anyOf, sourceIds.toList()),
      if (resolutions.isNotEmpty)
        RuleGroup(
          matchAll: false,
          children: [
            for (final r in resolutions)
              RuleCondition(
                RuleField.height,
                RuleOp.between,
                r.minHeight,
                r.maxHeight,
              ),
          ],
        ),
      if (videoCodecs.isNotEmpty)
        RuleCondition(RuleField.videoCodec, RuleOp.anyOf, videoCodecs.toList()),
      if (audioCodecs.isNotEmpty)
        RuleCondition(RuleField.audioCodec, RuleOp.anyOf, audioCodecs.toList()),
      if (hdrTypes.isNotEmpty)
        RuleCondition(RuleField.hdrType, RuleOp.anyOf, hdrTypes.toList()),
      if (minDuration != null)
        RuleCondition(
          RuleField.durationMs,
          RuleOp.atLeast,
          minDuration!.inMilliseconds,
        ),
      if (maxDuration != null)
        RuleCondition(
          RuleField.durationMs,
          RuleOp.atMost,
          maxDuration!.inMilliseconds,
        ),
      if (addedAfter != null)
        RuleCondition(
          RuleField.dateAdded,
          RuleOp.greaterThan,
          addedAfter!.toIso8601String(),
        ),
      if (addedBefore != null)
        RuleCondition(
          RuleField.dateAdded,
          RuleOp.lessThan,
          addedBefore!.toIso8601String(),
        ),
      if (minRating != null)
        RuleCondition(RuleField.rating, RuleOp.atLeast, minRating),
      if (unplayedOnly)
        const RuleCondition(RuleField.playCount, RuleOp.equals, 0),
    ],
  );
}

@immutable
final class SearchRequest {
  const SearchRequest(
    this.text, {
    this.filters = const SearchFilters(),
    this.visibility = Visibility.standard,
    this.limit = 200,
  });

  final String text;
  final SearchFilters filters;
  final Visibility visibility;
  final int limit;
}

/// Instant prefix search over titles, file names, tags, artists, albums,
/// people and places (LIB-005) on the FTS5 index, ranked by bm25.
final class LibrarySearch {
  LibrarySearch(this.db, {RuleCompiler? compiler})
    : _compiler = compiler ?? RuleCompiler();

  final LibraryDatabase db;
  final RuleCompiler _compiler;

  Future<List<ItemRow>> search(SearchRequest req) async {
    final match = ftsQuery(req.text);
    final vars = <Variable<Object>>[];
    final where = <String>[
      req.visibility.sql,
      if (req.filters.kinds.isNotEmpty)
        'i.kind IN (${[for (final k in req.filters.kinds) _bind(vars, k.name)].join(', ')})',
    ];
    final rule = _compiler.condition(req.filters.toRule(), vars);
    if (rule.isNotEmpty) where.add(rule);
    final String sql;
    if (match == null) {
      if (req.filters.isEmpty) return const [];
      sql =
          'SELECT i.* $itemJoins WHERE ${where.join(' AND ')} '
          'ORDER BY i.sort_title, i.id LIMIT ${req.limit}';
    } else {
      // bm25 weights: title, name, tags, artist, album, people, places.
      sql =
          'SELECT i.* FROM item_fts f JOIN item i ON i.id = f.rowid '
          '${itemJoins.substring('FROM item i '.length)} '
          'WHERE item_fts MATCH ? AND ${where.join(' AND ')} '
          'ORDER BY bm25(item_fts, 10.0, 4.0, 3.0, 5.0, 4.0, 3.0, 2.0), i.sort_title '
          'LIMIT ${req.limit}';
      vars.insert(0, Variable.withString(match));
    }
    final rows = await db
        .customSelect(sql, variables: vars, readsFrom: {db.items})
        .get();
    return [for (final r in rows) db.items.map(r.data)];
  }

  static String _bind(List<Variable<Object>> vars, String v) {
    vars.add(Variable.withString(v));
    return '?';
  }
}

/// FTS5 query for user text: every token becomes a quoted prefix term and
/// all must match. Returns null for blank input. Quotes are escaped, so
/// FTS syntax in user text is never interpreted.
String? ftsQuery(String text) {
  final tokens = text
      .split(RegExp(r'[\s\p{P}\p{S}]+', unicode: true))
      .where((t) => t.isNotEmpty)
      .take(16)
      .toList();
  if (tokens.isEmpty) return null;
  return tokens.map((t) => '"${t.replaceAll('"', '""')}"*').join(' ');
}
