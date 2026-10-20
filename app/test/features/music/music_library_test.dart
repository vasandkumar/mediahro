import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mediahro/core/db/library_database.dart';
import 'package:mediahro/features/music/library/artwork_store.dart';
import 'package:mediahro/features/music/library/music_indexer.dart';
import 'package:mediahro/features/music/library/music_library.dart';

import 'music_test_support.dart';
import 'tag_fixtures.dart';

void main() {
  late LibraryDatabase db;
  late MusicSeed seed;
  late MusicLibrary lib;

  setUp(() {
    db = LibraryDatabase.memory();
    seed = MusicSeed(db);
    lib = MusicLibrary(db);
  });
  tearDown(() => db.close());

  group('MUS-001 library views', () {
    test('MUS-001 songs sort by title, artist, album, date added', () async {
      await seed.song('b.mp3', title: 'Beta', artist: 'Zed', album: 'A1');
      await seed.song(
        'a.mp3',
        title: 'Alpha',
        artist: 'Amy',
        album: 'Z1',
        addedAt: DateTime.utc(2027),
      );
      Future<List<String>> titles(SongSort s, {bool desc = false}) async => [
        for (final t in await lib.songs(sort: s, descending: desc)) t.title,
      ];
      expect(await titles(SongSort.title), ['Alpha', 'Beta']);
      expect(await titles(SongSort.title, desc: true), ['Beta', 'Alpha']);
      expect(await titles(SongSort.artist), ['Alpha', 'Beta']);
      expect(await titles(SongSort.album), ['Beta', 'Alpha']);
      expect(await titles(SongSort.dateAdded, desc: true), ['Alpha', 'Beta']);
    });

    test('MUS-001 albums group by album artist; compilations stay together '
        'by folder', () async {
      await seed.song(
        'x/1.mp3',
        album: 'Hits',
        albumArtist: 'Band',
        artist: 'Band',
        track: 1,
      );
      await seed.song(
        'y/2.mp3',
        album: 'Hits',
        albumArtist: 'Band',
        artist: 'Band',
        track: 2,
      );
      await seed.song('c/1.mp3', album: 'Mix', artist: 'P', track: 1);
      await seed.song('c/2.mp3', album: 'Mix', artist: 'Q', track: 2);
      await seed.song('d/1.mp3', album: 'Mix', artist: 'R');
      final albums = await lib.albums();
      expect(albums.map((a) => (a.title, a.trackCount)), [
        ('Hits', 2),
        ('Mix', 2),
        ('Mix', 1),
      ]);
      expect(albums[0].displayArtist, 'Band');
      expect(albums[1].isCompilation, isTrue);
      expect(albums[1].displayArtist, isNull);
      expect(albums[2].displayArtist, 'R');
      final tracks = await lib.albumTracks(albums[1].groupKey);
      expect(tracks.map((t) => t.artist), ['P', 'Q']);
      expect(tracks.first.albumKey, albums[1].groupKey);
    });

    test('MUS-001 album tracks in disc then track order', () async {
      await seed.song(
        'a/3.mp3',
        album: 'Set',
        albumArtist: 'S',
        disc: 2,
        track: 1,
      );
      await seed.song(
        'a/2.mp3',
        album: 'Set',
        albumArtist: 'S',
        disc: 1,
        track: 2,
      );
      await seed.song(
        'a/1.mp3',
        album: 'Set',
        albumArtist: 'S',
        disc: 1,
        track: 1,
      );
      final key = (await lib.albums()).single.groupKey;
      expect((await lib.albumTracks(key)).map((t) => t.relPath), [
        'a/1.mp3',
        'a/2.mp3',
        'a/3.mp3',
      ]);
    });

    test(
      'MUS-001 artists, album artists, genres, composers and years',
      () async {
        await seed.song(
          '1.mp3',
          artist: 'Amy',
          albumArtist: 'Group',
          genre: 'Jazz',
          composer: 'C',
          year: 1999,
          album: 'A',
        );
        await seed.song(
          '2.mp3',
          artist: 'amy',
          genre: 'jazz',
          year: 2001,
          album: 'B',
        );
        await seed.song('3.mp3', artist: 'Bob', genre: 'Rock', year: 2001);
        final artists = await lib.groups(GroupField.artist);
        expect(artists.map((g) => (g.name, g.trackCount)), [
          ('Amy', 2),
          ('Bob', 1),
        ]);
        expect(artists.first.albumCount, 2);
        expect((await lib.groups(GroupField.albumArtist)).map((g) => g.name), [
          'amy',
          'Bob',
          'Group',
        ]);
        expect((await lib.groups(GroupField.genre)).map((g) => g.trackCount), [
          2,
          1,
        ]);
        expect((await lib.groups(GroupField.composer)).single.name, 'C');
        expect((await lib.groups(GroupField.year)).map((g) => g.name), [
          '2001',
          '1999',
        ]);
        expect(
          (await lib.groupTracks(
            GroupField.year,
            '2001',
          )).map((t) => t.relPath),
          ['3.mp3', '2.mp3'],
        );
        expect((await lib.albums(artist: 'AMY')).length, 2);
      },
    );

    test('MUS-001 folder tracks and counts', () async {
      final sid = await seed.source();
      await seed.song('f/a.mp3', artist: 'X', track: 2);
      await seed.song('f/b.mp3', artist: 'X', track: 1);
      await seed.song('g/c.mp3');
      expect((await lib.folderTracks(sid, 'f')).map((t) => t.relPath), [
        'f/b.mp3',
        'f/a.mp3',
      ]);
      expect(await lib.songCount(), 3);
    });
  });

  group('MUS-002 / MUS-004 indexer', () {
    late Directory dir;
    setUp(() async => dir = await Directory.systemTemp.createTemp('c2_index'));
    tearDown(() => dir.delete(recursive: true));

    Future<int> rawItem(int sid, String rel, ItemKind kind) => db
        .into(db.items)
        .insert(
          ItemsCompanion.insert(
            sourceId: sid,
            relPath: rel,
            parentPath: rel.contains('/')
                ? rel.substring(0, rel.lastIndexOf('/'))
                : '',
            name: rel.split('/').last,
            ext: rel.split('.').last,
            kind: kind,
            size: File('${dir.path}/$rel').lengthSync(),
            mtime: DateTime.utc(2026),
            addedAt: DateTime.utc(2026),
            scannedAt: DateTime.utc(2026),
            title: rel,
            sortTitle: rel,
          ),
        );

    test('MUS-002 MUS-004 tags, ReplayGain, embedded and folder art', () async {
      final sid = await seed.source(dir.uri.toString());
      Directory('${dir.path}/al').createSync();
      Directory('${dir.path}/b').createSync();
      File('${dir.path}/al/1.flac').writeAsBytesSync(
        flac([
          'TITLE=One',
          'ARTIST=Amy',
          'ALBUM=Al',
          'TRACKNUMBER=1',
          'REPLAYGAIN_TRACK_GAIN=-4.5 dB',
        ], picture: jpeg),
      );
      File('${dir.path}/b/2.mp3').writeAsBytesSync(
        bytesOf([
          id3v2(3, [
            id3Text(3, 'TIT2', ['Two']),
            id3Text(3, 'TALB', ['Bee']),
          ]),
          mpegAudio,
        ]),
      );
      File('${dir.path}/b/Cover.PNG').writeAsBytesSync(png);
      final a = await rawItem(sid, 'al/1.flac', ItemKind.audio);
      final b = await rawItem(sid, 'b/2.mp3', ItemKind.audio);
      final art = ArtworkStore(db, Directory('${dir.path}/art'));
      final indexer = MusicIndexer(db: db, files: localMusicFiles(db), art: art)
        ..start();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await indexer.idle();
      final one = (await lib.track(a))!;
      expect(one.title, 'One');
      expect(one.artist, 'Amy');
      expect(one.trackGainDb, -4.5);
      expect(one.duration, const Duration(seconds: 10));
      expect((await lib.track(b))!.album, 'Bee');
      final ap = await art.coverPath(a);
      final bp = await art.coverPath(b);
      expect(File(ap!).readAsBytesSync(), jpeg);
      expect(File(bp!).readAsBytesSync(), png);
      final probed = await (db.select(
        db.items,
      )..where((i) => i.id.equals(a))).getSingle();
      expect(probed.probed, isTrue);
      await indexer.dispose();
    });

    test('MUS-004 identical covers are stored once', () async {
      final art = ArtworkStore(db, Directory('${dir.path}/art'));
      final p1 = await art.store(
        1,
        Uint8List.fromList(jpeg),
        mimeType: 'image/jpeg',
        source: ArtSource.embedded,
      );
      final p2 = await art.store(
        2,
        Uint8List.fromList(jpeg),
        mimeType: 'image/jpeg',
        source: ArtSource.embedded,
      );
      expect(p1, p2);
      expect(Directory('${dir.path}/art').listSync().length, 1);
    });

    test('MUS-004 folder art names in priority order', () {
      expect(
        ArtworkStore.pickFolderArt([
          'thumb.jpg',
          'Folder.jpg',
          'cover.png',
          'x.jpg',
        ]),
        'cover.png',
      );
      expect(
        ArtworkStore.pickFolderArt(['front.webp', 'notes.txt']),
        'front.webp',
      );
      expect(ArtworkStore.pickFolderArt(['back.jpg']), isNull);
    });

    test(
      'MUS-002 unreadable files stay unprobed and do not stop the queue',
      () async {
        final sid = await seed.source(dir.uri.toString());
        File('${dir.path}/ok.flac').writeAsBytesSync(flac(['TITLE=Ok']));
        final missing = await db
            .into(db.items)
            .insert(
              ItemsCompanion.insert(
                sourceId: sid,
                relPath: 'gone.mp3',
                parentPath: '',
                name: 'gone.mp3',
                ext: 'mp3',
                kind: ItemKind.audio,
                size: 1,
                mtime: DateTime.utc(2026),
                addedAt: DateTime.utc(2026),
                scannedAt: DateTime.utc(2026),
                title: 'gone',
                sortTitle: 'gone',
              ),
            );
        final ok = await rawItem(sid, 'ok.flac', ItemKind.audio);
        final indexer = MusicIndexer(
          db: db,
          files: localMusicFiles(db),
          art: ArtworkStore(db, Directory('${dir.path}/art')),
        )..enqueue([missing, ok]);
        await indexer.idle();
        expect((await lib.track(ok))!.title, 'Ok');
        final row = await (db.select(
          db.items,
        )..where((i) => i.id.equals(missing))).getSingle();
        expect(row.probed, isFalse);
        await indexer.dispose();
      },
    );
  });
}
