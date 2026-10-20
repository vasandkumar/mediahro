import 'dart:convert';
import 'dart:typed_data';

/// Builders for synthetic tagged files (MUS-002 tests and fuzz seeds).

Uint8List bytesOf(List<List<int>> parts) =>
    Uint8List.fromList([for (final p in parts) ...p]);

List<int> ascii(String s) => s.codeUnits;
List<int> u16be(int v) => [(v >> 8) & 0xFF, v & 0xFF];
List<int> u16le(int v) => [v & 0xFF, (v >> 8) & 0xFF];
List<int> u24be(int v) => [(v >> 16) & 0xFF, (v >> 8) & 0xFF, v & 0xFF];
List<int> u32be(int v) => [
  (v >> 24) & 0xFF,
  (v >> 16) & 0xFF,
  (v >> 8) & 0xFF,
  v & 0xFF,
];
List<int> u32le(int v) => u32be(v).reversed.toList();
List<int> u64be(int v) => [...u32be(v >> 32), ...u32be(v & 0xFFFFFFFF)];
List<int> u64le(int v) => u64be(v).reversed.toList();
List<int> syncSafe(int v) => [
  (v >> 21) & 0x7F,
  (v >> 14) & 0x7F,
  (v >> 7) & 0x7F,
  v & 0x7F,
];
List<int> utf16le(String s, {bool bom = false, bool nul = false}) => [
  if (bom) ...[0xFF, 0xFE],
  for (final u in s.codeUnits) ...[u & 0xFF, u >> 8],
  if (nul) ...[0, 0],
];

/// A tiny valid JPEG-looking payload (magic bytes are what we sniff).
final jpeg = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, 1, 2, 3, 4, 5]);
final png = Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 9, 9]);

/// Fake MPEG audio frames after the tags.
final mpegAudio = List<int>.filled(64, 0xFF);

// ---- ID3v2

List<int> id3Frame(int major, String id, List<int> body, {int flags = 0}) {
  if (major == 2) return [...ascii(id), ...u24be(body.length), ...body];
  return [
    ...ascii(id),
    ...(major == 4 ? syncSafe(body.length) : u32be(body.length)),
    ...u16be(flags),
    ...body,
  ];
}

/// Text frame in UTF-8 (v2.4) or UTF-16 with BOM (v2.2/2.3); multiple values
/// NUL-separated.
List<int> id3Text(int major, String id, List<String> values) {
  if (major == 4) {
    return id3Frame(major, id, [3, ...utf8.encode(values.join('\u0000'))]);
  }
  return id3Frame(major, id, [
    1,
    for (var i = 0; i < values.length; i++) ...[
      if (i > 0) ...[0, 0],
      ...utf16le(values[i], bom: true),
    ],
  ]);
}

List<int> id3Txxx(int major, String desc, String value) => id3Frame(
  major,
  major == 2 ? 'TXX' : 'TXXX',
  [3, ...utf8.encode(desc), 0, ...utf8.encode(value)],
);

List<int> id3Apic(int major, Uint8List data, {int type = 3}) => major == 2
    ? id3Frame(2, 'PIC', [0, ...ascii('JPG'), type, ...ascii('d'), 0, ...data])
    : id3Frame(major, 'APIC', [
        0,
        ...ascii('image/jpeg'),
        0,
        type,
        ...ascii('Cover'),
        0,
        ...data,
      ]);

List<int> id3Uslt(int major, String text) => id3Frame(
  major,
  major == 2 ? 'ULT' : 'USLT',
  [3, ...ascii('eng'), 0, ...utf8.encode(text)],
);

List<int> id3Sylt(int major, List<(int, String)> lines) => id3Frame(
  major,
  major == 2 ? 'SLT' : 'SYLT',
  [
    3,
    ...ascii('eng'),
    2,
    1,
    0,
    for (final (ms, text) in lines) ...[...utf8.encode(text), 0, ...u32be(ms)],
  ],
);

List<int> id3Chap(int major, String id, int startMs, int endMs, String title) =>
    id3Frame(major, 'CHAP', [
      ...ascii(id),
      0,
      ...u32be(startMs),
      ...u32be(endMs),
      ...u32be(0xFFFFFFFF),
      ...u32be(0xFFFFFFFF),
      ...id3Text(major, 'TIT2', [title]),
    ]);

