import 'package:mediahro_subtitles/mediahro_subtitles.dart';
import 'package:test/test.dart';

void main() {
  group('SUB-012 sidecar matching', () {
    const video = 'The.Film.2024.1080p.mkv';

    List<SidecarMatch> m(List<String> names, {String folder = ''}) =>
        matchSidecars(video, [for (final n in names) (folder, n)]);

    test('SUB-012 same name, with and without a language suffix', () {
      final r = m([
        'The.Film.2024.1080p.srt',
        'The.Film.2024.1080p.en.srt',
        'The.Film.2024.1080p.ger.ass',
        'The.Film.2024.1080p.French.vtt',
        'Other.Film.srt',
        'The.Film.2024.1080p.mkv',
        'notes.txt',
      ]);
      expect(r.map((x) => x.name), [
        'The.Film.2024.1080p.srt',
        'The.Film.2024.1080p.en.srt',
        'The.Film.2024.1080p.ger.ass',
        'The.Film.2024.1080p.French.vtt',
      ]);
      expect(r.map((x) => x.language), [null, 'en', 'de', 'fr']);
    });

    test('SUB-012 forced and hearing-impaired flags', () {
      final r = m([
        'The.Film.2024.1080p.eng.forced.srt',
        'The.Film.2024.1080p.en.sdh.srt',
        'The.Film.2024.1080p.en.cc.srt',
      ]);
      expect(r[0].forced, isTrue);
      expect(r[0].language, 'en');
      expect(r[1].hearingImpaired, isTrue);
      expect(r[2].hearingImpaired, isTrue);
    });

    test('SUB-012 a Subs folder: everything in it belongs to the video', () {
      final r = matchSidecars(video, [
        ('Subs', '2_English.srt'),
        ('Subs', '3_Spanish.srt'),
        ('Subs/The.Film.2024.1080p', '4_Japanese.ass'),
        ('Subs/Other.Film', '2_English.srt'),
      ]);
      expect(r.map((x) => x.path), [
        'Subs/2_English.srt',
        'Subs/3_Spanish.srt',
        'Subs/The.Film.2024.1080p/4_Japanese.ass',
      ]);
      expect(r.map((x) => x.language), ['en', 'es', 'ja']);
    });

    test('SUB-012 matching ignores case; VobSub pairs keep the .idx', () {
      final r = m([
        'the.film.2024.1080p.SRT',
        'The.Film.2024.1080p.idx',
        'The.Film.2024.1080p.sub',
      ]);
      expect(r.map((x) => x.name), [
        'the.film.2024.1080p.SRT',
        'The.Film.2024.1080p.idx',
      ]);
      expect(r.last.companions, ['The.Film.2024.1080p.sub']);
    });

    test('SUB-012 a lone .sub is MicroDVD text', () {
      final r = m(['The.Film.2024.1080p.sub']);
      expect(r.single.format, SubtitleFormat.microDvd);
      expect(r.single.companions, isEmpty);
    });

    test('SUB-012 isSubtitleName knows every supported extension', () {
      for (final e in [
        'srt', 'ass', 'ssa', 'vtt', 'sub', 'idx', 'sup', 'smi', 'ttml', //
        'dfxp', 'lrc',
      ]) {
        expect(isSubtitleName('x.$e'), isTrue, reason: e);
      }
      expect(isSubtitleName('x.mkv'), isFalse);
      expect(isSubtitleName('x.txt'), isFalse, reason: 'too generic alone');
    });
  });

  test('SUB-012 the language in a file name', () {
    expect(languageOfName('Film.en.srt'), 'en');
    expect(languageOfName('Film.2024.English.forced.ass'), 'en');
    expect(languageOfName('Film.ger.sdh.srt'), 'de');
    expect(languageOfName('Film.srt'), isNull);
  });
}
