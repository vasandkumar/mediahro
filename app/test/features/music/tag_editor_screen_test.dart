import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediahro/app/app.dart';
import 'package:mediahro/app/router.dart';
import 'package:mediahro/core/db/library_database.dart';
import 'package:mediahro/core/providers.dart';
import 'package:mediahro/engine/engine_pool.dart';
import 'package:mediahro/features/music/music_wiring.dart';
import 'package:mediahro/features/music/tags/tag_reader.dart';
import 'package:mediahro/features/settings/settings_providers.dart';

import '../../helpers.dart';
import 'music_screens_test.dart' show finish, settle;
import 'music_test_support.dart';
import 'tag_fixtures.dart';

void main() {
  late LibraryDatabase db;
  late Directory dir;

  setUp(() async {
    db = LibraryDatabase.memory();
    dir = Directory.systemTemp.createTempSync('c2_tagui');
  });
  tearDown(() async {
    await db.close();
    try {
      dir.deleteSync(recursive: true);
    } on FileSystemException {
      // Best effort on Windows.
    }
  });

  testWidgets('MUS-003 edit one song from its menu; the file and the library '
      'change', (tester) async {
    await tester.runAsync(() async {
      File('${dir.path}/one.flac')
          .writeAsBytesSync(flac(['TITLE=Before', 'ARTIST=Amy', 'ALBUM=Al']));
      final seed = MusicSeed(db);
      await seed.source(dir.uri.toString());
      await seed.song('one.flac', title: 'Before', artist: 'Amy', album: 'Al');
    });
    tester.view
      ..physicalSize = const Size(420, 900) * tester.view.devicePixelRatio
      ..devicePixelRatio = tester.view.devicePixelRatio;
    addTearDown(tester.view.resetPhysicalSize);
    final store = await tester.runAsync(memoryStore);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsStoreProvider.overrideWithValue(store!),
          ...musicOverrides,
          libraryDatabaseProvider.overrideWithValue(db),
          appDataDirectoryProvider.overrideWithValue(dir),
          sourceResolverProvider.overrideWithValue(
            localMusicFiles(db).resolver,
          ),
          playbackEngineFactoryProvider.overrideWithValue(
            (_) => ScriptedMusicEngine(),
          ),
        ],
        child: MediahroApp(router: buildRouter(initialLocation: '/music')),
      ),
    );
    await settle(tester);
    await tester.tap(find.byTooltip('More actions for Before'));
    await settle(tester);
    await tester.tap(find.text('Edit tags'));
    await settle(tester);
    // Tags are read in an isolate.
    for (
      var i = 0;
      i < 50 && find.text('Reading tags…').evaluate().isNotEmpty;
      i++
    ) {
      await settle(tester);
    }
    expect(find.widgetWithText(TextField, 'Before'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextField, 'Before'), 'After');
    await tester.tap(find.text('Save'));
    for (
      var i = 0;
      i < 50 && find.text('Saved tags of 1 song').evaluate().isEmpty;
      i++
    ) {
      await settle(tester);
    }
    expect(find.text('Saved tags of 1 song'), findsOneWidget);
    final t = await tester.runAsync(
      () => TagReader.readFile('${dir.path}/one.flac'),
    );
    expect(t!.title, 'After');
    expect(t.artist, 'Amy');
    expect(find.text('After'), findsWidgets);
    await finish(tester);
  });
}
