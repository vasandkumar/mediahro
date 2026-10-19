import 'package:intl/intl.dart';
import 'package:mediahro/app/l10n/gen/app_localizations.dart';

export 'package:mediahro_design/mediahro_design.dart'
    show formatMediaDuration, formatRemaining;

/// File sizes in binary units with one decimal, numbers per locale
/// (docs/06 §8): `912 bytes`, `1.5 KiB`, `4.0 GiB`, `1,5 GiB` in German.
String formatBytes(int bytes, AppLocalizations l10n) {
  if (bytes < 1024) return l10n.appSizeBytes(bytes);
  final number = NumberFormat.decimalPatternDigits(
    locale: l10n.localeName,
    decimalDigits: 1,
  );
  var value = bytes / 1024;
  var unit = 0;
  while (value >= 1024 && unit < 3) {
    value /= 1024;
    unit++;
  }
  final v = number.format(value);
  return switch (unit) {
    0 => l10n.appSizeKiB(v),
    1 => l10n.appSizeMiB(v),
    2 => l10n.appSizeGiB(v),
    _ => l10n.appSizeTiB(v),
  };
}

/// Locale-formatted integer (`12,345`, `12.345`, `12 345`).
String formatCount(int n, AppLocalizations l10n) =>
    NumberFormat.decimalPattern(l10n.localeName).format(n);
