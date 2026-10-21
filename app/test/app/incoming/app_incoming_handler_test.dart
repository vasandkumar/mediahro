import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mediahro/app/incoming/app_incoming_handler.dart';
import 'package:mediahro/app/incoming/incoming_seams.dart';
import 'package:mediahro/app/l10n/gen/app_localizations.dart';
import 'package:mediahro/core/db/library_database.dart';
import 'package:mediahro/core/net/persistent_network_policy.dart';
import 'package:mediahro/core/providers.dart';
import 'package:mediahro/features/photos/viewer/external_image_viewer.dart';
import 'package:mediahro/features/settings/core_settings.dart';
import 'package:mediahro/features/settings/settings_providers.dart';
import 'package:mediahro/features/video/player/play_request.dart';
import 'package:mediahro/platform/platform_facades.dart';
import 'package:mediahro_engine/mediahro_engine.dart';

import '../../core/seed.dart';
import '../../helpers.dart';

/// A storage facade that knows documents by URI; everything else is unused.
final class _Storage implements StorageFacade {
  final documents = <String, DocumentEntry>{};
  final failing = <String>{};
  List<FolderGrant> held = const [];

  @override
  Future<DocumentEntry> statDocument(Uri uri) async {
    if (failing.contains(uri.toString())) throw StateError('gone');
    return documents[uri.toString()] ??
        DocumentEntry(uri: uri, name: 'unknown', isDirectory: false);
  }

  @override
  Future<List<FolderGrant>> grants() async => held;

