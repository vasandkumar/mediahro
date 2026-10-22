import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:mediahro/app/l10n/gen/app_localizations.dart';
import 'package:mediahro/core/db/library_database.dart';
import 'package:mediahro/core/providers.dart';
import 'package:mediahro/core/sources/source_repository.dart';
import 'package:mediahro/features/photos/timeline/photo_access_banner.dart';
import 'package:mediahro/platform/platform_facades.dart';
import 'package:mediahro_design/mediahro_design.dart';

/// Only the calls the banner makes.
final class _Storage implements StorageFacade {
  _Storage(this.state);

  MediaPermission state;
  MediaPermission afterRequest = MediaPermission.granted;
  int requests = 0;

  @override
  Future<MediaPermission> mediaPermission(PickKind kind) async {
    expect(kind, PickKind.image);
    return state;
  }

  @override
  Future<MediaPermission> requestMediaPermission(PickKind kind) async {
    requests++;
    return state = afterRequest;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

final class _Library implements PhotoLibraryFacade {
  int selections = 0;

  @override
  Future<void> manageLimitedSelection() async => selections++;

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

SourceSummary _source(String root, {int id = 1}) => SourceSummary(
  SourceRow(
    id: id,
    kind: SourceKind.local,
    name: 'Device media',
    rootUri: root,
    options: '{}',
    schedule: ScanSchedule.onOpen,
    includeVideo: true,
    includeMusic: true,
    includePhotos: true,
    scrapeMetadata: false,
    locked: false,
    enabled: true,
    addedAt: DateTime.utc(2026),
    sortOrder: 0,
  ),
  items: 0,
  missing: 0,
);

/// IMG-001 / IMG-016 (owner hand check): the Photos timeline said nothing
/// when Android showed the app only some of the pictures, or none, so the
/// screenshots seemed to be missing. It says which, and offers the fix.
void main() {
  late _Storage storage;
  late _Library library;
  late List<int> scanned;

  Future<void> pump(
    WidgetTester tester, {
    required MediaPermission state,
    List<SourceSummary>? sources,
  }) async {
    storage = _Storage(state);
    library = _Library();
    scanned = [];
    final overrides = <Override>[
      storageProvider.overrideWithValue(storage),
      photoLibraryProvider.overrideWithValue(library),
      deviceMediaRescanProvider.overrideWithValue(scanned.add),
      sourceSummariesProvider.overrideWith(
        (ref) => Stream.value(sources ?? [_source('mediastore:///')]),
      ),
    ];
    await tester.pumpWidget(
      ProviderScope(
        overrides: overrides,
        child: MaterialApp(
          theme: MediahroTheme.build(
            const ThemeSpec(
              family: PlatformFamily.material,
              brightness: Brightness.light,
            ),
          ),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(body: PhotoAccessBanner()),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('IMG-016 full access shows no banner', (tester) async {
    await pump(tester, state: MediaPermission.granted);
    expect(find.byType(Material), findsWidgets);
    expect(find.text('Allow all'), findsNothing);
    expect(find.text('Allow access'), findsNothing);
  });

  testWidgets('IMG-016 refused access is said, and Allow asks again', (
    tester,
  ) async {
    await pump(tester, state: MediaPermission.denied);
    expect(
      find.text("Mediahro can't see the pictures on this device."),
      findsOneWidget,
    );

    await tester.tap(find.text('Allow access'));
    await tester.pumpAndSettle();

    expect(storage.requests, 1);
    expect(scanned, [1], reason: 'the device media are scanned again');
    expect(find.text('Allow access'), findsNothing, reason: 'now granted');
  });

  testWidgets('IMG-016 limited access offers more photos and all of them', (
    tester,
  ) async {
    await pump(tester, state: MediaPermission.limited);
    expect(
      find.text('Mediahro can see only the photos you selected.'),
      findsOneWidget,
    );

    await tester.tap(find.text('Select more'));
    await tester.pumpAndSettle();
    expect(library.selections, 1);
    expect(scanned, [1]);

    await tester.tap(find.text('Allow all'));
    await tester.pumpAndSettle();
    expect(storage.requests, 1);
    expect(scanned, [1, 1]);
  });

  testWidgets('IMG-016 without the device media source nothing is said', (
    tester,
  ) async {
    await pump(
      tester,
      state: MediaPermission.denied,
      sources: [_source('saf://tree/g1/')],
    );
    expect(find.text('Allow access'), findsNothing);
  });

  testWidgets('IMG-016 where there is no such permission nothing is said', (
    tester,
  ) async {
    await pump(tester, state: MediaPermission.notApplicable);
    expect(find.text('Allow access'), findsNothing);
    expect(find.text('Select more'), findsNothing);
  });

  test('IMG-016 the device media source is the MediaStore one', () {
    expect(
      deviceMediaSource([
        _source('saf://tree/g1/'),
        _source('mediastore:///', id: 2),
      ])?.source.id,
      2,
    );
    expect(deviceMediaSource([_source('saf://tree/g1/')]), isNull);
  });
}
