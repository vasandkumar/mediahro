// Lane C3 device batch, places (IMG-007): the bundled gazetteer is packaged
// in the APK and names places, and the location chooser finds a city in it
// and takes typed coordinates on the Samsung. Needs `assets/gazetteer/` in
// app/pubspec.yaml.
//
//   flutter test integration_test/c3_places_test.dart -d <serial> --no-dds \
//     -P kotlin.incremental=false
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mediahro/app/l10n/gen/app_localizations.dart';
import 'package:mediahro/features/photos/map/gazetteer.dart';
import 'package:mediahro/features/photos/map/gazetteer_providers.dart';
import 'package:mediahro/features/photos/map/location_picker.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('IMG-007 the gazetteer is packaged and names places', (
    tester,
  ) async {
    final data = await rootBundle.load(gazetteerAsset);
    final g = Gazetteer.parse(
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
    );
    expect(g.length, greaterThan(30000));
    expect(g.nearest(12.9716, 77.5946)!.name, 'Bengaluru');
    expect(g.nearest(48.8566, 2.3522)!.country, 'France');
    expect(g.search('zurich').first.country, 'Switzerland');
  });

  testWidgets('IMG-007 the chooser finds a city and takes typed coordinates', (
    tester,
  ) async {
    PickedLocation? result;
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: FilledButton(
                  onPressed: () async => result = await pickLocation(context),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    // The gazetteer loads from the asset bundle.
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      if (find.byType(TextField).evaluate().length == 2) break;
    }
    await tester.enterText(find.byType(TextField).first, 'zurich');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Switzerland').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Use this location'));
    await tester.pumpAndSettle();
    expect(result!.lat, closeTo(47.37, 0.3));
    expect(result!.lon, closeTo(8.54, 0.3));

    result = null;
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, '35.6762, 139.6503');
    await tester.pump();
    await tester.tap(find.text('Use this location'));
    await tester.pumpAndSettle();
    expect(result!.lat, closeTo(35.6762, 1e-6));
    expect(result!.lon, closeTo(139.6503, 1e-6));
  });
}
