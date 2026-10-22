import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mediahro/features/video/subtitles/subtitle_sources.dart';

import '../../../integration_test/support/c1_player.dart';

List<int> _text(String s) => utf8.encode(s);

/// SUB-012 (hand check on the profile APK): "Add a subtitle file" would not
/// take a `.srt`. Providers report `.srt` as `application/x-subrip`,
/// `text/plain` or `application/octet-stream`, so the picker takes any file
/// and what was picked is checked by name and by content afterwards.
void main() {
  const srt = '1\n00:00:01,000 --> 00:00:02,000\nHello\n';

  group('SUB-012 a picked file is recognised as a subtitle', () {
    test('SUB-012 by its extension, whatever type the provider reported', () {
      for (final name in ['Film.srt', 'Film.en.ASS', 'x.vtt', 'a.ssa']) {
        expect(subtitleNameFor(name, _text('whatever')), name);
      }
    });

    test('SUB-012 by its content when the name has no known extension', () {
      expect(subtitleNameFor('Film', _text(srt)), 'Film.srt');
      expect(
        subtitleNameFor(
          'document',
          _text('WEBVTT\n\n00:01.000 --> 00:02.000\nHi'),
        ),
        'document.vtt',
      );
      expect(
        subtitleNameFor('Film.txt', _text(srt)),
        'Film.txt.srt',
        reason: 'the engine needs the right extension',
      );
      expect(subtitleNameFor('', _text(srt)), 'subtitle.srt');
    });

    test('SUB-012 a BOM and UTF-16 free text still sniffs', () {
      expect(
        subtitleNameFor('Film', [0xEF, 0xBB, 0xBF, ..._text(srt)]),
        'Film.srt',
      );
    });

    test('SUB-012 other files are not subtitles', () {
      expect(subtitleNameFor('notes.txt', _text('buy milk')), isNull);
      expect(subtitleNameFor('photo.jpg', List.filled(100, 0xFF)), isNull);
      expect(subtitleNameFor('Film', const []), isNull);
    });
  });

  playerTest('SUB-012 a pick that is not a subtitle says so', (tester) async {
    await pumpPlayer(
      tester,
      overrides: [
        subtitleFilePickerProvider.overrideWithValue(
          () async => throw const NotASubtitleFile('photo.jpg'),
        ),
      ],
    );
    await tester.tap(find.text('Subtitles'));
    await tester.pumpAndSettle();
    await tapVisible(tester, find.text('Add a subtitle file'));
    await tester.pumpAndSettle();

    expect(find.textContaining("doesn't look like a subtitle"), findsOneWidget);
  });

  playerTest('SUB-012 a pick that fails says so instead of doing nothing', (
    tester,
  ) async {
    await pumpPlayer(
      tester,
      overrides: [
        subtitleFilePickerProvider.overrideWithValue(
          () async => throw StateError('permission denied'),
        ),
      ],
    );
    await tester.tap(find.text('Subtitles'));
    await tester.pumpAndSettle();
    await tapVisible(tester, find.text('Add a subtitle file'));
    await tester.pumpAndSettle();

    expect(find.text("Couldn't add that subtitle file."), findsOneWidget);
  });
}
