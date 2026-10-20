import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:meta/meta.dart';

/// A city of the offline gazetteer.
@immutable
final class GazetteerPlace {
  const GazetteerPlace({
    required this.name,
    required this.countryCode,
    required this.country,
    required this.latitude,
    required this.longitude,
    required this.population,
    required this.distanceKm,
  });

  final String name;
  final String countryCode;
  final String country;
  final double latitude;
  final double longitude;
  final int population;

  /// Distance from the point that was looked up.
  final double distanceKm;

  @override
  String toString() => '$name, $country (${distanceKm.toStringAsFixed(1)} km)';
}

/// Offline reverse geocoding (IMG-007): the nearest of ~32 000 cities of
/// 15 000 people or more, from the bundled GeoNames table (CC BY 4.0,
/// `assets/gazetteer`). No network request is ever made.
final class Gazetteer {
  Gazetteer._(
    this._data,
    this.length,
    this._countryCodes,
    this._countryNameAt,
    this._placesAt,
    this._namesAt,
  );

  /// Parses `places.bin` (layout in `tools/gazetteer/build_gazetteer.py`).
  factory Gazetteer.parse(Uint8List bytes) {
    if (bytes.length < 14 ||
        String.fromCharCodes(bytes.sublist(0, 4)) != 'MGZ1') {
      throw const FormatException('not a gazetteer file');
    }
    final d = ByteData.sublistView(bytes);
    final places = d.getUint32(4, Endian.little);
    final countries = d.getUint16(8, Endian.little);
    final namesLength = d.getUint32(10, Endian.little);
    var p = 14;
    if (p + countries * 6 + places * _recordSize + namesLength > bytes.length) {
      throw const FormatException('gazetteer is truncated');
    }
    final codes = <String>[];
    final nameAt = <int>[];
    for (var i = 0; i < countries; i++) {
      codes.add(String.fromCharCodes(bytes.sublist(p, p + 2)));
      nameAt.add(d.getUint32(p + 2, Endian.little));
      p += 6;
    }
    return Gazetteer._(d, places, codes, nameAt, p, p + places * _recordSize);
  }

  final ByteData _data;
  final int length;
  final List<String> _countryCodes;
  final List<int> _countryNameAt;
  final int _placesAt;
  final int _namesAt;
  final Map<int, String> _names = {};

  static const int _recordSize = 18;

  String _string(int offset) => _names[offset] ??= () {
    final bytes = _data.buffer.asUint8List(
      _data.offsetInBytes + _namesAt + offset,
    );
    final end = bytes.indexOf(0);
    return utf8.decode(end < 0 ? bytes : bytes.sublist(0, end));
  }();

  double _lat(int i) =>
      _data.getFloat32(_placesAt + i * _recordSize, Endian.little);
  double _lon(int i) =>
      _data.getFloat32(_placesAt + i * _recordSize + 4, Endian.little);

  GazetteerPlace _place(int i, double km) {
    final at = _placesAt + i * _recordSize;
    final country = _data.getUint16(at + 8, Endian.little);
    return GazetteerPlace(
      name: _string(_data.getUint32(at + 10, Endian.little)),
      countryCode: _countryCodes[country],
      country: _string(_countryNameAt[country]),
      latitude: _lat(i),
      longitude: _lon(i),
      population: _data.getUint32(at + 14, Endian.little),
      distanceKm: km,
    );
  }

  /// Great-circle distance in kilometres.
  static double distanceKm(double lat1, double lon1, double lat2, double lon2) {
    const r = 6371.0088;
    final p1 = lat1 * math.pi / 180;
    final p2 = lat2 * math.pi / 180;
    final dp = p2 - p1;
    final dl = (lon2 - lon1) * math.pi / 180;
    final a =
        math.pow(math.sin(dp / 2), 2) +
        math.cos(p1) * math.cos(p2) * math.pow(math.sin(dl / 2), 2);
    return 2 * r * math.asin(math.sqrt(a));
  }

  int _lowerBound(double lat) {
    var lo = 0;
    var hi = length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (_lat(mid) < lat) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return lo;
  }

