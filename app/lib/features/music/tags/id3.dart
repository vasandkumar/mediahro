import 'dart:io' show ZLibDecoder;
import 'dart:typed_data';

import 'package:mediahro/features/music/tags/audio_tags.dart';
import 'package:mediahro/features/music/tags/byte_reader.dart';
import 'package:mediahro/features/music/tags/text_codec.dart';

/// ID3v1 genre names (with the Winamp extensions), indexed by code.
const id3v1Genres = [
  'Blues', 'Classic Rock', 'Country', 'Dance', 'Disco', 'Funk', 'Grunge', //
  'Hip-Hop', 'Jazz', 'Metal', 'New Age', 'Oldies', 'Other', 'Pop', 'R&B',
  'Rap', 'Reggae', 'Rock', 'Techno', 'Industrial', 'Alternative', 'Ska',
  'Death Metal', 'Pranks', 'Soundtrack', 'Euro-Techno', 'Ambient',
  'Trip-Hop', 'Vocal', 'Jazz+Funk', 'Fusion', 'Trance', 'Classical',
  'Instrumental', 'Acid', 'House', 'Game', 'Sound Clip', 'Gospel', 'Noise',
  'Alternative Rock', 'Bass', 'Soul', 'Punk', 'Space', 'Meditative',
  'Instrumental Pop', 'Instrumental Rock', 'Ethnic', 'Gothic', 'Darkwave',
  'Techno-Industrial', 'Electronic', 'Pop-Folk', 'Eurodance', 'Dream',
  'Southern Rock', 'Comedy', 'Cult', 'Gangsta', 'Top 40', 'Christian Rap',
  'Pop/Funk', 'Jungle', 'Native American', 'Cabaret', 'New Wave',
  'Psychedelic', 'Rave', 'Showtunes', 'Trailer', 'Lo-Fi', 'Tribal',
  'Acid Punk', 'Acid Jazz', 'Polka', 'Retro', 'Musical', 'Rock & Roll',
  'Hard Rock', 'Folk', 'Folk-Rock', 'National Folk', 'Swing', 'Fast Fusion',
  'Bebop', 'Latin', 'Revival', 'Celtic', 'Bluegrass', 'Avantgarde',
  'Gothic Rock', 'Progressive Rock', 'Psychedelic Rock', 'Symphonic Rock',
  'Slow Rock', 'Big Band', 'Chorus', 'Easy Listening', 'Acoustic', 'Humour',
  'Speech', 'Chanson', 'Opera', 'Chamber Music', 'Sonata', 'Symphony',
  'Booty Bass', 'Primus', 'Porn Groove', 'Satire', 'Slow Jam', 'Club',
  'Tango', 'Samba', 'Folklore', 'Ballad', 'Power Ballad', 'Rhythmic Soul',
  'Freestyle', 'Duet', 'Punk Rock', 'Drum Solo', 'A Cappella', 'Euro-House',
  'Dance Hall', 'Goa', 'Drum & Bass', 'Club-House', 'Hardcore Techno',
  'Terror', 'Indie', 'BritPop', 'Negerpunk', 'Polsk Punk', 'Beat',
  'Christian Gangsta Rap', 'Heavy Metal', 'Black Metal', 'Crossover',
  'Contemporary Christian', 'Christian Rock', 'Merengue', 'Salsa',
  'Thrash Metal', 'Anime', 'J-Pop', 'Synthpop', 'Abstract', 'Art Rock',
  'Baroque', 'Bhangra', 'Big Beat', 'Breakbeat', 'Chillout', 'Downtempo',
  'Dub', 'EBM', 'Eclectic', 'Electro', 'Electroclash', 'Emo',
  'Experimental', 'Garage', 'Global', 'IDM', 'Illbient', 'Industro-Goth',
  'Jam Band', 'Krautrock', 'Leftfield', 'Lounge', 'Math Rock',
  'New Romantic', 'Nu-Breakz', 'Post-Punk', 'Post-Rock', 'Psytrance',
  'Shoegaze', 'Space Rock', 'Trop Rock', 'World Music', 'Neoclassical',
  'Audiobook', 'Audio Theatre', 'Neue Deutsche Welle', 'Podcast',
  'Indie Rock', 'G-Funk', 'Dubstep', 'Garage Rock', 'Psybient',
];

