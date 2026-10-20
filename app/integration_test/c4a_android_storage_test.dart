import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mediahro/core/files/media_store_file_system.dart';
import 'package:mediahro/core/files/saf_file_system.dart';
import 'package:mediahro/platform/android/android_storage.dart';
import 'package:mediahro/platform/platform_bindings.dart';
import 'package:mediahro/platform/platform_facades.dart';
import 'package:path_provider/path_provider.dart';

/// Lane C4a: StorageFacade and PhotoLibraryFacade on the Android emulator,
/// driving B2's SAF and MediaStore file systems against the real Kotlin
/// modules. SAF trees come from the debug-only `TestDocumentsProvider`
/// (every call still goes through DocumentsContract); system pickers are
/// answered by the debug-only `mediahro.test/pickers` hook. MediaStore rows
/// are real: files the app creates under Movies/, Music/ and Pictures/ are
/// indexed by the OS and owned by the app.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final android = Platform.isAndroid;

  const pickers = BasicMessageChannel<Object?>(
    'mediahro.test/pickers',
    StandardMessageCodec(),
  );
  Future<void> answerPickers(List<Object?> answers) => pickers.send(answers);
  const scanner = BasicMessageChannel<Object?>(
    'mediahro.test/scan',
    StandardMessageCodec(),
  );

  const authority = 'com.mediahro.app.testdocs';
  final tree = Uri.parse('content://$authority/tree/root');
  Uri doc(String rel) => Uri.parse(
    'content://$authority/tree/root/document/${Uri.encodeComponent('root/$rel')}',
  );

  late AndroidStorage storage;
  late Directory safBase;
  final run = DateTime.now().microsecondsSinceEpoch;

  setUp(() async {
    if (!android) return;
    storage = AndroidStorage();
    safBase = Directory(
      '${(await getApplicationSupportDirectory()).path}/saf-test',
    );
    if (safBase.existsSync()) await safBase.delete(recursive: true);
    await safBase.create(recursive: true);
    await answerPickers(const []);
  });

  Future<File> safFile(String rel, List<int> bytes) async {
    final f = File('${safBase.path}/$rel');
    await f.parent.create(recursive: true);
    return f..writeAsBytesSync(bytes);
  }

  Future<File> sharedFile(String dir, String name, List<int> bytes) async {
    final f = File('/storage/emulated/0/$dir/MediahroC4a/$run-$name');
    await f.parent.create(recursive: true);
    addTearDown(() async {
      if (f.existsSync()) await f.delete();
    });
    f.writeAsBytesSync(bytes, flush: true);
    // Index it as the OS does for other apps' files (debug-only hook).
    await scanner.send([f.path]);
    return f;
  }

  testWidgets('SYS-007 Android bindings provide Storage and PhotoLibrary', (
    tester,
  ) async {
    final c = ProviderContainer(overrides: platformOverrides());
    addTearDown(c.dispose);
    expect(c.read(storageProvider), isA<AndroidStorage>());
    expect(c.read(photoLibraryProvider), isA<AndroidPhotoLibrary>());
  }, skip: !android);

  testWidgets(
    'SYS-007 folder grant persists, resolves after lookup and releases',
    (tester) async {
      await answerPickers(['$tree']);
      final grant = await storage.pickFolder();
      expect(grant, isNotNull);
      expect(grant!.uri, tree);
      expect(grant.displayName, 'Mediahro test');
      expect((await storage.grants()).map((g) => g.id), contains(grant.id));
      expect(await storage.resolveGrant(grant.id), tree);
      final access = await storage.startAccess(grant.id);
      expect(access.root, tree);
      await access.stop();
      await storage.releaseGrant(grant.id);
      expect(await storage.resolveGrant(grant.id), isNull);
      await answerPickers([null]);
      expect(await storage.pickFolder(), isNull, reason: 'cancelled picker');
    },
    skip: !android,
  );

  testWidgets('SYS-007 picked files keep their name and size', (tester) async {
    await safFile('Films/a.mkv', List.filled(1234, 7));
    await safFile('Subs/a.srt', [1, 2, 3]);
    await answerPickers([
      '${doc('Films/a.mkv')}',
      ['${doc('Films/a.mkv')}', '${doc('Subs/a.srt')}'],
    ]);
    final one = await storage.pickFiles(kinds: {PickKind.video});
    expect(one.single.name, 'a.mkv');
    expect(one.single.size, 1234);
    final many = await storage.pickFiles(
      kinds: {PickKind.subtitle},
      multiple: true,
    );
    expect(many.map((p) => p.name), ['a.mkv', 'a.srt']);
  }, skip: !android);

  testWidgets('LIB-002 SafFileSystem lists, stats and reads a granted tree', (
    tester,
  ) async {
    final bytes = List<int>.generate(70000, (i) => i % 251);
    await safFile('Films/Holiday/clip.mkv', bytes);
    await safFile('Films/notes.txt', [65]);
    final fs = SafFileSystem(
      storage,
      tree: tree,
      root: SafFileSystem.rootFor('t'),
    );
    addTearDown(fs.close);
    final root = SafFileSystem.rootFor('t');
    final films = await fs.list(root).single;
    expect(films.name, 'Films');
    expect(films.isDirectory, isTrue);
    final names = await fs.list(films.uri).map((e) => e.name).toList();
    expect(names, unorderedEquals(['Holiday', 'notes.txt']));
    final clip = root.resolve('Films/Holiday/clip.mkv');
    expect((await fs.stat(clip)).size, bytes.length);
    final file = await fs.open(clip);
    expect(await file.length(), bytes.length);
    expect(await file.read(65000, 5000), bytes.sublist(65000, 70000));
    await file.close();
  }, skip: !android);

  testWidgets(
    'FILE-002 new folder, write, rename, move and delete in a SAF tree',
    (tester) async {
      final root = SafFileSystem.rootFor('t');
      final fs = SafFileSystem(storage, tree: tree, root: root);
      addTearDown(fs.close);
      final dir = await fs.createDirectory(root, 'New');
      expect(Directory('${safBase.path}/New').existsSync(), isTrue);
      final w = await fs.create(dir.resolve('n.bin'));
      await w.write(Uint8List.fromList([1, 2, 3, 4]));
      await w.close();
      expect(File('${safBase.path}/New/n.bin').readAsBytesSync(), [1, 2, 3, 4]);
      final renamed = await fs.rename(dir.resolve('n.bin'), 'm.bin');
      expect(File('${safBase.path}/New/m.bin').existsSync(), isTrue);
      final other = await fs.createDirectory(root, 'Other');
      await fs.move(renamed, other);
      expect(File('${safBase.path}/Other/m.bin').existsSync(), isTrue);
      expect(File('${safBase.path}/New/m.bin').existsSync(), isFalse);
      await fs.delete(dir, recursive: true);
      expect(Directory('${safBase.path}/New').existsSync(), isFalse);
    },
    skip: !android,
  );

  testWidgets('FILE-002 SAF document trash and undo', (tester) async {
    await safFile('Films/b.mkv', [9, 9]);
    final r = await storage.moveToTrash([doc('Films/b.mkv')]);
    expect(r.undoToken, isNotNull);
    expect(File('${safBase.path}/Films/b.mkv').existsSync(), isFalse);
    expect(File('${safBase.path}/.Trash-mediahro/b.mkv').existsSync(), isTrue);
    await storage.restoreFromTrash(r);
    expect(File('${safBase.path}/Films/b.mkv').readAsBytesSync(), [9, 9]);
  }, skip: !android);

  testWidgets('FILE-002 app-private file trash and undo', (tester) async {
    final dir = await Directory.systemTemp.createTemp('c4a_trash');
    addTearDown(() => dir.delete(recursive: true));
    final f = File('${dir.path}/Trash me/a.mkv');
    await f.parent.create(recursive: true);
    await f.writeAsBytes([1, 2, 3]);
    final r = await storage.moveToTrash([f.uri]);
    expect(r.trashed, [f.uri]);
    expect(f.existsSync(), isFalse);
    await storage.restoreFromTrash(r);
    expect(f.readAsBytesSync(), [1, 2, 3]);
  }, skip: !android);

  testWidgets(
    'LIB-002 MediaStore video and audio through MediaStoreFileSystem',
    (tester) async {
      final since = DateTime.now().subtract(const Duration(seconds: 5));
      final video = await sharedFile('Movies', 'v.mp4', List.filled(4096, 1));
      await sharedFile('Music', 'a.mp3', List.filled(2048, 2));
      final entries = await storage
          .mediaStoreEntries(
            kinds: {PickKind.video, PickKind.audio},
            modifiedSince: since,
          )
          .toList();
      final v = entries.singleWhere((e) => e.name == '$run-v.mp4');
      expect(v.kind, PickKind.video);
      expect(v.relativePath, 'Movies/MediahroC4a/');
      expect(v.size, 4096);
      expect(v.uri.scheme, 'content');
      final a = entries.singleWhere((e) => e.name == '$run-a.mp3');
      expect(a.kind, PickKind.audio);

      final fs = MediaStoreFileSystem(storage);
      addTearDown(fs.close);
      final dir = MediaStoreFileSystem.root.resolve('Movies/MediahroC4a/');
      expect(
        await fs.list(dir).map((e) => e.name).toList(),
        contains('$run-v.mp4'),
      );
      final file = await fs.open(dir.resolve('$run-v.mp4'));
      expect(await file.read(0, 16), List.filled(16, 1));
      await file.close();
      expect(video.existsSync(), isTrue);
    },
    skip: !android,
  );

  testWidgets('FILE-002 MediaStore OS trash (IS_TRASHED) and undo', (
    tester,
  ) async {
    final video = await sharedFile('Movies', 't.mp4', List.filled(512, 3));
    final entry = await storage
        .mediaStoreEntries(kinds: {PickKind.video})
        .firstWhere((e) => e.name == '$run-t.mp4');
    final r = await storage.moveToTrash([entry.uri]);
    expect(r.trashed, [entry.uri]);
    expect(video.existsSync(), isFalse, reason: 'renamed to .trashed-*');
    final after = await storage
        .mediaStoreEntries(kinds: {PickKind.video})
        .map((e) => e.name)
        .toList();
    expect(after, isNot(contains('$run-t.mp4')));
    await storage.restoreFromTrash(r);
    expect(video.existsSync(), isTrue);
  }, skip: !android);

  testWidgets('LIB-003 changes() reports MediaStore and SAF tree changes', (
    tester,
  ) async {
    await answerPickers(['$tree']);
    final grant = (await storage.pickFolder())!;
    addTearDown(() => storage.releaseGrant(grant.id));

    final saf = Completer<Uri>();
    final s1 = storage.changes(grant.id).listen((u) {
      if (!saf.isCompleted) saf.complete(u);
    });
    addTearDown(s1.cancel);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    await storage.createDocument(tree, 'fresh.txt', mimeType: 'text/plain');
    expect(
      (await saf.future.timeout(const Duration(seconds: 10))).scheme,
      'content',
    );

    final media = Completer<Uri>();
    final s2 = storage.changes(AndroidStorage.mediaStoreGrant).listen((u) {
      if (!media.isCompleted) media.complete(u);
    });
    addTearDown(s2.cancel);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    await sharedFile('Movies', 'w.mp4', List.filled(64, 4));
    await media.future.timeout(const Duration(seconds: 10));
  }, skip: !android);

  testWidgets('FILE-002 saveFile streams content in chunks', (tester) async {
    final target = await storage.createDocument(
      tree,
      'export.m3u8',
      mimeType: 'application/vnd.apple.mpegurl',
    );
    await answerPickers(['$target']);
    final bytes = List<int>.generate(600 * 1024, (i) => i % 256);
    final saved = await storage.saveFile(
      suggestedName: 'export.m3u8',
      mimeType: 'application/vnd.apple.mpegurl',
      content: Stream.fromIterable([
        for (var i = 0; i < bytes.length; i += 70000)
          bytes.sublist(i, i + 70000 > bytes.length ? bytes.length : i + 70000),
      ]),
    );
    expect(saved, target);
    expect(File('${safBase.path}/export.m3u8').readAsBytesSync(), bytes);
    await answerPickers([null]);
    expect(
      await storage.saveFile(
        suggestedName: 'x',
        mimeType: 'text/plain',
        content: const Stream.empty(),
      ),
      isNull,
    );
  }, skip: !android);

  testWidgets('SYS-007 READ_MEDIA_* states', (tester) async {
    expect(
      await storage.mediaPermission(PickKind.subtitle),
      MediaPermission.notApplicable,
    );
    expect(
      await storage.mediaPermission(PickKind.video),
      isIn([
        MediaPermission.granted,
        MediaPermission.limited,
        MediaPermission.denied,
      ]),
    );
  }, skip: !android);

  testWidgets(
    'IMG-016 photo library pages images and extracts the Motion Photo video',
    (tester) async {
      final mp4 = [
        0,
        0,
        0,
        24,
        ...'ftypmp42'.codeUnits,
        ...List.filled(500, 5),
      ];
      final xmp =
          '<x:xmpmeta><rdf:Description GCamera:MicroVideo="1" '
          'GCamera:MicroVideoOffset="${mp4.length}"/></x:xmpmeta>';
      final jpeg = [
        0xFF, 0xD8, 0xFF, 0xE1, //
        ...'http://ns.adobe.com/xap/1.0/\u0000'.codeUnits,
        ...xmp.codeUnits,
        0xFF, 0xD9,
        ...mp4,
      ];
      await sharedFile('Pictures', 'PXL_1.MP.jpg', jpeg);
      final photos = AndroidPhotoLibrary();
      final asset = await photos
          .assets(pageSize: 50)
          .expand((page) => page)
          .firstWhere((a) => a.isLive);
      expect(asset.uri.scheme, 'content');
      final video = await photos.pairedVideo(asset.id);
      expect(video, isNotNull);
      expect(File.fromUri(video!).readAsBytesSync(), mp4);
      expect(await photos.access(), isIn(PhotoAccess.values));
    },
    skip: !android,
  );
}
