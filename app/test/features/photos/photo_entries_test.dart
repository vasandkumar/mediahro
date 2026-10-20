import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:mediahro/core/db/library_database.dart';
import 'package:mediahro/core/rules/rule_sql.dart' as rules;
import 'package:mediahro/features/photos/photos_providers.dart';

import '../../core/seed.dart';

void main() {
  late LibraryDatabase db;
  late Seed seed;

  setUp(() {
    db = LibraryDatabase.memory();
    seed = Seed(db);
  });

  tearDown(() => db.close());

  Future<List<int>> ids({bool unlocked = false}) async {
    final q = db.customSelect(
      photoEntriesSql(rules.Visibility(unlocked: unlocked)),
      readsFrom: {db.items, db.imageMeta, db.sources},
    );
    return [for (final e in await loadPhotoEntries(q)) e.id];
  }

  Future<void> setTaken(int id, DateTime t) => db.customStatement(
    'UPDATE item SET taken_at = ? WHERE id = ?',
    [t.millisecondsSinceEpoch ~/ 1000, id],
  );

  test('IMG-003 photos and videos are listed, music is not', () async {
    final a = await seed.item('a.jpg', kind: ItemKind.image);
    final v = await seed.item('b.mp4');
    await seed.item('c.mp3', kind: ItemKind.audio);
    expect(await ids(), containsAll([a, v]));
    expect(await ids(), hasLength(2));
  });

  test(
    'IMG-003 newest first by capture time, falling back to file time',
    () async {
      final old = await seed.item('old.jpg', kind: ItemKind.image);
      final taken = await seed.item('taken.jpg', kind: ItemKind.image);
      final plain = await seed.item('plain.jpg', kind: ItemKind.image);
      await setTaken(old, DateTime.utc(2019, 5));
      await setTaken(taken, DateTime.utc(2027));
      // `plain` has only the file time from the seed (2026-01-01 UTC).
      expect(await ids(), [taken, plain, old]);
    },
  );

  test(
    'IMG-003 missing, hidden and vault items stay out of the timeline',
    () async {
      final keep = await seed.item('keep.jpg', kind: ItemKind.image);
      await seed.item('hid.jpg', kind: ItemKind.image, hidden: true);
      final gone = await seed.item('gone.jpg', kind: ItemKind.image);
      final vaulted = await seed.item('vault.jpg', kind: ItemKind.image);
      await db.customStatement('UPDATE item SET missing = 1 WHERE id = ?', [
        gone,
      ]);
      await db.customStatement('UPDATE item SET vault = 1 WHERE id = ?', [
        vaulted,
      ]);
      expect(await ids(), [keep]);
    },
  );

  test(
    'IMG-003 locked sources only appear once the parental gate is open',
    () async {
      final s = await seed.source(name: 'Kids', locked: true);
      final k = await seed.item('x.jpg', kind: ItemKind.image, sourceId: s);
      expect(await ids(), isNot(contains(k)));
      expect(await ids(unlocked: true), contains(k));
    },
  );

  test('IMG-003 entry fields: aspect, orientation, favourite, live and motion flags', () async {
    final id = await seed.item('live.heic', kind: ItemKind.image, height: 3000);
    await db
        .into(db.imageMeta)
        .insert(
          ImageMetaCompanion.insert(
            itemId: Value(id),
            orientation: const Value(6),
            favourite: const Value(true),
            pairedVideoPath: const Value('live.mov'),
          ),
        );
    final motion = await seed.item(
      'mp.jpg',
      kind: ItemKind.image,
      videoCodec: 'mp4',
    );
    final hdr = await seed.item(
      'hdr.avif',
      kind: ItemKind.image,
      hdrType: 'hdr10',
    );
    final q = db.customSelect(
      photoEntriesSql(rules.Visibility.standard),
      readsFrom: {db.items, db.imageMeta, db.sources},
    );
    final byId = {for (final e in await loadPhotoEntries(q)) e.id: e};
    final live = byId[id]!;
    expect(live.favourite, isTrue);
    expect(live.livePhoto, isTrue);
    expect(live.orientation, 6);
    expect(
      live.aspect,
      closeTo(9 / 16, 1e-3),
      reason: 'rotated: height over width',
    );
    expect(live.ext, 'heic');
    expect(byId[motion]!.motionPhoto, isTrue);
    expect(byId[motion]!.livePhoto, isFalse);
    expect(byId[hdr]!.hdr, isTrue);
  });
}
