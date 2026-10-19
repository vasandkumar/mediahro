import 'dart:math';
import 'dart:typed_data';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:mediahro/core/db/library_database.dart';
import 'package:mediahro/core/library/duplicates.dart';
import 'package:mediahro/core/library/library_views.dart';
import 'package:mediahro/core/library/parental_gate.dart';
import 'package:mediahro/core/library/progress.dart';
import 'package:mediahro/core/library/queues.dart';
import 'package:mediahro/core/library/tags.dart';
import 'package:mediahro/core/search/library_search.dart';

import '../fakes.dart';
import '../seed.dart';

void main() {
  late LibraryDatabase db;
  late Seed seed;
  var now = DateTime.utc(2026, 10, 19, 12);

  setUp(() {
    db = LibraryDatabase.memory();
    seed = Seed(db);
    now = DateTime.utc(2026, 10, 19, 12);
  });
  tearDown(() => db.close());

  group('LIB-008 queues', () {
    late QueueRepository q;
    late List<int> songs;

    setUp(() async {
      q = QueueRepository(db, clock: () => now, random: Random(1));
      songs = [
        for (final n in ['a', 'b', 'c', 'd'])
          await seed.item('$n.flac', kind: ItemKind.audio, title: n),
      ];
    });

    Future<List<int?>> ids(int queue) async => [
      for (final e in (await q.load(queue)).entries) e.itemId,
    ];

    test('named audio queues, one active; one video queue', () async {
      final party = await q.createAudioQueue('Party');
      final focus = await q.createAudioQueue('Focus');
      expect((await q.active(QueueMode.audio))!.id, party);
      await q.activate(focus);
      expect((await q.active(QueueMode.audio))!.id, focus);
      final v1 = await q.videoQueue();
      expect(await q.videoQueue(), v1);
      await q.delete(focus);
      expect((await q.active(QueueMode.audio))!.id, party);
      expect(() => q.delete(v1), throwsStateError);
    });

    test('append, play next, move, remove keep the playing entry', () async {
      final id = await q.createAudioQueue('Q');
      await q.replace(id, [songs[0], songs[1]]);
      await q.append(id, [songs[2]]);
      await q.playNext(id, [songs[3]]);
      expect(await ids(id), [songs[0], songs[3], songs[1], songs[2]]);
      await q.savePosition(id, 2, const Duration(seconds: 7));
      await q.move(id, 2, 0);
      final loaded = await q.load(id);
      expect(loaded.current!.itemId, songs[1]);
      expect(loaded.row.positionMs, 7000);
      await q.removeAt(id, 3);
      expect(await ids(id), [songs[1], songs[0], songs[3]]);
    });

    test('repeat, shuffle and persistence across reopen', () async {
      final id = await q.createAudioQueue('Q');
      await q.replace(id, songs, startIndex: 3);
      expect(await q.next(id), isNull);
      await q.setRepeat(id, RepeatMode.all);
      expect(await q.next(id), 0);
      await q.setRepeat(id, RepeatMode.one);
      expect(await q.next(id), 0);
      await q.savePosition(id, 1, Duration.zero);
      await q.shuffle(id, enabled: true);
      final shuffled = await q.load(id);
      expect(shuffled.current!.itemId, songs[1]);
      expect(shuffled.entries.map((e) => e.itemId).toSet(), songs.toSet());
      // A fresh repository over the same DB sees the same queue.
      final reopened = await QueueRepository(db).load(id);
      expect(reopened.entries.length, 4);
      expect(reopened.row.shuffle, isTrue);
    });
  });

  test(
    'LIB-009 tags (case-insensitive, bulk, searchable) and colour labels',
    () async {
      final tags = TagRepository(db);
      final a = await seed.item('a.mkv', title: 'Alpha');
      final b = await seed.item('b.mkv', title: 'Bravo');
      await tags.addTag([a, b], 'Holiday');
      await tags.addTag([a], 'holiday');
      expect(await tags.allTags(), {'Holiday': 2});
      final search = LibrarySearch(db);
      expect(await search.search(const SearchRequest('holi')), hasLength(2));
      await tags.editTags([b], add: {'Kids'}, remove: {'Holiday'});
      expect(await tags.tagsOf(b), ['Kids']);
      await tags.renameTag('Kids', 'Family');
      expect((await search.search(const SearchRequest('fam'))).single.id, b);
      await tags.setLabel([a, b], LabelColor.red);
      expect(await tags.labelOf(a), LabelColor.red);
      await tags.setLabel([a], null);
      expect(await tags.labelOf(a), isNull);
      expect(await tags.labelOf(b), LabelColor.red);
    },
  );

  group('LIB-010 progress', () {
    test('positions, watched threshold, play counts and events', () async {
      final p = ProgressRepository(db, clock: () => now);
      final film = await seed.item('f.mkv', durationMs: 100000);
      await p.savePosition(film, const Duration(seconds: 10));
      expect(await p.of(film), isNull, reason: 'too early for a resume point');
      await p.savePosition(
        film,
        const Duration(seconds: 50),
        duration: const Duration(seconds: 100),
      );
      expect((await p.of(film))!.positionMs, 50000);
      await p.savePosition(
        film,
        const Duration(seconds: 95),
        duration: const Duration(seconds: 100),
      );
      final w = (await p.of(film))!;
      expect(w.watched, isTrue);
      expect(w.positionMs, 0);
      await p.recordPlay(film, const Duration(minutes: 2));
      final item = await (db.select(
        db.items,
      )..where((i) => i.id.equals(film))).getSingle();
      expect(item.playCount, 1);
      expect(item.lastPlayedAt!.isAtSameMomentAs(now), isTrue);
    });

    test(
      'opt-in sync pushes dirty rows and applies newer remote state',
      () async {
        final p = ProgressRepository(db, clock: () => now);
        final a = await seed.item('a.mkv');
        final b = await seed.item('b.mkv');
        await p.savePosition(a, const Duration(minutes: 5));
        final remote = _FakeTarget(
          {a},
          [
            ProgressUpdate(
              itemId: b,
              position: Duration.zero,
              watched: true,
              at: now.add(const Duration(hours: 1)),
            ),
          ],
        );
        expect(await p.sync([remote]), 1);
        expect(remote.pushed.single.position, const Duration(minutes: 5));
        expect((await p.of(a))!.dirty, isFalse);
        expect((await p.of(b))!.watched, isTrue);
      },
    );
  });

  group('LIB-006 / LIB-004 / LIB-012 / LIB-015 views', () {
    test(
      'home rows: continue watching, recently added/played, unwatched',
      () async {
        final views = LibraryViews(db);
        final p = ProgressRepository(db, clock: () => now);
        final a = await seed.item(
          'a.mkv',
          title: 'A',
          durationMs: 600000,
          addedAt: DateTime.utc(2026),
        );
        final b = await seed.item(
          'b.mkv',
          title: 'B',
          addedAt: DateTime.utc(2026, 3),
        );
        await seed.item('c.flac', title: 'C', kind: ItemKind.audio);
        await p.savePosition(
          a,
          const Duration(minutes: 5),
          duration: const Duration(minutes: 10),
        );
        await p.recordPlay(b, const Duration(minutes: 1));
        final cw = await views.continueWatching(LibraryMode.video);
        expect(cw.single.item.id, a);
        expect(cw.single.fraction, closeTo(0.5, 1e-9));
        expect(
          (await views.recentlyAdded(LibraryMode.video)).map((i) => i.title),
          ['B', 'A'],
        );
        expect((await views.recentlyPlayed(LibraryMode.video)).single.id, b);
        expect(await views.unwatched(LibraryMode.video), isEmpty);
        expect(
          (await views.recentlyAdded(LibraryMode.music)).single.title,
          'C',
        );
      },
    );

    test('folder mode and library mode toggle persists per mode', () async {
      final views = LibraryViews(db);
      final sid = await seed.source();
      await seed.item('Films/Action/a.mkv', sourceId: sid);
      await seed.item('Films/Action/b.mkv', sourceId: sid);
      await seed.item('Films/Drama/c.mkv', sourceId: sid);
      await seed.item('Films/top.mkv', sourceId: sid);
      await seed.item('Music/x.flac', sourceId: sid, kind: ItemKind.audio);
      final root = await views.folders(sid, '', LibraryMode.video);
      expect(root.map((f) => (f.name, f.itemCount)), [('Films', 4)]);
      final films = await views.folders(sid, 'Films', LibraryMode.video);
      expect(films.map((f) => (f.path, f.itemCount)), [
        ('Films/Action', 2),
        ('Films/Drama', 1),
      ]);
      expect(
        (await views.folderItems(sid, 'Films', LibraryMode.video)).single.name,
        'top.mkv',
      );
      expect(await views.viewMode(LibraryMode.music), ViewMode.library);
      await views.setViewMode(LibraryMode.music, ViewMode.folders);
      expect(await views.viewMode(LibraryMode.music), ViewMode.folders);
      expect(await views.viewMode(LibraryMode.video), ViewMode.library);
    });

    test(
      'collections: series, albums, artists, genres, years, photo albums',
      () async {
        final views = LibraryViews(db);
        final s1 = await db
            .into(db.seriesTable)
            .insert(SeriesTableCompanion.insert(title: 'Show'));
        final e1 = await seed.item('s/e1.mkv');
        final e2 = await seed.item('s/e2.mkv');
        for (final e in [e1, e2]) {
          await db
              .into(db.videoMeta)
              .insert(
                VideoMetaCompanion.insert(
                  itemId: Value(e),
                  seriesId: Value(s1),
                ),
              );
        }
        await seed.item(
          'm/1.flac',
          kind: ItemKind.audio,
          album: 'LP',
          artist: 'Band',
          genre: 'Rock',
          year: 1999,
        );
        await seed.item(
          'm/2.flac',
          kind: ItemKind.audio,
          album: 'LP',
          artist: 'Band',
          genre: 'rock',
          year: 1999,
        );
        expect(
          (await views.collections(CollectionKind.series)).single.itemCount,
          2,
        );
        expect(
          (await views.collections(CollectionKind.albums)).single.title,
          'LP',
        );
        expect(
          (await views.collections(CollectionKind.artists)).single.itemCount,
          2,
        );
        expect(
          (await views.collections(CollectionKind.genres)).single.itemCount,
          2,
        );
        expect(
          (await views.collections(CollectionKind.years)).single.year,
          1999,
        );
        await db
            .into(db.playlists)
            .insert(
              PlaylistsCompanion.insert(
                name: 'Trip',
                mode: const Value('image'),
                createdAt: now,
                updatedAt: now,
              ),
            );
        expect(
          (await views.collections(CollectionKind.photoAlbums)).single.title,
          'Trip',
        );
      },
    );

    test(
      'statistics: plays, time played, top items, storage by type and source',
      () async {
        final views = LibraryViews(db);
        final p = ProgressRepository(db, clock: () => now);
        final nas = await seed.source(name: 'NAS');
        final a = await seed.item('a.mkv');
        final b = await seed.item(
          'b.flac',
          kind: ItemKind.audio,
          size: 300,
          sourceId: nas,
        );
        await p.recordPlay(a, const Duration(minutes: 30));
        await p.recordPlay(b, const Duration(minutes: 3));
        await p.recordPlay(b, const Duration(minutes: 3));
        final s = await views.stats();
        expect(s.playCount, 3);
        expect(s.timePlayed, const Duration(minutes: 36));
        expect(s.topItems.first.$1.id, b);
        expect(s.topItems.first.$2, 2);
        expect(s.bytesByKind, {ItemKind.video: 1000, ItemKind.audio: 300});
        expect(s.bytesBySource[nas], 300);
      },
    );
  });

  group('LIB-013 parental gate', () {
    test('PIN unlock, lockout, relock and visibility', () async {
      final store = FakeSecureStorage();
      final gate = ParentalGate(db: db, secureStorage: store, clock: () => now);
      expect(await gate.unlock(pin: '1234'), UnlockResult.noPin);
      await gate.setPin('1234');
      expect(store.values['parental.pin'], isNot(contains('1234')));
      final kids = await seed.source(name: 'Adult');
      await gate.setSourceLocked(kids, locked: true);
      await seed.item('x.mkv', title: 'Secret', sourceId: kids);
      final search = LibrarySearch(db);
      Future<int> visible() async => (await search.search(
        SearchRequest('secret', visibility: gate.visibility),
      )).length;
      expect(await visible(), 0);
      expect(await gate.unlock(pin: '0000'), UnlockResult.wrongPin);
      expect(await gate.unlock(pin: '1234'), UnlockResult.unlocked);
      expect(await visible(), 1);
      now = now.add(const Duration(minutes: 11));
      expect(gate.isUnlocked, isFalse);
      for (var i = 0; i < 4; i++) {
        expect(await gate.unlock(pin: '9999'), UnlockResult.wrongPin);
      }
      expect(await gate.unlock(pin: '9999'), UnlockResult.lockedOut);
      expect(await gate.unlock(pin: '1234'), UnlockResult.lockedOut);
      now = now.add(const Duration(seconds: 31));
      expect(await gate.unlock(pin: '1234'), UnlockResult.unlocked);
      expect(
        () => gate.setPin('12'),
        throwsA(
          isA<ParentalGateException>().having(
            (e) => e.reason,
            'reason',
            ParentalGateRefusal.invalidPin,
          ),
        ),
      );
      await gate.dispose();
    });

    test('biometric unlock and hidden items', () async {
      final bio = FakeBiometrics();
      final gate = ParentalGate(
        db: db,
        secureStorage: FakeSecureStorage(),
        biometrics: bio,
        clock: () => now,
      );
      await gate.setPin('2468');
      final a = await seed.item('a.mkv', title: 'Hide me');
      await gate.setHidden([a], hidden: true);
      expect(
        await LibrarySearch(db).search(const SearchRequest('hide')),
        isEmpty,
      );
      expect(
        () => gate.setHidden([a], hidden: false),
        throwsA(isA<ParentalGateException>()),
      );
      expect(await gate.unlock(), UnlockResult.unlocked);
      expect(bio.prompts, 1);
      await gate.setHidden([a], hidden: false);
      expect(
        await LibrarySearch(db).search(const SearchRequest('hide')),
        hasLength(1),
      );
    });
  });

  group('LIB-014 duplicates', () {
    test('exact by hash, perceptual images, acoustic audio, video duration+size; never deletes', () async {
      final a = await seed.item('a.mkv', size: 500, durationMs: 60000);
      final b = await seed.item('copy/a.mkv', size: 500, durationMs: 60000);
      await seed.item('other.mkv', size: 500, durationMs: 999000);
      final v1 = await seed.item('v1.mp4', size: 100000, durationMs: 3600000);
      final v2 = await seed.item('v2.mkv', size: 100500, durationMs: 3600400);
      final i1 = await seed.item('p1.jpg', kind: ItemKind.image, size: 10);
      final i2 = await seed.item('p2.jpg', kind: ItemKind.image, size: 11);
      final i3 = await seed.item('p3.jpg', kind: ItemKind.image, size: 12);
      final s1 = await seed.item('s1.flac', kind: ItemKind.audio, size: 20);
      final s2 = await seed.item('s2.mp3', kind: ItemKind.audio, size: 21);
      final inputs = _Inputs(
        hashes: {a: 'h1', b: 'h1'},
        grey: {i1: _gradient(0), i2: _gradient(3), i3: _checker()},
        prints: {s1: _print(1), s2: _flipBits(_print(1), 0.05)},
      );
      final finder = DuplicateFinder(db, inputs: inputs);
      final all = await finder.find(DuplicateKind.values.toSet());
      Set<int> idsOf(DuplicateKind k) => {
        for (final g in all.where((g) => g.kind == k))
          ...g.items.map((i) => i.id),
      };
      expect(idsOf(DuplicateKind.exact), {a, b});
      expect(idsOf(DuplicateKind.perceptualImage), {i1, i2});
      expect(idsOf(DuplicateKind.acousticAudio), {s1, s2});
      expect(idsOf(DuplicateKind.videoDurationSize), containsAll([v1, v2]));
      expect(await db.select(db.items).get(), hasLength(10));
      final g = all.firstWhere(
        (g) =>
            g.kind == DuplicateKind.videoDurationSize &&
            g.items.any((i) => i.id == v1),
      );
      expect(g.suggestedKeep.id, v2);
    });

    test(
      'pHash is stable under small changes and differs for different images',
      () {
        final base = phash64(_gradient(0));
        expect(hamming64(base, phash64(_gradient(2))), lessThanOrEqualTo(6));
        expect(hamming64(base, phash64(_checker())), greaterThan(10));
      },
    );
  });
}

