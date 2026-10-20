import 'dart:convert';
import 'dart:io' show ZLibDecoder;
import 'dart:typed_data';

import 'package:mediahro/features/music/tags/audio_tags.dart';
import 'package:mediahro/features/music/tags/byte_reader.dart';
import 'package:mediahro/features/music/tags/id3.dart';
import 'package:mediahro/features/music/tags/writer/tag_edit.dart';

/// Alias: a `label:` map key reads like a UI label to the project lint.
const String _labelKey = TagField.label;

/// Canonical field → ID3v2.4 text frame written for it.
const Map<String, String> _frameFor = {
  TagField.title: 'TIT2',
  TagField.artist: 'TPE1',
  TagField.albumArtist: 'TPE2',
  TagField.album: 'TALB',
  TagField.genre: 'TCON',
  TagField.composer: 'TCOM',
  TagField.conductor: 'TPE3',
  TagField.lyricist: 'TEXT',
  TagField.date: 'TDRC',
  TagField.originalDate: 'TDOR',
  TagField.bpm: 'TBPM',
  TagField.compilation: 'TCMP',
  _labelKey: 'TPUB',
  TagField.isrc: 'TSRC',
  TagField.copyright: 'TCOP',
  TagField.encoder: 'TSSE',
  TagField.titleSort: 'TSOT',
  TagField.artistSort: 'TSOP',
  TagField.albumSort: 'TSOA',
  TagField.albumArtistSort: 'TSO2',
  TagField.grouping: 'TIT1',
  TagField.discSubtitle: 'TSST',
};

/// Frames an edit of a canonical key replaces (v2.2, v2.3 and v2.4 ids).
Set<String> _framesOf(String key) => switch (key) {
  TagField.date => {'TDRC', 'TYER', 'TDAT', 'TIME', 'TYE', 'TDA', 'TIM'},
  TagField.originalDate => {'TDOR', 'TORY', 'TOR'},
  TagField.trackNumber || TagField.trackTotal => {'TRCK', 'TRK'},
  TagField.discNumber || TagField.discTotal => {'TPOS', 'TPA'},
  TagField.comment => {'COMM', 'COM'},
  TagField.lyrics => {'USLT', 'ULT'},
  TagField.rating => {'POPM', 'POP'},
  TagField.mbRecordingId => {'UFID', 'UFI'},
  TagField.grouping => {'TIT1', 'GRP1', 'TT1'},
  _ => {?_frameFor[key], ?_v22Of(_frameFor[key])},
};

String? _v22Of(String? v24) {
  if (v24 == null) return null;
  for (final e in _v22ToV24.entries) {
    if (e.value == v24) return e.key;
  }
  return null;
}

const Map<String, String> _v22ToV24 = {
  'TT2': 'TIT2', 'TP1': 'TPE1', 'TP2': 'TPE2', 'TAL': 'TALB', 'TCO': 'TCON', //
  'TCM': 'TCOM', 'TP3': 'TPE3', 'TXT': 'TEXT', 'TYE': 'TYER', 'TOR': 'TORY',
  'TRK': 'TRCK', 'TPA': 'TPOS', 'TBP': 'TBPM', 'TCP': 'TCMP', 'TPB': 'TPUB',
  'TRC': 'TSRC', 'TCR': 'TCOP', 'TSS': 'TSSE', 'TT1': 'TIT1', 'COM': 'COMM',
  'ULT': 'USLT', 'SLT': 'SYLT', 'PIC': 'APIC', 'TXX': 'TXXX', 'UFI': 'UFID',
  'POP': 'POPM', 'TLE': 'TLEN', 'TST': 'TSOT', 'TSP': 'TSOP', 'TSA': 'TSOA',
  'TS2': 'TSO2',
};

/// TXXX descriptions written for canonical keys without a dedicated frame.
const Map<String, String> _txxxFor = {
  TagField.trackGain: 'REPLAYGAIN_TRACK_GAIN',
  TagField.trackPeak: 'REPLAYGAIN_TRACK_PEAK',
  TagField.albumGain: 'REPLAYGAIN_ALBUM_GAIN',
  TagField.albumPeak: 'REPLAYGAIN_ALBUM_PEAK',
  TagField.mbAlbumId: 'MusicBrainz Album Id',
  TagField.mbArtistId: 'MusicBrainz Artist Id',
  TagField.mbAlbumArtistId: 'MusicBrainz Album Artist Id',
  TagField.mbReleaseGroupId: 'MusicBrainz Release Group Id',
  TagField.mbReleaseTrackId: 'MusicBrainz Release Track Id',
  TagField.acoustIdId: 'Acoustid Id',
  TagField.acoustIdFingerprint: 'Acoustid Fingerprint',
};

