import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mediahro/features/photos/map/gazetteer.dart';

void main() {
  late Gazetteer g;
  late List<int> bytes;

  setUpAll(() {
    bytes = File('assets/gazetteer/places.bin').readAsBytesSync();
    g = Gazetteer.parse(Uint8List.fromList(bytes));
  });

  test('IMG-007 the bundled table holds the larger cities of the world', () {
    expect(g.length, greaterThan(30000));
  });

  test('IMG-007 coordinates resolve to the right city and country', () {
    final cases = <(double, double, String, String)>[
      (12.9716, 77.5946, 'Bengaluru', 'India'),
      (48.8566, 2.3522, 'Paris', 'France'),
      (40.7128, -74.0060, 'New York City', 'United States'),
      (-33.8688, 151.2093, 'Sydney', 'Australia'),
      (35.6762, 139.6503, 'Tokyo', 'Japan'),
      (-23.5505, -46.6333, 'São Paulo', 'Brazil'),
      (55.7558, 37.6173, 'Moscow', 'Russia'),
    ];
    for (final (lat, lon, city, country) in cases) {
      final p = g.nearest(lat, lon);
      expect(p, isNotNull, reason: city);
      expect(p!.name, city);
      expect(p.country, country);
      expect(p.distanceKm, lessThan(25), reason: city);
    }
  });

  test('IMG-007 a photo in the countryside gets the nearest city', () {
    final p = g.nearest(51, 0)!;
    expect(p.country, 'United Kingdom');
    expect(p.distanceKm, lessThan(100));
  });

  test('IMG-007 open sea and the poles have no place', () {
    expect(g.nearest(0, -140), isNull);
    expect(g.nearest(-85, 0), isNull);
    expect(g.nearest(30, -40), isNull);
  });

  test('IMG-007 a larger radius finds more', () {
    expect(g.nearest(-20, -140), isNull);
    expect(g.nearest(-20, -140, maxKm: 4000), isNotNull);
  });

  test('IMG-007 invalid coordinates give nothing', () {
    expect(g.nearest(double.nan, 0), isNull);
    expect(g.nearest(91, 0), isNull);
    expect(g.nearest(0, 181), isNull);
  });

  test('IMG-007 places near the antimeridian are found', () {
    final p = g.nearest(-16.8, -179.9, maxKm: 300);
    expect(p, isNotNull);
    expect(p!.country, 'Fiji');
  });

  test('IMG-007 distances are great-circle', () {
    expect(Gazetteer.distanceKm(0, 0, 0, 1), closeTo(111.19, 0.1));
    expect(
      Gazetteer.distanceKm(48.8566, 2.3522, 51.5074, -0.1278),
      closeTo(343.6, 1),
    );
    expect(Gazetteer.distanceKm(10, 179.5, 10, -179.5), closeTo(109.5, 1));
  });

  test('IMG-007 damaged files are rejected', () {
    expect(
      () => Gazetteer.parse(Uint8List.fromList(bytes.sublist(0, 1000))),
      throwsFormatException,
    );
    expect(
      () => Gazetteer.parse(Uint8List.fromList('MGZ2 nope'.codeUnits)),
      throwsFormatException,
    );
  });

  group('search', () {
    test('IMG-007 a name is found without its accents', () {
      final hits = g.search('sao paulo');
      expect(hits, isNotEmpty);
      expect(hits.first.name, 'São Paulo');
      expect(hits.first.country, 'Brazil');
    });

    test('IMG-007 names starting with the text come first, biggest first', () {
      final hits = g.search('new y');
      expect(hits.first.name, 'New York City');
      final names = hits.map((p) => p.name).toList();
      expect(names.every((n) => n.toLowerCase().contains('new y')), isTrue);
    });

    test('IMG-007 a name that merely contains the text still matches', () {
      final hits = g.search('york');
      expect(hits.map((p) => p.name), contains('New York City'));
    });

    test('IMG-007 search is capped and ignores case and spaces around', () {
      expect(g.search('  PARIS  ', limit: 3), hasLength(3));
      expect(g.search('paris').first.name, 'Paris');
    });

    test('IMG-007 nothing typed or nothing found gives an empty list', () {
      expect(g.search(''), isEmpty);
      expect(g.search('   '), isEmpty);
      expect(g.search('qqqqzzzz'), isEmpty);
    });

    test('IMG-007 folding keeps plain letters and drops accents', () {
      expect(Gazetteer.foldForSearch('Zürich'), 'zurich');
      expect(Gazetteer.foldForSearch('Łódź'), 'lodz');
      expect(Gazetteer.foldForSearch('Straße'), 'strasse');
      expect(Gazetteer.foldForSearch('東京'), '東京');
    });
  });

  group('metropolitan areas', () {
    test('IMG-007 a photo in a big city is named after the city', () {
      for (final (lat, lon, city) in [
        (35.70, 139.60, 'Tokyo'),
        (28.60, 77.20, 'Delhi'),
        (40.75, -73.98, 'New York City'),
      ]) {
        expect(g.nearest(lat, lon)!.name, city, reason: '$lat, $lon');
      }
    });

    test('IMG-007 a small town next to a city keeps its own name', () {
      // Windsor, UK is 33 km from central London: not renamed to London.
      expect(g.nearest(51.4816, -0.6044)!.name, isNot('London'));
    });
  });
}
