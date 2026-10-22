import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart' show Scaffold, ScaffoldMessenger;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mediahro/app/app.dart';
import 'package:mediahro/app/incoming/incoming_router.dart'
    show appRouterProvider;
import 'package:mediahro/features/video/player/play_request.dart';
import 'package:mediahro/features/video/subtitles/sidecar_loader.dart';
import 'package:mediahro/features/video/subtitles/subtitle_sources.dart';
import 'package:mediahro/features/video/video_open.dart';
import 'package:mediahro/features/video/video_settings.dart';
import 'package:mediahro/platform/platform_facades.dart';
import 'package:mediahro_engine/mediahro_engine.dart';
import 'package:mediahro_ffi/mediahro_ffi.dart';

import '../../../integration_test/support/c1_player.dart';

/// A storage facade that only knows folder grants.
final class _Storage implements StorageFacade {
  int picks = 0;
  FolderGrant? answer;

  @override
  Future<List<FolderGrant>> grants() async => const [];

  @override
  Future<FolderGrant?> pickFolder() async {
    picks++;
    return answer;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

/// SUB-012 (owner decision, Android 11+): the MediaStore shows no `.srt`, so
/// for a device-media video with no subtitle found, the app offers once to
/// allow access to the folder, and looks again after it. It never asks for
/// all-files access.
void main() {
  late Directory cache;
  late _Storage storage;
  var scans = 0;

  setUp(() {
    cache = Directory.systemTemp.createTempSync('sub_access');
    storage = _Storage();
    scans = 0;
  });
  tearDown(() => cache.deleteSync(recursive: true));

  PlayRequest film(String name) => PlayRequest(
    source: UriSource(Uri.parse('file:///v/$name.mkv')),
    title: name,
    memoryKey: name,
    locate: () async => Uri.parse('mediastore:///Movies/$name.mkv'),
  );

  GoRouter routerOf(WidgetTester tester) =>
      ProviderScope.containerOf(tester.element(find.byType(MediahroApp)))
          .read(appRouterProvider)!;

  Future<void> openFilm(WidgetTester tester, String name) async {
    unawaited(routerOf(tester).push(VideoRoutes.play, extra: film(name)));
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  final prompt = find.textContaining('Allow access to its folder');

  List<dynamic> overrides() => [
    storageProvider.overrideWithValue(storage),
    sidecarLoaderProvider.overrideWithValue(
      SidecarLoader(
        fileSystemFor: (uri) {
          scans++;
          throw VirtualFileException(VirtualFileError.notFound, uri);
        },
        cacheDir: cache,
      ),
    ),
  ];

  playerTest(
    'SUB-012 a device video with no subtitle offers folder access once',
    (tester) async {
      final (_, store) = await pumpPlayer(
        tester,
        overrides: [...overrides().cast()],
      );
      routerOf(tester).pop();
      await tester.pumpAndSettle();

      await openFilm(tester, 'Film');

      expect(prompt, findsOneWidget);
      expect(store.get(VideoSettings.subtitleAccessAsked), isTrue);
      expect(storage.picks, 0, reason: 'nothing is asked before the tap');

      // A second video does not ask again.
      routerOf(tester).pop();
      await tester.pumpAndSettle();
      ScaffoldMessenger.of(tester.element(find.byType(Scaffold).first))
          .clearSnackBars();
      await tester.pumpAndSettle();
      await openFilm(tester, 'Other');
      expect(prompt, findsNothing);
    },
  );

  playerTest('SUB-012 allowing opens the folder picker and looks again', (
    tester,
  ) async {
    storage.answer = FolderGrant(
      id: 'g1',
      uri: Uri.parse('content://x.documents/tree/primary%3AMovies'),
      displayName: 'Movies',
    );
    await pumpPlayer(tester, overrides: [...overrides().cast()]);
    routerOf(tester).pop();
    await tester.pumpAndSettle();
    await openFilm(tester, 'Film');
    final before = scans;

    await tester.tap(find.text('Allow'));
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(storage.picks, 1);
    expect(scans, greaterThan(before), reason: 'the folder is searched again');
  });

  playerTest('SUB-012 a video that is not device media is never asked about', (
    tester,
  ) async {
    await pumpPlayer(tester, overrides: [...overrides().cast()]);
    routerOf(tester).pop();
    await tester.pumpAndSettle();
    unawaited(
      routerOf(tester).push(
        VideoRoutes.play,
        extra: PlayRequest(
          source: UriSource(Uri.parse('file:///v/x.mkv')),
          title: 'x',
          memoryKey: 'x',
          locate: () async => Uri.parse('saf://tree/g1/x.mkv'),
        ),
      ),
    );
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(prompt, findsNothing);
  });
}
