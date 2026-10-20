import 'dart:io';

import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:mediahro/core/db/library_database.dart';
import 'package:mediahro/features/photos/info/metadata_edit_service.dart';
import 'package:mediahro/features/photos/organise/photo_organiser.dart';
import 'package:mediahro/features/photos/organise/write_back.dart';
import 'package:mediahro/features/photos/photos_providers.dart';
import 'package:mediahro/features/photos/photos_settings.dart';
import 'package:mediahro/features/photos/timeline/timeline_model.dart';
import 'package:mediahro/features/settings/settings_registry.dart';
import 'package:mediahro/images/image_pipeline.dart';
import 'package:mediahro/images/pipeline/mediahro_image_pipeline.dart';
import 'package:mediahro_design/mediahro_design.dart';

import '../../core/seed.dart';
import 'photos_harness.dart';

final class _Edits implements MetadataEditor {
  final List<(int, ImageMetadataEdit)> saved = [];
  final Set<int> failing = {};

  @override
  Future<MetadataWriteOutcome> save(
    PhotoEntry entry,
    ImageMetadataEdit edit,
  ) async {
    if (failing.contains(entry.id)) throw const FileSystemException('locked');
    saved.add((entry.id, edit));
    return const MetadataWriteOutcome.file();
  }
}

void main() {
  group('IMG-005 write back to files', () {
    late LibraryDatabase db;
    late PhotoOrganiser org;
    late _Edits edits;
    var on = true;

    OrganisationWriteBack writer() => OrganisationWriteBack(
      editor: edits,
      organiser: org,
      enabled: () => on,
      fileRating: (_) async => null,
    );

    setUp(() {
      db = LibraryDatabase.memory();
      org = PhotoOrganiser(db: db);
      edits = _Edits();
      on = true;
    });

    tearDown(() => db.close());

    List<PhotoEntry> photos(int n, {Set<int> videos = const {}}) =>
        fakeEntries(days: 1, perDay: n, firstId: 1, videos: videos);

    test('IMG-005 with the setting off no file is touched', () async {
      on = false;
      expect(await writer().rating(photos(3), 4), 0);
      expect(await writer().label(photos(3), LabelColor.red), 0);
      expect(await writer().tags(photos(3)), 0);
      expect(edits.saved, isEmpty);
    });

    test(
      'IMG-005 a rating goes into every photo but not into videos',
      () async {
        expect(await writer().rating(photos(3, videos: {2}), 4), 0);
        expect(edits.saved.map((s) => s.$1), [1, 3]);
        expect(edits.saved.every((s) => s.$2.rating == 4), isTrue);
      },
    );

    test(
      'IMG-005 a colour label is written the way photo programs spell it',
      () async {
        await writer().label(photos(1), LabelColor.purple);
        expect(edits.saved.single.$2.label, 'Purple');
        await writer().label(photos(1), null);
        expect(edits.saved.last.$2.label, '', reason: 'removes the label');
        for (final c in LabelColor.values) {
          expect(xmpLabel(c), isNotEmpty);
          expect(xmpLabel(c)[0], xmpLabel(c)[0].toUpperCase());
        }
      },
    );

    test('IMG-005 each photo gets its own complete tag list', () async {
      final seed = Seed(db);
      final a = await seed.item('a.jpg', kind: ItemKind.image);
      final b = await seed.item('b.jpg', kind: ItemKind.image);
      await org.addTag([a, b], 'lake');
      await org.addTag([a], 'sunrise');
      final list = [photos(1).single, photos(2).last];
      // Entry ids are the seeded item ids.
      final entries = [
        PhotoEntry(
          id: a,
          sourceId: 1,
          relPath: 'a.jpg',
          name: 'a.jpg',
          ext: 'jpg',
          isVideo: false,
          size: 1,
          mtime: list.first.mtime,
          date: list.first.date,
        ),
        PhotoEntry(
          id: b,
          sourceId: 1,
          relPath: 'b.jpg',
          name: 'b.jpg',
          ext: 'jpg',
          isVideo: false,
          size: 1,
          mtime: list.first.mtime,
          date: list.first.date,
        ),
      ];
      await writer().tags(entries);
      expect(edits.saved.map((s) => s.$1), [a, b]);
      expect(edits.saved[0].$2.keywords, unorderedEquals(['lake', 'sunrise']));
      expect(edits.saved[1].$2.keywords, ['lake']);
    });

    test(
      'IMG-005 a file that cannot be written is counted, the rest go on',
      () async {
        edits.failing.add(2);
        final failed = await writer().rating(photos(4), 5);
        expect(failed, 1);
        expect(writer().lastFailures, 0);
        expect(edits.saved.map((s) => s.$1), [1, 3, 4]);
      },
    );

    test('IMG-005 the setting is off until the user turns it on', () {
      expect(PhotoSettings.writeOrganisation.defaultValue, isFalse);
      final row = photoSettingsContributions.single;
      expect(row.section, SettingsSectionId.photos);
      expect(row.entries, everyElement(isA<ToggleSetting>()));
      expect(PhotoSettings.stripOnShare.defaultValue, isFalse);
    });
  });

  group('IMG-005 write back from the selection bar', () {
    late _Edits edits;
    var on = true;

    List<Override> overrides() => [
      metadataEditServiceProvider.overrideWithValue(edits),
      organisationWriteBackProvider.overrideWith(
        (ref) => OrganisationWriteBack(
          editor: edits,
          organiser: ref.watch(photoOrganiserProvider),
          enabled: () => on,
          fileRating: (_) async => null,
        ),
      ),
    ];

    Future<PhotosHarness> open(WidgetTester tester) async {
      edits = _Edits();
      final h = await PhotosHarness.create(tester);
      final seed = Seed(h.db);
      await tester.runAsync(() async {
        for (var i = 1; i <= 6; i++) {
          await seed.item('p/IMG_$i.jpg', kind: ItemKind.image);
        }
      });
      await h.pump(
        tester,
        entries: fakeEntries(days: 1, firstId: 1),
        extra: overrides(),
      );
      return h;
    }

    Future<void> settle(WidgetTester tester) async {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('IMG-005 a rating given in the app reaches the file', (
      tester,
    ) async {
      on = true;
      await open(tester);
      await tester.longPress(find.byType(KGridTile).first);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('More'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Rate'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('4 stars'));
      await settle(tester);
      expect(edits.saved, hasLength(1));
      expect(edits.saved.single.$1, 1);
      expect(edits.saved.single.$2.rating, 4);
    });

    testWidgets('IMG-005 a colour label reaches the file too', (tester) async {
      on = true;
      await open(tester);
      await tester.longPress(find.byType(KGridTile).first);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('More'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Colour label'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Green'));
      await settle(tester);
      expect(edits.saved.single.$2.label, 'Green');
    });

    testWidgets('IMG-005 with the setting off the library alone changes', (
      tester,
    ) async {
      on = false;
      final h = await open(tester);
      await tester.longPress(find.byType(KGridTile).first);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('More'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Rate'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('4 stars'));
      await settle(tester);
      expect(edits.saved, isEmpty);
      final r = await tester.runAsync(() => h.db.select(h.db.ratings).get());
      expect(r!.single.value, 8);
    });

    testWidgets('IMG-005 a file that cannot be written is reported', (
      tester,
    ) async {
      on = true;
      await open(tester);
      edits.failing.add(1);
      await tester.longPress(find.byType(KGridTile).first);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('More'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Rate'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('2 stars'));
      await settle(tester);
      expect(
        find.textContaining('could not be updated with the rating'),
        findsOneWidget,
      );
    });
  });
}
