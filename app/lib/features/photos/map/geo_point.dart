/// A position on Earth.
typedef GeoPoint = ({double lat, double lon});

/// Whether [lat], [lon] is a real position. A (0, 0) fix is a camera that
/// had no GPS lock, not a photo of the Atlantic.
bool isRealPosition(double lat, double lon) =>
    lat.abs() <= 90 && lon.abs() <= 180 && !(lat == 0 && lon == 0);

/// Reads a position typed by a person: two decimal-degree numbers separated
/// by a comma, semicolon or space (`48.8566, 2.3522`, `48.8566 N 2.3522 E`,
/// `N 48.8566 E 2.3522`, `-33.86 151.21`). A letter N/S/E/W next to a number
/// sets the sign (S and W are negative). Null when the text is not a
/// position.
GeoPoint? parsePosition(String text) {
  final spaced = text
      .toUpperCase()
      .replaceAll('°', ' ')
      .replaceAll(RegExp('[,;]'), ' ')
      .replaceAllMapped(RegExp('([NSEW])'), (m) => ' ${m[1]} ')
      .trim();
  if (spaced.isEmpty) return null;
  final values = <double>[];
  final letters = <String?>[];
  String? pending;
  for (final t in spaced.split(RegExp(r'\s+'))) {
    if ('NSEW'.contains(t) && t.length == 1) {
      if (letters.isNotEmpty && letters.last == null && pending == null) {
        letters[letters.length - 1] = t;
      } else if (pending == null) {
        pending = t;
      } else {
        return null;
      }
      continue;
    }
    final n = double.tryParse(t);
    if (n == null || !n.isFinite) return null;
    values.add(n);
    letters.add(pending);
    pending = null;
  }
  if (values.length != 2 || pending != null) return null;
  double signed(int i, String ok) {
    final l = letters[i];
    if (l == null) return values[i];
    if (!ok.contains(l)) return double.nan;
    return values[i].abs() * (l == 'S' || l == 'W' ? -1 : 1);
  }

  final lat = signed(0, 'NS');
  final lon = signed(1, 'EW');
  if (lat.isNaN || lon.isNaN || lat.abs() > 90 || lon.abs() > 180) return null;
  return (lat: lat, lon: lon);
}