  /// The city nearest to ([lat], [lon]) within [maxKm], or null (open sea,
  /// polar regions, far from any city of 15 000 people).
  GazetteerPlace? nearest(double lat, double lon, {double maxKm = 100}) {
    if (lat.isNaN || lon.isNaN || lat.abs() > 90 || lon.abs() > 180) {
      return null;
    }
    final degrees = maxKm / 110.5;
    var best = -1;
    var bestKm = maxKm;
    for (
      var i = _lowerBound(lat - degrees);
      i < length && _lat(i) <= lat + degrees;
      i++
    ) {
      final km = distanceKm(lat, lon, _lat(i), _lon(i));
      if (km <= bestKm) {
        bestKm = km;
        best = i;
      }
    }
    if (best < 0) {
      return null;
    }
    // In a big metropolis the nearest row is a ward or suburb; a photo is
    // better named after the city it is in: the most populous place within
    // a short drive, when it is much larger than the nearest one.
    var named = best;
    var namedKm = bestKm;
    var namedPopulation = _population(best);
    const nearDegrees = _cityRadiusKm / 110.5;
    for (
      var i = _lowerBound(lat - nearDegrees);
      i < length && _lat(i) <= lat + nearDegrees;
      i++
    ) {
      final population = _population(i);
      if (population <= namedPopulation) {
        continue;
      }
      final km = distanceKm(lat, lon, _lat(i), _lon(i));
      if (km <= math.min(_cityRadiusKm, maxKm)) {
        named = i;
        namedKm = km;
        namedPopulation = population;
      }
    }
    final nearestPopulation = _population(best);
    return _place(
      namedPopulation > nearestPopulation * 4 ? named : best,
      namedPopulation > nearestPopulation * 4 ? namedKm : bestKm,
    );
  }

  static const double _cityRadiusKm = 15;

  List<String>? _folded;

  /// Cities whose name starts with [query] (then those that contain it),
  /// biggest first; accents and case are ignored. For the location picker.
  List<GazetteerPlace> search(String query, {int limit = 8}) {
    final q = foldForSearch(query.trim());
    if (q.isEmpty) return const [];
    final names = _folded ??= [
      for (var i = 0; i < length; i++)
        foldForSearch(
          _string(
            _data.getUint32(_placesAt + i * _recordSize + 10, Endian.little),
          ),
        ),
    ];
    final starts = <int>[];
    final contains = <int>[];
    for (var i = 0; i < length; i++) {
      final n = names[i];
      if (n.startsWith(q)) {
        starts.add(i);
      } else if (n.contains(q)) {
        contains.add(i);
      }
    }
    int byPopulation(int a, int b) => _population(b).compareTo(_population(a));
    starts.sort(byPopulation);
    contains.sort(byPopulation);
    return [
      for (final i in [...starts, ...contains].take(limit)) _place(i, 0),
    ];
  }

  /// Lower case without the accents of European names ("São" → "sao").
  static String foldForSearch(String s) {
    final b = StringBuffer();
    for (final r in s.toLowerCase().runes) {
      b.write(_folds[r] ?? String.fromCharCode(r));
    }
    return b.toString();
  }

  static final Map<int, String> _folds = () {
    const groups = {
      'a': 'àáâãäåāăą',
      'c': 'çćčĉċ',
      'd': 'ďđ',
      'e': 'èéêëēĕėęě',
      'g': 'ĝğġģ',
      'h': 'ĥħ',
      'i': 'ìíîïĩīĭįı',
      'j': 'ĵ',
      'k': 'ķ',
      'l': 'ĺļľŀł',
      'n': 'ñńņňŉ',
      'o': 'òóôõöøōŏő',
      'r': 'ŕŗř',
      's': 'śŝşš',
      't': 'ţťŧ',
      'u': 'ùúûüũūŭůűų',
      'w': 'ŵ',
      'y': 'ýÿŷ',
      'z': 'źżž',
    };
    return {
      for (final e in groups.entries)
        for (final r in e.value.runes) r: e.key,
      'ß'.runes.first: 'ss',
      'æ'.runes.first: 'ae',
      'œ'.runes.first: 'oe',
    };
  }();

  int _population(int i) =>
      _data.getUint32(_placesAt + i * _recordSize + 14, Endian.little);
}
