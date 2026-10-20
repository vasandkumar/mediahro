# Offline gazetteer (IMG-007)

`places.bin` lets the app name the place a photo was taken without any network
request (reverse geocoding on the device). It holds the the cities with a
population of 15 000 or more, with country, position and population.

- **Source:** GeoNames `cities15000.txt` and `countryInfo.txt`,
  <https://download.geonames.org/export/dump/> (fetched 2026-10-21).
- **Licence:** Creative Commons Attribution 4.0 International
  (<https://creativecommons.org/licenses/by/4.0/>). Attribution required: the
  app's licences screen shows "Contains data from GeoNames (geonames.org),
  CC BY 4.0".
- **Changes:** reduced to the columns name, position, country and population and
  packed into the binary layout documented in `tools/gazetteer/build_gazetteer.py`,
  which rebuilds the file from the two GeoNames files.
- The licence scan treats this directory as data (not code); it is a CC BY
  data licence, compatible with the app's licence policy (docs/09).
