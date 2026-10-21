import 'package:flutter/foundation.dart';

/// Attribution for the data behind place names (IMG-007, CORE-013): GeoNames
/// for the bundled gazetteer. The licence requires the notice to be shown to
/// users.
const geoNamesNotice =
    'Contains data from GeoNames (https://www.geonames.org), licensed under '
    'the Creative Commons Attribution 4.0 International licence '
    '(CC BY 4.0, https://creativecommons.org/licenses/by/4.0/). The data was '
    'reduced to name, position, country and population and repacked into a '
    'binary file.';

/// Adds the GeoNames notice to the app's licence list.
/// Call once at start-up.
void registerMapLicences() {
  LicenseRegistry.addLicense(() async* {
    yield const LicenseEntryWithLineBreaks(['GeoNames'], geoNamesNotice);
  });
}
