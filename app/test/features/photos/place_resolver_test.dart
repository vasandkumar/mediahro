import 'dart:io';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:mediahro/core/db/library_database.dart';
import 'package:mediahro/features/photos/map/gazetteer.dart';
import 'package:mediahro/features/photos/map/place_resolver.dart';

import '../../core/seed.dart';

void main() {
  late LibraryDatabase db;
  late Seed seed;
  late Gazetteer gazetteer;
  Gazetteer? available;

  setUpAll(() {
    gazetteer = Gazetteer.parse(
      File('assets/gazetteer/places.bin').readAsBytesSync(),
    );
  });

  setUp(() {
    db = LibraryDatabase.memory();
    seed = Seed(db);
    available = gazetteer;
  });

  tearDown(() => db.close());

  PlaceResolver resolver() => PlaceResolver(db, () async => available);

  Future<int> photoAt(String name, double? lat, double? lon) async {
    final id = await seed.item(name, kind: ItemKind.image);
    await db
        .into(db.imageMeta)
        .insert(
          ImageMetaCompanion.insert(
            itemId: Value(id),
            latitude: Value(lat),
            longitude: Value(lon),
          ),
        );
    return id;
  }

  Future<int?> placeOf(int itemId) async => (await (db.select(
    db.imageMeta,
  )..where((m) => m.itemId.equals(itemId))).getSingle()).placeId;

  test('IMG-007 a position becomes a city and country', () async {
    final id = await resolver().resolve(48.8566, 2.3522);
    final place = await (db.select(
      db.places,
    )..where((p) => p.id.equals(id!))).getSingle();
    expect(place.name, 'Paris');
    expect(place.country, 'France');
    expect(place.latitude, closeTo(48.85, 0.1));
  });

  test('IMG-007 photos of one city share one place', () async {
    final r = resolver();
    final a = await r.resolve(48.8566, 2.3522);
    final b = await r.resolve(48.86, 2.34);
    final c = await r.resolve(51.5074, -0.1278);
    expect(a, b);
    expect(a, isNot(c));
    expect(await db.select(db.places).get(), hasLength(2));
  });

  test('IMG-007 a second resolver finds the places the first made', () async {
    final a = await resolver().resolve(35.68, 139.65);
    final b = await resolver().resolve(35.68, 139.65);
    expect(a, b);
    expect(await db.select(db.places).get(), hasLength(1));
  });

  test('IMG-007 nothing is made up for the open sea or missing data', () async {
    final r = resolver();
    expect(await r.resolve(0, -140), isNull);
    expect(await r.resolve(null, 10), isNull);
    expect(await r.resolve(10, null), isNull);
    available = null;
    expect(await r.resolve(48.85, 2.35), isNull);
    expect(await db.select(db.places).get(), isEmpty);
  });

  test('IMG-007 photos indexed earlier are named afterwards', () async {
    final paris = await photoAt('a.jpg', 48.8566, 2.3522);
    final tokyo = await photoAt('b.jpg', 35.68, 139.65);
    final sea = await photoAt('c.jpg', 0, -140);
    final none = await photoAt('d.jpg', null, null);
    final r = resolver();
    expect(await r.backfill(batch: 2), 2);
    expect(await placeOf(paris), isNotNull);
    expect(await placeOf(tokyo), isNotNull);
    expect(await placeOf(paris), isNot(await placeOf(tokyo)));
    expect(await placeOf(sea), isNull);
    expect(await placeOf(none), isNull);
    // Nothing left to do the second time.
    expect(await r.backfill(), 0);
  });

  test('IMG-007 backfill without the gazetteer changes nothing', () async {
    final id = await photoAt('a.jpg', 48.8566, 2.3522);
    available = null;
    expect(await resolver().backfill(), 0);
    expect(await placeOf(id), isNull);
  });
}
