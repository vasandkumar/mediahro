import 'package:flutter_test/flutter_test.dart';
import 'package:mediahro/features/photos/map/geo_point.dart';

void main() {
  group('IMG-007 typed positions', () {
    void expectPos(String text, double lat, double lon) {
      final p = parsePosition(text);
      expect(p, isNotNull, reason: text);
      expect(p!.lat, closeTo(lat, 1e-9), reason: text);
      expect(p.lon, closeTo(lon, 1e-9), reason: text);
    }

    test('IMG-007 decimal degrees with a comma, semicolon or space', () {
      expectPos('48.8566, 2.3522', 48.8566, 2.3522);
      expectPos('48.8566;2.3522', 48.8566, 2.3522);
      expectPos('  -33.86   151.21 ', -33.86, 151.21);
      expectPos('12.5,-77.25', 12.5, -77.25);
    });

    test('IMG-007 hemisphere letters set the sign', () {
      expectPos('33.8688 S 151.2093 E', -33.8688, 151.2093);
      expectPos('33.8688S, 151.2093E', -33.8688, 151.2093);
      expectPos('N 40.7128 W 74.006', 40.7128, -74.006);
      expectPos('40.7128° N, 74.0060° W', 40.7128, -74.006);
    });

    test('IMG-007 text that is not a position is refused', () {
      for (final bad in [
        '',
        '  ',
        '48.85',
        '48.85, 2.35, 10',
        'Paris',
        '95, 10',
        '10, 181',
        '10 E 20 N',
        'N N 10 20',
        '10 20 S',
        'NaN, 1',
        'infinity 3',
      ]) {
        expect(parsePosition(bad), isNull, reason: bad);
      }
    });

    test('IMG-007 a camera with no GPS lock is not a real position', () {
      expect(isRealPosition(0, 0), isFalse);
      expect(isRealPosition(91, 0), isFalse);
      expect(isRealPosition(48.85, 2.35), isTrue);
      expect(isRealPosition(0, 12), isTrue);
    });
  });
}
