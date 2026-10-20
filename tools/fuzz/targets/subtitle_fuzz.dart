// Dart fuzz target for the subtitle parsers, decoder and sidecar matcher
// (PRIV-005, docs/11 §1).
//
//   dart run tools/fuzz/targets/subtitle_fuzz.dart --iterations 1000000
//
// Mutates seed files of every text format (SRT, WebVTT, ASS/SSA, MicroDVD,
// LRC, SAMI) at the byte level and asserts that each input either parses
// or throws SubtitleParseException / FormatException, within the time
// budget: no other error, hang or crash. Also feeds random names to the
// sidecar matcher.
// ignore_for_file: depend_on_referenced_packages
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:mediahro_subtitles/mediahro_subtitles.dart';

const _seeds = <(SubtitleFormat, String)>[
  (
    SubtitleFormat.srt,
    '1\n00:00:01,000 --> 00:00:02,500\nHello\n<i>world</i>\n\n'
        '2\n00:00:03,000 --> 00:00:04,000\nSecond\n',
  ),
  (
    SubtitleFormat.webvtt,
    'WEBVTT\n\nNOTE x\n\nid\n00:01.000 --> 00:02.000 align:start\nHi\n',
  ),
  (
    SubtitleFormat.ass,
    '[Script Info]\nScriptType: v4.00+\n\n[Events]\n'
        'Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text\n'
        r'Dialogue: 0,0:00:01.00,0:00:02.00,Default,,0,0,0,,{\i1}Hi\Nthere'
        '\n',
  ),
  (SubtitleFormat.microDvd, '{1}{1}25.000\n{25}{50}One|Two\n'),
  (SubtitleFormat.lrc, '[00:01.00][00:05.50]Chorus\n[00:03.00]Verse\n'),
  (
    SubtitleFormat.smi,
    '<SAMI><BODY><SYNC Start=1000><P>Tom &amp; Jerry<br>run '
        '<SYNC Start=3000><P>&nbsp;</BODY></SAMI>',
  ),
];

const _tokens = [
  '-->', ',', '.', ':', '\n', '\r', '\r\n', '{', '}', '|', '[', ']', '<', //
  '>', '&', ';', r'\N', r'{\i1}', 'Dialogue:', 'Format:', '[Events]',
  'WEBVTT', 'NOTE', '<SYNC Start=', '99:99:99,999', '-1', '0', '\u0000',
  '﻿', '{999999999999}', '1e309',
];

const _limits = ParseLimits(
  maxBytes: 1 << 16,
  maxCues: 2000,
  timeout: Duration(seconds: 2),
);

void main(List<String> args) {
  final iterations = args.length >= 2 && args[0] == '--iterations'
      ? int.parse(args[1])
      : 10000;
  final rnd = Random(0x5ab5);
  final watch = Stopwatch();
  for (var i = 0; i < iterations; i++) {
    final (format, seed) = _seeds[rnd.nextInt(_seeds.length)];
    final bytes = _mutate(utf8.encode(seed), rnd);
    final sniff = rnd.nextInt(4) == 0;
    final charset = rnd.nextInt(8) == 0 ? 'cp1251' : null;
    watch
      ..reset()
      ..start();
    try {
      parseSubtitleBytes(
        bytes,
        format: sniff ? null : format,
        charset: charset,
        limits: _limits,
      );
    } on SubtitleParseException {
      // Expected for malformed input.
    } on FormatException {
      // Expected.
    } on Object catch (e, st) {
      _fail('parse', i, format, bytes, e, st);
    }
    if (watch.elapsed > _limits.timeout) {
      _fail(
        'parse (slow)',
        i,
        format,
        bytes,
        watch.elapsed,
        StackTrace.current,
      );
    }
    try {
      final name = latin1.decode(bytes.take(80).toList(), allowInvalid: true);
      matchSidecars('Film.mkv', [('', name), ('Subs', name), (name, 'x.srt')]);
    } on Object catch (e, st) {
      _fail('sidecar', i, format, bytes, e, st);
    }
  }
  stdout.writeln('subtitle_fuzz: $iterations iterations, no crashes');
}

Never _fail(
  String what,
  int i,
  SubtitleFormat format,
  Uint8List bytes,
  Object e,
  StackTrace st,
) {
  stderr.writeln(
    'subtitle_fuzz: $what failed at iteration $i, format ${format.name}, '
    'input base64 ${base64.encode(bytes)}\n$e\n$st',
  );
  exit(1);
}

Uint8List _mutate(List<int> seed, Random r) {
  final b = [...seed];
  final ops = 1 + r.nextInt(8);
  for (var k = 0; k < ops; k++) {
    final at = b.isEmpty ? 0 : r.nextInt(b.length + 1);
    switch (r.nextInt(5)) {
      case 0:
        b.insertAll(at, utf8.encode(_tokens[r.nextInt(_tokens.length)]));
      case 1:
        final end = min(b.length, at + r.nextInt(8));
        b.removeRange(at, end);
      case 2:
        b.insert(at, r.nextInt(256));
      case 3:
        if (b.isNotEmpty) b[r.nextInt(b.length)] = r.nextInt(256);
      case 4:
        final from = b.isEmpty ? 0 : r.nextInt(b.length);
        final end = min(b.length, from + r.nextInt(64));
        b.insertAll(at, b.sublist(from, end));
    }
  }
  return Uint8List.fromList(b);
}