/// A smooth natural-ish image; [noise] adds a small deterministic jitter.
Uint8List _gradient(int noise) {
  final r = Random(7);
  return Uint8List.fromList([
    for (var y = 0; y < 32; y++)
      for (var x = 0; x < 32; x++)
        (128 +
                60 * sin(x / 5) +
                50 * cos(y / 4) +
                30 * sin((x + y) / 7) +
                (noise == 0 ? 0 : r.nextInt(2 * noise + 1) - noise))
            .round()
            .clamp(0, 255),
  ]);
}

Uint8List _checker() => Uint8List.fromList([
  for (var y = 0; y < 32; y++)
    for (var x = 0; x < 32; x++)
      if ((x ~/ 4 + y ~/ 4).isEven) 0 else 255,
]);

Uint32List _print(int seed) {
  final r = Random(seed);
  return Uint32List.fromList([
    for (var i = 0; i < 300; i++) r.nextInt(1 << 32),
  ]);
}

Uint32List _flipBits(Uint32List p, double rate) {
  final r = Random(99);
  return Uint32List.fromList([
    for (final w in p)
      w ^ (r.nextDouble() < rate * 8 ? (1 << r.nextInt(32)) : 0),
  ]);
}

final class _Inputs implements DuplicateInputs {
  _Inputs({required this.hashes, required this.grey, required this.prints});

  final Map<int, String> hashes;
  final Map<int, Uint8List> grey;
  final Map<int, Uint32List> prints;

  @override
  Future<String?> contentHash(ItemRow item) async =>
      hashes[item.id] ?? 'u${item.id}';

  @override
  Future<Uint8List?> grey32(ItemRow item) async => grey[item.id];

  @override
  Future<Uint32List?> fingerprint(ItemRow item) async => prints[item.id];
}

final class _FakeTarget implements ProgressSyncTarget {
  _FakeTarget(this.known, this.remote);

  final Set<int> known;
  final List<ProgressUpdate> remote;
  final pushed = <ProgressUpdate>[];

  @override
  String get id => 'fake';

  @override
  Future<bool> handles(int itemId) async => known.contains(itemId);

  @override
  Future<void> push(ProgressUpdate update) async => pushed.add(update);

  @override
  Future<List<ProgressUpdate>> pull({DateTime? since}) async => remote;
}
