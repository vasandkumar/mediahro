import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mediahro/core/parsers/playlist_parser.dart';
import 'package:mediahro/core/parsers/xml_lite.dart';

void main() {
  final base = Uri.parse('file:///music/lists/');

  test(
    'LIB-007 M3U with EXTINF, relative paths, Windows paths and VLC headers',
    () {
      final p = parseM3u(
        '#EXTM3U\n#PLAYLIST:Mix\n'
        '#EXTINF:123,Artist - Title, with comma\n../a/song.mp3\n'
        r'C:\Music\b.flac'
        '\n'
        '#EXTVLCOPT:http-user-agent=MyAgent\n#EXTINF:-1,Live\nhttp://x/live\n',
        base: base,
      );
      expect(p.title, 'Mix');
      expect(p.entries[0].location, 'file:///music/a/song.mp3');
      expect(p.entries[0].artist, 'Artist');
      expect(p.entries[0].title, 'Title, with comma');
      expect(p.entries[0].duration, const Duration(seconds: 123));
      expect(p.entries[1].location, 'file:///C:/Music/b.flac');
      expect(p.entries[2].duration, isNull);
      expect(p.entries[2].headers, {'User-Agent': 'MyAgent'});
    },
  );

  test('NET-006 an HLS .m3u8 is a stream, not a playlist', () {
    final p = parseM3u(
      '#EXTM3U\n#EXT-X-TARGETDURATION:6\n#EXTINF:6,\nseg1.ts\n',
    );
    expect(p.isHlsStream, isTrue);
    expect(p.entries, isEmpty);
  });

  test('LIB-007 PLS', () {
    final p = parsePls(
      '[playlist]\nFile2=b.mp3\nFile1=http://r/x\nTitle1=Radio\nLength1=-1\nLength2=60\nNumberOfEntries=2\n',
      base: base,
    );
    expect(p.entries.map((e) => e.location), [
      'http://r/x',
      'file:///music/lists/b.mp3',
    ]);
    expect(p.entries.first.title, 'Radio');
    expect(p.entries.last.duration, const Duration(minutes: 1));
  });

  test('LIB-007 XSPF with entities and CDATA', () {
    final p = parseXspf(
      [
        '<?xml version="1.0"?><playlist version="1" xmlns="http://xspf.org/ns/0/">',
        '<title>Rock &amp; Roll</title><trackList>',
        '<track><location>http://h/a.mp3</location><title><![CDATA[A <1>]]></title>',
        '<creator>X</creator><duration>1500</duration></track>',
        '<track><title>no location</title></track>',
        '</trackList></playlist>',
      ].join(),
    );
    expect(p.title, 'Rock & Roll');
    expect(p.entries.single.title, 'A <1>');
    expect(p.entries.single.duration, const Duration(milliseconds: 1500));
  });

  test(
    'LIB-007 CUE sheet splits a FLAC into tracks with starts and durations',
    () {
      final p = parseCue(
        'PERFORMER "Band"\nTITLE "Album"\nFILE "album.flac" WAVE\n'
        '  TRACK 01 AUDIO\n    TITLE "One"\n    INDEX 01 00:00:00\n'
        '  TRACK 02 AUDIO\n    TITLE "Two"\n    PERFORMER "Guest"\n    INDEX 00 03:58:00\n    INDEX 01 04:00:37\n',
        base: base,
      );
      expect(p.title, 'Album');
      expect(p.entries, hasLength(2));
      expect(p.entries[0].location, 'file:///music/lists/album.flac');
      expect(p.entries[1].start, const Duration(minutes: 4, milliseconds: 493));
      expect(
        p.entries[0].duration,
        const Duration(minutes: 4, milliseconds: 493),
      );
      expect(p.entries[1].artist, 'Guest');
      expect(p.entries[0].artist, 'Band');
    },
  );

  test('PRIV-005 playlists over the size limit are refused; parsing runs on an isolate', () async {
    final huge = Uint8List(maxPlaylistBytes + 1);
    expect(
      () => parsePlaylistIsolated(huge, PlaylistFormat.m3u),
      throwsA(isA<PlaylistFormatException>()),
    );
    final p = await parsePlaylistIsolated(
      Uint8List.fromList(utf8.encode('a.mp3\n')),
      PlaylistFormat.m3u,
      base: base,
    );
    expect(p.entries.single.location, 'file:///music/lists/a.mp3');
  });

  test('PRIV-005 legacy Latin-1 and UTF-16 playlists decode', () {
    expect(decodeText(Uint8List.fromList([0x63, 0x61, 0x66, 0xE9])), 'café');
    expect(
      decodeText(Uint8List.fromList([0xFF, 0xFE, 0x61, 0x00, 0x62, 0x00])),
      'ab',
    );
  });

  test('PRIV-005 XML parser refuses deep nesting and never expands DOCTYPE entities', () {
    expect(
      () => parseXml('${'<a>' * 100}${'</a>' * 100}'),
      throwsA(isA<XmlFormatException>()),
    );
    final doc = parseXml(
      '<!DOCTYPE x [<!ENTITY e SYSTEM "file:///etc/passwd">]><x>&e;&#65;&lt;</x>',
    );
    expect(doc.text, '&e;A<');
  });

  test('LIB-007 writers round-trip', () {
    const entries = [
      PlaylistEntry(
        'http://h/a.mp3',
        title: 'A & B',
        artist: 'X',
        duration: Duration(seconds: 61),
      ),
      PlaylistEntry('file:///m/b.flac', title: 'B'),
    ];
    expect(
      parseM3u(writeM3u(entries, title: 'T')).entries.first.title,
      'A & B',
    );
    expect(
      parsePls(writePls(entries)).entries.last.location,
      'file:///m/b.flac',
    );
    final x = parseXspf(writeXspf(entries, title: 'T'));
    expect(x.entries.first.title, 'A & B');
    expect(x.entries.first.duration, const Duration(seconds: 61));
  });
}
