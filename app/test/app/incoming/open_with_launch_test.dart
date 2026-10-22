import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mediahro/app/app.dart';
import 'package:mediahro/app/incoming/app_incoming_handler.dart';
import 'package:mediahro/app/incoming/incoming_router.dart';
import 'package:mediahro/app/router.dart';
import 'package:mediahro/core/db/library_database.dart';
import 'package:mediahro/core/net/persistent_network_policy.dart';
import 'package:mediahro/core/providers.dart';
import 'package:mediahro/features/settings/settings_providers.dart';
import 'package:mediahro/features/video/player/play_request.dart';
import 'package:mediahro/features/video/video_open.dart';
import 'package:mediahro/platform/platform_facades.dart';

import '../../helpers.dart';

/// The facade the OS delivers through: a broadcast stream like the Pigeon
/// event channel, which drops what nobody listens to yet.
final class _System implements SystemIntegrationFacade {
  final controller = StreamController<List<Uri>>.broadcast();

  @override
  Stream<List<Uri>> get openRequests => controller.stream;

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

final class _Intents implements IntentsFacade {
  @override
  Stream<AppIntent> get incoming => const Stream.empty();

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

/// A storage facade where a MediaStore-style URI answers like the platform
/// module does after the batch 6 fix, and a denied one throws.
final class _Storage implements StorageFacade {
  final denied = <String>{};

  @override
  Future<DocumentEntry> statDocument(Uri uri) async {
    if (denied.contains(uri.toString())) throw StateError('permissionDenied');
    return DocumentEntry(
      uri: uri,
      name: 'clip.mp4',
      isDirectory: false,
      mimeType: 'video/mp4',
    );
  }

  @override
  Future<List<FolderGrant>> grants() async => const [];

  @override
  Future<int> openDocumentFd(
    Uri uri, {
    DocumentMode mode = DocumentMode.read,
  }) async => 9;

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

/// CORE-003 as the batch 6 device checks launched it: through the real app
/// (shell, router, `startIncoming`), with the OS handing the URI over before
/// the first frame (cold start) or after it (warm), instead of calling the
/// handler directly.
void main() {
  late _System system;
  late _Storage storage;
  late ProviderContainer container;
  final plays = <PlayRequest>[];

  Future<void> launch(
    WidgetTester tester, {
    void Function()? beforeFrame,
  }) async {
    plays.clear();
    system = _System();
    storage = _Storage();
    final store = await tester.runAsync(memoryStore);
    final db = LibraryDatabase.memory();
    final policy = (await tester.runAsync(
      () => PersistentNetworkPolicy.load(db),
    ))!;
    container = ProviderContainer(
      overrides: [
        storageProvider.overrideWithValue(storage),
        libraryDatabaseProvider.overrideWithValue(db),
        networkPolicyProvider.overrideWithValue(policy),
        settingsStoreProvider.overrideWithValue(store!),
        systemIntegrationProvider.overrideWithValue(system),
        intentsProvider.overrideWithValue(_Intents()),
        appRoutesProvider.overrideWithValue([
          GoRoute(
            path: VideoRoutes.play,
            builder: (_, state) {
              plays.add(state.extra! as PlayRequest);
              return const Scaffold(body: Text('player'));
            },
          ),
        ]),
      ],
    );
    final incoming = startIncoming(
      container,
      handlerFor: AppIncomingHandler.new,
    );
    addTearDown(() async {
      await incoming.dispose();
      await system.controller.close();
      container.dispose();
      await tester.runAsync(db.close);
    });
    // The Activity hands the intent over as soon as Dart listens, which is
    // before any widget exists.
    beforeFrame?.call();
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MediahroApp(),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> deliver(WidgetTester tester, String uri) async {
    system.controller.add([Uri.parse(uri)]);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pumpAndSettle();
  }

  const notOpened = "Couldn't open this link or file. Choose another.";
  const failed =
      "Couldn't open this file. It may be corrupt or on a disconnected drive.";

  testWidgets('CORE-003 a video handed over at cold start opens the player', (
    tester,
  ) async {
    await launch(
      tester,
      beforeFrame: () => system.controller.add([
        Uri.parse('content://media/external/video/media/150'),
      ]),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pumpAndSettle();

    expect(find.text('player'), findsOneWidget);
    expect(plays.single.title, 'clip.mp4');
    expect(plays.single.memoryKey, 'content://media/external/video/media/150');
  });

  testWidgets(
    'CORE-003 a video handed over while the app runs opens the player',
    (tester) async {
      await launch(tester);

      await deliver(tester, 'content://media/external/video/media/150');

      expect(find.text('player'), findsOneWidget);
    },
  );

  testWidgets('CORE-003 a file the app may not read says so, cold or warm', (
    tester,
  ) async {
    await launch(tester);
    storage.denied.add('content://media/external/video/media/151');

    await deliver(tester, 'content://media/external/video/media/151');

    expect(find.text(failed), findsOneWidget);
    expect(find.text('player'), findsNothing);
  });

  testWidgets('CORE-003 refused schemes show the refusal, cold and warm', (
    tester,
  ) async {
    await launch(
      tester,
      beforeFrame: () => system.controller.add([Uri.parse('ftp://host/a.mkv')]),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pumpAndSettle();
    expect(find.text(notOpened), findsOneWidget, reason: 'cold');

    ScaffoldMessenger.of(tester.element(find.byType(Scaffold).first))
        .clearSnackBars();
    await tester.pumpAndSettle();

    await deliver(tester, 'javascript:alert(1)');
    expect(find.text(notOpened), findsOneWidget, reason: 'warm');
    expect(find.text('player'), findsNothing);
  });
}
