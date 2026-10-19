import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mediahro/core/db/library_database.dart';
import 'package:mediahro/core/library/playlists.dart';
import 'package:mediahro/core/parsers/playlist_parser.dart';
import 'package:mediahro/core/rules/smart_rule.dart';

import '../seed.dart';

void main() {
  late LibraryDatabase db;
  late Seed seed;
  late PlaylistRepository repo;
  final now = DateTime.utc(2026, 10, 19);

  setUp(() {
    db = LibraryDatabase.memory();
    seed = Seed(db);
    repo = PlaylistRepository(db, clock: () => now);
  });
  tearDown(() => db.close());

  group('LIB-007 smart rules', () {
    late int rock1;
    late int rock2;
    late int jazz;
    late int film;

    setUp(() async {
      rock1 = await seed.item(
        'm/a.flac',
        kind: ItemKind.audio,
        title: 'Alpha',
        genre: 'Rock',
        artist: 'Band',
        durationMs: 4 * 60000,
        playCount: 10,
        year: 1991,
        lastPlayedAt: DateTime.utc(2026, 10, 15),
      );
      rock2 = await seed.item(
        'm/b.flac',
        kind: ItemKind.audio,
        title: 'Bravo',
        genre: 'Rock',
        artist: 'Other',
        durationMs: 5 * 60000,
        playCount: 2,
        year: 2001,
        lastPlayedAt: DateTime.utc(2025),
      );
      jazz = await seed.item(
        'm/c.flac',
        kind: ItemKind.audio,
        title: 'Charlie',
        genre: 'Jazz',
        durationMs: 3 * 60000,
        year: 1959,
      );
      film = await seed.item('v/film.mkv', title: 'Delta', height: 2160);
      await seed.tag(jazz, 'favourite');
      await seed.rate(rock1, 10);
    });

    Future<List<String>> run(SmartRule r) async => [
      for (final i in await repo.evaluate(r)) i.title,
    ];

    test('AND/OR groups over any indexed field', () async {
      const r = SmartRule(
        root: RuleGroup(
          matchAll: false,
          children: [
            RuleGroup(
              children: [
                RuleCondition(RuleField.genre, RuleOp.equals, 'rock'),
                RuleCondition(RuleField.playCount, RuleOp.atLeast, 5),
              ],
            ),
            RuleCondition(RuleField.tag, RuleOp.equals, 'Favourite'),
          ],
        ),
      );
      expect(await run(r), ['Alpha', 'Charlie']);
      expect(rock2, isPositive);
    });

    test('text, number, date and set operators', () async {
      Future<List<String>> one(RuleCondition c) =>
          run(SmartRule(root: RuleGroup(children: [c])));
      expect(
        await one(
          const RuleCondition(RuleField.title, RuleOp.startsWith, 'br'),
        ),
        ['Bravo'],
      );
      expect(
        await one(const RuleCondition(RuleField.title, RuleOp.endsWith, 'LIE')),
        ['Charlie'],
      );
      expect(
        await one(const RuleCondition(RuleField.artist, RuleOp.contains, 'an')),
        ['Alpha'],
      );
      expect(
        await one(
          const RuleCondition(RuleField.artist, RuleOp.notContains, 'an'),
        ),
        ['Bravo', 'Charlie', 'Delta'],
      );
      expect(
        await one(
          const RuleCondition(RuleField.year, RuleOp.between, 1950, 1995),
        ),
        ['Alpha', 'Charlie'],
      );
      expect(
        await one(
          const RuleCondition(RuleField.lastPlayed, RuleOp.inLastDays, 30),
        ),
        ['Alpha'],
      );
      expect(
        await one(
          const RuleCondition(RuleField.lastPlayed, RuleOp.notInLastDays, 30),
        ),
        ['Bravo', 'Charlie', 'Delta'],
      );
      expect(await one(const RuleCondition(RuleField.rating, RuleOp.isSet)), [
        'Alpha',
      ]);
      expect(await one(const RuleCondition(RuleField.tag, RuleOp.isNotSet)), [
        'Alpha',
        'Bravo',
        'Delta',
      ]);
      expect(
        await one(const RuleCondition(RuleField.kind, RuleOp.equals, 'video')),
        ['Delta'],
      );
      expect(
        await one(
          const RuleCondition(RuleField.genre, RuleOp.anyOf, ['jazz', 'Blues']),
        ),
        ['Charlie'],
      );
      expect(
        await one(
          const RuleCondition(RuleField.height, RuleOp.greaterThan, 1080),
        ),
        ['Delta'],
      );
      expect(film, isPositive);
    });

    test('limits by count, minutes and size, and sorting', () async {
      final audio = {'audio'};
      expect(
        await run(
          SmartRule(
            kinds: audio,
            sort: const RuleSort(RuleField.playCount, descending: true),
            limit: 2,
          ),
        ),
        ['Alpha', 'Bravo'],
      );
      // 4 + 3 minutes fit in 8; the 5-minute track does not.
      expect(
        await run(
          SmartRule(
            kinds: audio,
            sort: const RuleSort(RuleField.year),
            limit: 8,
            limitUnit: RuleLimitUnit.minutes,
          ),
        ),
        ['Charlie', 'Alpha'],
      );
      expect(
        await run(SmartRule(kinds: audio, sort: RuleSort.random)),
        hasLength(3),
      );
    });

    test(
      'rules round-trip through JSON and smart playlists stay live',
      () async {
        const rule = SmartRule(
          root: RuleGroup(
            children: [RuleCondition(RuleField.genre, RuleOp.equals, 'Rock')],
          ),
          limit: 10,
          sort: RuleSort(RuleField.dateAdded, descending: true),
          kinds: {'audio'},
        );
        expect(SmartRule.decode(rule.encode()), rule);
        final id = await repo.createSmart('Rock', rule);
        expect(
          (await repo.tracks(id)).map((t) => t.displayTitle),
          hasLength(2),
        );
        await seed.item(
          'm/d.flac',
          kind: ItemKind.audio,
          title: 'Echo',
          genre: 'rock',
        );
        expect(
          (await repo.tracks(id)).map((t) => t.displayTitle),
          hasLength(3),
        );
      },
    );
  });

  test(
    'LIB-007 manual playlists: add, reorder, remove, cross-source URIs',
    () async {
      final a = await seed.item('a.mkv', title: 'A');
      final b = await seed.item('b.mkv', title: 'B');
      final id = await repo.createManual('Mine');
      await repo.addItems(id, [a, b]);
      await repo.addUri(id, 'https://example.org/live.m3u8', title: 'Live');
      await repo.move(id, 2, 0);
      expect((await repo.tracks(id)).map((t) => t.displayTitle), [
        'Live',
        'A',
        'B',
      ]);
      await repo.removeAt(id, 1);
      expect((await repo.tracks(id)).map((t) => t.displayTitle), ['Live', 'B']);
    },
  );

  test(
    'LIB-007 import and export M3U8, PLS and XSPF, linking indexed items',
    () async {
      final a = await seed.item(
        'Music/a.flac',
        kind: ItemKind.audio,
        title: 'Song A',
      );
      expect(a, isPositive);
      const m3u =
          '#EXTM3U\n#EXTINF:215,Artist - Song A\nMusic/a.flac\n'
          '#EXTINF:-1,Radio\nhttps://radio.example/stream\n';
      final id = await repo.import(
        'Imported',
        Uint8List.fromList(utf8.encode(m3u)),
        PlaylistFormat.m3u,
        base: Uri.parse('file:///Local/'),
      );
      final tracks = await repo.tracks(id);
      expect(tracks.first.item?.id, a);
      expect(tracks.last.uri, 'https://radio.example/stream');

      final out = await repo.export(id, PlaylistFormat.m3u);
      expect(out, contains('file:///Local/Music/a.flac'));
      expect(out, contains('https://radio.example/stream'));
      final pls = parsePls(await repo.export(id, PlaylistFormat.pls));
      expect(pls.entries, hasLength(2));
      final xspf = parseXspf(await repo.export(id, PlaylistFormat.xspf));
      expect(xspf.entries.first.location, 'file:///Local/Music/a.flac');
      expect(xspf.title, 'Imported');
    },
  );
}
