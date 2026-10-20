import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:mediahro/core/db/library_database.dart';
import 'package:mediahro/core/rules/smart_rule.dart';
import 'package:mediahro/features/photos/organise/photo_organiser.dart';

import '../../core/seed.dart';

void main() {
  late LibraryDatabase db;
  late Seed seed;
  late PhotoOrganiser org;

  setUp(() {
    db = LibraryDatabase.memory();
    seed = Seed(db);
    org = PhotoOrganiser(db: db);
  });

  tearDown(() => db.close());

  Future<int> photo(String p) => seed.item(p, kind: ItemKind.image);

  Future<bool> fav(int id) async =>
      (await (db.select(
        db.imageMeta,
      )..where((m) => m.itemId.equals(id))).getSingleOrNull())?.favourite ??
      false;

  group('IMG-005 favourites, ratings, labels, tags', () {
    test(
      'IMG-005 favourites are set and cleared for many photos at once',
      () async {
        final a = await photo('a.jpg');
        final b = await photo('b.jpg');
        await org.setFavourite([a, b], value: true);
        expect(await fav(a), isTrue);
        expect(await fav(b), isTrue);
        await org.setFavourite([a], value: false);
        expect(await fav(a), isFalse);
        expect(await fav(b), isTrue);
      },
    );

    test('IMG-005 a favourite keeps the facts the prober stored', () async {
      final a = await photo('a.jpg');
      await db
          .into(db.imageMeta)
          .insert(
            ImageMetaCompanion.insert(
              itemId: Value(a),
              camera: const Value('Samsung'),
              phash: const Value('ab'),
            ),
          );
      await org.setFavourite([a], value: true);
      final m = await (db.select(
        db.imageMeta,
      )..where((x) => x.itemId.equals(a))).getSingle();
      expect((m.camera, m.phash, m.favourite), ('Samsung', 'ab', true));
    });

    test(
      'IMG-005 ratings are 1–5 stars stored as half stars, 0 clears',
      () async {
        final a = await photo('a.jpg');
        await org.setRating([a], 4);
        expect((await db.select(db.ratings).getSingle()).value, 8);
        await org.setRating([a], 5);
        expect((await db.select(db.ratings).getSingle()).value, 10);
        await org.setRating([a], 99);
        expect(
          (await db.select(db.ratings).getSingle()).value,
          10,
          reason: 'clamped',
        );
        await org.setRating([a], 0);
        expect(await db.select(db.ratings).get(), isEmpty);
      },
    );

    test('IMG-005 colour labels and tags', () async {
      final a = await photo('a.jpg');
      final b = await photo('b.jpg');
      await org.setLabel([a, b], LabelColor.green);
      expect((await db.select(db.labels).get()).map((l) => l.color), [
        LabelColor.green,
        LabelColor.green,
      ]);
      await org.setLabel([a], null);
      expect(await db.select(db.labels).get(), hasLength(1));
      await org.addTag([a, b], 'Holiday');
      await org.addTag([a], 'beach');
      expect(await org.commonTags([a, b]), {'Holiday'});
      expect((await org.tagsOf(a)).toSet(), {'Holiday', 'beach'});
      await org.removeTag([a, b], 'holiday');
      expect(await org.commonTags([a, b]), isEmpty);
    });
  });

  group('IMG-005 albums', () {
    test(
      'IMG-005 a user album holds photos in order without duplicates',
      () async {
        final ids = [
          await photo('a.jpg'),
          await photo('b.jpg'),
          await photo('c.jpg'),
        ];
        final album = await org.createAlbum('Trip', items: [ids[2], ids[0]]);
        expect(
          await org.addToAlbum(album, [ids[0], ids[1]]),
          1,
          reason: 'a is already there',
        );
        expect(await org.albumItemIds(album), [ids[2], ids[0], ids[1]]);
      },
    );

    test('IMG-005 removing photos leaves the others in order', () async {
      final ids = [
        await photo('a.jpg'),
        await photo('b.jpg'),
        await photo('c.jpg'),
      ];
      final album = await org.createAlbum('Trip', items: ids);
      await org.removeFromAlbum(album, [ids[1]]);
      expect(await org.albumItemIds(album), [ids[0], ids[2]]);
    });

    test(
      'IMG-005 albums list with counts and a cover; rename and delete',
      () async {
        final a = await photo('a.jpg');
        final album = await org.createAlbum('Zoo', items: [a]);
        await org.createAlbum('Beach');
        var list = await org.albums();
        expect(list.map((x) => x.name), ['Beach', 'Zoo']);
        final zoo = list.last;
        expect((zoo.count, zoo.smart, zoo.coverItemId), (1, false, a));
        await org.renameAlbum(album, 'Safari');
        await org.deleteAlbum(list.first.id);
        list = await org.albums();
        expect(list.map((x) => x.name), ['Safari']);
      },
    );

    test('IMG-005 a smart album follows its rule as photos change', () async {
      final a = await photo('a.jpg');
      final b = await photo('b.jpg');
      await seed.item('v.mp3', kind: ItemKind.audio);
      final album = await org.createSmartAlbum(
        'Favourites 4+',
        const SmartRule(
          root: RuleGroup(
            children: [
              RuleCondition(RuleField.favourite, RuleOp.isTrue),
              RuleCondition(RuleField.rating, RuleOp.atLeast, 8),
            ],
          ),
        ),
      );
      expect(await org.albumItemIds(album), isEmpty);
      await org.setFavourite([a, b], value: true);
      await org.setRating([a], 5);
      await org.setRating([b], 2);
      expect(await org.albumItemIds(album), [a]);
      final listed = (await org.albums()).single;
      expect((listed.smart, listed.count), (true, 1));
    });

    test('IMG-005 a smart album never includes music', () async {
      await photo('a.jpg');
      final song = await seed.item('s.mp3', kind: ItemKind.audio);
      await org.setRating([song], 5);
      final album = await org.createSmartAlbum(
        'Rated',
        const SmartRule(
          root: RuleGroup(
            children: [RuleCondition(RuleField.rating, RuleOp.atLeast, 2)],
          ),
        ),
      );
      expect(await org.albumItemIds(album), isEmpty);
    });

    test('IMG-005 music playlists are not photo albums', () async {
      await org.createAlbum('Photos');
      await org.playlists.createManual('Songs', mode: 'audio');
      expect((await org.albums()).map((a) => a.name), ['Photos']);
    });
  });
}
