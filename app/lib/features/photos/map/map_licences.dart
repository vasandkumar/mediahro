import 'package:flutter/foundation.dart';

/// Attribution for the data behind the photo map (IMG-007, CORE-013):
/// GeoNames for the bundled gazetteer, OpenStreetMap for the optional map
/// pictures. Both licences require the notice to be shown to users.
const geoNamesNotice =
    'Contains data from GeoNames (https://www.geonames.org), licensed under '
    'the Creative Commons Attribution 4.0 International licence '
    '(CC BY 4.0, https://creativecommons.org/licenses/by/4.0/). The data was '
    'reduced to name, position, country and population and repacked into a '
    'binary file.';

const openStreetMapNotice =
    'Map data © OpenStreetMap contributors, available under the Open '
    'Database Licence (ODbL, https://opendatacommons.org/licenses/odbl/). '
    'See https://www.openstreetmap.org/copyright.';

/// Adds the GeoNames and OpenStreetMap notices to the app's licence list.
/// Call once at start-up.
void registerMapLicences() {
  LicenseRegistry.addLicense(() async* {
    yield const LicenseEntryWithLineBreaks(['GeoNames'], geoNamesNotice);
    yield const LicenseEntryWithLineBreaks([
      'OpenStreetMap',
    ], openStreetMapNotice);
  });
}