/// ID3v2 text frames → canonical fields (v2.3/v2.4 ids; v2.2 ids are mapped
/// through [_v22]).
const Map<String, String> _textFrames = {
  'TIT2': TagField.title,
  'TPE1': TagField.artist,
  'TPE2': TagField.albumArtist,
  'TALB': TagField.album,
  'TCON': TagField.genre,
  'TCOM': TagField.composer,
  'TPE3': TagField.conductor,
  'TEXT': TagField.lyricist,
  'TYER': TagField.date,
  'TDRC': TagField.date,
  'TORY': TagField.originalDate,
  'TDOR': TagField.originalDate,
  'TRCK': TagField.trackNumber,
  'TPOS': TagField.discNumber,
  'TBPM': TagField.bpm,
  'TCMP': TagField.compilation,
  'TPUB': TagField.label,
  'TSRC': TagField.isrc,
  'TCOP': TagField.copyright,
  'TSSE': TagField.encoder,
  'TSOT': TagField.titleSort,
  'TSOP': TagField.artistSort,
  'TSOA': TagField.albumSort,
  'TSO2': TagField.albumArtistSort,
  'TIT1': TagField.grouping,
  'GRP1': TagField.grouping,
  'TSST': TagField.discSubtitle,
};

/// TXXX descriptions, MP4 freeform and ASF names (lower case) → canonical
/// fields (Picard/foobar2000 conventions).
const Map<String, String> userFieldAliases = {
  'musicbrainz album id': TagField.mbAlbumId,
  'musicbrainz artist id': TagField.mbArtistId,
  'musicbrainz album artist id': TagField.mbAlbumArtistId,
  'musicbrainz release group id': TagField.mbReleaseGroupId,
  'musicbrainz release track id': TagField.mbReleaseTrackId,
  'musicbrainz track id': TagField.mbRecordingId,
  'acoustid id': TagField.acoustIdId,
  'acoustid fingerprint': TagField.acoustIdFingerprint,
  'replaygain_track_gain': TagField.trackGain,
  'replaygain_track_peak': TagField.trackPeak,
  'replaygain_album_gain': TagField.albumGain,
  'replaygain_album_peak': TagField.albumPeak,
  'albumartist': TagField.albumArtist,
  'album artist': TagField.albumArtist,
  'tracktotal': TagField.trackTotal,
  'totaltracks': TagField.trackTotal,
  'disctotal': TagField.discTotal,
  'totaldiscs': TagField.discTotal,
  'originaldate': TagField.originalDate,
};

const Map<String, String> _v22 = {
  'TT2': 'TIT2', 'TP1': 'TPE1', 'TP2': 'TPE2', 'TAL': 'TALB', 'TCO': 'TCON', //
  'TCM': 'TCOM', 'TP3': 'TPE3', 'TXT': 'TEXT', 'TYE': 'TYER', 'TOR': 'TORY',
  'TRK': 'TRCK', 'TPA': 'TPOS', 'TBP': 'TBPM', 'TCP': 'TCMP', 'TPB': 'TPUB',
  'TRC': 'TSRC', 'TCR': 'TCOP', 'TSS': 'TSSE', 'TT1': 'TIT1', 'COM': 'COMM',
  'ULT': 'USLT', 'SLT': 'SYLT', 'PIC': 'APIC', 'TXX': 'TXXX', 'UFI': 'UFID',
  'POP': 'POPM', 'TLE': 'TLEN', 'TST': 'TSOT', 'TSP': 'TSOP', 'TSA': 'TSOA',
  'TS2': 'TSO2',
};

/// Size of the ID3v2 tag starting at [offset] (header + body + footer), or
/// null when there is none.
int? id3v2Size(ByteReader r, int offset) {
  final h = r.read(offset, 10);
  if (h.length < 10 || !h.startsWithAscii('ID3')) return null;
  if (h[3] < 2 || h[3] > 4 || h[3] == 0xFF) return null;
  if (h[6] | h[7] | h[8] | h[9] >= 0x80) return null;
  final footer = h[3] == 4 && (h[5] & 0x10) != 0 ? 10 : 0;
  return 10 + h.syncSafe(6) + footer;
}

/// Parses the ID3v2 tag at [offset] into [out]. Throws
/// [TagFormatException] on malformed input.
void parseId3v2(ByteReader r, int offset, TagBuilder out) {
  final size = id3v2Size(r, offset);
  if (size == null) return;
  final h = r.read(offset, 10);
  final major = h[3];
  final flags = h[5];
  final bodySize = h.syncSafe(6);
  if (bodySize > TagLimits.maxTagBytes) {
    throw const TagFormatException('ID3v2 tag too large');
  }
  var body = r.read(offset + 10, bodySize);
  final globalUnsync = (flags & 0x80) != 0;
  if (globalUnsync && major < 4) body = _deUnsync(body);
  var pos = 0;
  if (major >= 3 && (flags & 0x40) != 0 && body.length >= 4) {
    // Extended header: v2.3 size excludes its own 4 bytes, v2.4 includes them.
    pos = major == 3 ? 4 + body.u32be(0) : body.syncSafe(0);
    if (pos < 0 || pos > body.length) return;
  }
  out.containers.add(TagContainer.id3v2);
  _parseFrames(body, pos, body.length, major, globalUnsync, out);
}