Uint8List id3v2(int major, List<List<int>> frames, {int padding = 32}) {
  final body = [for (final f in frames) ...f, ...List.filled(padding, 0)];
  return bytesOf([
    ascii('ID3'),
    [major, 0, 0],
    syncSafe(body.length),
    body,
  ]);
}

Uint8List id3v1({
  String title = '',
  String artist = '',
  String album = '',
  String year = '',
  int track = 0,
  int genre = 255,
}) {
  List<int> pad(String s, int n) =>
      [...latin1.encode(s), ...List.filled(n, 0)].sublist(0, n);
  return bytesOf([
    ascii('TAG'),
    pad(title, 30),
    pad(artist, 30),
    pad(album, 30),
    pad(year, 4),
    pad('', 28),
    [0, track, genre],
  ]);
}

// ---- APEv2

Uint8List apeTag(Map<String, String> items, {Uint8List? cover}) {
  final body = <int>[
    for (final e in items.entries) ...[
      ...u32le(utf8.encode(e.value).length),
      ...u32le(0),
      ...ascii(e.key),
      0,
      ...utf8.encode(e.value),
    ],
    if (cover != null) ...[
      ...u32le(cover.length + 6),
      ...u32le(2),
      ...ascii('Cover Art (Front)'),
      0,
      ...ascii('c.jpg'),
      0,
      ...cover,
    ],
  ];
  final count = items.length + (cover == null ? 0 : 1);
  List<int> hf(int flags) => [
    ...ascii('APETAGEX'),
    ...u32le(2000),
    ...u32le(body.length + 32),
    ...u32le(count),
    ...u32le(flags),
    ...List.filled(8, 0),
  ];
  return bytesOf([hf(0xA0000000), body, hf(0x80000000)]);
}

// ---- Vorbis comment / FLAC / Ogg

List<int> vorbisComment(List<String> entries) => [
  ...u32le(6),
  ...ascii('vendor'),
  ...u32le(entries.length),
  for (final e in entries) ...[
    ...u32le(utf8.encode(e).length),
    ...utf8.encode(e),
  ],
];

List<int> flacPicture(Uint8List data, {int type = 3}) => [
  ...u32be(type),
  ...u32be(10),
  ...ascii('image/jpeg'),
  ...u32be(5),
  ...ascii('Front'),
  ...List.filled(16, 0),
  ...u32be(data.length),
  ...data,
];

Uint8List flac(
  List<String> comments, {
  Uint8List? picture,
  int samples = 441000,
}) {
  // STREAMINFO: 44100 Hz, [samples] total.
  final si = List<int>.filled(18, 0);
  const rate = 44100;
  si[10] = (rate >> 12) & 0xFF;
  si[11] = (rate >> 4) & 0xFF;
  si[12] = ((rate & 0x0F) << 4) | 0x02;
  si[13] = (samples >> 32) & 0x0F;
  si.setRange(14, 18, u32be(samples & 0xFFFFFFFF));
  final vc = vorbisComment(comments);
  final pic = picture == null ? null : flacPicture(picture);
  List<int> block(int type, List<int> data, {bool last = false}) => [
    (last ? 0x80 : 0) | type,
    ...u24be(data.length),
    ...data,
  ];
  return bytesOf([
    ascii('fLaC'),
    block(0, si),
    block(4, vc, last: pic == null),
    if (pic != null) block(6, pic, last: true),
    List.filled(32, 0),
  ]);
}

List<int> oggPage(int serial, int seq, List<int> packet, {int flags = 0}) {
  final segs = <int>[];
  var n = packet.length;
  while (n >= 255) {
    segs.add(255);
    n -= 255;
  }
  segs.add(n);
  final page = [
    ...ascii('OggS'),
    0,
    flags,
    ...List.filled(8, 0),
    ...u32le(serial),
    ...u32le(seq),
    ...u32le(0),
    segs.length,
    ...segs,
    ...packet,
  ];
  return page..setRange(22, 26, u32le(_oggCrc(page)));
}

int _oggCrc(List<int> page) {
  var crc = 0;
  for (final b in page) {
    var c = ((crc >> 24) & 0xFF) ^ b;
    var r = c << 24;
    for (var k = 0; k < 8; k++) {
      r = (r & 0x80000000) != 0 ? ((r << 1) ^ 0x04C11DB7) : (r << 1);
      r &= 0xFFFFFFFF;
    }
    c = r;
    crc = ((crc << 8) ^ c) & 0xFFFFFFFF;
  }
  return crc;
}

