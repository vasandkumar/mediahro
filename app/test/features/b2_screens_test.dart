import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:mediahro/app/l10n/gen/app_localizations.dart';
import 'package:mediahro/core/db/library_database.dart';
import 'package:mediahro/core/net/persistent_network_policy.dart';
import 'package:mediahro/core/providers.dart';
import 'package:mediahro/core/sources/source_access.dart';
import 'package:mediahro/core/sources/url_open.dart';
import 'package:mediahro/features/library/folder_browser_screen.dart';
import 'package:mediahro/features/library/library_hub_screen.dart';
import 'package:mediahro/features/library/search_screen.dart';
import 'package:mediahro/features/sources/add_share_screen.dart';
import 'package:mediahro/features/sources/open_url_dialog.dart';
import 'package:mediahro/features/sources/sources_screen.dart';
import 'package:mediahro_ffi/mediahro_ffi.dart';

import '../core/seed.dart';

Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  required LibraryDatabase db,
  required PersistentNetworkPolicy policy,
  List<Override> overrides = const [],
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        libraryDatabaseProvider.overrideWithValue(db),
        networkPolicyProvider.overrideWithValue(policy),
        ...overrides,
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

const _fp =
    'AB:CD:EF:01:23:45:67:89:AB:CD:EF:01:23:45:67:89:AB:CD:EF:01:23:45:67:89:AB:CD:EF:01:23:45:67:89';

/// A WebDAV server with a self-signed certificate: listing works only once
/// the source carries the pinned fingerprint.
final class _SelfSignedFs implements VirtualFileSystem {
  _SelfSignedFs(this.spec);

  final SourceSpec spec;

  @override
  Set<String> get schemes => const {'davs'};

  @override
  Set<VirtualFsCapability> get capabilities => const {};

  @override
  Stream<VirtualEntry> list(Uri directory) => spec.options['certSha256'] == _fp
      ? Stream.value(
          VirtualEntry(
            uri: directory.resolve('a.mkv'),
            name: 'a.mkv',
            isDirectory: false,
          ),
        )
      : Stream.error(
          VirtualFileException(
            VirtualFileError.untrustedCertificate,
            directory,
            _fp,
          ),
        );

  @override
  Future<VirtualFile> open(Uri uri) => throw UnimplementedError();

  @override
  Future<VirtualEntry> stat(Uri uri) => throw UnimplementedError();
}

