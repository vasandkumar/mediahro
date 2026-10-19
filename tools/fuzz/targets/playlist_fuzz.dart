// Dart fuzz target for the playlist and XML parsers (PRIV-005, docs/11 §1).
//
//   dart run tools/fuzz/targets/playlist_fuzz.dart --iterations 1000000
//
// Mutates seed playlists (M3U/PLS/XSPF/CUE) and asserts that every input
// either parses or throws FormatException: no other error, hang or crash.
// The parsers are pure Dart and live in the app package.
// ignore_for_file: depend_on_referenced_packages
import 'dart:io';
import 'dart:math';

import 'package:mediahro/core/parsers/playlist_parser.dart';
import 'package:mediahro/core/parsers/xml_lite.dart';

const _seeds = <(PlaylistFormat, String)>[
  (
    PlaylistFormat.m3u,
    '#EXTM3U\n#EXTINF:12,A - B\nhttp://h/x.mp3\n../rel/y.flac\n',
  ),
  (PlaylistFormat.m3u, '#EXTM3U\n#EXT-X-TARGETDURATION:6\nseg.ts\n'),
  (
    PlaylistFormat.pls,
    '[playlist]\nFile1=a.mp3\nTitle1=T\nLength1=10\nNumberOfEntries=1\n',
  ),
  (
    PlaylistFormat.xspf,
    '<?xml version="1.0"?><playlist><title>x &amp; y</title><trackList><track><location>a</location><duration>1</duration></track></trackList></playlist>',
  ),
  (
    PlaylistFormat.cue,
    'FILE "a.flac" WAVE\n TRACK 01 AUDIO\n  TITLE "x"\n  INDEX 01 00:00:00\n TRACK 02 AUDIO\n  INDEX 01 01:02:03\n',
  ),
];

const _tokens = [
  '<',
  '>',
  '"',
  "'",
  '&',
  '&#x110000;',
  '<![CDATA[',
  ']]>',
  '<!--',
  '-->',
  '<!DOCTYPE x [',
  ']>',
  '\n',
  '#EXTINF:',
  ',',
  '=',
  ':',
  '\u0000',
  '￿',
  'FILE ',
  'TRACK ',
  'INDEX 01 ',
  '99:99:99',
  '-1',
  'File99999999=',
];

void main(List<String> args) {
  final iterations = args.length >= 2 && args[0] == '--iterations'
      ? int.parse(args[1])
      : 10000;
  final rnd = Random(0x5eed);
  for (var i = 0; i < iterations; i++) {
    final (format, seed) = _seeds[rnd.nextInt(_seeds.length)];
    final input = _mutate(seed, rnd);
    try {
      parsePlaylist(input, format, base: Uri.parse('file:///base/'));
    } on FormatException {
      // Expected for malformed input.
    } on Object catch (e, st) {
      stderr.writeln(
        'playlist_fuzz: iteration $i, format $format, input ${Uri.encodeComponent(input)}\n$e\n$st',
      );
      exit(1);
    }
    try {
      parseXml(
        input,
        limits: const XmlLimits(
          maxLength: 1 << 16,
          maxDepth: 32,
          maxNodes: 4096,
        ),
      );
    } on FormatException {
      // Expected.
    } on Object catch (e, st) {
      stderr.writeln(
        'xml_fuzz: iteration $i, input ${Uri.encodeComponent(input)}\n$e\n$st',
      );
      exit(1);
    }
  }
  stdout.writeln('playlist_fuzz: $iterations iterations, no crashes');
}

String _mutate(String s, Random r) {
  final b = StringBuffer();
  var text = s;
  final ops = 1 + r.nextInt(6);
  for (var k = 0; k < ops; k++) {
    if (text.isEmpty) text = _tokens[r.nextInt(_tokens.length)];
    final at = r.nextInt(text.length + 1);
    switch (r.nextInt(4)) {
      case 0:
        text =
            text.substring(0, at) +
            _tokens[r.nextInt(_tokens.length)] +
            text.substring(at);
      case 1:
        final end = min(text.length, at + r.nextInt(8));
        text = text.substring(0, at) + text.substring(end);
      case 2:
        text =
            text.substring(0, at) +
            String.fromCharCode(r.nextInt(0x3000)) +
            text.substring(at);
      case 3:
        final from = r.nextInt(text.length + 1);
        final end = min(text.length, from + r.nextInt(32));
        text =
            text.substring(0, at) +
            text.substring(from, end) +
            text.substring(at);
    }
  }
  b.write(text);
  return b.toString();
}
