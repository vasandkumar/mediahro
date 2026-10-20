import 'dart:convert';
import 'dart:typed_data';

import 'package:mediahro_subtitles/mediahro_subtitles.dart';
import 'package:test/test.dart';

const _srt =
    '﻿1\r\n00:00:01,000 --> 00:00:02,500\r\nHello\r\n<i>world</i>\r\n\r\n'
    '2\n00:00:03,000 --> 00:00:04,000\nSecond\n\n'
    '3\n0:00:05.5 --> 00:00:06,000\nLoose times\n';

const _vtt =
    'WEBVTT - title\n\nNOTE a comment\nspanning lines\n\n'
    'intro\n00:01.000 --> 00:02.000 align:start line:10%\nHi\n\n'
    '01:00:00.000 --> 01:00:01.500\nAn hour in\n';

const _ass = r'''
[Script Info]
ScriptType: v4.00+
PlayResX: 1280

[V4+ Styles]
Format: Name, Fontname, Fontsize
Style: Default,Arial,40

[Events]
Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text
Comment: 0,0:00:00.00,0:00:01.00,Default,,0,0,0,,ignored
Dialogue: 1,0:00:01.50,0:00:03.25,Default,Bob,0,0,10,,{\i1}Hi,{\i0} there\Nfriend
''';

Duration ms(int v) => Duration(milliseconds: v);