/// Identification page, then one page holding the comment and setup
/// packets (as encoders write them).
Uint8List oggVorbis(List<String> comments) {
  final comment = [3, ...ascii('vorbis'), ...vorbisComment(comments), 1];
  final setup = [5, ...ascii('vorbis'), ...List.filled(40, 0x55)];
  final segs = <int>[];
  for (final p in [comment, setup]) {
    var n = p.length;
    while (n >= 255) {
      segs.add(255);
      n -= 255;
    }
    segs.add(n);
  }
  final page = [
    ...ascii('OggS'), 0, 0, ...List.filled(8, 0), ...u32le(7), ...u32le(1), //
    ...u32le(0), segs.length, ...segs, ...comment, ...setup,
  ];
  page.setRange(22, 26, u32le(_oggCrc(page)));
  return bytesOf([
    oggPage(7, 0, [1, ...ascii('vorbis'), ...List.filled(23, 0)], flags: 2),
    page,
  ]);
}

Uint8List oggOpus(List<String> comments) => bytesOf([
  oggPage(9, 0, [...ascii('OpusHead'), ...List.filled(11, 0)], flags: 2),
  oggPage(9, 1, [...ascii('OpusTags'), ...vorbisComment(comments)]),
]);

// ---- MP4

List<int> atom(String type, List<int> body) => [
  ...u32be(body.length + 8),
  ...latin1.encode(type),
  ...body,
];

List<int> mp4Data(int type, List<int> value) =>
    atom('data', [...u32be(type), ...u32be(0), ...value]);

Uint8List mp4({
  required Map<String, String> text,
  int? track,
  int? trackTotal,
  Uint8List? cover,
  Map<String, String> freeform = const {},
  int timescale = 1000,
  int duration = 0,
  List<(int, String)> chapters = const [],
}) {
  final ilst = [
    for (final e in text.entries)
      ...atom(e.key, mp4Data(1, utf8.encode(e.value))),
    if (track != null)
      ...atom(
        'trkn',
        mp4Data(0, [0, 0, ...u16be(track), ...u16be(trackTotal ?? 0), 0, 0]),
      ),
    if (cover != null) ...atom('covr', mp4Data(13, cover)),
    for (final e in freeform.entries)
      ...atom('----', [
        ...atom('mean', [0, 0, 0, 0, ...ascii('com.apple.iTunes')]),
        ...atom('name', [0, 0, 0, 0, ...utf8.encode(e.key)]),
        ...mp4Data(1, utf8.encode(e.value)),
      ]),
  ];
  final mvhd = atom('mvhd', [
    0, 0, 0, 0, //
    ...u32be(0),
    ...u32be(0),
    ...u32be(timescale),
    ...u32be(duration),
    ...List.filled(80, 0),
  ]);
  final chpl = chapters.isEmpty
      ? <int>[]
      : atom('chpl', [
          1, 0, 0, 0, //
          ...u32be(0),
          chapters.length,
          for (final (ms, t) in chapters) ...[
            ...u64be(ms * 10000),
            utf8.encode(t).length,
            ...utf8.encode(t),
          ],
        ]);
  final meta = atom('meta', [
    0, 0, 0, 0, //
    ...atom('hdlr', [
      ...List.filled(8, 0),
      ...ascii('mdir'),
      ...List.filled(13, 0),
    ]),
    ...atom('ilst', ilst),
  ]);
  return bytesOf([
    atom('ftyp', [...ascii('M4A '), ...u32be(0), ...ascii('isomM4A ')]),
    atom('moov', [
      ...mvhd,
      ...atom('udta', [...chpl, ...meta]),
    ]),
    atom('mdat', List.filled(16, 0)),
  ]);
}

// ---- ASF

List<int> _guid(String hex) => [
  for (var i = 0; i < hex.length; i += 2)
    int.parse(hex.substring(i, i + 2), radix: 16),
];