/// A raw frame kept from the original tag (already de-unsynchronised,
/// decompressed and stripped of grouping/length prefixes).
final class _Frame {
  _Frame(this.id, this.data);
  final String id;
  final Uint8List data;
}

/// Builds a new ID3v2.4 tag: the edited fields, plus every original frame
/// the edit does not touch (unknown frames such as PRIV, GEOB, RVA2, CHAP
/// are preserved). v2.2 and v2.3 tags are upgraded to v2.4.
Uint8List buildId3v2(
  ByteReader? original,
  int offset,
  AudioTags after,
  TagEdit edit, {
  int minSize = 0,
}) {
  final kept = original == null ? <_Frame>[] : _readFrames(original, offset);
  final replaced = <String>{};
  final replacedTxxx = <String>{};
  for (final k in edit.fields.keys) {
    replaced.addAll(_framesOf(k));
    final txxx = _txxxFor[k];
    if (txxx != null) replacedTxxx.add(txxx.toLowerCase());
    if (!_frameFor.containsKey(k) && txxx == null && _framesOf(k).isEmpty) {
      replacedTxxx.add(k.toLowerCase());
    }
  }
  if (edit.pictures != null) replaced.addAll({'APIC', 'PIC'});

  final out = BytesBuilder(copy: false);
  for (final f in kept) {
    if (replaced.contains(f.id)) continue;
    if (f.id == 'TXXX' || f.id == 'TXX') {
      final desc = _txxxDesc(f.data).toLowerCase();
      final canonical = userFieldAliases[desc];
      if (replacedTxxx.contains(desc) ||
          (canonical != null && edit.fields.containsKey(canonical))) {
        continue;
      }
    }
    final id = _v22ToV24[f.id] ?? f.id;
    if (id.length != 4) continue; // v2.2 frames without a v2.4 equivalent
    _frame(out, id, f.data);
  }
  for (final k in edit.fields.keys) {
    _writeField(out, k, after);
  }
  if (edit.pictures != null) {
    for (final p in after.pictures) {
      _frame(out, 'APIC', _apic(p));
    }
  }
  var body = out.toBytes();
  // Padding: keep the old size when the tag shrinks (cheap re-edits) and
  // add 1 KiB otherwise.
  final padding = body.length + 10 <= minSize
      ? minSize - body.length - 10
      : 1024;
  body = Uint8List.fromList([...body, ...Uint8List(padding)]);
  final tag = BytesBuilder(copy: false)
    ..ascii('ID3')
    ..add([4, 0, 0])
    ..syncSafe(body.length)
    ..add(body);
  return tag.toBytes();
}

void _writeField(BytesBuilder out, String key, AudioTags t) {
  final values = t.values(key);
  if (key == TagField.trackNumber || key == TagField.trackTotal) {
    final v = numberWithTotal(t, TagField.trackNumber, TagField.trackTotal);
    if (v != null && key == TagField.trackNumber) _text(out, 'TRCK', [v]);
    if (v != null &&
        key == TagField.trackTotal &&
        t.first(TagField.trackNumber) == null) {
      _text(out, 'TRCK', [v]);
    }
    return;
  }
  if (key == TagField.discNumber || key == TagField.discTotal) {
    final v = numberWithTotal(t, TagField.discNumber, TagField.discTotal);
    if (v != null && key == TagField.discNumber) _text(out, 'TPOS', [v]);
    if (v != null &&
        key == TagField.discTotal &&
        t.first(TagField.discNumber) == null) {
      _text(out, 'TPOS', [v]);
    }
    return;
  }
  if (values.isEmpty) return;
  final frame = _frameFor[key];
  if (frame != null) {
    _text(out, frame, values);
    return;
  }
  switch (key) {
    case TagField.comment:
      _frame(out, 'COMM', _langText(values.first));
    case TagField.lyrics:
      _frame(out, 'USLT', _langText(values.first));
    case TagField.rating:
      final percent = int.tryParse(values.first) ?? 0;
      _frame(
        out,
        'POPM',
        Uint8List.fromList([0, percentToPopm(percent), 0, 0, 0, 0]),
      );
    case TagField.mbRecordingId:
      _frame(
        out,
        'UFID',
        Uint8List.fromList([
          ...latin1.encode('http://musicbrainz.org'),
          0,
          ...latin1Bytes(values.first),
        ]),
      );
    default:
      final desc = _txxxFor[key] ?? key;
      _frame(
        out,
        'TXXX',
        Uint8List.fromList([
          3,
          ...utf8.encode(desc),
          0,
          ...utf8.encode(values.join('\u0000')),
        ]),
      );
  }
}

