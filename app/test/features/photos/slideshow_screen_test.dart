import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart' hide ImageInfo;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediahro/app/l10n/gen/app_localizations.dart';
import 'package:mediahro/features/photos/photos_providers.dart';
import 'package:mediahro/features/photos/slideshow/slideshow_music.dart';
import 'package:mediahro/features/photos/slideshow/slideshow_options.dart';
import 'package:mediahro/features/photos/slideshow/slideshow_screen.dart';
import 'package:mediahro/features/photos/timeline/timeline_model.dart';
import 'package:mediahro/features/settings/settings_providers.dart';
import 'package:mediahro/features/settings/settings_store.dart';
import 'package:mediahro/platform/display.dart';
import 'package:mediahro/platform/platform_facades.dart' show displayProvider;

import '../../helpers.dart';
import 'photos_harness.dart';

final class _Music implements SlideshowMusic {
  _Music({this.isAvailable = true, this.list = const []});

  final bool isAvailable;
  final List<SlideMusicPlaylist> list;
  final List<SlideshowOptions> started = [];
  int stops = 0;

  @override
  bool get available => isAvailable;

  @override
  Future<List<SlideMusicPlaylist>> playlists() async => list;

  @override
  Future<bool> start(SlideshowOptions options) async {
    started.add(options);
    return true;
  }

  @override
  Future<void> stop() async => stops++;
}

final class _Display implements DisplayFacade {
  final List<bool> awake = [];
  List<DisplayInfo> shown = const [];
  final StreamController<List<DisplayInfo>> changesController =
      StreamController<List<DisplayInfo>>.broadcast();
  PresentationHandle? handle;
  final List<String> opened = [];
  final List<PresentationHandle> closed = [];

  @override
  Future<List<DisplayInfo>> displays() async => shown;

  @override
  Stream<List<DisplayInfo>> get changes => changesController.stream;

  @override
  Future<PresentationHandle?> openPresentation(String displayId) async {
    opened.add(displayId);
    return handle;
  }

  @override
  Future<void> closePresentation(PresentationHandle h) async => closed.add(h);

  @override
  Future<void> present(PresentationHandle h, PresentationFrame f) async {}

  @override
  Future<void> keepScreenOn({required bool on}) async => awake.add(on);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late PhotosHarness h;
  late _Display display;
  late SettingsStore store;
  late _Music music;
  late List<PhotoEntry> photos;
  final loaded = <int>[];
  var failing = <int>{};

