// Dart fuzz target for the music tag reader (MUS-002, CLAUDE.md §1.10).
//
//   dart run tools/fuzz/targets/music_tags_fuzz.dart --iterations 1000000
//
// Mutates seed files of every tag container (ID3v2.2–2.4, ID3v1, APE, FLAC,
// Ogg, MP4, ASF, WAV, AIFF, DSF) and asserts that TagReader.read never
// throws, hangs or allocates past its limits, and that TagWriter.plan
// either plans a rewrite or refuses with TagFormatException /
// TagWriteUnsupported (MUS-003). The reader is pure Dart and
// lives in the app package.
// ignore_for_file: depend_on_referenced_packages
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:mediahro/features/music/tags/byte_reader.dart';
import 'package:mediahro/features/music/tags/audio_tags.dart';
import 'package:mediahro/features/music/tags/tag_reader.dart';
import 'package:mediahro/features/music/tags/writer/tag_edit.dart';
import 'package:mediahro/features/music/tags/writer/tag_writer.dart';

import '../../../app/test/features/music/tag_fixtures.dart';

List<Uint8List> _seeds() => [
  bytesOf([
    id3v2(2, [
      id3Text(2, 'TT2', ['a']),
      id3Apic(2, jpeg),
    ]),
    mpegAudio,
  ]),
  bytesOf([
    id3v2(3, [
      id3Text(3, 'TIT2', ['a', 'b']),
      id3Txxx(3, 'REPLAYGAIN_TRACK_GAIN', '-1 dB'),
      id3Uslt(3, 'x'),
    ]),
    mpegAudio,
    apeTag({'Album': 'b'}, cover: jpeg),
    id3v1(title: 't', track: 3),
  ]),
  bytesOf([
    id3v2(4, [
      id3Sylt(4, [(1, 'a'), (2, 'b')]),
      id3Chap(4, 'c', 0, 10, 'x'),
      id3Apic(4, png),
    ]),
    mpegAudio,
  ]),
  flac(['TITLE=a', 'ARTIST=b', 'CHAPTER001=00:00:01.000'], picture: jpeg),
  oggVorbis(['TITLE=a']),
  oggOpus(['TITLE=a']),
  mp4(
    text: {'©nam': 'a'},
    track: 1,
    cover: jpeg,
    freeform: {'MusicBrainz Album Id': 'x'},
    duration: 100,
    chapters: [(0, 'a')],
  ),
  asf(title: 'a', artist: 'b', extended: {'WM/AlbumTitle': 'c'}, picture: jpeg),
  wav(
    info: {'INAM': 'a'},
    id3: id3v2(3, [
      id3Text(3, 'TALB', ['b']),
    ]),
  ),
  aiff(
    name: 'a',
    id3: id3v2(3, [
      id3Text(3, 'TPE1', ['b']),
    ]),
  ),
  dsf(
    id3v2(3, [
      id3Text(3, 'TIT2', ['a']),
    ]),
  ),
];

const _edit = TagEdit(
  fields: {
    TagField.title: ['Fuzz'],
    TagField.trackNumber: ['3'],
  },
);

void main(List<String> args) {
  final i = args.indexOf('--iterations');
  final iterations = i >= 0 ? int.parse(args[i + 1]) : 10000;
  final rnd = Random(args.contains('--seed') ? 1 : DateTime.now().microsecond);
  final seeds = _seeds();
  final sw = Stopwatch()..start();
  for (var n = 0; n < iterations; n++) {
    final seed = seeds[rnd.nextInt(seeds.length)];
    final b = Uint8List.fromList(seed);
    final edits = 1 + rnd.nextInt(16);
    for (var e = 0; e < edits; e++) {
      final at = rnd.nextInt(b.length);
      b[at] = switch (rnd.nextInt(4)) {
        0 => 0,
        1 => 0xFF,
        2 => 0x7F,
        _ => rnd.nextInt(256),
      };
    }
    final cut = rnd.nextInt(4) == 0 ? rnd.nextInt(b.length + 1) : b.length;
    final input = Uint8List.sublistView(b, 0, cut);
    final t = Stopwatch()..start();
    try {
      final r = MemoryByteReader(input);
      final before = TagReader.read(r);
      // Writers must refuse broken files cleanly (MUS-003).
      try {
        TagWriter.plan(r, before, _edit);
      } on TagFormatException {
        // refused
      } on TagWriteUnsupported {
        // refused
      }
    } on Object catch (e, s) {
      stderr
        ..writeln('music_tags_fuzz: iteration $n threw $e')
        ..writeln(s)
        ..writeln('input (${input.length} bytes): ${input.take(256).toList()}');
      exit(1);
    }
    if (t.elapsedMilliseconds > 2000) {
      stderr.writeln(
        'music_tags_fuzz: iteration $n took ${t.elapsedMilliseconds} ms',
      );
      exit(1);
    }
  }
  stdout.writeln(
    'music_tags_fuzz: $iterations iterations in ${sw.elapsed.inSeconds} s, no failures',
  );
}
