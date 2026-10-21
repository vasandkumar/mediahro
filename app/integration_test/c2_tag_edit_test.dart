import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mediahro/core/db/library_database.dart';
import 'package:mediahro/core/scanner/scan_service.dart';
import 'package:mediahro/core/sources/source_access.dart';
import 'package:mediahro/features/music/library/artwork_store.dart';
import 'package:mediahro/features/music/library/music_files.dart';
import 'package:mediahro/features/music/library/music_indexer.dart';
import 'package:mediahro/features/music/library/music_library.dart';
import 'package:mediahro/features/music/player/music_prefs.dart';
import 'package:mediahro/features/music/tags/audio_tags.dart';
import 'package:mediahro/features/music/tags/tag_reader.dart';
import 'package:mediahro/features/music/tags/writer/tag_edit.dart';
import 'package:mediahro/features/music/tags/writer/tag_editor.dart';
import 'package:mediahro_ffi/mediahro_ffi.dart';

import '../test/features/music/tag_fixtures.dart';

/// Lane C2, tag editing on real devices (MUS-003): every container is
/// edited through the device file system (temp file, verify, swap), the
/// index follows, and undo restores.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late Directory media;
  late Directory data;
  late LibraryDatabase db;

  setUp(() async {
    media = await Directory.systemTemp.createTemp('c2te_media');
    data = await Directory.systemTemp.createTemp('c2te_data');
    db = LibraryDatabase.open(data);
  });
  tearDown(() async {
    await db.close();
    for (final d in [media, data]) {
      try {
        await d.delete(recursive: true);
      } on FileSystemException {
        // The OS cleans temp.
      }
    }
  });

  testWidgets('MUS-003 edit, verify, swap and undo across every container on '
      'the device', (tester) async {
    await tester.runAsync(() async {
      final files = <String, Uint8List>{
        'a.mp3': bytesOf([
          id3v2(3, [
            id3Text(3, 'TIT2', ['Old']),
          ]),
          mpegAudio,
        ]),
        'b.flac': flac(['TITLE=Old'], picture: jpeg),
        'c.ogg': oggVorbis(['TITLE=Old']),
        'd.opus': oggOpus(['TITLE=Old']),
        'e.m4a': mp4(text: {'©nam': 'Old'}),
        'f.wma': asf(title: 'Old', artist: 'x'),
        'g.wav': wav(info: {'INAM': 'Old'}),
        'h.aiff': aiff(name: 'Old'),
        'i.ape': bytesOf([
          ascii('MAC '),
          List.filled(60, 0),
          apeTag({'Title': 'Old'}),
        ]),
      };
      for (final e in files.entries) {
        await File('${media.path}/${e.key}').writeAsBytes(e.value);
      }
      SourceResolver resolver() => DefaultSourceResolver(
        builders: {SourceKind.local: (_) => const LocalFileSystem()},
      );
      final sid = await db
          .into(db.sources)
          .insert(
            SourcesCompanion.insert(
              kind: SourceKind.local,
              name: 'Edit',
              rootUri: media.uri.toString(),
              addedAt: DateTime.now().toUtc(),
            ),
          );
      final scan = ScanService(db: db, resolver: resolver());
      await scan.scan(sid);
      await scan.dispose();
      final mf = MusicFiles(db, resolver());
      final art = ArtworkStore(db, Directory('${data.path}/art'));
      final indexer = MusicIndexer(db: db, files: mf, art: art)..start();
      for (var i = 0; i < 100 && indexer.pending == 0; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      await indexer.idle();
      await indexer.dispose();
      final lib = MusicLibrary(db);
      final tracks = await lib.songs();
      expect(tracks.length, files.length);
      final editor = TagEditor(
        db: db,
        files: mf,
        art: art,
        prefs: MusicPrefs(db),
        cacheDir: Directory('${data.path}/edit'),
      );
      final res = await editor.apply(
        tracks,
        (_, _) => const TagEdit(
          fields: {
            TagField.title: ['Edited'],
            TagField.album: ['Device Album'],
          },
        ),
      );
      expect(res.failed, isEmpty);
      expect(res.changed, files.length);
      for (final name in files.keys) {
        final t = await TagReader.readFile('${media.path}/$name');
        expect(t.title, 'Edited', reason: name);
        expect(t.album, 'Device Album', reason: name);
      }
      expect((await lib.albums()).single.title, 'Device Album');
      // Anything beside the files this test created is a leftover temp or
      // backup. Compare file names only: the full path itself contains
      // 'mediahro' (com.mediahro.app) on a device.
      final leftovers = media
          .listSync()
          .map((e) => e.uri.pathSegments.lastWhere((s) => s.isNotEmpty))
          .where((name) => !files.containsKey(name));
      expect(leftovers, isEmpty);
      await editor.undoLast();
      for (final name in files.keys) {
        final t = await TagReader.readFile('${media.path}/$name');
        expect(t.title, 'Old', reason: name);
      }
    });
  });
}