  Future<void> open(
    WidgetTester tester, {
    int count = 4,
    int start = 0,
    Map<String, Object?>? settings,
    Random? random,
    _Music? withMusic,
    Set<int> failures = const {},
    bool external = false,
  }) async {
    h = await PhotosHarness.create(tester);
    display = _Display()
      ..shown = [
        const DisplayInfo(id: 'main', name: 'Phone', refreshRate: 60),
        if (external)
          const DisplayInfo(
            id: 'tv',
            name: 'TV',
            refreshRate: 60,
            isExternal: true,
          ),
      ];
    music = withMusic ?? _Music();
    photos = fakeEntries(days: 1, perDay: count, firstId: 1);
    failing = failures;
    loaded.clear();
    store =
        await tester.runAsync(() => memoryStore(settings)) ??
        (throw StateError('store'));
    tester.view
      ..physicalSize = const Size(400, 800)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsStoreProvider.overrideWithValue(store),
          slideshowMusicProvider.overrideWithValue(music),
          displayProvider.overrideWithValue(display),
          viewerImageLoaderProvider.overrideWithValue((entry) async {
            loaded.add(entry.id);
            if (failing.contains(entry.id)) throw StateError('unreadable');
            return h.take();
          }),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, child) => MediaQuery(
            // The controls stay up (as for a screen reader), so tests can
            // press them without chasing the auto-hide.
            data: MediaQuery.of(context).copyWith(accessibleNavigation: true),
            child: child!,
          ),
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: FilledButton(
                  onPressed: () => Navigator.of(context).push<void>(
                    MaterialPageRoute(
                      builder: (_) => SlideshowScreen(
                        photos: photos,
                        start: start,
                        random: random,
                      ),
                    ),
                  ),
                  child: const Text('go'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pump();
    // The route slides in; the slide clock is already running.
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();
  }

  String position() {
    final t = tester0
        .widgetList<Text>(find.textContaining(' of '))
        .map((t) => t.data!)
        .firstWhere((s) => RegExp(r'^\d+ of \d+$').hasMatch(s));
    return t;
  }

  testWidgets('IMG-012 it starts at the chosen photo and counts the run', (
    tester,
  ) async {
    tester0 = tester;
    await open(tester, start: 2);
    expect(position(), '1 of 4');
    expect(loaded.first, photos[2].id);
  });

  testWidgets(
    'IMG-012 each photo stays for the interval, then the next shows',
    (tester) async {
      tester0 = tester;
      await open(tester);
      await tester.pump(const Duration(seconds: 4));
      expect(position(), '1 of 4');
      await tester.pump(const Duration(seconds: 2));
      await tester.pump(const Duration(milliseconds: 800));
      expect(position(), '2 of 4');
      expect(loaded, [photos[0].id, photos[1].id, photos[2].id]);
    },
  );

  testWidgets('IMG-012 the next photo is loaded while this one shows', (
    tester,
  ) async {
    tester0 = tester;
    await open(tester);
    expect(loaded, contains(photos[1].id));
  });

  testWidgets('IMG-012 pause holds the photo and play lets it go on', (
    tester,
  ) async {
    tester0 = tester;
    await open(tester);
    await tester.tap(find.byTooltip('Pause'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 30));
    expect(position(), '1 of 4');
    await tester.tap(find.byTooltip('Play'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 6));
    await tester.pump(const Duration(milliseconds: 800));
    expect(position(), '2 of 4');
  });

  testWidgets('IMG-012 next and previous work by hand, with a loop', (
    tester,
  ) async {
    tester0 = tester;
    await open(tester);
    await tester.tap(find.byTooltip('Previous photo'));
    await tester.pump();
    await tester.pump();
    expect(position(), '4 of 4');
    await tester.tap(find.byTooltip('Next photo'));
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 800));
    expect(position(), '1 of 4');
  });

  testWidgets('IMG-012 without a loop it ends and can be played again', (
    tester,
  ) async {
    tester0 = tester;
    await open(tester, count: 2, settings: {'photos.slideshow.loop': false});
    await tester.pump(const Duration(seconds: 6));
    await tester.pump(const Duration(milliseconds: 800));
    expect(position(), '2 of 2');
    await tester.pump(const Duration(seconds: 6));
    expect(find.text('End of the slideshow'), findsOneWidget);
    await tester.tap(find.text('Play again'));
    await tester.pump();
    await tester.pump();
    expect(find.text('End of the slideshow'), findsNothing);
    expect(position(), '1 of 2');
  });

  testWidgets('IMG-012 faster shortens the stay and the speed is shown', (
    tester,
  ) async {
    tester0 = tester;
    await open(tester);
    expect(find.text('Speed 1×'), findsOneWidget);
    await tester.tap(find.byTooltip('Faster'));
    await tester.pump();
    await tester.tap(find.byTooltip('Faster'));
    await tester.pump();
    expect(find.text('Speed 1.56×'), findsOneWidget);
    // 5 s / 1.5625 = 3.2 s.
    await tester.pump(const Duration(milliseconds: 3300));
    await tester.pump(const Duration(milliseconds: 800));
    expect(position(), '2 of 4');
    expect(store.get(SlideshowSettings.speed), closeTo(1.5625, 1e-9));
  });

  testWidgets('IMG-012 slower lengthens the stay and stops at a quarter', (
    tester,
  ) async {
    tester0 = tester;
    await open(tester, settings: {'photos.slideshow.speed': 0.25});
    expect(find.text('Speed 0.25×'), findsOneWidget);
    expect(
      tester
          .widget<IconButton>(
            find.widgetWithIcon(IconButton, Icons.fast_rewind),
          )
          .onPressed,
      isNull,
    );
  });

  testWidgets('IMG-012 a random order shows every photo once', (tester) async {
    tester0 = tester;
    await open(
      tester,
      count: 5,
      settings: {
        'photos.slideshow.random': true,
        'photos.slideshow.loop': false,
      },
      random: Random(3),
    );
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(seconds: 6));
      await tester.pump(const Duration(milliseconds: 800));
    }
    final firstShown = loaded.take(5).toSet();
    expect(loaded.first, photos.first.id);
    expect(firstShown, hasLength(5));
    expect(loaded.take(5), isNot(photos.map((e) => e.id).toList()));
  });

  testWidgets('IMG-012 a photo that cannot be opened is skipped', (
    tester,
  ) async {
    tester0 = tester;
    await open(tester, failures: {2});
    await tester.pump(const Duration(seconds: 6));
    await tester.pump(const Duration(milliseconds: 800));
    expect(position(), '3 of 4');
    expect(loaded, contains(2));
  });

  testWidgets('IMG-012 if nothing can be opened it says so', (tester) async {
    tester0 = tester;
    await open(tester, count: 3, failures: {1, 2, 3});
    await tester.pump();
    await tester.pump();
    expect(find.text('None of these photos could be opened.'), findsOneWidget);
  });

  testWidgets('IMG-012 every transition runs without trouble', (tester) async {
    tester0 = tester;
    for (final t in SlideChange.values) {
      await open(
        tester,
        settings: {
          'photos.slideshow.transition': t.name,
          'photos.slideshow.kenBurns': true,
        },
      );
      await tester.pump(const Duration(seconds: 6));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 800));
      expect(position(), '2 of 4', reason: t.name);
      expect(tester.takeException(), isNull, reason: t.name);
      await tester.pumpWidget(const SizedBox());
    }
  });

  testWidgets('IMG-012 the options sheet changes what runs and is remembered', (
    tester,
  ) async {
    tester0 = tester;
    await open(tester);
    await tester.tap(find.byTooltip('Slideshow options'));
    await tester.pumpAndSettle();
    expect(find.text('5 seconds per photo'), findsWidgets);
    await tester.tap(find.text('Zoom'));
    await tester.pump();
    final ken = find.widgetWithText(SwitchListTile, 'Slow zoom (Ken Burns)');
    await tester.ensureVisible(ken);
    await tester.tap(ken);
    final rnd = find.widgetWithText(SwitchListTile, 'Random order');
    await tester.ensureVisible(rnd);
    await tester.tap(rnd);
    final loop = find.widgetWithText(SwitchListTile, 'Loop');
    await tester.ensureVisible(loop);
    await tester.tap(loop);
    await tester.pump();
    await tester.drag(find.byType(Slider), const Offset(120, 0));
    await tester.pump();
    final saved = SlideshowSettings.read(store);
    expect(saved.transition, SlideChange.zoom);
    expect(saved.kenBurns, isTrue);
    expect(saved.random, isTrue);
    expect(saved.loop, isFalse);
    expect(saved.interval, greaterThan(5));
  });

  testWidgets(
    'IMG-012 music starts with the slideshow and stops when it ends',
    (tester) async {
      tester0 = tester;
      await open(
        tester,
        settings: {'photos.slideshow.music': 'library'},
        withMusic: _Music(),
      );
      await tester.pump();
      expect(music.started, hasLength(1));
      expect(music.started.single.music, SlideMusicSource.library);
      expect(find.byIcon(Icons.music_note), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      expect(music.stops, greaterThan(0));
    },
  );

  testWidgets('IMG-012 no music option means no music', (tester) async {
    tester0 = tester;
    await open(tester);
    expect(music.started, isEmpty);
    expect(find.byIcon(Icons.music_note), findsNothing);
  });

  testWidgets('IMG-012 a playlist can be chosen when there are playlists', (
    tester,
  ) async {
    tester0 = tester;
    await open(
      tester,
      withMusic: _Music(list: [(id: 4, name: 'Road trip', count: 12)]),
    );
    await tester.tap(find.byTooltip('Slideshow options'));
    await tester.pumpAndSettle();
    final chip = find.widgetWithText(ChoiceChip, 'Playlist');
    await tester.ensureVisible(chip);
    await tester.tap(chip);
    await tester.pumpAndSettle();
    expect(find.text('Road trip'), findsOneWidget);
    final saved = SlideshowSettings.read(store);
    expect(saved.music, SlideMusicSource.playlist);
    expect(saved.playlistId, 4);
    await tester.pumpAndSettle();
    expect(music.started.last.playlistId, 4);
  });

  testWidgets('IMG-012 without a music library the sheet has no music part', (
    tester,
  ) async {
    tester0 = tester;
    await open(tester, withMusic: _Music(isAvailable: false));
    await tester.tap(find.byTooltip('Slideshow options'));
    await tester.pumpAndSettle();
    expect(find.text('Music'), findsNothing);
  });

  testWidgets('IMG-012 the close button leaves', (tester) async {
    tester0 = tester;
    await open(tester);
    await tester.tap(find.byTooltip('Close slideshow'));
    await tester.pumpAndSettle();
    expect(find.byType(SlideshowScreen), findsNothing);
  });

  /// The widest sideways shift of any picture layer on screen.
  double sideways(WidgetTester tester) {
    var widest = 0.0;
    for (final t in tester.widgetList<Transform>(find.byType(Transform))) {
      final x = t.transform.getTranslation().x.abs();
      if (x > widest) widest = x;
    }
    return widest;
  }

  testWidgets('IMG-012 the slide transition slides the picture in', (
    tester,
  ) async {
    tester0 = tester;
    await open(
      tester,
      settings: {
        'photos.slideshow.transition': 'slide',
        'photos.slideshow.kenBurns': false,
      },
    );
    await tester.pump(const Duration(seconds: 6));
    await tester.pump(const Duration(milliseconds: 350));
    expect(sideways(tester) > 50, isTrue);
    await tester.pump(const Duration(seconds: 1));
  });

  for (final kind in ['slide', 'zoom']) {
    testWidgets(
      'IMG-012 with reduced motion the $kind transition is a short fade',
      (tester) async {
        tester0 = tester;
        tester.platformDispatcher.accessibilityFeaturesTestValue =
            const FakeAccessibilityFeatures(disableAnimations: true);
        addTearDown(
          tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
        );
        await open(
          tester,
          settings: {
            'photos.slideshow.transition': kind,
            'photos.slideshow.kenBurns': true,
          },
        );
        for (var i = 0; i < 450; i++) {
          await tester.pump(const Duration(milliseconds: 20));
          expect(sideways(tester), 0, reason: 'nothing slides');
          for (final t in tester.widgetList<Transform>(
            find.byType(Transform),
          )) {
            // Nothing is scaled either (no zoom transition, no Ken Burns).
            expect(t.transform.getMaxScaleOnAxis(), closeTo(1, 1e-6));
          }
        }
        expect(position(), isNot('1 of 4'));
      },
    );
  }

  testWidgets('IMG-012 the screen is held awake only while the show plays', (
    tester,
  ) async {
    tester0 = tester;
    await open(tester);
    await tester.pump();
    expect(display.awake, [true]);
    await tester.tap(find.byTooltip('Pause'));
    await tester.pump();
    expect(display.awake, [true, false]);
    await tester.tap(find.byTooltip('Play'));
    await tester.pump();
    expect(display.awake, [true, false, true]);
    await tester.pumpWidget(const SizedBox());
    expect(display.awake.last, isFalse);
  });

  testWidgets('IMG-012 the screen is released when the show ends', (
    tester,
  ) async {
    tester0 = tester;
    await open(tester, count: 2, settings: {'photos.slideshow.loop': false});
    await tester.pump(const Duration(seconds: 6));
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 6));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('End of the slideshow'), findsOneWidget);
    expect(display.awake.last, isFalse);
    await tester.tap(find.text('Play again'));
    await tester.pump();
    expect(display.awake.last, isTrue);
  });

  group('IMG-012 the external display (ADR-044)', () {
    testWidgets('IMG-012 with only the phone there is no cast button', (
      tester,
    ) async {
      tester0 = tester;
      await open(tester);
      await tester.pump();
      expect(find.byTooltip('Show on the external display'), findsNothing);
    });

    testWidgets('IMG-012 a platform that cannot present keeps the show here', (
      tester,
    ) async {
      tester0 = tester;
      await open(tester, external: true);
      await tester.pump();
      await tester.tap(find.byTooltip('Show on the external display'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(display.opened, ['tv']);
      expect(
        find.text(
          'That display cannot show the slideshow. It stays on this screen.',
        ),
        findsOneWidget,
      );
      // Still running here.
      expect(find.byTooltip('Show on this screen only'), findsNothing);
      expect(position(), '1 of 4');
    });

    testWidgets(
      'IMG-012 a presentation with no view behind it is closed again',
      (tester) async {
        tester0 = tester;
        await open(tester, external: true);
        display.handle = const PresentationHandle(id: 99, displayId: 'tv');
        await tester.pump();
        await tester.tap(find.byTooltip('Show on the external display'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(display.closed, [display.handle]);
        expect(find.byTooltip('Show on this screen only'), findsNothing);
      },
    );

    testWidgets('IMG-012 the button goes when the display is unplugged', (
      tester,
    ) async {
      tester0 = tester;
      await open(tester, external: true);
      await tester.pump();
      expect(find.byTooltip('Show on the external display'), findsOneWidget);
      display.changesController.add(const [
        DisplayInfo(id: 'main', name: 'Phone', refreshRate: 60),
      ]);
      await tester.pump();
      expect(find.byTooltip('Show on the external display'), findsNothing);
    });
  });
}

late WidgetTester tester0;
