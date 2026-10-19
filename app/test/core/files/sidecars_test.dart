import 'package:flutter_test/flutter_test.dart';
import 'package:mediahro/core/files/sidecars.dart';

void main() {
  const siblings = [
    'Movie (2024).mkv',
    'Movie (2024).srt',
    'Movie (2024).en.srt',
    'Movie (2024).pt-BR.forced.ass',
    'Movie (2024).English.SDH.srt',
    'Movie (2024).zh-hans.Commentary.vtt',
    'Movie (2024).ac3',
    'Movie (2024).nfo',
    'Movie (2024)-poster.jpg',
    'Movie (2024) Part 2.mkv',
    'Other.en.srt',
  ];

  test(
    'FILE-006 sidecars are matched by name with language, forced and SDH flags',
    () {
      final s = {
        for (final x in findSidecars('Movie (2024).mkv', siblings)) x.name: x,
      };
      expect(s.keys.toSet(), {
        'Movie (2024).srt',
        'Movie (2024).en.srt',
        'Movie (2024).pt-BR.forced.ass',
        'Movie (2024).English.SDH.srt',
        'Movie (2024).zh-hans.Commentary.vtt',
        'Movie (2024).ac3',
        'Movie (2024).nfo',
        'Movie (2024)-poster.jpg',
      });
      expect(s['Movie (2024).en.srt']!.language, 'en');
      expect(
        s['Movie (2024).pt-BR.forced.ass'],
        const Sidecar(
          'Movie (2024).pt-BR.forced.ass',
          SidecarKind.subtitle,
          language: 'pt-BR',
          forced: true,
        ),
      );
      expect(s['Movie (2024).English.SDH.srt']!.language, 'en');
      expect(s['Movie (2024).English.SDH.srt']!.sdh, isTrue);
      expect(s['Movie (2024).zh-hans.Commentary.vtt']!.language, 'zh-Hans');
      expect(s['Movie (2024).zh-hans.Commentary.vtt']!.title, 'Commentary');
      expect(s['Movie (2024).ac3']!.kind, SidecarKind.audio);
      expect(s['Movie (2024).nfo']!.kind, SidecarKind.nfo);
      expect(s['Movie (2024)-poster.jpg']!.kind, SidecarKind.artwork);
    },
  );

  test('FILE-006 renaming a video renames its sidecars with it', () {
    expect(renameSidecars('Movie (2024).mkv', 'Film.mkv', siblings), {
      'Movie (2024).srt': 'Film.srt',
      'Movie (2024).en.srt': 'Film.en.srt',
      'Movie (2024).pt-BR.forced.ass': 'Film.pt-BR.forced.ass',
      'Movie (2024).English.SDH.srt': 'Film.English.SDH.srt',
      'Movie (2024).zh-hans.Commentary.vtt': 'Film.zh-hans.Commentary.vtt',
      'Movie (2024).ac3': 'Film.ac3',
      'Movie (2024).nfo': 'Film.nfo',
      'Movie (2024)-poster.jpg': 'Film-poster.jpg',
    });
  });
}
