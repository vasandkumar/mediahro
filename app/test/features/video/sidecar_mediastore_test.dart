import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mediahro/core/files/saf_file_system.dart';
import 'package:mediahro/features/video/subtitles/sidecar_loader.dart';
import 'package:mediahro/features/video/subtitles/subtitle_sources.dart';
import 'package:mediahro/platform/platform_facades.dart';
import 'package:mediahro_ffi/mediahro_ffi.dart';

import '../../core/files/storage_fakes.dart';

/// SUB-012 on a real phone: a video of the device library (`mediastore:`)
/// has its `.srt` next to it in the same folder, but the library's MediaStore
/// tree holds video and audio only. Subtitles are queried on their own.
void main() {
  late Directory dir;
  late Directory cache;
  late FakeFdIo io;
  late FakeSafStorage storage;
  var now = DateTime.utc(2026, 10, 22, 12);

  MediaStoreEntry entry(String folder, String name, PickKind kind) =>
      MediaStoreEntry(
        uri: Uri.parse(
          'content://media/external/'
          '${kind == PickKind.subtitle ? 'file' : 'video'}/'
          '${(folder + name).hashCode.abs()}',
        ),
        relativePath: folder,
        name: name,
        size: 40,
        modified: DateTime.utc(2026),
        kind: kind,
      );

  setUp(() {
    dir = Directory.systemTemp.createTempSync('sidecar_ms');
    cache = Directory.systemTemp.createTempSync('sidecar_ms_cache');
    io = FakeFdIo();
    storage = FakeSafStorage(dir, io);
    now = DateTime.utc(2026, 10, 22, 12);
    for (final f in [
      'Movies/Film.mkv',
      'Movies/Film.en.srt',
      'Movies/Other.srt',
    ]) {
      File('${dir.path}/$f')
        ..createSync(recursive: true)
        ..writeAsStringSync('1\n00:00:01,000 --> 00:00:02,000\nHi\n');
    }
    storage.media.addAll([
      entry('Movies/', 'Film.mkv', PickKind.video),
      entry('Movies/', 'Film.en.srt', PickKind.subtitle),
      entry('Movies/', 'Other.srt', PickKind.subtitle),
    ]);
  });
  tearDown(() {
    for (final f in io.open.values) {
      f.closeSync();
    }
    dir.deleteSync(recursive: true);
    cache.deleteSync(recursive: true);
  });

  SidecarLoader loader() {
    final systems = SidecarFileSystems(
      mounted: (uri) =>
          throw VirtualFileException(VirtualFileError.notFound, uri),
      storage: storage,
      io: io,
      clock: () => now,
    );
    return SidecarLoader(fileSystemFor: systems.forUri, cacheDir: cache);
  }

  test('SUB-012 a MediaStore video finds the subtitle next to it', () async {
    final found = await loader().find(
      Uri.parse('mediastore:///Movies/Film.mkv'),
    );

    expect(found.map((f) => f.title), ['Film.en.srt']);
    expect(found.single.language, 'en');
    expect(File.fromUri(found.single.file).existsSync(), isTrue);
  });

  test('SUB-012 a video with no subtitle beside it finds nothing', () async {
    storage.media.removeWhere((m) => m.kind == PickKind.subtitle);
    final found = await loader().find(
      Uri.parse('mediastore:///Movies/Film.mkv'),
    );
    expect(found, isEmpty);
  });

  test('SUB-012 other schemes still use the mounted sources', () {
    final asked = <Uri>[];
    final systems = SidecarFileSystems(
      mounted: (uri) {
        asked.add(uri);
        throw VirtualFileException(VirtualFileError.notFound, uri);
      },
      storage: storage,
      io: io,
    );
    expect(
      () => systems.forUri(Uri.parse('saf://tree/g1/Films/')),
      throwsA(isA<VirtualFileException>()),
    );
    expect(asked, hasLength(1));
  });

  test('SUB-012 a subtitle added meanwhile is found after a while', () async {
    final l = loader();
    final video = Uri.parse('mediastore:///Movies/Film.mkv');
    storage.media.removeWhere((m) => m.name == 'Film.en.srt');
    expect(await l.find(video), isEmpty);

    storage.media.add(entry('Movies/', 'Film.en.srt', PickKind.subtitle));
    expect(await l.find(video), isEmpty, reason: 'the query is still fresh');

    now = now.add(const Duration(seconds: 30));
    expect((await l.find(video)).map((f) => f.title), ['Film.en.srt']);
  });

  test(
    'SUB-012 a video in a granted folder finds the subtitle next to it',
    () async {
      final root = SafFileSystem.rootFor('g1');
      final saf = SafFileSystem(
        storage,
        tree: FakeSafStorage.tree,
        root: root,
        io: io,
      );
      final systems = SidecarFileSystems(mounted: (_) => saf, storage: storage);
      final l = SidecarLoader(fileSystemFor: systems.forUri, cacheDir: cache);

      final found = await l.find(
        root.replace(pathSegments: ['g1', 'Movies', 'Film.mkv']),
      );

      expect(found.map((f) => f.title), ['Film.en.srt']);
    },
  );
}
