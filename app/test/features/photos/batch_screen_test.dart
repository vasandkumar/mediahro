import 'package:flutter/material.dart' hide ImageInfo;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediahro/app/l10n/gen/app_localizations.dart';
import 'package:mediahro/core/files/batch.dart';
import 'package:mediahro/features/photos/batch/batch_screen.dart';
import 'package:mediahro/features/photos/batch/photo_batch_service.dart';
import 'package:mediahro/features/photos/photos_providers.dart';
import 'package:mediahro/features/photos/timeline/timeline_model.dart';
import 'package:mediahro/images/image_pipeline.dart';
import 'package:mediahro_design/mediahro_design.dart';

import 'photos_harness.dart';

final class FakeBatch implements PhotoBatch {
  FakeBatch({
    this.available = const {
      EncodeFormat.jpeg,
      EncodeFormat.png,
      EncodeFormat.webp,
      EncodeFormat.jxl,
    },
    this.report = const BatchReport(done: 3),
  });

  final Set<EncodeFormat> available;
  BatchReport report;
  final List<String> calls = [];
  String? pattern;
  ConvertOptions? convertOptions;
  StripScope? scope;

  /// When set, a call waits until it is cancelled.
  bool waitForStop = false;

  @override
  Future<Set<EncodeFormat>> formats() async => available;

  @override
  List<RenamePlan> previewRename(List<PhotoEntry> photos, String pattern) =>
      planRename([
        for (final p in photos)
          RenameFacts(name: p.name, modified: p.date, width: p.width),
      ], pattern);

  Future<BatchReport> _go(
    String name,
    int total,
    void Function(int)? onProgress,
    bool Function()? cancelled,
  ) async {
    calls.add(name);
    onProgress?.call(1);
    if (waitForStop) {
      while (!(cancelled?.call() ?? false)) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      return const BatchReport(done: 1, stopped: true);
    }
    return report;
  }

  @override
  Future<BatchReport> rename(
    List<PhotoEntry> photos,
    String pattern, {
    void Function(int done)? onProgress,
    bool Function()? cancelled,
  }) {
    this.pattern = pattern;
    return _go('rename', photos.length, onProgress, cancelled);
  }

  @override
  Future<BatchReport> convert(
    List<PhotoEntry> photos,
    ConvertOptions options, {
    void Function(int done)? onProgress,
    bool Function()? cancelled,
  }) {
    convertOptions = options;
    return _go('convert', photos.length, onProgress, cancelled);
  }

  @override
  Future<BatchReport> uprightByExif(
    List<PhotoEntry> photos, {
    void Function(int done)? onProgress,
    bool Function()? cancelled,
  }) => _go('upright', photos.length, onProgress, cancelled);

  @override
  Future<BatchReport> strip(
    List<PhotoEntry> photos,
    StripScope scope, {
    void Function(int done)? onProgress,
    bool Function()? cancelled,
  }) {
    this.scope = scope;
    return _go('strip', photos.length, onProgress, cancelled);
  }
}

PhotoEntry _photo(int id, {int? orientation}) {
  final e = fakeEntries(days: 1, perDay: 1, firstId: id).single;
  return PhotoEntry(
    id: id,
    sourceId: 1,
    relPath: 'p/IMG_$id.jpg',
    name: 'IMG_$id.jpg',
    ext: 'jpg',
    isVideo: false,
    size: 1,
    mtime: e.mtime,
    date: DateTime(2026, 10, 21, 9, id),
    orientation: orientation,
  );
}

