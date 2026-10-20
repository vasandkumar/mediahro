import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediahro/app/l10n/gen/app_localizations.dart';
import 'package:mediahro/core/db/library_database.dart';
import 'package:mediahro/core/net/persistent_network_policy.dart';
import 'package:mediahro/core/providers.dart';
import 'package:mediahro/features/library/folder_browser_screen.dart';
import 'package:mediahro/features/library/playlists_screen.dart';
import 'package:mediahro/features/sources/backup_screen.dart';
import 'package:mediahro/platform/platform_facades.dart';
import 'package:mediahro_ffi/mediahro_ffi.dart';

import '../core/files/storage_fakes.dart';

void main() {
  late LibraryDatabase db;
  late PersistentNetworkPolicy policy;
  late Directory dir;
  late FakeSafStorage storage;

  setUp(() async {
    db = LibraryDatabase.memory();
    policy = await PersistentNetworkPolicy.load(db);
    dir = Directory.systemTemp.createTempSync('mediahro_ui_storage');
    storage = FakeSafStorage(dir, FakeFdIo());
  });
  tearDown(() async {
    await policy.dispose();
    await db.close();
    dir.deleteSync(recursive: true);
  });

  Future<void> pump(WidgetTester tester, Widget child) async {
    tester.view.physicalSize = const Size(900, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          libraryDatabaseProvider.overrideWithValue(db),
          networkPolicyProvider.overrideWithValue(policy),
          storageProvider.overrideWithValue(storage),
          fdIoProvider.overrideWithValue(storage.io),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: child,
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('CORE-014 the backup is saved through the system save dialog', (
    tester,
  ) async {
    await pump(tester, const BackupScreen());
    await tester.enterText(
      find.widgetWithText(TextField, 'Passphrase'),
      'correct horse',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Repeat passphrase'),
      'correct horse',
    );
    await tester.runAsync(() async {
      await tester.tap(find.text('Back up'));
      for (var i = 0; i < 100 && storage.saved.isEmpty; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
    });
    await tester.pumpAndSettle();
    final (name, mime, bytes) = storage.saved.single;
    expect(name, endsWith('.mhrobackup'));
    expect(mime, 'application/octet-stream');
    expect(utf8.decode(bytes.take(7).toList()), 'MHROBK1');
    expect(find.text('Backup saved as $name.'), findsOneWidget);
  });

  testWidgets('LIB-007 a playlist exports as M3U8 through the save dialog', (
    tester,
  ) async {
    final id = await db
        .into(db.playlists)
        .insert(
          PlaylistsCompanion.insert(
            name: 'Road trip',
            createdAt: DateTime.utc(2026),
            updatedAt: DateTime.utc(2026),
          ),
        );
    final row = await (db.select(
      db.playlists,
    )..where((p) => p.id.equals(id))).getSingle();
    await pump(tester, PlaylistScreen(playlist: row));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Export playlist'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Export as M3U8'));
    await tester.pumpAndSettle();
    final (name, mime, bytes) = storage.saved.single;
    expect(name, 'Road trip.m3u8');
    expect(mime, 'application/vnd.apple.mpegurl');
    expect(utf8.decode(bytes), startsWith('#EXTM3U'));
    expect(find.text('Saved Road trip.m3u8.'), findsOneWidget);
  });

  testWidgets(
    'LIB-007 a picked playlist file is imported (content URI read by fd)',
    (tester) async {
      final doc = await storage.createDocument(FakeSafStorage.tree, 'Mix.m3u');
      File('${dir.path}/Mix.m3u').writeAsStringSync(
        '#EXTM3U\n#EXTINF:-1,Radio\nhttps://example.org/live\n',
      );
      storage.nextPick = [PickedFile(uri: doc, name: 'Mix.m3u')];
      await pump(tester, const PlaylistsScreen());
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await tester.tap(find.byTooltip('Import playlist'));
        for (
          var i = 0;
          i < 50 && (await db.select(db.playlists).get()).isEmpty;
          i++
        ) {
          await Future<void>.delayed(const Duration(milliseconds: 50));
        }
      });
      await tester.pumpAndSettle();
      expect((await db.select(db.playlists).get()).single.name, 'Mix');
    },
  );

  testWidgets('FILE-002 selected files are shared and opened in another app', (
    tester,
  ) async {
    final media = Directory('${dir.path}/media')..createSync();
    File('${media.path}/a.mkv').writeAsBytesSync([1]);
    await tester.runAsync(() async {
      await pump(
        tester,
        FolderBrowserScreen(
          fileSystem: const LocalFileSystem(),
          root: media.uri,
          title: 'Disk',
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pumpAndSettle();
    await tester.longPress(find.text('a.mkv'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Share'));
    await tester.pumpAndSettle();
    expect(storage.shared.single.single.pathSegments.last, 'a.mkv');
    await tester.tap(find.byTooltip('Open in another app'));
    await tester.pumpAndSettle();
    expect(storage.opened.single.pathSegments.last, 'a.mkv');
  });
}