void main() {
  late LibraryDatabase db;
  late PersistentNetworkPolicy policy;

  setUp(() async {
    db = LibraryDatabase.memory();
    policy = await PersistentNetworkPolicy.load(db);
  });
  tearDown(() async {
    await policy.dispose();
    await db.close();
  });

  testWidgets(
    'LIB-002 empty Sources screen offers the three add actions (docs/06 §9)',
    (tester) async {
      await _pump(
        tester,
        const SourcesScreen(),
        db: db,
        policy: policy,
        overrides: [addServerActionProvider.overrideWithValue((_) {})],
      );
      await tester.pumpAndSettle();
      expect(find.text('Add a folder'), findsOneWidget);
      expect(find.text('Add a network share'), findsOneWidget);
      expect(find.text('Add a server'), findsOneWidget);
      await tester.tap(find.text('Add source'));
      await tester.pumpAndSettle();
      // Flutter tests run as Android: device media (MediaStore) is offered.
      expect(find.text('Device media'), findsOneWidget);
      final sheet = find.descendant(
        of: find.byType(BottomSheet),
        matching: find.byType(Scrollable),
      );
      await tester.scrollUntilVisible(
        find.text('Media server on this network'),
        100,
        scrollable: sheet,
      );
      expect(find.text('Media server on this network'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Open URL'),
        100,
        scrollable: find.descendant(
          of: find.byType(BottomSheet),
          matching: find.byType(Scrollable),
        ),
      );
      expect(find.text('Open URL'), findsWidgets);
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    },
  );

  testWidgets(
    'NET-003/NET-004 a self-signed server is used only after the user accepts its fingerprint',
    (tester) async {
      final specs = <SourceSpec>[];
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await _pump(
        tester,
        const AddShareScreen(),
        db: db,
        policy: policy,
        overrides: [
          shareDiscoveryProvider.overrideWithValue(Stream<Never>.empty),
          sourceResolverProvider.overrideWithValue(
            DefaultSourceResolver(
              builders: {
                SourceKind.webdav: (s) {
                  specs.add(s);
                  return _SelfSignedFs(s);
                },
              },
            ),
          ),
        ],
      );
      await tester.tap(find.byType(DropdownButtonFormField<SourceKind>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('WebDAV').last);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Server'),
        'nas.local',
      );
      await tester.tap(find.text('Test connection'));
      await tester.pumpAndSettle();
      expect(find.text('Trust this server?'), findsOneWidget);
      expect(find.textContaining(_fp), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(
        find.text(
          "This server's certificate is not trusted. Check it before connecting.",
        ),
        findsOneWidget,
      );
      expect(specs.every((s) => !s.options.containsKey('certSha256')), isTrue);

      await tester.tap(find.text('Test connection'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Trust'));
      await tester.pumpAndSettle();
      expect(find.text('Connected. 1 item at the top level.'), findsOneWidget);
      expect(specs.last.options['certSha256'], _fp);
    },
  );

  testWidgets('LIB-001 a source shows its item count', (tester) async {
    final seed = Seed(db);
    final sid = await seed.source(name: 'Films');
    await seed.item('a.mkv', sourceId: sid);
    await seed.item('b.mkv', sourceId: sid);
    await _pump(tester, const SourcesScreen(), db: db, policy: policy);
    await tester.pumpAndSettle();
    expect(find.text('Films'), findsOneWidget);
    expect(find.textContaining('2 items'), findsOneWidget);
  });

  testWidgets(
    'LIB-005 search screen finds items as the user types and filters by kind',
    (tester) async {
      final seed = Seed(db);
      await seed.item('a.mkv', title: 'Blade Runner');
      await seed.item('b.flac', title: 'Blade Song', kind: ItemKind.audio);
      await _pump(tester, const SearchScreen(), db: db, policy: policy);
      await tester.enterText(find.byType(TextField), 'blade');
      await tester.pumpAndSettle();
      expect(find.text('Blade Runner'), findsOneWidget);
      expect(find.text('Blade Song'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilterChip, 'Music'));
      await tester.pumpAndSettle();
      expect(find.text('Blade Runner'), findsNothing);
      expect(find.text('Blade Song'), findsOneWidget);
    },
  );

  testWidgets(
    'CORE-005 open URL validates, remembers and hands the URL to the player',
    (tester) async {
      OpenableUrl? opened;
      await _pump(
        tester,
        Builder(
          builder: (c) => TextButton(
            onPressed: () => showOpenUrlDialog(c),
            child: const Text('go'),
          ),
        ),
        db: db,
        policy: policy,
        overrides: [
          openUrlActionProvider.overrideWithValue((_, u) => opened = u),
        ],
      );
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextField).first,
        'file:///etc/passwd',
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(
        find.text('This kind of address is not supported.'),
        findsOneWidget,
      );
      await tester.enterText(
        find.byType(TextField).first,
        'example.org/live.m3u8',
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(opened?.uri.toString(), 'https://example.org/live.m3u8');
      expect(
        (await db.select(db.urlHistory).get()).single.url,
        'https://example.org/live.m3u8',
      );
    },
  );

  testWidgets('FILE-001/FILE-002 browser lists, creates folders and sorts', (
    tester,
  ) async {
    final dir = Directory.systemTemp.createTempSync('mediahro_browser');
    addTearDown(() => dir.deleteSync(recursive: true));
    File('${dir.path}/b.mkv').writeAsBytesSync([1, 2]);
    File('${dir.path}/a.mkv').writeAsBytesSync([1]);
    Directory('${dir.path}/Sub').createSync();
    await tester.runAsync(() async {
      await _pump(
        tester,
        FolderBrowserScreen(
          fileSystem: const LocalFileSystem(),
          root: dir.uri,
          title: 'Disk',
        ),
        db: db,
        policy: policy,
      );
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pumpAndSettle();
    final names = tester
        .widgetList<ListTile>(find.byType(ListTile))
        .map((t) => (t.title! as Text).data)
        .toList();
    expect(names, ['Sub', 'a.mkv', 'b.mkv']);
    await tester.tap(find.byTooltip('New folder'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Made');
    final made = Directory('${dir.path}/Made');
    await tester.runAsync(() async {
      await tester.tap(find.text('OK'));
      // Bounded wait: the mkdir runs on the file system's worker.
      for (var i = 0; i < 100 && !made.existsSync(); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
    });
    await tester.pumpAndSettle();
    expect(made.existsSync(), isTrue);
  });

  testWidgets('LIB-007/LIB-014/LIB-015 library hub opens its tools', (
    tester,
  ) async {
    await _pump(tester, const LibraryHubScreen(), db: db, policy: policy);
    for (final t in [
      'Playlists',
      'Queues',
      'Collections',
      'Duplicates',
      'Statistics',
      'Parental controls',
    ]) {
      expect(find.text(t), findsOneWidget);
    }
    await tester.tap(find.text('Statistics'));
    await tester.pumpAndSettle();
    expect(find.text('Plays'), findsOneWidget);
  });
}
