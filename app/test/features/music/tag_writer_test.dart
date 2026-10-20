import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mediahro/features/music/tags/audio_tags.dart';
import 'package:mediahro/features/music/tags/byte_reader.dart';
import 'package:mediahro/features/music/tags/tag_reader.dart';
import 'package:mediahro/features/music/tags/writer/tag_edit.dart';
import 'package:mediahro/features/music/tags/writer/tag_writer.dart';

import 'tag_fixtures.dart';

Uint8List materialize(Uint8List original, WritePlan plan) {
  final b = BytesBuilder(copy: false);
  for (final p in plan.parts) {
    switch (p) {
      case BytesPart(:final bytes):
        b.add(bytes);
      case RangePart(:final offset, :final length):
        b.add(Uint8List.sublistView(original, offset, offset + length));
    }
  }
  return b.toBytes();
}

/// Edits [file] and returns the new bytes.
Uint8List edit(Uint8List file, TagEdit e) {
  final r = MemoryByteReader(file);
  final before = TagReader.read(r);
  return materialize(file, TagWriter.plan(r, before, e));
}

AudioTags read(Uint8List b) => TagReader.read(MemoryByteReader(b));

const titleAndArtists = TagEdit(
  fields: {
    TagField.title: ['New Title'],
    TagField.artist: ['A1', 'A2'],
    TagField.trackNumber: ['7'],
    TagField.trackTotal: ['12'],
    TagField.date: ['2024'],
    TagField.trackGain: ['-5.00 dB'],
    TagField.lyrics: ['la la'],
  },
);

void expectEdited(AudioTags t) {
  expect(t.title, 'New Title');
  expect(t.artists, ['A1', 'A2']);
  expect(t.trackNumber, 7);
  expect(t.trackTotal, 12);
  expect(t.year, 2024);
  expect(t.trackGainDb, -5);
  expect(t.lyrics, 'la la');
}

bool endsWithBytes(Uint8List file, List<int> tail) {
  if (file.length < tail.length) return false;
  for (var i = 0; i < tail.length; i++) {
    if (file[file.length - tail.length + i] != tail[i]) return false;
  }
  return true;
}

