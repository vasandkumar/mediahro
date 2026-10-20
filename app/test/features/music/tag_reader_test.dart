import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mediahro/features/music/tags/audio_tags.dart';
import 'package:mediahro/features/music/tags/byte_reader.dart';
import 'package:mediahro/features/music/tags/tag_reader.dart';
import 'package:mediahro_ffi/mediahro_ffi.dart';

import 'tag_fixtures.dart';

AudioTags read(Uint8List b) => TagReader.read(MemoryByteReader(b));

void main() {
  group('MUS-002 ID3v2', () {
    for (final major in [2, 3, 4]) {
      test('MUS-002 reads ID3v2.$major text, art, lyrics and ReplayGain', () {
        final tag = id3v2(major, [
          id3Text(major, major == 2 ? 'TT2' : 'TIT2', ['Song']),
          id3Text(major, major == 2 ? 'TP1' : 'TPE1', ['A', 'B']),
          id3Text(major, major == 2 ? 'TAL' : 'TALB', ['Album']),
          id3Text(major, major == 2 ? 'TRK' : 'TRCK', ['3/12']),
          id3Text(major, major == 2 ? 'TPA' : 'TPOS', ['1/2']),
          id3Text(major, major == 2 ? 'TCO' : 'TCON', ['(17)']),
          id3Text(major, major == 2 ? 'TYE' : (major == 4 ? 'TDRC' : 'TYER'), [
            '1999',
          ]),
          id3Txxx(major, 'REPLAYGAIN_TRACK_GAIN', '-6.50 dB'),
          id3Txxx(major, 'MusicBrainz Album Id', 'mb-album'),
          id3Apic(major, jpeg),
          id3Uslt(major, 'Hello\nWorld'),
        ]);
        final t = read(bytesOf([tag, mpegAudio]));
        expect(t.title, 'Song');
        expect(t.artists, ['A', 'B']);
        expect(t.album, 'Album');
        expect(t.trackNumber, 3);
        expect(t.trackTotal, 12);
        expect(t.discNumber, 1);
        expect(t.discTotal, 2);
        expect(t.genres, ['Rock']);
        expect(t.year, 1999);
        expect(t.trackGainDb, -6.5);
        expect(t.musicBrainzIds[TagField.mbAlbumId], 'mb-album');
        expect(t.cover!.mimeType, 'image/jpeg');
        expect(t.cover!.bytes, jpeg);
        expect(t.lyrics, 'Hello\nWorld');
        expect(t.containers, contains(TagContainer.id3v2));
      });
    }

    test('MUS-002 SYLT synced lyrics and CHAP chapters', () {
      final t = read(
        bytesOf([
          id3v2(4, [
            id3Sylt(4, [(1000, 'one'), (2500, 'two')]),
            id3Chap(4, 'ch0', 0, 60000, 'Intro'),
            id3Chap(4, 'ch1', 60000, 120000, 'Part 1'),
          ]),
          mpegAudio,
        ]),
      );
      expect(t.syncedLyrics, const [
        SyncedLyricLine(Duration(seconds: 1), 'one'),
        SyncedLyricLine(Duration(milliseconds: 2500), 'two'),
      ]);
      expect(t.chapters.map((c) => c.title), ['Intro', 'Part 1']);
      expect(t.chapters[1].start, const Duration(minutes: 1));
    });

    test('MUS-002 unsynchronised v2.3 tag and numeric genres', () {
      final frames = [
        id3Text(3, 'TIT2', ['x']),
        id3Text(3, 'TCON', ['(13)Synth', '4']),
      ];
      final body = [for (final f in frames) ...f];
      final unsynced = <int>[];
      for (final b in body) {
        unsynced.add(b);
        if (b == 0xFF) unsynced.add(0);
      }
      final tag = bytesOf([
        ascii('ID3'),
        [3, 0, 0x80],
        syncSafe(unsynced.length),
        unsynced,
      ]);
      final t = read(bytesOf([tag, mpegAudio]));
      expect(t.title, 'x');
      expect(t.genres, ['Synth', 'Disco']);
    });

    test('MUS-002 ID3v1.1 and APEv2 fill gaps below ID3v2', () {
      final t = read(
        bytesOf([
          id3v2(3, [
            id3Text(3, 'TIT2', ['From v2']),
          ]),
          mpegAudio,
          apeTag({'Album': 'From APE', 'Composer': 'C1\u0000C2'}),
          id3v1(title: 'From v1', artist: 'V1 Artist', track: 7, genre: 8),
        ]),
      );
      expect(t.title, 'From v2');
      expect(t.album, 'From APE');
      expect(t.composers, ['C1', 'C2']);
      expect(t.artist, 'V1 Artist');
      expect(t.trackNumber, 7);
      expect(t.genres, ['Jazz']);
      expect(t.containers, {
        TagContainer.id3v2,
        TagContainer.ape,
        TagContainer.id3v1,
      });
    });

    test("MUS-002 APE-only Monkey's Audio with cover art", () {
      final t = read(
        bytesOf([
          ascii('MAC '),
          List.filled(60, 0),
          apeTag({'Title': 'Ape', 'Year': '2001'}, cover: jpeg),
        ]),
      );
      expect(t.title, 'Ape');
      expect(t.year, 2001);
      expect(t.cover!.bytes, jpeg);
    });
  });

  group('MUS-002 Vorbis comments', () {
    test('MUS-002 FLAC comments, multi-value artists, picture, duration', () {
      final t = read(
        flac([
          'TITLE=Flac',
          'ARTIST=One',
          'ARTIST=Two',
          'ALBUMARTIST=Band',
          'TRACKNUMBER=4',
          'TRACKTOTAL=9',
          'REPLAYGAIN_ALBUM_GAIN=+1.25 dB',
          'MUSICBRAINZ_TRACKID=mb-track',
          'LYRICS=la la',
        ], picture: jpeg),
      );
      expect(t.title, 'Flac');
      expect(t.artists, ['One', 'Two']);
      expect(t.albumArtist, 'Band');
      expect(t.trackNumber, 4);
      expect(t.trackTotal, 9);
      expect(t.albumGainDb, 1.25);
      expect(t.first(TagField.mbTrackId), 'mb-track');
      expect(t.lyrics, 'la la');
      expect(t.cover!.bytes, jpeg);
      expect(t.duration, const Duration(seconds: 10));
    });

    test('MUS-002 Ogg Vorbis and Opus comment headers', () {
      expect(read(oggVorbis(['TITLE=Vorbis', 'GENRE=Pop'])).genres, ['Pop']);
      final opus = read(oggOpus(['TITLE=Opus', 'DATE=2020-05-01']));
      expect(opus.title, 'Opus');
      expect(opus.year, 2020);
    });
  });

  group('MUS-002 other containers', () {
    test('MUS-002 MP4 atoms: text, trkn, covr, freeform, mvhd, chpl', () {
      final t = read(
        mp4(
          text: {
            '©nam': 'M4A',
            '©ART': 'Artist',
            'aART': 'Album Artist',
            '©alb': 'Album',
          },
          track: 2,
          trackTotal: 10,
          cover: png,
          freeform: {
            'MusicBrainz Album Id': 'mb-alb',
            'replaygain_track_gain': '-3.00 dB',
          },
          duration: 185000,
          chapters: [(0, 'Start'), (30000, 'Middle')],
        ),
      );
      expect(t.title, 'M4A');
      expect(t.artist, 'Artist');
      expect(t.albumArtist, 'Album Artist');
      expect(t.trackNumber, 2);
      expect(t.trackTotal, 10);
      expect(t.cover!.mimeType, 'image/png');
      expect(t.musicBrainzIds[TagField.mbAlbumId], 'mb-alb');
      expect(t.trackGainDb, -3);
      expect(t.duration, const Duration(seconds: 185));
      expect(t.chapters.map((c) => c.title), ['Start', 'Middle']);
      expect(t.chapters[1].start, const Duration(seconds: 30));
    });

    test('MUS-002 ASF content description, WM attributes and picture', () {
      final t = read(
        asf(
          title: 'Wma',
          artist: 'WArtist',
          extended: {
            'WM/AlbumTitle': 'WAlbum',
            'WM/TrackNumber': '5',
            'MusicBrainz/Album Id': 'mb-w',
          },
          picture: jpeg,
        ),
      );
      expect(t.title, 'Wma');
      expect(t.artist, 'WArtist');
      expect(t.album, 'WAlbum');
      expect(t.trackNumber, 5);
      expect(t.musicBrainzIds[TagField.mbAlbumId], 'mb-w');
      expect(t.cover!.bytes, jpeg);
    });

    test('MUS-002 WAV INFO chunk, id3 chunk and duration', () {
      final t = read(
        wav(
          info: {'INAM': 'Wave', 'IART': 'WA'},
          id3: id3v2(4, [
            id3Text(4, 'TALB', ['From ID3']),
          ]),
        ),
      );
      expect(t.title, 'Wave');
      expect(t.album, 'From ID3');
      expect(t.duration, const Duration(milliseconds: 100));
    });

    test('MUS-002 AIFF NAME and ID3 chunk', () {
      final t = read(
        aiff(
          name: 'Aiff',
          id3: id3v2(3, [
            id3Text(3, 'TPE1', ['AI']),
          ]),
        ),
      );
      expect(t.title, 'Aiff');
      expect(t.artist, 'AI');
      expect(t.duration, const Duration(seconds: 1));
    });

    test('MUS-002 DSF ID3v2 at the metadata pointer', () {
      final t = read(
        dsf(
          id3v2(3, [
            id3Text(3, 'TIT2', ['Dsd']),
          ]),
        ),
      );
      expect(t.title, 'Dsd');
      expect(t.duration, const Duration(seconds: 3));
    });
  });

  group('MUS-002 limits and robustness', () {
    test('MUS-002 garbage, empty and truncated input never throw', () {
      final rnd = Random(2);
      expect(read(Uint8List(0)).isEmpty, isTrue);
      expect(read(Uint8List.fromList(ascii('ID3'))).isEmpty, isTrue);
      final seeds = [
        bytesOf([
          id3v2(4, [
            id3Text(4, 'TIT2', ['x']),
            id3Apic(4, jpeg),
          ]),
          mpegAudio,
        ]),
        flac(['TITLE=x'], picture: jpeg),
        oggVorbis(['TITLE=x']),
        mp4(text: {'©nam': 'x'}, cover: jpeg),
        asf(title: 'x', artist: 'y', picture: jpeg),
        wav(info: {'INAM': 'x'}),
      ];
      for (final seed in seeds) {
        for (var i = 0; i < 300; i++) {
          final b = Uint8List.fromList(seed);
          final flips = 1 + rnd.nextInt(8);
          for (var f = 0; f < flips; f++) {
            b[rnd.nextInt(b.length)] = rnd.nextInt(256);
          }
          final cut = rnd.nextBool() ? b.length : rnd.nextInt(b.length);
          expect(() => read(Uint8List.sublistView(b, 0, cut)), returnsNormally);
        }
      }
    });

    test('MUS-002 an oversized ID3v2 size field is refused, not allocated', () {
      final b = bytesOf([
        ascii('ID3'),
        [4, 0, 0],
        [0x7F, 0x7F, 0x7F, 0x7F],
        mpegAudio,
      ]);
      expect(read(b).isEmpty, isTrue);
    });

    test('MUS-002 pictures above the limit are dropped', () {
      final big = Uint8List(TagLimits.maxPictureBytes + 1)..[0] = 0xFF;
      final t = read(
        bytesOf([
          id3v2(4, [
            id3Text(4, 'TIT2', ['big']),
            id3Apic(4, big),
          ]),
        ]),
      );
      expect(t.title, 'big');
      expect(t.pictures, isEmpty);
    });
  });

  group('MUS-002 isolates', () {
    late Directory dir;
    setUp(() async => dir = await Directory.systemTemp.createTemp('c2_tags'));
    tearDown(() => dir.delete(recursive: true));

    test('MUS-002 readFile parses in a background isolate', () async {
      final f = File('${dir.path}/a.flac')
        ..writeAsBytesSync(flac(['TITLE=Iso']));
      expect((await TagReader.readFile(f.path)).title, 'Iso');
    });

    test('MUS-002 readVirtualFile fetches tail tags on demand', () async {
      final bytes = bytesOf([
        List.filled(600 * 1024, 0x11),
        apeTag({'Title': 'Remote'}),
        id3v1(artist: 'Tail'),
      ]);
      final file = _MemoryVirtualFile(bytes);
      final t = await TagReader.readVirtualFile(file);
      expect(t.title, 'Remote');
      expect(t.artist, 'Tail');
      expect(file.bytesRead, lessThan(bytes.length));
    });

    test('MUS-002 readVirtualFile follows MP4 atoms past the first fetch', () {
      final m = mp4(text: {'©nam': 'Late'});
      // Put a large mdat before moov so moov is beyond the head fetch.
      final ftypEnd = (m[0] << 24) | (m[1] << 16) | (m[2] << 8) | m[3];
      final bytes = bytesOf([
        Uint8List.sublistView(m, 0, ftypEnd),
        atom('free', List.filled(700 * 1024, 0)),
        Uint8List.sublistView(m, ftypEnd),
      ]);
      return expectLater(
        TagReader.readVirtualFile(_MemoryVirtualFile(bytes))
            .then((t) => t.title),
        completion('Late'),
      );
    });
  });
}

final class _MemoryVirtualFile implements VirtualFile {
  _MemoryVirtualFile(this.bytes);

  final Uint8List bytes;
  int bytesRead = 0;

  @override
  Uri get uri => Uri.parse('memory:/f');

  @override
  Future<int?> length() async => bytes.length;

  @override
  Future<Uint8List> read(int offset, int length) async {
    final end = min(offset + length, bytes.length);
    bytesRead += end - offset;
    return Uint8List.sublistView(bytes, offset, end);
  }

  @override
  bool get isSeekable => true;

  @override
  Future<void> close() async {}
}
