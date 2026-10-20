import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediahro/features/photos/map/map_licences.dart';

void main() {
  test('IMG-007 GeoNames and OpenStreetMap notices are in the licence list',
      () async {
    registerMapLicences();
    final entries = await LicenseRegistry.licenses.toList();
    String text(String package) => entries
        .where((e) => e.packages.contains(package))
        .expand((e) => e.paragraphs)
        .map((p) => p.text)
        .join('\n');
    expect(text('GeoNames'), contains('CC BY 4.0'));
    expect(text('OpenStreetMap'), contains('OpenStreetMap contributors'));
    expect(text('OpenStreetMap'), contains('ODbL'));
  });
}