void main() {
  late FakeBatch batch;

  Future<void> open(
    WidgetTester tester,
    List<PhotoEntry> photos, {
    FakeBatch? fake,
  }) async {
    batch = fake ?? FakeBatch();
    tester.view
      ..physicalSize = const Size(400, 900)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [photoBatchProvider.overrideWithValue(batch)],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (c) => Scaffold(
              body: Center(
                child: FilledButton(
                  onPressed: () => openBatch(c, photos),
                  child: const Text('batch'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('batch'));
    await tester.pumpAndSettle();
  }

  final photos = [_photo(1), _photo(2), _photo(3)];

  testWidgets('IMG-010 the batch screen starts on rename with a preview', (
    tester,
  ) async {
    await open(tester, photos);
    expect(find.text('Batch: 3 photos'), findsOneWidget);
    for (final a in ['Rename', 'Convert', 'Upright', 'Strip']) {
      expect(find.text(a), findsWidgets);
    }
    expect(find.text('2026-10-21_001.jpg'), findsOneWidget);
    expect(find.text('2026-10-21_003.jpg'), findsOneWidget);
    expect(find.text('IMG_1.jpg'), findsOneWidget);
  });

  testWidgets('IMG-010 a token chip is added where the cursor is', (
    tester,
  ) async {
    await open(tester, photos);
    await tester.enterText(find.byType(TextField), 'trip_');
    await tester.tap(find.text('{n:3}'));
    await tester.pump();
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'trip_{n:3}',
    );
    expect(find.text('trip_001.jpg'), findsOneWidget);
  });

  testWidgets('IMG-010 a name shared by several photos blocks the start', (
    tester,
  ) async {
    await open(tester, photos);
    await tester.enterText(find.byType(TextField), 'holiday');
    await tester.pump();
    expect(find.textContaining('same name'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Rename'))
          .onPressed,
      isNull,
    );
  });

  testWidgets('IMG-010 an unknown token is explained and blocks the start', (
    tester,
  ) async {
    await open(tester, photos);
    await tester.enterText(find.byType(TextField), '{nope}');
    await tester.pump();
    expect(find.text("This name has a token I don't know."), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Rename'))
          .onPressed,
      isNull,
    );
  });

  testWidgets(
    'IMG-010 starting a rename reports and closes when all went well',
    (tester) async {
      await open(tester, photos);
      await tester.enterText(find.byType(TextField), 'trip_{n:2}');
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Rename'));
      await tester.pumpAndSettle();
      expect(batch.calls, ['rename']);
      expect(batch.pattern, 'trip_{n:2}');
      expect(find.text('Batch finished'), findsOneWidget);
      expect(
        find.textContaining('3 done, 0 left as they were, 0 could not'),
        findsOneWidget,
      );
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      expect(find.byType(BatchScreen), findsNothing);
    },
  );

  testWidgets('IMG-010 failures are listed and the screen stays', (
    tester,
  ) async {
    await open(
      tester,
      photos,
      fake: FakeBatch(
        report: const BatchReport(
          done: 1,
          skipped: 1,
          failed: ['b.jpg', 'c.jpg'],
        ),
      ),
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Rename'));
    await tester.pumpAndSettle();
    expect(find.text('Could not process:'), findsOneWidget);
    expect(find.text('b.jpg'), findsOneWidget);
    expect(find.text('c.jpg'), findsOneWidget);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(find.byType(BatchScreen), findsOneWidget);
  });

  group('IMG-010 convert', () {
    Future<void> toConvert(WidgetTester tester) async {
      await tester.tap(find.text('Convert').first);
      await tester.pumpAndSettle();
    }

    testWidgets('IMG-010 only formats the device can write are offered', (
      tester,
    ) async {
      await open(tester, photos);
      await toConvert(tester);
      for (final f in ['Keep each format', 'JPEG', 'PNG', 'WebP', 'JPEG XL']) {
        expect(find.widgetWithText(ChoiceChip, f), findsOneWidget, reason: f);
      }
      expect(find.widgetWithText(ChoiceChip, 'AVIF'), findsNothing);
      expect(find.widgetWithText(ChoiceChip, 'HEIC'), findsNothing);
    });

    testWidgets('IMG-010 AVIF and HEIC appear when the OS encodes them', (
      tester,
    ) async {
      await open(
        tester,
        photos,
        fake: FakeBatch(
          available: {
            EncodeFormat.jpeg,
            EncodeFormat.png,
            EncodeFormat.avif,
            EncodeFormat.heic,
          },
        ),
      );
      await toConvert(tester);
      expect(find.widgetWithText(ChoiceChip, 'AVIF'), findsOneWidget);
      expect(find.widgetWithText(ChoiceChip, 'HEIC'), findsOneWidget);
      expect(find.widgetWithText(ChoiceChip, 'WebP'), findsNothing);
    });

    testWidgets('IMG-010 the chosen options reach the batch', (tester) async {
      await open(tester, photos);
      await toConvert(tester);
      await tester.tap(find.widgetWithText(ChoiceChip, 'JPEG XL'));
      await tester.tap(find.widgetWithText(ChoiceChip, 'Up to 1600 px'));
      await tester.tap(find.byType(Switch));
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Convert'));
      await tester.pumpAndSettle();
      final o = batch.convertOptions!;
      expect(o.format, EncodeFormat.jxl);
      expect(o.maxEdge, 1600);
      expect(o.stripMetadata, isTrue);
      expect(o.quality, 90);
    });

    testWidgets('IMG-010 PNG has no quality slider, JPEG does', (tester) async {
      await open(tester, photos);
      await toConvert(tester);
      expect(find.textContaining('Quality'), findsOneWidget);
      await tester.tap(find.widgetWithText(ChoiceChip, 'PNG'));
      await tester.pump();
      expect(find.textContaining('Quality'), findsNothing);
    });

    testWidgets('IMG-010 quality moves with the slider', (tester) async {
      await open(tester, photos);
      await toConvert(tester);
      await tester.drag(find.byType(Slider), const Offset(-150, 0));
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Convert'));
      await tester.pumpAndSettle();
      expect(batch.convertOptions!.quality, lessThan(90));
      expect(batch.convertOptions!.format, isNull);
    });
  });

  group('IMG-010 upright and strip', () {
    testWidgets('IMG-010 with nothing stored sideways, upright cannot start', (
      tester,
    ) async {
      await open(tester, photos);
      await tester.tap(find.text('Upright').first);
      await tester.pumpAndSettle();
      expect(find.textContaining('None of these photos'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Turn upright'),
            )
            .onPressed,
        isNull,
      );
    });

    testWidgets('IMG-010 upright asks before saving over originals', (
      tester,
    ) async {
      await open(tester, [
        _photo(1, orientation: 6),
        _photo(2),
        _photo(3, orientation: 3),
      ]);
      await tester.tap(find.text('Upright').first);
      await tester.pumpAndSettle();
      expect(
        find.textContaining('2 photos are stored sideways'),
        findsOneWidget,
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Turn upright'));
      await tester.pumpAndSettle();
      expect(find.text('Change the original files?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(batch.calls, isEmpty);
      await tester.tap(find.widgetWithText(FilledButton, 'Turn upright'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Turn upright').last);
      await tester.pumpAndSettle();
      expect(batch.calls, ['upright']);
    });

    testWidgets(
      'IMG-010 strip offers location only or everything, with a warning',
      (tester) async {
        await open(tester, photos);
        await tester.tap(find.text('Strip').first);
        await tester.pumpAndSettle();
        expect(find.text('Remove the location only'), findsOneWidget);
        await tester.tap(find.text('Remove all metadata'));
        await tester.pump();
        await tester.tap(find.widgetWithText(FilledButton, 'Remove'));
        await tester.pumpAndSettle();
        expect(find.text('Change the original files?'), findsOneWidget);
        expect(find.textContaining('metadata of 3 photos'), findsOneWidget);
        await tester.tap(find.widgetWithText(FilledButton, 'Remove').last);
        await tester.pumpAndSettle();
        expect(batch.calls, ['strip']);
        expect(batch.scope, StripScope.everything);
      },
    );

    testWidgets('IMG-010 the default strip removes only the location', (
      tester,
    ) async {
      await open(tester, photos);
      await tester.tap(find.text('Strip').first);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Remove'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Remove').last);
      await tester.pumpAndSettle();
      expect(batch.scope, StripScope.location);
    });
  });

  testWidgets('IMG-010 Stop ends a running batch early', (tester) async {
    await open(tester, photos, fake: FakeBatch()..waitForStop = true);
    await tester.tap(find.widgetWithText(FilledButton, 'Rename'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('Working: 1 of 3'), findsOneWidget);
    await tester.tap(find.text('Stop'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();
    expect(find.text('Stopped before the end.'), findsOneWidget);
  });

  group('IMG-010 reaching the batch tools', () {
    testWidgets('IMG-010 the selection bar opens them', (tester) async {
      final h = await PhotosHarness.create(tester);
      final fake = FakeBatch();
      await h.pump(
        tester,
        entries: fakeEntries(days: 1, firstId: 1),
        extra: [photoBatchProvider.overrideWithValue(fake)],
      );
      await tester.longPress(find.byType(KGridTile).at(0));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(KGridTile).at(1));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('More'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Batch tools'));
      await tester.pumpAndSettle();
      expect(find.byType(BatchScreen), findsOneWidget);
      expect(find.text('Batch: 2 photos'), findsOneWidget);
    });

    testWidgets('IMG-010 videos alone give a message, not an empty screen', (
      tester,
    ) async {
      final h = await PhotosHarness.create(tester);
      await h.pump(
        tester,
        entries: fakeEntries(days: 1, firstId: 1, videos: {1, 2, 3, 4, 5, 6}),
        extra: [photoBatchProvider.overrideWithValue(FakeBatch())],
      );
      await tester.longPress(find.byType(KGridTile).at(0));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('More'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Batch tools'));
      await tester.pumpAndSettle();
      expect(find.byType(BatchScreen), findsNothing);
      expect(find.text('Videos have no location to change.'), findsOneWidget);
    });
  });
}
