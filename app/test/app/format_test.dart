import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediahro/app/format.dart';
import 'package:mediahro/app/l10n/gen/app_localizations.dart';
import 'package:mediahro/app/locales.dart';

void main() {
  Future<AppLocalizations> l10n(String tag) =>
      AppLocalizations.delegate.load(localeFromTag(tag)!);

  group('CORE-008 formatting helpers (docs/06 §8)', () {
    test('binary sizes with one decimal, numbers per locale', () async {
      final en = await l10n('en');
      expect(formatBytes(1, en), '1 byte');
      expect(formatBytes(912, en), '912 bytes');
      expect(formatBytes(1536, en), '1.5 KiB');
      expect(formatBytes(5 * 1024 * 1024, en), '5.0 MiB');
      expect(formatBytes(4 * 1024 * 1024 * 1024, en), '4.0 GiB');
      expect(formatBytes(3 * 1024 * 1024 * 1024 * 1024, en), '3.0 TiB');
      final de = await l10n('de');
      expect(formatBytes(1536, de), contains('1,5'));
    });

    test('durations as 1:23:45', () {
      expect(
        formatMediaDuration(const Duration(hours: 1, minutes: 23, seconds: 45)),
        '1:23:45',
      );
      expect(formatMediaDuration(const Duration(seconds: 65)), '1:05');
    });

    test('plural rules come from the ARB messages', () async {
      final en = await l10n('en');
      expect(en.appItemCount(0), 'No items');
      expect(en.appItemCount(1), '1 item');
      expect(en.appItemCount(5), '5 items');
    });

    test('launch languages and RTL locales resolve', () {
      for (final tag in appLanguageTags) {
        final l = localeFromTag(tag)!;
        expect(AppLocalizations.delegate.isSupported(l), isTrue, reason: tag);
      }
      expect(localeFromTag('zh-Hans')!.scriptCode, 'Hans');
      expect(localeFromTag('pt-BR')!.countryCode, 'BR');
      expect(localeFromTag(''), isNull);
      expect(isPseudoLocale(pseudoExpanded), isTrue);
      expect(
        AppLocalizations.supportedLocales,
        containsAll(<Locale>[pseudoExpanded, pseudoRtl]),
      );
    });
  });
}
