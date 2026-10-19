import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediahro/app/l10n/gen/app_localizations.dart';
import 'package:mediahro/core/db/library_database.dart';
import 'package:mediahro/core/db/sqlite_support.dart';
import 'package:mediahro/features/library/widgets.dart';

void main() {
  test('LIB-001/LIB-005 the bundled SQLite runs the index: FTS5 and JSON compiled in, never stripped for size', () async {
    final db = LibraryDatabase.memory();
    addTearDown(db.close);
    final r = await inspectSqlite(db);
    expect(r.missing, isEmpty);
    expect(r.compileOptions, contains('ENABLE_FTS5'));
    expect(r.compileOptions.where((o) => o.contains('OMIT_JSON')), isEmpty);
    expect(
      r.compileOptions.where((o) => o.contains('OMIT_WINDOWFUNC')),
      isEmpty,
    );
    final v = parseSqliteVersion(r.version);
    expect(v.$1 > 3 || v.$2 >= 30, isTrue, reason: r.version);
    // The probe leaves nothing behind.
    final temp = await db
        .customSelect(
          "SELECT name FROM temp.sqlite_master WHERE name LIKE 'mediahro_%'",
        )
        .get();
    expect(temp, isEmpty);
  });

  test('LIB-001 an old or stripped SQLite is refused, naming every missing feature', () {
    expect(parseSqliteVersion('3.39.5'), (3, 39, 5));
    expect(parseSqliteVersion('3.30'), (3, 30, 0));
    expect(
      missingSqliteFeatures(version: '3.39.5', fts5: true, json: true),
      isEmpty,
    );
    expect(
      missingSqliteFeatures(version: '3.30.0', fts5: true, json: true),
      isEmpty,
    );
    expect(missingSqliteFeatures(version: '3.29.9', fts5: true, json: true), {
      SqliteFeature.version,
    });
    expect(missingSqliteFeatures(version: '4.0.0', fts5: false, json: true), {
      SqliteFeature.fts5,
    });
    expect(missingSqliteFeatures(version: '3.22.0', fts5: false, json: false), {
      SqliteFeature.version,
      SqliteFeature.fts5,
      SqliteFeature.json,
    });
    expect(
      const SqliteUnsupported('3.22.0', {SqliteFeature.fts5}).toString(),
      contains('fts5'),
    );
  });

  testWidgets(
    'LIB-001 an unsupported database engine gets actionable copy (docs/06 §8)',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: LibraryUnavailable(
              error: SqliteUnsupported('3.22.0', {SqliteFeature.fts5}),
            ),
          ),
        ),
      );
      expect(
        find.textContaining('Update the operating system'),
        findsOneWidget,
      );
      expect(find.text('SQLite 3.22.0'), findsOneWidget);
    },
  );
}
