import 'package:drift/drift.dart';
import 'package:meta/meta.dart';

/// The oldest SQLite the index runs on (docs/05 §6): window functions
/// (3.25), `NULLS LAST` (3.30), UPSERT (3.24) and the FTS5 tokenizer option
/// `remove_diacritics 2` (3.27). iOS 16 ships 3.39 and macOS 12 at least
/// 3.36, so the system library qualifies on every supported Apple release.
const (int, int, int) minimumSqliteVersion = (3, 30, 0);

/// What the library index needs from the SQLite it runs on.
enum SqliteFeature {
  /// [minimumSqliteVersion] or newer.
  version,

  /// FTS5 with bm25 ranking and prefix indexes (LIB-005).
  fts5,

  /// JSON functions (`json_each`, LIB-001 batch updates).
  json,
}

/// The device's SQLite lacks something the index needs. Apple builds use
/// the system library (ADR-020), so this can only happen there on an
/// unexpected OS build; Android and Windows bundle their own.
final class SqliteUnsupported implements Exception {
  const SqliteUnsupported(this.version, this.missing);

  final String version;
  final Set<SqliteFeature> missing;

  @override
  String toString() =>
      'SqliteUnsupported(SQLite $version lacks ${missing.map((m) => m.name).join(', ')})';
}

/// Parses `3.39.5` into a comparable triple; unknown parts count as 0.
@visibleForTesting
(int, int, int) parseSqliteVersion(String v) {
  final p = v.split('.').map((s) => int.tryParse(s) ?? 0).toList();
  return (
    p.isNotEmpty ? p[0] : 0,
    p.length > 1 ? p[1] : 0,
    p.length > 2 ? p[2] : 0,
  );
}

bool _atLeast((int, int, int) v, (int, int, int) min) => v.$1 != min.$1
    ? v.$1 > min.$1
    : (v.$2 != min.$2 ? v.$2 > min.$2 : v.$3 >= min.$3);

/// The features missing for [version] given the probe results.
@visibleForTesting
Set<SqliteFeature> missingSqliteFeatures({
  required String version,
  required bool fts5,
  required bool json,
}) => {
  if (!_atLeast(parseSqliteVersion(version), minimumSqliteVersion))
    SqliteFeature.version,
  if (!fts5) SqliteFeature.fts5,
  if (!json) SqliteFeature.json,
};

/// What the connected SQLite is and offers, for the check and diagnostics.
@immutable
final class SqliteReport {
  const SqliteReport({
    required this.version,
    required this.compileOptions,
    required this.missing,
  });

  final String version;
  final List<String> compileOptions;
  final Set<SqliteFeature> missing;
}

Future<bool> _probe(Future<void> Function() f) async {
  try {
    await f();
    return true;
  } on Object {
    return false;
  }
}

/// Probes the connected SQLite: features are exercised, not just read from
/// `PRAGMA compile_options` (FTS5 can also come from a loadable module).
Future<SqliteReport> inspectSqlite(GeneratedDatabase db) async {
  final version =
      (await db.customSelect('SELECT sqlite_version() AS v').getSingle())
          .read<String>('v');
  final options = [
    for (final r in await db.customSelect('PRAGMA compile_options').get())
      r.data.values.first.toString(),
  ];
  final fts5 = await _probe(() async {
    await db.customStatement(
      'CREATE VIRTUAL TABLE temp.mediahro_fts5_probe USING fts5(x, '
      "tokenize = 'unicode61 remove_diacritics 2', prefix = '2 3')",
    );
    try {
      await db.customStatement(
        "INSERT INTO temp.mediahro_fts5_probe(x) VALUES ('probe')",
      );
      await db
          .customSelect(
            'SELECT bm25(mediahro_fts5_probe) FROM temp.mediahro_fts5_probe '
            "WHERE mediahro_fts5_probe MATCH 'pr*'",
          )
          .getSingle();
    } finally {
      await db.customStatement('DROP TABLE temp.mediahro_fts5_probe');
    }
  });
  final json = await _probe(() async {
    final n = await db
        .customSelect("SELECT count(*) AS n FROM json_each('[1,2]')")
        .getSingle();
    if (n.read<int>('n') != 2) throw StateError('json_each');
  });
  return SqliteReport(
    version: version,
    compileOptions: options,
    missing: missingSqliteFeatures(version: version, fts5: fts5, json: json),
  );
}

/// Throws [SqliteUnsupported] when the SQLite underneath cannot run the
/// index; called before the schema is created and on every open.
Future<SqliteReport> checkSqliteSupport(GeneratedDatabase db) async {
  final r = await inspectSqlite(db);
  if (r.missing.isNotEmpty) throw SqliteUnsupported(r.version, r.missing);
  return r;
}