void main() {
  group('MUS-003 ID3v2', () {
    for (final major in [2, 3, 4]) {
      test('MUS-003 ID3v2.$major is upgraded to v2.4 with edits; untouched '
          'and unknown frames survive; audio is identical', () {
        final audio = List<int>.generate(4000, (i) => (i * 7) & 0xFF)
          ..[0] = 0xFF;
        final file = bytesOf([
          id3v2(major, [
            id3Text(major, major == 2 ? 'TT2' : 'TIT2', ['Old']),
            id3Text(major, major == 2 ? 'TAL' : 'TALB', ['Keep Album']),
            id3Apic(major, jpeg),
            if (major > 2)
              id3Frame(major, 'PRIV', [...ascii('owner'), 0, 1, 2, 3]),
          ]),
          audio,
        ]);
        final out = edit(file, titleAndArtists);
        final t = read(out);
        expectEdited(t);
        expect(t.album, 'Keep Album');
        expect(t.cover!.bytes, jpeg);
        expect(out.sublist(3, 4), [4]);
        if (major > 2) {
          expect(latin1.decode(out, allowInvalid: true), contains('PRIV'));
        }
        expect(endsWithBytes(out, audio), isTrue);
      });
    }

    test('MUS-003 clearing a field and replacing pictures', () {
      final file = bytesOf([
        id3v2(4, [
          id3Text(4, 'TIT2', ['T']),
          id3Text(4, 'TCOM', ['C']),
          id3Apic(4, jpeg),
        ]),
        mpegAudio,
      ]);
      final out = edit(
        file,
        TagEdit(
          fields: const {TagField.composer: []},
          pictures: [
            EmbeddedPicture(
              type: PictureType.frontCover,
              mimeType: 'image/png',
              bytes: png,
            ),
          ],
        ),
      );
      final t = read(out);
      expect(t.composers, isEmpty);
      expect(t.title, 'T');
      expect(t.pictures.single.bytes, png);
    });

    test('MUS-003 MP3 with APE and ID3v1: all three stay in step', () {
      final file = bytesOf([
        id3v2(3, [
          id3Text(3, 'TIT2', ['x']),
        ]),
        mpegAudio,
        apeTag({'Title': 'x', 'Custom': 'keep'}),
        id3v1(title: 'x'),
      ]);
      final out = edit(file, titleAndArtists);
      expectEdited(read(out));
      // ID3v1 refreshed (30-char field).
      final v1 = out.sublist(out.length - 128);
      expect(latin1.decode(v1.sublist(3, 12)), 'New Title');
      expect(latin1.decode(out, allowInvalid: true), contains('APETAGEX'));
      expect(
        latin1.decode(out, allowInvalid: true).toUpperCase(),
        contains('CUSTOM'),
      );
    });

    test('MUS-003 a shorter tag keeps its old size (cheap re-edits)', () {
      final file = bytesOf([
        id3v2(4, [
          id3Text(4, 'TIT2', ['A long title ' * 10]),
        ], padding: 0),
        mpegAudio,
      ]);
      final out = edit(
        file,
        const TagEdit(
          fields: {
            TagField.title: ['Short'],
          },
        ),
      );
      expect(out.length, file.length);
    });
  });

  group('MUS-003 Vorbis comments', () {
    test('MUS-003 FLAC: edited comment, pictures replaced, STREAMINFO and '
        'audio kept', () {
      final file = flac([
        'TITLE=Old',
        'GENRE=Rock',
        'CUSTOMKEY=v',
      ], picture: jpeg);
      final audioTail = file.sublist(file.length - 32);
      final out = edit(file, titleAndArtists);
      final t = read(out);
      expectEdited(t);
      expect(t.genres, ['Rock']);
      expect(t.first('CUSTOMKEY'), 'v');
      expect(t.cover!.bytes, jpeg);
      expect(t.duration, const Duration(seconds: 10));
      expect(endsWithBytes(out, audioTail), isTrue);
      // Re-edit reuses the padding: same size.
      final again = edit(
        out,
        const TagEdit(
          fields: {
            TagField.title: ['N'],
          },
        ),
      );
      expect(again.length, out.length);
    });

    for (final (name, make) in [('Vorbis', oggVorbis), ('Opus', oggOpus)]) {
      test('MUS-003 Ogg $name: comment rebuilt, pages valid', () {
        final file = bytesOf([
          make(['TITLE=Old', 'ALBUM=Keep']),
          oggPage(make == oggVorbis ? 7 : 9, 2, List.filled(300, 9)),
        ]);
        final out = edit(file, titleAndArtists);
        final t = read(out);
        expectEdited(t);
        expect(t.album, 'Keep');
        expect(endsWithBytes(out, List.filled(300, 9)), isTrue);
      });
    }

    test('MUS-003 Ogg: a big picture spans pages; later pages are renumbered '
        'with valid CRCs', () {
      final file = bytesOf([
        oggVorbis(['TITLE=Old']),
        oggPage(7, 2, List.filled(100, 1)),
        oggPage(7, 3, List.filled(100, 2)),
      ]);
      final out = edit(
        file,
        TagEdit(
          pictures: [
            EmbeddedPicture(
              type: PictureType.frontCover,
              mimeType: 'image/jpeg',
              bytes: Uint8List.fromList([...jpeg, ...List.filled(200000, 7)]),
            ),
          ],
        ),
      );
      final t = read(out);
      expect(t.title, 'Old');
      expect(t.cover!.bytes.length, jpeg.length + 200000);
      // Walk all pages: sequence numbers are consecutive and CRCs verify.
      var pos = 0;
      var seq = 0;
      while (pos < out.length) {
        expect(String.fromCharCodes(out.sublist(pos, pos + 4)), 'OggS');
        final page = out.sublist(pos);
        final nSeg = page[26];
        final len =
            27 +
            nSeg +
            page.sublist(27, 27 + nSeg).fold<int>(0, (a, b) => a + b);
        final p = Uint8List.fromList(page.sublist(0, len));
        final s = p.buffer.asByteData().getUint32(18, Endian.little);
        expect(s, seq++);
        final crc = p.buffer.asByteData().getUint32(22, Endian.little);
        p.setRange(22, 26, [0, 0, 0, 0]);
        expect(crc, oggCrcForTest(p));
        pos += len;
      }
      expect(seq, greaterThan(4));
    });
  });

  group('MUS-003 MP4', () {
    test('MUS-003 ilst rebuilt; unknown items kept; freeform written', () {
      final file = mp4(
        text: {'©nam': 'Old', '©xyz': 'unknown item'},
        track: 1,
        trackTotal: 2,
        cover: jpeg,
        freeform: {'Custom Thing': 'keep me'},
        duration: 5000,
      );
      final out = edit(file, titleAndArtists);
      final t = read(out);
      expectEdited(t);
      expect(t.first('CUSTOM THING'), 'keep me');
      expect(t.first('©XYZ'), isNull); // not a canonical field…
      expect(latin1.decode(out), contains('unknown item')); // …but kept
      expect(t.cover!.bytes, jpeg);
      expect(t.duration, const Duration(seconds: 5));
    });

    test('MUS-003 moov before mdat: stco offsets follow the moved audio', () {
      final file = mp4WithChunkOffsets();
      final before = chunkTarget(file);
      final out = edit(file, titleAndArtists);
      expectEdited(read(out));
      expect(chunkTarget(out), before);
    });
  });

  group('MUS-003 other containers', () {
    test("MUS-003 APE (Monkey's Audio): replaced, binary items kept", () {
      final file = bytesOf([
        ascii('MAC '),
        List.filled(60, 3),
        apeTag({'Title': 'Old', 'Album': 'Keep'}, cover: jpeg),
      ]);
      final out = edit(file, titleAndArtists);
      final t = read(out);
      expectEdited(t);
      expect(t.album, 'Keep');
      expect(t.cover!.bytes, jpeg);
      expect(out.sublist(0, 64), file.sublist(0, 64));
    });

    test('MUS-003 WMA: content description and attributes rebuilt', () {
      final file = asf(
        title: 'Old',
        artist: 'Old Artist',
        extended: {'WM/AlbumTitle': 'Keep'},
        picture: jpeg,
      );
      final out = edit(file, titleAndArtists);
      final t = read(out);
      expectEdited(t);
      expect(t.album, 'Keep');
      expect(t.cover!.bytes, jpeg);
      expect(endsWithBytes(out, List.filled(32, 0)), isTrue);
    });

    test('MUS-003 WAV: id3 chunk and INFO refreshed; data chunk kept', () {
      final file = wav(info: {'INAM': 'Old', 'IPRD': 'Keep'});
      final out = edit(file, titleAndArtists);
      final t = read(out);
      expectEdited(t);
      expect(t.album, 'Keep');
      expect(t.duration, const Duration(milliseconds: 100));
      final riffSize = ByteData.sublistView(out).getUint32(4, Endian.little);
      expect(riffSize, out.length - 8);
    });

    test('MUS-003 AIFF and DSF', () {
      final a = edit(aiff(name: 'Old'), titleAndArtists);
      expectEdited(read(a));
      expect(read(a).duration, const Duration(seconds: 1));
      final d = edit(
        dsf(
          id3v2(3, [
            id3Text(3, 'TIT2', ['Old']),
          ]),
        ),
        titleAndArtists,
      );
      expectEdited(read(d));
      expect(read(d).duration, const Duration(seconds: 3));
      final total = ByteData.sublistView(d).getUint64(12, Endian.little);
      expect(total, d.length);
    });
  });

  test('MUS-003 undo: the inverse edit restores the old values', () {
    final file = flac(['TITLE=Old', 'ARTIST=Who']);
    final before = read(file);
    final out = edit(file, titleAndArtists);
    final undone = edit(out, titleAndArtists.inverse(before));
    final t = read(undone);
    expect(t.title, 'Old');
    expect(t.artists, ['Who']);
    expect(t.lyrics, isNull);
    expect(t.trackNumber, isNull);
  });
}