void _text(BytesBuilder out, String id, List<String> values) => _frame(
  out,
  id,
  Uint8List.fromList([3, ...utf8.encode(values.join('\u0000'))]),
);

Uint8List _langText(String text) => Uint8List.fromList([
  3,
  ...'eng'.codeUnits,
  0, // empty description
  ...utf8.encode(text),
]);

Uint8List _apic(EmbeddedPicture p) => Uint8List.fromList([
  3,
  ...latin1Bytes(p.mimeType),
  0,
  p.type.index,
  ...utf8.encode(p.description),
  0,
  ...p.bytes,
]);

void _frame(BytesBuilder out, String id, Uint8List data) {
  out
    ..ascii(id)
    ..syncSafe(data.length)
    ..u16be(0)
    ..add(data);
}

String _txxxDesc(Uint8List d) {
  if (d.isEmpty) return '';
  final enc = d[0];
  final wide = enc == 1 || enc == 2;
  var i = 1;
  final start = i;
  if (wide) {
    while (i + 1 < d.length && !(d[i] == 0 && d[i + 1] == 0)) {
      i += 2;
    }
    final raw = Uint8List.sublistView(d, start, i);
    final units = <int>[];
    var be = enc == 2;
    var j = 0;
    if (raw.length >= 2 && raw[0] == 0xFF && raw[1] == 0xFE) {
      be = false;
      j = 2;
    } else if (raw.length >= 2 && raw[0] == 0xFE && raw[1] == 0xFF) {
      be = true;
      j = 2;
    }
    for (; j + 1 < raw.length; j += 2) {
      units.add(be ? (raw[j] << 8) | raw[j + 1] : raw[j] | (raw[j + 1] << 8));
    }
    return String.fromCharCodes(units);
  }
  while (i < d.length && d[i] != 0) {
    i++;
  }
  final raw = Uint8List.sublistView(d, start, i);
  return enc == 3 ? utf8.decode(raw, allowMalformed: true) : latin1.decode(raw);
}

/// Raw frames of the tag at [offset], normalised to plain frame data.
List<_Frame> _readFrames(ByteReader r, int offset) {
  final size = id3v2Size(r, offset);
  if (size == null) return const [];
  final h = r.read(offset, 10);
  final major = h[3];
  final flags = h[5];
  var body = readExact(r, offset + 10, h.syncSafe(6));
  final globalUnsync = flags & 0x80 != 0;
  if (globalUnsync && major < 4) body = _deUnsync(body);
  var pos = 0;
  if (major >= 3 && flags & 0x40 != 0 && body.length >= 4) {
    pos = major == 3 ? 4 + body.u32be(0) : body.syncSafe(0);
  }
  final frames = <_Frame>[];
  final headerLen = major == 2 ? 6 : 10;
  while (pos + headerLen <= body.length &&
      frames.length < TagLimits.maxFields) {
    if (body[pos] == 0) break;
    final id = body.ascii(pos, major == 2 ? 3 : 4);
    if (!RegExp(r'^[A-Z0-9]+$').hasMatch(id)) break;
    final size = major == 2
        ? body.u24be(pos + 3)
        : major == 4
        ? body.syncSafe(pos + 4)
        : body.u32be(pos + 4);
    final fFlags = major == 2 ? 0 : body.u16be(pos + 8);
    final start = pos + headerLen;
    if (start + size > body.length) break;
    var data = Uint8List.sublistView(body, start, start + size);
    pos = start + size;
    try {
      data = _normalise(data, major, fFlags, globalUnsync);
    } on TagFormatException {
      continue; // encrypted frames are dropped
    }
    if (id == 'PIC' && data.length > 5) {
      // v2.2 PIC: encoding, 3-char format, type, description, data →
      // v2.4 APIC: encoding, MIME, NUL, type, description, data.
      final fmt = latin1
          .decode(Uint8List.sublistView(data, 1, 4))
          .toUpperCase();
      final mime = fmt == 'PNG' ? 'image/png' : 'image/jpeg';
      frames.add(
        _Frame(
          'APIC',
          Uint8List.fromList([
            data[0],
            ...latin1.encode(mime),
            0,
            ...Uint8List.sublistView(data, 4),
          ]),
        ),
      );
      continue;
    }
    frames.add(_Frame(id, Uint8List.fromList(data)));
  }
  return frames;
}