void _parseFrames(
  Uint8List body,
  int start,
  int end,
  int major,
  bool globalUnsync,
  TagBuilder out,
) {
  final headerLen = major == 2 ? 6 : 10;
  var pos = start;
  var frames = 0;
  while (pos + headerLen <= end && frames++ < TagLimits.maxFields) {
    if (body[pos] == 0) break; // padding
    final idLen = major == 2 ? 3 : 4;
    final rawId = body.ascii(pos, idLen);
    if (!RegExp(r'^[A-Z0-9]+$').hasMatch(rawId)) break;
    int size;
    var fFlags = 0;
    if (major == 2) {
      size = body.u24be(pos + 3);
    } else {
      size = major == 4 ? body.syncSafe(pos + 4) : body.u32be(pos + 4);
      // iTunes wrote v2.4 sizes without sync-safe encoding; trust the plain
      // value when the sync-safe one does not land on a frame boundary.
      if (major == 4 && !_frameBoundary(body, pos + 10 + size, end)) {
        final plain = body.u32be(pos + 4);
        if (_frameBoundary(body, pos + 10 + plain, end)) size = plain;
      }
      fFlags = body.u16be(pos + 8);
    }
    final dataStart = pos + headerLen;
    if (size < 0 || dataStart + size > end) break;
    var data = Uint8List.sublistView(body, dataStart, dataStart + size);
    pos = dataStart + size;
    final id = major == 2 ? (_v22[rawId] ?? rawId) : rawId;
    try {
      data = _frameData(data, major, fFlags, globalUnsync);
    } on TagFormatException {
      continue;
    }
    if (data.isEmpty) continue;
    try {
      _frame(id, data, major, out);
    } on TagFormatException {
      continue;
      // A truncated frame body indexes past its end; skip just that frame.
      // ignore: avoid_catching_errors
    } on RangeError {
      continue;
    }
  }
}

bool _frameBoundary(Uint8List b, int at, int end) {
  if (at == end) return true;
  if (at > end || at + 4 > end) return at <= end;
  return b[at] == 0 || RegExp(r'^[A-Z0-9]{4}$').hasMatch(b.ascii(at, 4));
}

Uint8List _frameData(Uint8List data, int major, int flags, bool globalUnsync) {
  if (major == 2) return data;
  var d = data;
  var compressed = false;
  if (major == 3) {
    if (flags & 0x40 != 0) throw const TagFormatException('encrypted');
    if (flags & 0x80 != 0) {
      compressed = true;
      d = slice(d, 4, d.length - 4);
    }
    if (flags & 0x20 != 0) d = slice(d, 1, d.length - 1);
  } else {
    if (flags & 0x04 != 0) throw const TagFormatException('encrypted');
    if (flags & 0x40 != 0) d = slice(d, 1, d.length - 1);
    if (flags & 0x01 != 0) d = slice(d, 4, d.length - 4);
    if (flags & 0x02 != 0 || globalUnsync) d = _deUnsync(d);
    compressed = flags & 0x08 != 0;
  }
  if (compressed) d = _inflate(d);
  return d;
}

Uint8List _inflate(Uint8List d) {
  try {
    final out = ZLibDecoder().convert(d);
    if (out.length > TagLimits.maxTagBytes) {
      throw const TagFormatException('frame too large');
    }
    return Uint8List.fromList(out);
  } on FormatException {
    throw const TagFormatException('bad zlib');
  }
}

/// Removes ID3 unsynchronisation (FF 00 → FF).
Uint8List _deUnsync(Uint8List b) {
  final out = BytesBuilder(copy: false);
  var last = 0;
  for (var i = 0; i < b.length; i++) {
    if (b[i] == 0x00 && i > 0 && b[i - 1] == 0xFF) {
      out.add(Uint8List.sublistView(b, last, i));
      last = i + 1;
    }
  }
  out.add(Uint8List.sublistView(b, last));
  return out.toBytes();
}

