import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:mediahro/core/db/library_database.dart';
import 'package:mediahro/features/video/last_played.dart';

import '../../core/seed.dart';

void main() {
  late LibraryDatabase db;
  late Seed seed;

  setUp(() {
    db = LibraryDatabase.memory();
    seed = Seed(db);
  });

  tearDown(() => db.close());

  test('SYS-003 nothing has been played', () async {
    await seed.item('a.mkv');
    expect(await lastPlayedVideo(db), isNull);
  });

  test('SYS-003 the video played most recently is returned', () async {
    await seed.item('old.mkv', lastPlayedAt: DateTime.utc(2026));
    await seed.item('new.mkv', lastPlayedAt: DateTime.utc(2026, 3));
    await seed.item('mid.mkv', lastPlayedAt: DateTime.utc(2026, 2));
    expect((await lastPlayedVideo(db))!.name, 'new.mkv');
  });

  test('SYS-003 music and photos are not videos', () async {
    await seed.item(
      's.flac',
      kind: ItemKind.audio,
      lastPlayedAt: DateTime.utc(2026, 5),
    );
    await seed.item('v.mkv', lastPlayedAt: DateTime.utc(2026));
    expect((await lastPlayedVideo(db))!.name, 'v.mkv');
  });

  test('SYS-003 hidden, vault and vanished items are never returned', () async {
    await seed.item(
      'hidden.mkv',
      hidden: true,
      lastPlayedAt: DateTime.utc(2026, 6),
    );
    final vault = await seed.item(
      'vault.mkv',
      lastPlayedAt: DateTime.utc(2026, 6, 2),
    );
    final gone = await seed.item(
      'gone.mkv',
      lastPlayedAt: DateTime.utc(2026, 6, 3),
    );
    await (db.update(db.items)..where((i) => i.id.equals(vault))).write(
      const ItemsCompanion(vault: Value(true)),
    );
    await (db.update(db.items)..where((i) => i.id.equals(gone))).write(
      const ItemsCompanion(missing: Value(true)),
    );
    await seed.item('ok.mkv', lastPlayedAt: DateTime.utc(2026));
    expect((await lastPlayedVideo(db))!.name, 'ok.mkv');
  });
}