Uint8List _normalise(Uint8List d, int major, int flags, bool globalUnsync) {
  if (major == 2) return d;
  var data = d;
  var compressed = false;
  if (major == 3) {
    if (flags & 0x40 != 0) throw const TagFormatException('encrypted');
    if (flags & 0x80 != 0) {
      compressed = true;
      data = slice(data, 4, data.length - 4);
    }
    if (flags & 0x20 != 0) data = slice(data, 1, data.length - 1);
  } else {
    if (flags & 0x04 != 0) throw const TagFormatException('encrypted');
    if (flags & 0x40 != 0) data = slice(data, 1, data.length - 1);
    if (flags & 0x01 != 0) data = slice(data, 4, data.length - 4);
    if (flags & 0x02 != 0 || globalUnsync) data = _deUnsync(data);
    compressed = flags & 0x08 != 0;
  }
  if (compressed) {
    try {
      data = Uint8List.fromList(ZLibDecoder().convert(data));
    } on FormatException {
      throw const TagFormatException('bad zlib');
    }
  }
  return data;
}

Uint8List _deUnsync(Uint8List b) {
  final out = BytesBuilder(copy: false);
  var last = 0;
  for (var i = 1; i < b.length; i++) {
    if (b[i] == 0 && b[i - 1] == 0xFF) {
      out.add(Uint8List.sublistView(b, last, i));
      last = i + 1;
    }
  }
  out.add(Uint8List.sublistView(b, last));
  return out.toBytes();
}

/// ID3v1.1 for files that already carry one (kept in step with v2).
Uint8List buildId3v1(AudioTags t, Uint8List old) {
  List<int> field(String? v, int n) {
    final bytes = latin1.encode(
      (v ?? '').replaceAll(RegExp(r'[^\u0000-ÿ]'), '?'),
    );
    return [...bytes.take(n), ...List.filled(n - bytes.take(n).length, 0)];
  }

  final year = t.year?.toString();
  final track = (t.trackNumber ?? 0).clamp(0, 255);
  var genre = old.length == 128 ? old[127] : 255;
  final g = t.genres.isEmpty ? null : t.genres.first.toLowerCase();
  if (g != null) {
    final i = id3v1Genres.indexWhere((x) => x.toLowerCase() == g);
    genre = i < 0 ? 255 : i;
  }
  return Uint8List.fromList([
    ...'TAG'.codeUnits,
    ...field(t.title, 30),
    ...field(t.artist, 30),
    ...field(t.album, 30),
    ...field(year, 4),
    ...field(t.comment, 28),
    0,
    track,
    genre,
  ]);
}

/// MP3 and other ID3v2-at-start files: a new tag, the audio, and refreshed
/// trailing tags.
WritePlan planId3File(ByteReader r, AudioTags after, TagEdit edit) {
  final oldSize = id3v2Size(r, 0) ?? 0;
  final tag = buildId3v2(
    oldSize > 0 ? r : null,
    0,
    after,
    edit,
    minSize: oldSize,
  );
  final v1 = hasId3v1(r);
  final end = v1 ? r.length - 128 : r.length;
  return WritePlan([
    BytesPart(tag),
    RangePart(oldSize, end - oldSize),
    if (v1) BytesPart(buildId3v1(after, r.read(r.length - 128, 128))),
  ]);
}
