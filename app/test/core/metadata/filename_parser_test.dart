import 'package:flutter_test/flutter_test.dart';
import 'package:mediahro/core/metadata/filename_parser.dart';

void main() {
  group('LIB-011 filename parser', () {
    final movies = <String, (String, int?)>{
      'The.Matrix.1999.1080p.BluRay.x264-GROUP.mkv': ('The Matrix', 1999),
      'Blade Runner 2049 (2017) 2160p UHD HDR.mkv': ('Blade Runner 2049', 2017),
      '2001.A.Space.Odyssey.1968.REMASTERED.mkv': (
        '2001 A Space Odyssey',
        1968,
      ),
      'Amélie (2001).mp4': ('Amélie', 2001),
      'Inception.mkv': ('Inception', null),
      'Spirited_Away_2001_720p.mp4': ('Spirited Away', 2001),
      'Parasite.2019.KOREAN.WEB-DL.1080p.H.264-RLS.mkv': ('Parasite', 2019),
      '1917.2019.1080p.mkv': ('1917', 2019),
      'home video.mov': ('home video', null),
    };
    for (final MapEntry(key: file, value: expected) in movies.entries) {
      test('movie: $file', () {
        final p = parseVideoFileName(file);
        expect((p.title, p.year), expected);
        expect(p.isEpisode, isFalse);
      });
    }

    test('release group is detected and ignored', () {
      final p = parseVideoFileName(
        'The.Matrix.1999.1080p.BluRay.x264-GROUP.mkv',
      );
      expect(p.releaseGroup, 'GROUP');
      expect(p.title, isNot(contains('GROUP')));
    });

    test('SxxEyy with episode title', () {
      final p = parseVideoFileName(
        'Breaking.Bad.S01E02.Cats.in.the.Bag.720p.HDTV.x264-RLS.mkv',
      );
      expect(p.title, 'Breaking Bad');
      expect(p.season, 1);
      expect(p.episode, 2);
      expect(p.episodeTitle, 'Cats in the Bag');
    });

    test('multi-episode file', () {
      final p = parseVideoFileName('Show.Name.S02E05E06.mkv');
      expect((p.season, p.episode, p.episodeEnd), (2, 5, 6));
      final q = parseVideoFileName('Show Name - S02E05-E07 - Finale.mkv');
      expect((q.season, q.episode, q.episodeEnd), (2, 5, 7));
    });

    test('1x02 numbering', () {
      final p = parseVideoFileName('Doctor Who 1x02 The End of the World.avi');
      expect((p.title, p.season, p.episode), ('Doctor Who', 1, 2));
    });

    test('series year before SxxEyy', () {
      final p = parseVideoFileName('Doctor.Who.2005.S03E08.mkv');
      expect(
        (p.title, p.year, p.season, p.episode),
        ('Doctor Who', 2005, 3, 8),
      );
    });

    test('anime absolute numbering with leading group', () {
      final p = parseVideoFileName('[SubGroup] Cowboy Bebop - 05 [1080p].mkv');
      expect(p.title, 'Cowboy Bebop');
      expect(p.absoluteEpisode, 5);
      expect(p.releaseGroup, 'SubGroup');
    });

    test('episode-only file name takes the series from folders', () {
      final p = parseVideoFileName(
        'S01E03.mkv',
        parentFolders: ['Season 1', 'The Expanse (2015)'],
      );
      expect((p.title, p.season, p.episode), ('The Expanse', 1, 3));
    });
  });

  test('LIB-001 clean and sort titles', () {
    expect(cleanTitle('my_holiday.video.mp4'), 'my holiday video');
    expect(sortTitle('The Matrix'), 'matrix');
    expect(sortTitle('A'), 'a');
  });
}