void main() {
  group('SUB-030 parsers', () {
    test('SUB-030 SRT: BOM, CRLF, markup and loose times', () {
      final d = const SrtParser().parse(_srt);
      expect(d.cues, hasLength(3));
      expect(d.cues[0].start, ms(1000));
      expect(d.cues[0].end, ms(2500));
      expect(d.cues[0].text, 'Hello\n<i>world</i>');
      expect(d.cues[0].plainText, 'Hello\nworld');
      expect(d.cues[2].start, ms(5500));
    });

    test('SUB-030 WebVTT: header, notes, ids and settings', () {
      final d = const WebVttParser().parse(_vtt);
      expect(d.cues, hasLength(2));
      expect(d.cues[0].extra, {
        'id': 'intro',
        'settings': 'align:start line:10%',
      });
      expect(d.cues[1].start, const Duration(hours: 1));
      expect(
        () => const WebVttParser().parse('1\n00:01.000 --> 00:02.000\nx'),
        throwsA(isA<SubtitleParseException>()),
      );
    });

    test('SUB-030 ASS: fields, commas in text, comments skipped', () {
      final d = const AssParser().parse(_ass);
      expect(d.format, SubtitleFormat.ass);
      final c = d.cues.single;
      expect(c.start, ms(1500));
      expect(c.end, ms(3250));
      expect(c.style, 'Default');
      expect(c.text, r'{\i1}Hi,{\i0} there\Nfriend');
      expect(c.plainText, 'Hi, there\nfriend');
      expect(c.extra['Name'], 'Bob');
      expect(c.extra['Layer'], '1');
      expect(d.header, contains('PlayResX: 1280'));
    });

    test('SUB-030 MicroDVD: frames with the frame-rate line', () {
      final d = const MicroDvdParser().parse(
        '{1}{1}25.000\n{25}{50}One|Two\n{75}{100}Three',
      );
      expect(d.cues.first.start, const Duration(seconds: 1));
      expect(d.cues.first.end, const Duration(seconds: 2));
      expect(d.cues.first.text, 'One\nTwo');
    });

    test('SUB-030 LRC: several stamps on one line, ends at the next', () {
      final d = const LrcParser().parse(
        '[ar:Someone]\n[00:01.00][00:05.50]Chorus\n[00:03.00]Verse\n',
      );
      expect(d.cues.map((c) => c.text), ['Chorus', 'Verse', 'Chorus']);
      expect(d.cues[0].end, ms(3000));
      expect(d.cues[2].start, ms(5500));
    });

    test('SUB-030 SAMI: syncs, breaks and entities', () {
      final d = const SamiParser().parse(
        '<SAMI><BODY><SYNC Start=1000><P Class=ENCC>Tom &amp; Jerry<br>run '
        '<SYNC Start=3000><P Class=ENCC>&nbsp;</BODY></SAMI>',
      );
      expect(d.cues.single.text, 'Tom & Jerry\nrun');
      expect(d.cues.single.end, ms(3000));
    });

    test('SUB-030 format sniffing', () {
      expect(sniffSubtitleFormat(_srt), SubtitleFormat.srt);
      expect(sniffSubtitleFormat(_vtt), SubtitleFormat.webvtt);
      expect(sniffSubtitleFormat(_ass), SubtitleFormat.ass);
      expect(sniffSubtitleFormat('{1}{25}x'), SubtitleFormat.microDvd);
      expect(sniffSubtitleFormat('[00:01.00]x'), SubtitleFormat.lrc);
      expect(sniffSubtitleFormat('hello'), isNull);
    });
  });

  group('SUB-030 save as SRT, ASS, VTT', () {
    test('SUB-030 SRT round-trips', () {
      final d = const SrtParser().parse(_srt);
      final again = const SrtParser().parse(const SrtParser().write(d));
      expect(again.cues, d.cues);
    });

    test('SUB-030 ASS round-trips its header and fields', () {
      final d = const AssParser().parse(_ass);
      final written = const AssParser().write(d);
      expect(written, contains('PlayResX: 1280'));
      final again = const AssParser().parse(written);
      expect(again.cues.single.text, d.cues.single.text);
      expect(again.cues.single.extra['Name'], 'Bob');
    });

    test('SUB-030 converting keeps italics and line breaks', () {
      final srt = const SrtParser().parse(_srt);
      final ass = const AssParser().write(srt);
      expect(ass, contains(r'Hello\N{\i1}world{\i0}'));
      expect(ass, contains('Style: Default'));
      final fromAss = const SrtParser().write(const AssParser().parse(_ass));
      expect(fromAss, contains('<i>Hi,</i> there\nfriend'));
      final vtt = const WebVttParser().write(srt);
      expect(vtt, startsWith('WEBVTT'));
      expect(vtt, contains('00:00:01.000 --> 00:00:02.500'));
      expect(const WebVttParser().parse(vtt).cues, hasLength(3));
    });
  });

  group('SUB-030 editing', () {
    final doc = const SrtParser().parse(_srt);

    test('SUB-030 shift all or a range; never below zero', () {
      expect(doc.shift(ms(500)).cues.first.start, ms(1500));
      final back = doc.shift(-ms(2000));
      expect(back.cues.first.start, Duration.zero);
      final range = doc.shift(ms(1000), from: 1, to: 1);
      expect(range.cues[0].start, ms(1000));
      expect(range.cues[1].start, ms(4000));
    });

    test('SUB-030 resync by two points fixes offset and drift', () {
      final fixed = doc.resync(
        from1: ms(1000),
        to1: ms(2000),
        from2: ms(5500),
        to2: ms(7000),
      );
      expect(fixed.cues[0].start, ms(2000));
      expect(fixed.cues[2].start, ms(7000));
      // 3000 → 2000 + 2000 * 5000/4500
      expect(fixed.cues[1].start.inMilliseconds, closeTo(4222, 1));
    });

    test('SUB-030 frame-rate stretch', () {
      final s = doc.stretch(25 / 23.976);
      expect(s.cues.first.start.inMilliseconds, closeTo(1043, 1));
    });

    test('SUB-030 split and merge', () {
      final split = doc.split(0, ms(2000));
      expect(split.cues, hasLength(4));
      expect(split.cues[0].text, 'Hello');
      expect(split.cues[1].text, '<i>world</i>');
      expect(split.cues[1].start, ms(2000));
      final merged = split.merge(0, 1);
      expect(merged.cues.first.text, 'Hello\n<i>world</i>');
      expect(merged.cues.first.end, ms(2500));
      expect(doc.split(0, ms(9000)), same(doc), reason: 'outside the cue');
    });

    test('SUB-030 overlaps are trimmed', () {
      final d = SubtitleDocument(
        format: SubtitleFormat.srt,
        cues: [
          SubtitleCue(start: ms(0), end: ms(3000), text: 'a'),
          SubtitleCue(start: ms(2000), end: ms(4000), text: 'b'),
        ],
      ).fixOverlaps();
      expect(d.cues.first.end, ms(2000));
      expect(d.cueAt(ms(2500)), 1);
    });
  });

  group('SUB-013 SUB-030 encodings', () {
    test('SUB-030 BOMs and strict UTF-8 first', () {
      expect(
        decodeSubtitleText(Uint8List.fromList([0xEF, 0xBB, 0xBF, 0x41])),
        'A',
      );
      expect(
        decodeSubtitleText(Uint8List.fromList([0xFF, 0xFE, 0x41, 0x00])),
        'A',
      );
      expect(
        decodeSubtitleText(Uint8List.fromList(utf8.encode('Привет'))),
        'Привет',
      );
    });

    test('SUB-030 fix encoding: Windows-1251, KOI8-R, fallback', () {
      final cp1251 = Uint8List.fromList([0xCF, 0xF0, 0xE8, 0xE2, 0xE5, 0xF2]);
      expect(decodeSubtitleText(cp1251, charset: 'cp1251'), 'Привет');
      expect(decodeSubtitleText(cp1251, charset: 'windows-1251'), 'Привет');
      final koi = Uint8List.fromList([0xF0, 0xD2, 0xC9, 0xD7, 0xC5, 0xD4]);
      expect(decodeSubtitleText(koi, charset: 'koi8-r'), 'Привет');
      expect(
        decodeSubtitleText(Uint8List.fromList([0xE9])),
        'é',
        reason: 'invalid UTF-8 falls back to Windows-1252',
      );
      expect(
        () => decodeWith(cp1251, 'x-unknown'),
        throwsA(isA<SubtitleParseException>()),
      );
    });

    test('SUB-030 saved files are UTF-8 with a BOM', () {
      final b = encodeSubtitleText('é');
      expect(b.take(3), [0xEF, 0xBB, 0xBF]);
      expect(utf8.decode(b.sublist(3)), 'é');
    });
  });

  group('PRIV-005 limits', () {
    test('PRIV-005 cue count and size limits', () {
      final many = List.generate(
        20,
        (i) => '${i + 1}\n00:00:0$i,000 --> 00:00:0$i,500\nx\n',
      ).join('\n');
      expect(
        () => const SrtParser().parse(
          many,
          limits: const ParseLimits(maxCues: 5),
        ),
        throwsA(isA<SubtitleParseException>()),
      );
      expect(
        () => const SrtParser().parse(
          many,
          limits: const ParseLimits(maxBytes: 10),
        ),
        throwsA(isA<SubtitleParseException>()),
      );
    });

    test('PRIV-005 parsing runs in an isolate and reports errors', () async {
      final doc = await parseSubtitlesIsolated(
        Uint8List.fromList(utf8.encode(_srt)),
      );
      expect(doc.cues, hasLength(3));
      expect(
        parseSubtitlesIsolated(Uint8List.fromList(utf8.encode('nothing'))),
        throwsA(isA<SubtitleParseException>()),
      );
      expect(
        parseSubtitlesIsolated(
          Uint8List(64),
          limits: const ParseLimits(maxBytes: 8),
        ),
        throwsA(isA<SubtitleParseException>()),
      );
    });
  });
}