void _frame(String id, Uint8List d, int major, TagBuilder out) {
  final canonical = _textFrames[id];
  if (canonical != null) {
    final e = id3Encoding(d[0]);
    var values = splitId3Text(Uint8List.sublistView(d, 1), e);
    if (id == 'TCON') values = values.expand(_genres).toList();
    out.add(canonical, values);
    return;
  }
  switch (id) {
    case 'TXXX':
      final e = id3Encoding(d[0]);
      final (desc, next) = readTerminated(d, 1, e);
      final values = splitId3Text(Uint8List.sublistView(d, next), e);
      final lower = desc.toLowerCase();
      if (lower == 'overdrive mediamarkers') {
        parseOverDriveMarkers(values.join(), out);
        return;
      }
      out.add(userFieldAliases[lower] ?? desc.toUpperCase(), values);
    case 'COMM' || 'USLT':
      final e = id3Encoding(d[0]);
      if (d.length < 4) return;
      final (desc, next) = readTerminated(d, 4, e);
      // iTunes stores normalisation and gapless data as comments.
      if (id == 'COMM' && desc.startsWith('iTun')) return;
      final text = decodeId3(Uint8List.sublistView(d, next), e);
      out.addOne(id == 'COMM' ? TagField.comment : TagField.lyrics, text);
    case 'SYLT':
      _sylt(d, out);
    case 'APIC':
      _apic(d, major, out);
    case 'UFID':
      final (owner, next) = readTerminated(d, 0, Id3Encoding.latin1);
      if (owner == 'http://musicbrainz.org') {
        out.addOne(
          TagField.mbRecordingId,
          decodeLatin1(Uint8List.sublistView(d, next)),
        );
      }
    case 'POPM':
      final (_, next) = readTerminated(d, 0, Id3Encoding.latin1);
      if (next < d.length && d[next] > 0) {
        out.addOne(TagField.rating, '${popmToPercent(d[next])}');
      }
    case 'TLEN':
      final ms = int.tryParse(
        decodeId3(Uint8List.sublistView(d, 1), id3Encoding(d[0])).trim(),
      );
      if (ms != null && ms > 0) out.duration ??= Duration(milliseconds: ms);
    case 'CHAP':
      _chap(d, major, out);
  }
}

/// TCON values: "(13)", "(13)Pop", "13", "(RX)", "(CR)" or free text.
Iterable<String> _genres(String v) sync* {
  final s = v.trim();
  if (s.isEmpty) return;
  final numeric = int.tryParse(s);
  if (numeric != null) {
    if (numeric >= 0 && numeric < id3v1Genres.length) {
      yield id3v1Genres[numeric];
    }
    return;
  }
  var rest = s;
  final refs = <String>[];
  while (rest.startsWith('(') && !rest.startsWith('((')) {
    final close = rest.indexOf(')');
    if (close < 0) break;
    final code = rest.substring(1, close);
    final n = int.tryParse(code);
    if (n != null && n >= 0 && n < id3v1Genres.length) {
      refs.add(id3v1Genres[n]);
    } else if (code == 'RX') {
      refs.add('Remix');
    } else if (code == 'CR') {
      refs.add('Cover');
    }
    rest = rest.substring(close + 1);
  }
  if (rest.startsWith('((')) rest = rest.substring(1);
  if (rest.trim().isNotEmpty) {
    yield rest.trim();
  } else {
    yield* refs;
  }
}

void _sylt(Uint8List d, TagBuilder out) {
  if (d.length < 6) return;
  final e = id3Encoding(d[0]);
  final format = d[4];
  if (format != 2) return; // only absolute milliseconds
  var (_, pos) = readTerminated(d, 6, e);
  while (pos < d.length) {
    final (text, next) = readTerminated(d, pos, e);
    if (next + 4 > d.length) break;
    final ms = d.u32be(next);
    out.syncedLyrics.add(
      SyncedLyricLine(Duration(milliseconds: ms), text.replaceAll('\n', '')),
    );
    if (out.syncedLyrics.length >= TagLimits.maxFields) break;
    pos = next + 4;
  }
}

void _apic(Uint8List d, int major, TagBuilder out) {
  final e = id3Encoding(d[0]);
  String mime;
  int pos;
  if (major == 2) {
    final fmt = d.ascii(1, 3).toUpperCase();
    mime = switch (fmt) {
      'PNG' => 'image/png',
      'JPG' => 'image/jpeg',
      _ => 'image/${fmt.toLowerCase()}',
    };
    pos = 4;
  } else {
    final (m, next) = readTerminated(d, 1, Id3Encoding.latin1);
    mime = m;
    pos = next;
  }
  if (pos >= d.length) return;
  final type = PictureType.fromCode(d[pos]);
  final (desc, dataAt) = readTerminated(d, pos + 1, e);
  final bytes = Uint8List.sublistView(d, dataAt);
  if (bytes.length > TagLimits.maxPictureBytes) return;
  out.addPicture(
    EmbeddedPicture(
      type: type,
      mimeType: normaliseMime(mime, bytes),
      description: desc,
      bytes: Uint8List.fromList(bytes),
    ),
  );
}

