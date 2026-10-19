import 'package:flutter_test/flutter_test.dart';
import 'package:mediahro_engine/mediahro_engine.dart';
import 'package:mediahro_engine/src/mpv/software_renderer.dart';

import 'support.dart';

/// SUB-010…016, engine rendering side: formats, image subtitles, external
/// lookup, charsets, styling, timing and dual subtitles.
void subtitlesSuite() {
  final skip = ffiSkipReason;
  prepareCorpus();

  /// Black video paused at [at] with [subtitle] loaded and selected.
  Future<MpvEngine> scene(
    String subtitle, {
    Duration at = const Duration(seconds: 1),
    SubtitleStyle? style,
  }) async {
    final e = headlessEngine(size: (640, 360));
    addTearDown(e.dispose);
    await e.open(
      UriSource(Uri.file(corpusPath('black.mkv'))),
      opts: const OpenOptions(autoplay: false),
    );
    await waitFor(e, (s) => s.status == PlaybackStatus.paused);
    await e.addExternalTrack(
      TrackType.subtitle,
      Uri.file(corpusPath(subtitle)),
    );
    if (style != null) await e.setSubtitleStyle(style);
    await e.seek(at, mode: SeekMode.exact);
    await waitFor(e, (s) => (s.position - at).inMilliseconds.abs() < 50);
    return e;
  }

  Future<String> subText(MpvEngine e) async {
    for (var i = 0; i < 40; i++) {
      final t = await prop(e, 'sub-text').catchError((Object _) => null);
      if (t is String && t.isNotEmpty) return t;
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    return '';
  }

  /// Bright pixels in the lower third of the latest frame (rendered text).
  Future<int> litPixels(MpvEngine e, {bool lowerThird = true}) async {
    final r = e.softwareRenderer!;
    // Force a redraw after the seek and use the newest frame.
    var frame = r.latest ?? await r.frames.first;
    for (var i = 0; i < 10; i++) {
      final next = await r.frames.first.timeout(
        const Duration(milliseconds: 300),
        onTimeout: () => frame,
      );
      frame = next;
      if (_count(frame, lowerThird: lowerThird) > 0) break;
    }
    return _count(frame, lowerThird: lowerThird);
  }

  group('SUB-010 text formats', () {
    for (final item in corpusItems(id: 'SUB-010')) {
      final expected = item.expect['subText'];
      if (expected is! String) continue;
      test('SUB-010 ${item.file} renders "$expected"', () async {
        final e = await scene(item.file);
        final text = await subText(e);
        expect(text.replaceAll('\n', ' '), contains(expected));
      }, skip: skip);
    }

    test('SUB-010 embedded Matroska fonts are used by libass', () async {
      final fonts = corpusItems(category: 'subtitle-fonts');
      if (fonts.length < 2) {
        markTestSkipped('no monospace font on the corpus host');
        return;
      }
      Future<int> width(String file) async {
        final e = headlessEngine(size: (640, 360));
        addTearDown(e.dispose);
        await e.open(
          UriSource(Uri.file(corpusPath(file))),
          opts: const OpenOptions(autoplay: false),
        );
        await waitFor(e, (s) => s.status == PlaybackStatus.paused);
        await e.seek(const Duration(seconds: 1), mode: SeekMode.exact);
        await waitFor(
          e,
          (s) => s.position >= const Duration(milliseconds: 950),
        );
        await litPixels(e);
        final f = e.softwareRenderer!.latest!;
        var minX = f.width;
        var maxX = -1;
        for (var y = f.height * 2 ~/ 3; y < f.height; y++) {
          for (var x = 0; x < f.width; x++) {
            final (r, g, b) = f.pixel(x, y);
            if (r > 150 || g > 150 || b > 150) {
              if (x < minX) minX = x;
              if (x > maxX) maxX = x;
            }
          }
        }
        return maxX - minX;
      }

      final embedded = await width('mkv_ass_fonts.mkv');
      final fallback = await width('mkv_ass_nofont.mkv');
      expect(embedded, greaterThan(0));
      // "iiii…" is wide in the embedded monospace face and narrow in any
      // proportional fallback.
      expect(
        (embedded - fallback).abs(),
        greaterThan(fallback ~/ 5),
        reason: 'embedded $embedded px vs fallback $fallback px',
      );
    }, skip: skip);

    test('SUB-010 ASS karaoke and animation render through libass', () async {
      final e = await scene('subs.ass');
      expect(await litPixels(e), greaterThan(50), reason: 'karaoke line');
      final top1 = await litPixels(e, lowerThird: false);
      await e.seek(const Duration(seconds: 3), mode: SeekMode.exact);
      await waitFor(e, (s) => s.position >= const Duration(milliseconds: 2950));
      final top3 = await litPixels(e, lowerThird: false);
      expect(top1, greaterThan(0));
      expect(top3, greaterThan(0));
    }, skip: skip);

    test('SUB-010 embedded tracks of every text codec load', () async {
      final e = await openItem('mkv_multitrack.mkv');
      final s = await waitPlaying(e);
      final subs = s.tracks.where((t) => t.type == TrackType.subtitle);
      expect(subs.map((t) => t.codec), containsAll(['subrip', 'ass']));
      expect(subs.firstWhere((t) => t.codec == 'ass').isForced, isTrue);
    }, skip: skip);
  });

  group('SUB-011 image formats', () {
    test('SUB-011 PGS (.sup) bitmap is drawn and cleared', () async {
      final e = await scene('subs.sup');
      expect(await litPixels(e), greaterThan(500), reason: '64×16 caption');
      await e.seek(const Duration(seconds: 3), mode: SeekMode.exact);
      await waitFor(e, (s) => s.position >= const Duration(milliseconds: 2950));
      expect(await litPixels(e), 0, reason: 'cleared at 2 s');
    }, skip: skip);

    for (final item in corpusItems(id: 'SUB-011')) {
      if (item.expect['video'] != 1) continue;
      test('SUB-011 ${item.file} decodes its bitmap track', () async {
        final e = await openItem(item.file);
        final s = await waitPlaying(e);
        final sub = s.tracks.where((t) => t.type == TrackType.subtitle);
        expect(sub.single.codec, (item.expect['subCodecs']! as List).first);
      }, skip: skip);
    }
  });

  group('SUB-012 embedded and external', () {
    test(
      'SUB-012 same-name, language-suffix and Subs/ files are found',
      () async {
        final e = headlessEngine();
        addTearDown(e.dispose);
        await e.open(UriSource(Uri.file(corpusPath('ext_subs/movie.mkv'))));
        final s = await waitPlaying(e);
        final external = s.tracks.where(
          (t) => t.type == TrackType.subtitle && t.isExternal,
        );
        expect(
          external.length,
          greaterThanOrEqualTo(3),
          reason: 'same name, language suffix and Subs/ folder',
        );
        expect(external.map((t) => t.language), containsAll(['en', 'fr']));
      },
      skip: skip,
    );

    test('SUB-012 any picked file can be added', () async {
      final e = await scene('subs.vtt');
      final s = e.current;
      final added = s.tracks.where((t) => t.isExternal).single;
      expect(s.subtitleTrackId, added.id, reason: 'added track is selected');
    }, skip: skip);
  });

  group('SUB-013 encoding detection', () {
    test('SUB-013 UTF-8 with BOM', () async {
      final e = await scene('subs_utf8bom.srt');
      expect(await subText(e), 'Привет, мир');
    }, skip: skip);

    test('SUB-013 Windows-1251 detected or forced', () async {
      final e = await scene('subs_cp1251.srt');
      var text = await subText(e);
      if (text != 'Привет, мир') {
        // Builds without uchardet need the manual override.
        await e.setSubtitleCodepage('cp1251');
        text = await subText(e);
      }
      expect(text, 'Привет, мир');
      await e.setSubtitleCodepage('cp1251');
      expect(await subText(e), 'Привет, мир', reason: 'manual override');
    }, skip: skip);
  });

  group('SUB-014 styling', () {
    test('SUB-014 colour, outline and position are applied', () async {
      final e = await scene(
        'subs.srt',
        style: const SubtitleStyle(
          colorArgb: 0xFFFF0000,
          outlineWidth: 0,
          shadowOffset: 0,
          scale: 2,
        ),
      );
      final r = e.softwareRenderer!;
      await litPixels(e);
      final f = r.latest!;
      var red = 0;
      var other = 0;
      for (var y = 0; y < f.height; y++) {
        for (var x = 0; x < f.width; x++) {
          final (rr, g, b) = f.pixel(x, y);
          if (rr > 150 && g < 80 && b < 80) red++;
          if (g > 150 || b > 150) other++;
        }
      }
      expect(red, greaterThan(100), reason: 'red text');
      expect(other, lessThan(red ~/ 4), reason: 'no white text left');
      // Move the line to the top of the frame.
      await e.setSubtitleStyle(const SubtitleStyle(verticalPosition: 90));
      await e.seek(const Duration(milliseconds: 1100), mode: SeekMode.exact);
      expect(await litPixels(e, lowerThird: false), greaterThan(0));
    }, skip: skip);

    test('SUB-014 ASS styles can be overridden', () async {
      final e = await scene(
        'subs.ass',
        style: const SubtitleStyle(overrideAssStyles: true),
      );
      expect(await prop(e, 'sub-ass-override'), 'force');
    }, skip: skip);
  });

  group('SUB-015 timing', () {
    test('SUB-015 delay shifts cues; ±60 s in 50 ms steps', () async {
      final e = await scene('subs.srt', at: const Duration(milliseconds: 1500));
      expect(await subText(e), 'Hello subtitle');
      await e.setSubDelay(const Duration(seconds: 2, milliseconds: 1));
      await waitFor(e, (s) => s.subtitleDelay == const Duration(seconds: 2));
      await e.seek(const Duration(milliseconds: 1600), mode: SeekMode.exact);
      expect(
        await prop(e, 'sub-text').catchError((Object _) => ''),
        '',
        reason: 'cue moved to 2.5 s',
      );
      await e.setSubDelay(const Duration(seconds: 90));
      await waitFor(e, (s) => s.subtitleDelay == const Duration(seconds: 60));
    }, skip: skip);

    test('SUB-015 speed converts frame-rate timing', () async {
      final e = await scene('subs.srt');
      await e.setSubSpeed(25 / 23.976);
      expect(await prop(e, 'sub-speed'), closeTo(1.0427, 0.001));
    }, skip: skip);
  });

  group('SUB-016 dual subtitles', () {
    test('SUB-016 secondary track with its own delay and text', () async {
      final e = await openItem(
        'mkv_multitrack.mkv',
        opts: const OpenOptions(autoplay: false),
      );
      await waitFor(e, (s) => s.status == PlaybackStatus.paused);
      final subs = e.current.tracks
          .where((t) => t.type == TrackType.subtitle)
          .toList();
      await e.selectTrack(TrackType.subtitle, subs[0].id);
      await e.selectTrack(
        TrackType.subtitle,
        subs[1].id,
        slot: SubtitleSlot.secondary,
      );
      await e.seek(const Duration(seconds: 1), mode: SeekMode.exact);
      final s = await waitFor(
        e,
        (s) =>
            s.secondarySubtitleTrackId == subs[1].id &&
            s.secondarySubtitleText != null,
        reason: 'secondary text',
      );
      expect(s.subtitleTrackId, subs[0].id);
      await e.setSubDelay(
        const Duration(milliseconds: 500),
        slot: SubtitleSlot.secondary,
      );
      final d = await waitFor(
        e,
        (s) => s.secondarySubtitleDelay == const Duration(milliseconds: 500),
      );
      expect(d.subtitleDelay, Duration.zero, reason: 'independent delays');
      await e.setSubtitleStyle(
        const SubtitleStyle(verticalPosition: 95),
        slot: SubtitleSlot.secondary,
      );
      expect(await prop(e, 'secondary-sub-pos'), anyOf(5, 5.0, '5'));
    }, skip: skip);
  });
}

int _count(SoftwareFrame f, {required bool lowerThird}) {
  final y0 = lowerThird ? f.height * 2 ~/ 3 : 0;
  final y1 = lowerThird ? f.height : f.height ~/ 3;
  var n = 0;
  for (var y = y0; y < y1; y++) {
    for (var x = 0; x < f.width; x++) {
      final (r, g, b) = f.pixel(x, y);
      if (r > 150 || g > 150 || b > 150) n++;
    }
  }
  return n;
}
