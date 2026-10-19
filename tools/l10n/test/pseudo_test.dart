import 'package:test/test.dart';

import '../pseudo.dart';

void main() {
  group('CORE-008 pseudo-locale', () {
    test('accents letters, pads about 40 % and brackets the message', () {
      final p = pseudoExpand('Open a file');
      expect(p, startsWith('[Öþéñ á ƒîļé'));
      expect(p, endsWith(']'));
      expect(p.length, greaterThanOrEqualTo('Open a file'.length * 1.4));
    });

    test('keeps placeholders and ICU structure', () {
      const m =
          '{count, plural, =0{No items} =1{1 item} other{{count} items in {place}}}';
      final p = pseudoExpand(m);
      expect(p, contains('{count, plural, =0{Ñö îţéɱš}'));
      expect(p, contains('other{{count} îţéɱš îñ {place}}'));
      expect(placeholdersOf(m), {'count', 'place'});
    });

    test('keeps # in plural cases and select selectors', () {
      expect(
        pseudoExpand('{n, plural, other{# files}}'),
        contains('other{# ƒîļéš}'),
      );
      expect(
        pseudoExpand('{g, select, male{He} other{They}}'),
        contains('male{Ĥé} other{Ţĥéý}'),
      );
    });

    test('RTL pseudo wraps each word in RLO/PDF and keeps placeholders', () {
      expect(pseudoRtl('Hello {name}'), '\u202EHello\u202C {name}');
    });

    test('reports malformed ICU', () {
      expect(icuError('Hello {name'), isNotNull);
      expect(icuError('Hello name}'), isNotNull);
      expect(icuError('{n, plural, }'), isNotNull);
      expect(icuError('{n, bogus, other{x}}'), isNotNull);
      expect(icuError('{n, plural, =1{one} other{many}}'), isNull);
    });
  });
}
