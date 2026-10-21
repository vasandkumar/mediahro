import 'package:flutter_test/flutter_test.dart';
import 'package:mediahro/features/photos/archive/comic_order.dart';

void main() {
  group('IMG-017 which entries are pages', () {
    test('IMG-017 pictures are pages whatever the case of the ending', () {
      for (final p in ['a.jpg', 'dir/b.PNG', 'c.Webp', 'd.avif', 'e.jpeg']) {
        expect(isPagePath(p), isTrue, reason: p);
      }
    });

    test('IMG-017 other files are not pages', () {
      for (final p in [
        'ComicInfo.xml',
        'readme.txt',
        'noending',
        'dir/',
        '',
        'archive.zip',
      ]) {
        expect(isPagePath(p), isFalse, reason: p);
      }
    });

    test(
      'IMG-017 hidden files, resource forks and thumbnail caches are skipped',
      () {
        expect(isPagePath('.hidden.jpg'), isFalse);
        expect(isPagePath('dir/.hidden/a.jpg'), isFalse);
        expect(isPagePath('__MACOSX/dir/._a.jpg'), isFalse);
        expect(isPagePath('dir/Thumbs.db'), isFalse);
        expect(isPagePath('dir/thumbs.db'), isFalse);
      },
    );
  });

  group('IMG-017 reading order', () {
    test('IMG-017 numbers compare as numbers', () {
      expect(naturalCompare('page2.jpg', 'page10.jpg') < 0, isTrue);
      expect(naturalCompare('page10.jpg', 'page2.jpg') > 0, isTrue);
      expect(naturalCompare('p1.jpg', 'p1.jpg'), 0);
    });

    test('IMG-017 case does not matter', () {
      expect(naturalCompare('B.jpg', 'a.jpg') > 0, isTrue);
      expect(naturalCompare('A.jpg', 'a.jpg'), 0);
    });

    test('IMG-017 leading zeros do not change the order', () {
      expect(naturalCompare('001.jpg', '2.jpg') < 0, isTrue);
      expect(naturalCompare('010.jpg', '9.jpg') > 0, isTrue);
      expect(naturalCompare('007.jpg', '7.jpg') != 0, isTrue);
    });

    test('IMG-017 a prefix comes first', () {
      expect(naturalCompare('a', 'a1') < 0, isTrue);
      expect(naturalCompare('a1', 'a') > 0, isTrue);
    });

    test('IMG-017 pages come folder by folder, in order', () {
      final out = orderedPages([
        'ch2/10.jpg',
        'ch1/2.jpg',
        'ch2/2.jpg',
        'ch1/10.jpg',
        'ch1/1.jpg',
        'ComicInfo.xml',
        '__MACOSX/ch1/._1.jpg',
        'cover.jpg',
      ]);
      expect(out, [
        'ch1/1.jpg',
        'ch1/2.jpg',
        'ch1/10.jpg',
        'ch2/2.jpg',
        'ch2/10.jpg',
        'cover.jpg',
      ]);
    });

    test('IMG-017 an archive of non-pictures has no pages', () {
      expect(orderedPages(['a.txt', 'b.xml']), isEmpty);
    });
  });
}