void _chap(Uint8List d, int major, TagBuilder out) {
  final (_, pos) = readTerminated(d, 0, Id3Encoding.latin1);
  if (pos + 16 > d.length) return;
  final start = d.u32be(pos);
  final end = d.u32be(pos + 4);
  final sub = TagBuilder();
  _parseFrames(d, pos + 16, d.length, major, false, sub);
  out.addChapter(
    TagChapter(
      Duration(milliseconds: start),
      sub.fields[TagField.title]?.first ?? '',
      end: end == 0xFFFFFFFF || end <= start
          ? null
          : Duration(milliseconds: end),
    ),
  );
}

/// OverDrive MediaMarkers XML (`<Marker><Name>…</Name><Time>m:ss.fff</Time>`).
void parseOverDriveMarkers(String xml, TagBuilder out) {
  final marker = RegExp(
    r'<Marker>\s*<Name>(.*?)</Name>\s*<Time>([\d:.]+)</Time>',
    dotAll: true,
  );
  for (final m in marker.allMatches(xml)) {
    final t = parseClock(m.group(2)!);
    if (t != null) {
      out.addChapter(TagChapter(t, _unescapeXml(m.group(1)!.trim())));
    }
  }
}

/// `h:mm:ss.fff`, `mm:ss.fff` or `ss.fff`.
Duration? parseClock(String s) {
  final parts = s.split(':');
  if (parts.isEmpty || parts.length > 3) return null;
  var seconds = 0.0;
  for (final p in parts) {
    final v = double.tryParse(p);
    if (v == null) return null;
    seconds = seconds * 60 + v;
  }
  return Duration(microseconds: (seconds * 1e6).round());
}

String _unescapeXml(String s) => s
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"')
    .replaceAll('&apos;', "'")
    .replaceAll('&amp;', '&');

/// Windows Media Player's POPM byte → percent (0 = unrated).
int popmToPercent(int b) => switch (b) {
  0 => 0,
  < 32 => 20,
  < 96 => 40,
  < 160 => 60,
  < 224 => 80,
  _ => 100,
};

int percentToPopm(int percent) => switch (percent) {
  <= 0 => 0,
  <= 20 => 1,
  <= 40 => 64,
  <= 60 => 128,
  <= 80 => 196,
  _ => 255,
};

/// Picture MIME type, sniffed from the bytes when the tag's value is vague.
String normaliseMime(String mime, Uint8List b) {
  final m = mime.trim().toLowerCase();
  if (b.length >= 4) {
    if (b[0] == 0xFF && b[1] == 0xD8) return 'image/jpeg';
    if (b[0] == 0x89 && b[1] == 0x50 && b[2] == 0x4E && b[3] == 0x47) {
      return 'image/png';
    }
    if (b.length >= 12 &&
        b.startsWithAscii('RIFF') &&
        b.startsWithAscii('WEBP', 8)) {
      return 'image/webp';
    }
    if (b.startsWithAscii('GIF8')) return 'image/gif';
  }
  if (m == 'jpg' || m == 'image/jpg') return 'image/jpeg';
  if (m == 'png') return 'image/png';
  return m.isEmpty ? 'application/octet-stream' : m;
}

/// ID3v1 / v1.1 at the last 128 bytes.
void parseId3v1(ByteReader r, TagBuilder out) {
  if (r.length < 128) return;
  final b = r.read(r.length - 128, 128);
  if (!b.startsWithAscii('TAG')) return;
  String field(int o, int n) {
    var end = o;
    while (end < o + n && b[end] != 0) {
      end++;
    }
    return decodeLatin1(Uint8List.sublistView(b, o, end)).trim();
  }

  out
    ..containers.add(TagContainer.id3v1)
    ..addOne(TagField.title, field(3, 30))
    ..addOne(TagField.artist, field(33, 30))
    ..addOne(TagField.album, field(63, 30))
    ..addOne(TagField.date, field(93, 4));
  if (b[125] == 0 && b[126] != 0) {
    out
      ..addOne(TagField.comment, field(97, 28))
      ..addOne(TagField.trackNumber, '${b[126]}');
  } else {
    out.addOne(TagField.comment, field(97, 30));
  }
  if (b[127] < id3v1Genres.length) {
    out.addOne(TagField.genre, id3v1Genres[b[127]]);
  }
}

/// Whether the file ends with an ID3v1 tag (128 bytes).
bool hasId3v1(ByteReader r) =>
    r.length >= 128 && r.read(r.length - 128, 3).startsWithAscii('TAG');
