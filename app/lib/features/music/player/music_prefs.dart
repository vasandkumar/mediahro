import 'dart:convert';

import 'package:drift/drift.dart' show StringExpressionOperators;
import 'package:mediahro/core/db/library_database.dart';

/// Small JSON preferences of the music feature, kept in the library's
/// `setting` table (`music.*` keys) so they travel with backups (CORE-013)
/// and per-profile databases.
final class MusicPrefs {
  MusicPrefs(this.db);

  final LibraryDatabase db;

  Future<Object?> read(String key) async {
    final row = await (db.select(
      db.settingsTable,
    )..where((s) => s.key.equals('music.$key'))).getSingleOrNull();
    if (row == null) return null;
    try {
      return jsonDecode(row.value);
    } on FormatException {
      return null;
    }
  }

  Future<void> write(String key, Object? value) => db
      .into(db.settingsTable)
      .insertOnConflictUpdate(
        SettingsTableCompanion.insert(
          key: 'music.$key',
          value: jsonEncode(value),
        ),
      );

  /// Every preference whose key starts with `music.<prefix>`, by the rest of
  /// the key. The prefix must not contain `%` or `_` (SQL wildcards).
  Future<Map<String, Object?>> readPrefix(String prefix) async {
    final start = 'music.$prefix';
    final rows = await (db.select(
      db.settingsTable,
    )..where((s) => s.key.like('$start%'))).get();
    final out = <String, Object?>{};
    for (final r in rows) {
      try {
        out[r.key.substring(start.length)] = jsonDecode(r.value);
      } on FormatException {
        // A damaged value reads as absent.
      }
    }
    return out;
  }

  Future<Map<String, Object?>?> readMap(String key) async =>
      switch (await read(key)) {
        final Map<String, Object?> m => m,
        _ => null,
      };

  Future<List<Object?>?> readList(String key) async =>
      switch (await read(key)) {
        final List<Object?> l => l,
        _ => null,
      };
}

/// Reads a number from decoded JSON.
double? jsonDouble(Object? v) => v is num ? v.toDouble() : null;
int? jsonInt(Object? v) => v is num ? v.toInt() : null;
