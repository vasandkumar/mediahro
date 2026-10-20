#!/usr/bin/env python3
"""Builds app/assets/gazetteer/places.bin from GeoNames cities15000.txt.

Offline reverse geocoding for the photo map and Places (IMG-007): every city
of 15 000 people or more (about 34 000), as a compact binary table the app
searches by distance. Data: GeoNames (https://www.geonames.org), licence
CC BY 4.0; the attribution is shown in the app's licences and recorded in
app/assets/gazetteer/README.md.

    python tools/gazetteer/build_gazetteer.py cities15000.txt countryInfo.txt \
        app/assets/gazetteer/places.bin

Layout (little endian):
  magic 'MGZ1' | u32 places | u16 countries | u32 namesLength
  countries:  code[2] | u32 nameOffset            (countries entries)
  places:     f32 lat | f32 lon | u16 country | u32 nameOffset | u32 population
  names:      NUL-terminated UTF-8 strings
"""
import re
import struct
import sys


def main(cities, countries, out):
    names = bytearray()
    offsets = {}

    def name(s):
        if s not in offsets:
            offsets[s] = len(names)
            names.extend(s.encode("utf-8") + b"\0")
        return offsets[s]

    country_rows = []
    index = {}
    with open(countries, encoding="utf-8") as f:
        for line in f:
            if line.startswith("#") or not line.strip():
                continue
            cols = line.rstrip("\n").split("\t")
            code, cname = cols[0], cols[4]
            index[code] = len(country_rows)
            country_rows.append((code, name(cname)))

    rows = []
    with open(cities, encoding="utf-8") as f:
        for line in f:
            c = line.rstrip("\n").split("\t")
            # PPLX is a section of a city; the city itself is in the table.
            if c[8] in index and c[7] != "PPLX":
                rows.append(c)
    # Districts numbered after their city ("Paris 04 Hôtel-de-Ville") would
    # name a photo by one arrondissement; the city row stands for them all.
    cities_by_country = {(c[8], c[1]) for c in rows}
    district = re.compile(r"^(.+?) \d{1,2}(?: .*)?$")
    places = []
    for c in rows:
        m = district.match(c[1])
        if m and (c[8], m.group(1)) in cities_by_country:
            continue
        places.append(
            (float(c[4]), float(c[5]), index[c[8]], name(c[1]), int(c[14] or 0))
        )
    places.sort(key=lambda p: (p[0], p[1]))

    with open(out, "wb") as f:
        f.write(b"MGZ1")
        f.write(struct.pack("<IHI", len(places), len(country_rows), len(names)))
        for code, off in country_rows:
            f.write(code.encode("ascii") + struct.pack("<I", off))
        for lat, lon, ci, off, pop in places:
            f.write(struct.pack("<ffHII", lat, lon, ci, off, pop))
        f.write(bytes(names))
    print(f"{len(places)} places, {len(country_rows)} countries, {len(names)} name bytes")


if __name__ == "__main__":
    if len(sys.argv) != 4:
        sys.exit(__doc__)
    main(*sys.argv[1:])