Uint8List asf({
  required String title,
  required String artist,
  Map<String, String> extended = const {},
  Uint8List? picture,
}) {
  final t = utf16le(title, nul: true);
  final a = utf16le(artist, nul: true);
  final cd = [
    ..._guid('3326B2758E66CF11A6D900AA0062CE6C'),
    ...u64le(24 + 10 + t.length + a.length),
    ...u16le(t.length),
    ...u16le(a.length),
    0, 0, 0, 0, 0, 0, //
    ...t,
    ...a,
  ];
  final attrs = <List<int>>[
    for (final e in extended.entries)
      [
        ...u16le(utf16le(e.key, nul: true).length),
        ...utf16le(e.key, nul: true),
        ...u16le(0),
        ...u16le(utf16le(e.value, nul: true).length),
        ...utf16le(e.value, nul: true),
      ],
    if (picture != null)
      () {
        final v = [
          3,
          ...u32le(picture.length),
          ...utf16le('image/jpeg', nul: true),
          ...utf16le('', nul: true),
          ...picture,
        ];
        return [
          ...u16le(utf16le('WM/Picture', nul: true).length),
          ...utf16le('WM/Picture', nul: true),
          ...u16le(1),
          ...u16le(v.length),
          ...v,
        ];
      }(),
  ];
  final ecBody = [...u16le(attrs.length), for (final x in attrs) ...x];
  final ec = [
    ..._guid('40A4D0D207E3D21197F000A0C95EA850'),
    ...u64le(24 + ecBody.length),
    ...ecBody,
  ];
  final total = 30 + cd.length + ec.length;
  return bytesOf([
    _guid('3026B2758E66CF11A6D900AA0062CE6C'),
    u64le(total),
    u32le(2),
    [1, 2],
    cd,
    ec,
    List.filled(32, 0),
  ]);
}

// ---- WAV / AIFF / DSF

Uint8List wav({Map<String, String> info = const {}, Uint8List? id3}) {
  final infoBody = [
    ...ascii('INFO'),
    for (final e in info.entries)
      ...() {
        final v = [...utf8.encode(e.value), 0];
        return [
          ...ascii(e.key),
          ...u32le(v.length),
          ...v,
          if (v.length.isOdd) 0,
        ];
      }(),
  ];
  final fmt = [
    ...u16le(1), ...u16le(2), ...u32le(44100), ...u32le(176400), //
    ...u16le(4), ...u16le(16),
  ];
  final data = List<int>.filled(176400 ~/ 10, 0);
  final chunks = [
    ...ascii('fmt '), ...u32le(fmt.length), ...fmt, //
    ...ascii('data'), ...u32le(data.length), ...data,
    if (info.isNotEmpty) ...[
      ...ascii('LIST'),
      ...u32le(infoBody.length),
      ...infoBody,
    ],
    if (id3 != null) ...[
      ...ascii('id3 '),
      ...u32le(id3.length),
      ...id3,
      if (id3.length.isOdd) 0,
    ],
  ];
  return bytesOf([
    ascii('RIFF'),
    u32le(chunks.length + 4),
    ascii('WAVE'),
    chunks,
  ]);
}

Uint8List aiff({String? name, Uint8List? id3}) {
  // 44100 Hz as 80-bit extended: 0x400E AC44 0000 0000 0000.
  final comm = [
    ...u16be(2), ...u32be(44100), ...u16be(16), //
    0x40, 0x0E, 0xAC, 0x44, 0, 0, 0, 0, 0, 0,
  ];
  final n = name == null ? <int>[] : [...ascii(name), if (name.length.isOdd) 0];
  final chunks = [
    ...ascii('COMM'), ...u32be(comm.length), ...comm, //
    if (name != null) ...[...ascii('NAME'), ...u32be(name.length), ...n],
    if (id3 != null) ...[
      ...ascii('ID3 '),
      ...u32be(id3.length),
      ...id3,
      if (id3.length.isOdd) 0,
    ],
  ];
  return bytesOf([
    ascii('FORM'),
    u32be(chunks.length + 4),
    ascii('AIFF'),
    chunks,
  ]);
}

Uint8List dsf(Uint8List id3) {
  const audio = 64;
  const metaAt = 28 + 52 + 12 + audio;
  return bytesOf([
    ascii('DSD '), u64le(28), u64le(metaAt + id3.length), u64le(metaAt), //
    ascii('fmt '), u64le(52), u32le(1), u32le(0), u32le(2), u32le(2),
    u32le(2822400), u32le(1), u64le(2822400 * 3), u32le(4096), u32le(0),
    ascii('data'), u64le(12 + audio), List.filled(audio, 0),
    id3,
  ]);
}