// ---- helpers for the MP4 chunk-offset test and the Ogg CRC check

int oggCrcForTest(Uint8List page) {
  final table = List<int>.generate(256, (i) {
    var r = i << 24;
    for (var k = 0; k < 8; k++) {
      r = (r & 0x80000000) != 0 ? ((r << 1) ^ 0x04C11DB7) : (r << 1);
      r &= 0xFFFFFFFF;
    }
    return r;
  });
  var crc = 0;
  for (final b in page) {
    crc = ((crc << 8) ^ table[((crc >> 24) & 0xFF) ^ b]) & 0xFFFFFFFF;
  }
  return crc;
}

final List<int> _marker = ascii('AUDIODATA!');

/// moov (with trak/mdia/minf/stbl/stco pointing into mdat) before mdat.
Uint8List mp4WithChunkOffsets() {
  List<int> build(int stcoValue) {
    final stco = atom('stco', [0, 0, 0, 0, ...u32be(1), ...u32be(stcoValue)]);
    final trak = atom('trak', atom('mdia', atom('minf', atom('stbl', stco))));
    final meta = atom('meta', [
      0, 0, 0, 0, //
      ...atom('hdlr', [
        ...List.filled(8, 0),
        ...ascii('mdir'),
        ...List.filled(13, 0),
      ]),
      ...atom('ilst', atom('©nam', mp4Data(1, utf8.encode('Old')))),
    ]);
    final moov = atom('moov', [...trak, ...atom('udta', meta)]);
    final ftyp = atom('ftyp', [...ascii('M4A '), ...u32be(0)]);
    return [
      ...ftyp,
      ...moov,
      ...atom('mdat', [..._marker, ...List.filled(20, 1)]),
    ];
  }

  // Two passes: find where mdat's payload lands, then point stco at it.
  final probe = build(0);
  final at = String.fromCharCodes(probe).indexOf('AUDIODATA!');
  return Uint8List.fromList(build(at));
}

/// The 10 bytes the first stco entry points at.
String chunkTarget(Uint8List file) {
  final s = String.fromCharCodes(file);
  final i = s.indexOf('stco');
  final offset = ByteData.sublistView(file).getUint32(i + 12);
  return String.fromCharCodes(file.sublist(offset, offset + 10));
}