  @override
  Future<int> openDocumentFd(
    Uri uri, {
    DocumentMode mode = DocumentMode.read,
  }) async => 7;

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

void main() {
  late _Storage storage;
  late ProviderContainer container;
  late GoRouter router;
  late LibraryDatabase db;
  late PersistentNetworkPolicy policy;
  late AppIncomingHandler handler;
  final plays = <PlayRequest>[];
  final viewed = <ExternalImageArgs>[];

  Future<void> pumpApp(
    WidgetTester tester, {
    List<Override> overrides = const [],
  }) async {
    plays.clear();
    viewed.clear();
    storage = _Storage();
    final store = await tester.runAsync(memoryStore);
    db = LibraryDatabase.memory();
    policy = (await tester.runAsync(() => PersistentNetworkPolicy.load(db)))!;
    container = ProviderContainer(
      overrides: [
        storageProvider.overrideWithValue(storage),
        libraryDatabaseProvider.overrideWithValue(db),
        networkPolicyProvider.overrideWithValue(policy),
        settingsStoreProvider.overrideWithValue(store!),
        ...overrides,
      ],
    );
    addTearDown(() async {
      container.dispose();
      await tester.runAsync(db.close);
    });
    Widget page(String name) => Scaffold(body: Text(name));
    router = GoRouter(
      initialLocation: '/video',
      routes: [
        for (final p in ['video', 'music', 'photos', 'search', 'vault'])
          GoRoute(path: '/$p', builder: (_, _) => page(p)),
        GoRoute(
          path: ExternalImageRoutes.view,
          builder: (_, state) {
            viewed.add(state.extra! as ExternalImageArgs);
            return page('view-external');
          },
        ),
        GoRoute(
          path: '/play',
          builder: (_, state) {
            plays.add(state.extra! as PlayRequest);
            return page('play');
          },
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(
          routerConfig: router,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
        ),
      ),
    );
    await tester.pumpAndSettle();
    handler = AppIncomingHandler(container, router);
  }

  String where() => router.routeInformationProvider.value.uri.toString();

  Future<void> open(WidgetTester tester, List<String> uris) async {
    await tester.runAsync(
      () => handler.openUris([for (final u in uris) Uri.parse(u)]),
    );
    await tester.pumpAndSettle();
  }

  void doc(String uri, String name, [String? mime]) {
    storage.documents[uri] = DocumentEntry(
      uri: Uri.parse(uri),
      name: name,
      isDirectory: false,
      mimeType: mime,
    );
  }

  testWidgets('CORE-003 a video from Open with plays at once', (tester) async {
    await pumpApp(tester);
    doc('content://media/1', 'Holiday.mkv', 'video/x-matroska');

    await open(tester, ['content://media/1']);

    expect(find.text('play'), findsOneWidget);
    expect(plays.single.title, 'Holiday.mkv');
    expect(plays.single.memoryKey, 'content://media/1');
    expect(plays.single.next, isEmpty);
    // It reads through a detached descriptor, as the open dialog does.
    final source = await plays.single.resolve!() as UriSource;
    expect(source.uri.toString(), 'fdclose://7');
  });

  testWidgets(
    'CORE-003 audio plays too, found by its mime type when its name has no extension',
    (tester) async {
      await pumpApp(tester);
      doc('content://media/2', 'Voice note', 'audio/mp4');

      await open(tester, ['content://media/2']);

      expect(find.text('play'), findsOneWidget);
      expect(plays.single.title, 'Voice note');
    },
  );

  testWidgets('SYS-004 several shared files play in order', (tester) async {
    await pumpApp(tester);
    doc('content://media/1', 'a.mp4');
    doc('content://media/2', 'b.mp4');
    doc('content://media/3', 'c.mp3');

    await open(tester, [
      'content://media/1',
      'content://media/2',
      'content://media/3',
    ]);

    expect(plays.single.title, 'a.mp4');
    expect([for (final n in plays.single.next) n.title], ['b.mp4', 'c.mp3']);
  });

  testWidgets('SYS-004 a shared link plays as a user-opened stream', (
    tester,
  ) async {
    await pumpApp(tester);
    expect(policy.isUserConfiguredHost('stream.example.com'), isFalse);

    await open(tester, ['https://stream.example.com/live/index.m3u8']);

    expect(find.text('play'), findsOneWidget);
    expect(plays.single.source, isA<UriSource>());
    expect(
      (plays.single.source! as UriSource).uri.toString(),
      'https://stream.example.com/live/index.m3u8',
    );
    expect(policy.isUserConfiguredHost('stream.example.com'), isTrue);
    final history = await tester.runAsync(
      container.read(urlHistoryProvider).recent,
    );
    expect(history, hasLength(1));
  });

  testWidgets('CORE-003 refused schemes open nothing and say so', (
    tester,
  ) async {
    await pumpApp(tester);
    for (final u in [
      'smb://server/share/a.mkv',
      'javascript:alert(1)',
      'file:///data/data/com.mediahro.app/files/x.mp4',
      'content://com.mediahro.app.files/vault/x.mp4',
    ]) {
      await open(tester, [u]);
      expect(where(), '/video', reason: u);
      expect(
        find.text("Couldn't open this link or file. Choose another."),
        findsOneWidget,
        reason: u,
      );
      expect(plays, isEmpty, reason: u);
      ScaffoldMessenger.of(tester.element(find.byType(Scaffold).first))
          .clearSnackBars();
      await tester.pumpAndSettle();
    }
    expect(policy.isUserConfiguredHost('server'), isFalse);
  });

  testWidgets(
    'CORE-003 a file inside a held folder is read; one outside is not',
    (tester) async {
      await pumpApp(tester);
      storage.held = [
        FolderGrant(
          id: 'g',
          uri: Uri.parse('file:///storage/movies'),
          displayName: 'Movies',
        ),
      ];

      await open(tester, ['file:///storage/other/a.mkv']);
      expect(where(), '/video');
      expect(find.text('play'), findsNothing);

      await open(tester, ['file:///storage/movies/a.mkv']);
      expect(find.text('play'), findsOneWidget);
      expect(plays.single.title, 'a.mkv');
    },
  );

  testWidgets('CORE-003 a picture opens in the external viewer', (
    tester,
  ) async {
    await pumpApp(tester);
    doc('content://media/9', 'IMG_1.jpg', 'image/jpeg');

    await open(tester, ['content://media/9']);

    expect(find.text('view-external'), findsOneWidget);
    expect(find.text('play'), findsNothing);
    final args = viewed.single;
    expect(args.images.single.uri.toString(), 'content://media/9');
    expect(args.images.single.name, 'IMG_1.jpg');
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('SYS-004 several shared pictures open as one swipeable set', (
    tester,
  ) async {
    await pumpApp(tester);
    doc('content://media/1', 'a.jpg');
    doc('content://media/2', 'b.png');
    doc('content://media/3', 'c.heic');

    await open(tester, [
      'content://media/1',
      'content://media/2',
      'content://media/3',
    ]);

    expect(
      [for (final i in viewed.single.images) i.name],
      ['a.jpg', 'b.png', 'c.heic'],
    );
    expect(viewed.single.index, 0);
  });

  testWidgets('SYS-004 a mix opens what the first item is', (tester) async {
    await pumpApp(tester);
    doc('content://media/1', 'a.jpg');
    doc('content://media/2', 'b.mp4');

    await open(tester, ['content://media/1', 'content://media/2']);
    expect(find.text('view-external'), findsOneWidget);
    expect(plays, isEmpty);

    router.go('/video');
    await tester.pumpAndSettle();
    await open(tester, ['content://media/2', 'content://media/1']);
    expect(plays.single.title, 'b.mp4');
  });

  testWidgets('CORE-003 audio goes to Music when Music offers to play it', (
    tester,
  ) async {
    final offered = <Uri>[];
    await pumpApp(
      tester,
      overrides: [
        playExternalAudioProvider.overrideWithValue((uri) async {
          offered.add(uri);
          return true;
        }),
      ],
    );
    doc('content://media/2', 'song.flac', 'audio/flac');

    await open(tester, ['content://media/2']);

    expect(offered.single.toString(), 'content://media/2');
    expect(plays, isEmpty);
    expect(find.text('play'), findsNothing);
  });

  testWidgets('CORE-003 audio Music declines plays in the player', (
    tester,
  ) async {
    await pumpApp(
      tester,
      overrides: [
        playExternalAudioProvider.overrideWithValue((_) async => false),
      ],
    );
    doc('content://media/2', 'song.flac', 'audio/flac');

    await open(tester, ['content://media/2']);

    expect(plays.single.title, 'song.flac');
  });

  testWidgets('SYS-003 a playlist by name goes to Music, which starts it', (
    tester,
  ) async {
    final asked = <String>[];
    await pumpApp(
      tester,
      overrides: [
        playPlaylistByNameProvider.overrideWithValue((name) async {
          asked.add(name);
          return true;
        }),
      ],
    );

    handler.runIntent(
      const AppIntent(AppIntentKind.playPlaylist, argument: ' Road trip '),
    );
    await tester.pumpAndSettle();

    expect(asked, ['Road trip']);
    expect(where(), '/music');
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('SYS-003 without Music support a playlist says not yet', (
    tester,
  ) async {
    await pumpApp(tester);

    handler.runIntent(
      const AppIntent(AppIntentKind.playPlaylist, argument: 'Road trip'),
    );
    await tester.pumpAndSettle();

    expect(where(), '/music');
    expect(find.textContaining("isn't available yet"), findsOneWidget);
  });

  testWidgets('SYS-003 a playlist that names the vault is never looked up', (
    tester,
  ) async {
    final asked = <String>[];
    await pumpApp(
      tester,
      overrides: [
        playPlaylistByNameProvider.overrideWithValue((name) async {
          asked.add(name);
          return true;
        }),
      ],
    );

    handler.runIntent(
      const AppIntent(AppIntentKind.playPlaylist, argument: 'Vault mix'),
    );
    await tester.pumpAndSettle();

    expect(asked, isEmpty);
    expect(where(), '/music');
  });

  testWidgets(
    'CORE-003 a kind of file with no way to open it is named as such',
    (tester) async {
      await pumpApp(tester);
      doc('content://media/10', 'notes.pdf', 'application/pdf');

      await open(tester, ['content://media/10']);

      expect(where(), '/video');
      expect(find.text('play'), findsNothing);
      expect(
        find.text("Couldn't open this kind of file. Choose another."),
        findsOneWidget,
      );
    },
  );

  testWidgets('CORE-003 a file that cannot be read says so', (tester) async {
    await pumpApp(tester);
    storage.failing.add('content://media/11');

    await open(tester, ['content://media/11']);

    expect(where(), '/video');
    expect(find.text('play'), findsNothing);
    expect(find.textContaining('It may be corrupt'), findsOneWidget);
  });

  testWidgets('CORE-003 one bad item does not stop the good ones', (
    tester,
  ) async {
    await pumpApp(tester);
    doc('content://media/1', 'a.mp4');

    await open(tester, ['smb://server/x.mp4', 'content://media/1']);

    expect(find.text('play'), findsOneWidget);
    expect(plays.single.title, 'a.mp4');
    expect(
      find.text("Couldn't open this link or file. Choose another."),
      findsOneWidget,
    );
  });

  testWidgets('SYS-003 open mode goes to the mode, search to the query', (
    tester,
  ) async {
    await pumpApp(tester);

    handler.runIntent(
      const AppIntent(AppIntentKind.openMode, argument: 'music'),
    );
    await tester.pumpAndSettle();
    expect(where(), '/music');

    handler.runIntent(const AppIntent(AppIntentKind.search, argument: 'cats'));
    await tester.pumpAndSettle();
    expect(where(), '/search?q=cats');
  });

  testWidgets(
    'SYS-003 an intent for the vault goes to Photos, never into the vault',
    (tester) async {
      await pumpApp(tester);

      for (final arg in ['vault', 'hidden albums', 'private mode']) {
        handler.runIntent(AppIntent(AppIntentKind.openMode, argument: arg));
        await tester.pumpAndSettle();
        expect(where(), '/photos', reason: arg);
        router.go('/video');
        await tester.pumpAndSettle();
      }
      handler.runIntent(
        const AppIntent(AppIntentKind.playPlaylist, argument: 'vault'),
      );
      await tester.pumpAndSettle();
      expect(where(), '/music');
      expect(find.text('vault'), findsNothing);
    },
  );

  testWidgets('SYS-003 resume plays the video played last', (tester) async {
    await pumpApp(tester);
    await tester.runAsync(() async {
      final seed = Seed(db);
      await seed.item('old.mkv', lastPlayedAt: DateTime.utc(2026));
      await seed.item('last.mkv', lastPlayedAt: DateTime.utc(2026, 2));
    });

    handler.runIntent(const AppIntent(AppIntentKind.resumeLast));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 300)),
    );
    await tester.pumpAndSettle();

    expect(find.text('play'), findsOneWidget);
    expect(plays.single.title, 'last');
    expect(plays.single.memoryKey, startsWith('item:'));
  });

  testWidgets('SYS-003 resume with nothing played returns to the last mode', (
    tester,
  ) async {
    await pumpApp(tester);
    container.read(settingsStoreProvider).set(CoreSettings.lastMode, 'photos');

    handler.runIntent(const AppIntent(AppIntentKind.resumeLast));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 300)),
    );
    await tester.pumpAndSettle();

    expect(where(), '/photos');
  });

  testWidgets('SYS-003 an unknown intent argument changes nothing', (
    tester,
  ) async {
    await pumpApp(tester);

    handler.runIntent(
      const AppIntent(AppIntentKind.openMode, argument: '/play'),
    );
    await tester.pumpAndSettle();

    expect(where(), '/video');
    expect(find.text('play'), findsNothing);
  });
}
