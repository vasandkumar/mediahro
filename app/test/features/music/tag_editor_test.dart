import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mediahro/core/db/library_database.dart';
import 'package:mediahro/features/music/library/artwork_store.dart';
import 'package:mediahro/features/music/library/music_library.dart';
import 'package:mediahro/features/music/player/music_prefs.dart';
import 'package:mediahro/features/music/tags/audio_tags.dart';
import 'package:mediahro/features/music/tags/tag_reader.dart';
import 'package:mediahro/features/music/tags/writer/tag_edit.dart';
import 'package:mediahro/features/music/tags/writer/tag_editor.dart';

import 'music_test_support.dart';
import 'tag_fixtures.dart';

void main() {
  group('MUS-003 patterns', () {
    const t = AudioTags(
      fields: {
        TagField.title: ['Song: One?'],
        TagField.artist: ['Amy'],
        TagField.album: ['Al'],
        TagField.trackNumber: ['3'],
        TagField.date: ['1999-04-01'],
      },
    );

    test('MUS-003 rename from tags pads tracks and cleans illegal chars', () {
      expect(
        nameFromTags('%track% - %artist% - %title%', t),
        '03 - Amy - Song_ One_',
      );
      expect(nameFromTags('%year%/%album%', t), '1999_Al');
      expect(nameFromTags('%composer% - %title%', t), isNull);
    });

    test('MUS-003 tags from file name', () {
      expect(
        tagsFromName('%track% - %artist% - %title%', '07 - Bo - Hey - You'),
        {
          TagField.trackNumber: ['7'],
          TagField.artist: ['Bo'],
          TagField.title: ['Hey - You'],
        },
      );
      expect(tagsFromName('%artist% - %title%', 'NoDash'), isNull);
    });
  });

  group('MUS-003 editor', () {
    late Directory dir;
    late LibraryDatabase db;
    late MusicLibrary lib;
    late TagEditor editor;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('c2_edit');
      db = LibraryDatabase.memory();
      lib = MusicLibrary(db);
      final seed = MusicSeed(db);
      await seed.source(dir.uri.toString());
      File('${dir.path}/a.flac')
          .writeAsBytesSync(flac(['TITLE=Old A', 'ARTIST=Amy', 'ALBUM=Al']));
      File('${dir.path}/b.mp3').writeAsBytesSync(
        bytesOf([
          id3v2(3, [
            id3Text(3, 'TIT2', ['Old B']),
            id3Text(3, 'TPE1', ['Bob']),
          ]),
          List<int>.filled(3000, 0xAA),
        ]),
      );
      File('${dir.path}/c.txt').writeAsStringSync('not audio');
      await seed.song('a.flac', title: 'Old A', artist: 'Amy', album: 'Al');
      await seed.song('b.mp3', title: 'Old B', artist: 'Bob');
      await seed.song('c.txt', title: 'c');
      editor = TagEditor(
        db: db,
        files: localMusicFiles(db),
        art: ArtworkStore(db, Directory('${dir.path}/art')),
        prefs: MusicPrefs(db),
        cacheDir: Directory('${dir.path}/cache'),
      );
    });
    tearDown(() async {
      await db.close();
      try {
        await dir.delete(recursive: true);
      } on FileSystemException {
        // Windows may hold a handle briefly.
      }
    });

    test('MUS-003 batch edit writes files, refreshes the index, leaves no '
        'temp or backup files, and undo restores', () async {
      final tracks = await lib.songs();
      final audio = tracks.where((t) => !t.relPath.endsWith('.txt')).toList();
      final res = await editor.apply(
        audio,
        (t, before) => TagEdit(
          fields: {
            TagField.album: const ['Batch Album'],
            TagField.title: ['New ${before.title}'],
          },
        ),
      );
      expect(res.changed, 2);
      expect(res.failed, isEmpty);
      final a = await TagReader.readFile('${dir.path}/a.flac');
      expect(a.title, 'New Old A');
      expect(a.album, 'Batch Album');
      expect(a.artist, 'Amy');
      final b = await TagReader.readFile('${dir.path}/b.mp3');
      expect(b.title, 'New Old B');
      final mp3 = File('${dir.path}/b.mp3').readAsBytesSync();
      expect(mp3.sublist(mp3.length - 3000), List<int>.filled(3000, 0xAA));
      // Index follows.
      final albums = await lib.albums();
      expect(albums.map((x) => x.title), contains('Batch Album'));
      // No leftovers next to the files.
      final names = dir.listSync().map(
        (e) => e.uri.pathSegments.where((s) => s.isNotEmpty).last,
      );
      expect(names.where((n) => n.contains('mediahro')), isEmpty);

      expect(await editor.canUndo(), isTrue);
      final undo = await editor.undoLast();
      expect(undo.changed, 2);
      expect((await TagReader.readFile('${dir.path}/a.flac')).title, 'Old A');
      expect((await TagReader.readFile('${dir.path}/a.flac')).album, 'Al');
      expect(await editor.canUndo(), isFalse);
    });

    test('MUS-003 unsupported files fail alone; the batch goes on', () async {
      final tracks = await lib.songs();
      final res = await editor.apply(
        tracks,
        (t, _) => const TagEdit(
          fields: {
            TagField.genre: ['Jazz'],
          },
        ),
      );
      expect(res.changed, 2);
      final c = tracks.firstWhere((t) => t.relPath == 'c.txt');
      expect(res.failed, {c.itemId: TagEditFailure.unsupported});
      expect(File('${dir.path}/c.txt').readAsStringSync(), 'not audio');
    });

    test('MUS-003 cover art replace updates the cached art', () async {
      final a = (await lib.songs()).firstWhere((t) => t.relPath == 'a.flac');
      final res = await editor.apply(
        [a],
        (t, _) => TagEdit(
          pictures: [
            EmbeddedPicture(
              type: PictureType.frontCover,
              mimeType: 'image/png',
              bytes: Uint8List.fromList(png),
            ),
          ],
        ),
      );
      expect(res.changed, 1);
      final path = await editor.art.coverPath(a.itemId);
      expect(File(path!).readAsBytesSync(), png);
    });
  });
}
