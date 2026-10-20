import 'dart:typed_data';

import 'package:mediahro/features/music/tags/audio_tags.dart';
import 'package:mediahro/features/music/tags/byte_reader.dart';
import 'package:mediahro/features/music/tags/id3.dart';
import 'package:mediahro/features/music/tags/text_codec.dart';

/// iTunes-style `ilst` item atoms → canonical fields. Keys use Latin-1 for
/// the © byte (0xA9).
const Map<String, String> mp4TextAtoms = {
  '©nam': TagField.title,
  '©ART': TagField.artist,
  'aART': TagField.albumArtist,
  '©alb': TagField.album,
  '©gen': TagField.genre,
  '©wrt': TagField.composer,
  '©day': TagField.date,
  '©lyr': TagField.lyrics,
  '©cmt': TagField.comment,
  '©too': TagField.encoder,
  'cprt': TagField.copyright,
  'sonm': TagField.titleSort,
  'soar': TagField.artistSort,
  'soal': TagField.albumSort,
  'soaa': TagField.albumArtistSort,
  '©grp': TagField.grouping,
};

/// One atom: [offset] of its header, [dataOffset] of its payload.
final class Mp4Atom {
  const Mp4Atom(this.type, this.offset, this.headerSize, this.size);

  final String type;
  final int offset;
  final int headerSize;
  final int size;

  int get dataOffset => offset + headerSize;
  int get dataSize => size - headerSize;
  int get end => offset + size;
}

/// Atoms between [start] and [end].
List<Mp4Atom> mp4Children(ByteReader r, int start, int end) {
  final atoms = <Mp4Atom>[];
  var pos = start;
  while (pos + 8 <= end && atoms.length < TagLimits.maxFields) {
    final h = r.read(pos, 16);
    if (h.length < 8) break;
    var size = h.u32be(0);
    final type = decodeLatin1(Uint8List.sublistView(h, 4, 8));
    var header = 8;
    if (size == 1) {
      if (h.length < 16) break;
      size = h.u64be(8);
      header = 16;
    } else if (size == 0) {
      size = end - pos;
    }
    if (size < header || pos + size > end) {
      throw TagFormatException('bad atom $type');
    }
    atoms.add(Mp4Atom(type, pos, header, size));
    pos += size;
  }
  return atoms;
}

Mp4Atom? _child(List<Mp4Atom> atoms, String type) {
  for (final a in atoms) {
    if (a.type == type) return a;
  }
  return null;
}

/// Path of `moov` → … → `ilst`, for the writer (MUS-003).
final class Mp4MetaPath {
  const Mp4MetaPath(this.moov, this.udta, this.meta, this.ilst);

  final Mp4Atom moov;
  final Mp4Atom? udta;
  final Mp4Atom? meta;
  final Mp4Atom? ilst;
}

/// Whether [r] starts with an ISO BMFF `ftyp` box.
bool isMp4(ByteReader r) => r.read(4, 4).startsWithAscii('ftyp');

Mp4MetaPath? mp4MetaPath(ByteReader r) {
  final top = mp4Children(r, 0, r.length);
  final moov = _child(top, 'moov');
  if (moov == null) return null;
  final moovKids = mp4Children(r, moov.dataOffset, moov.end);
  final udta = _child(moovKids, 'udta');
  Mp4Atom? meta;
  if (udta != null) {
    meta = _child(mp4Children(r, udta.dataOffset, udta.end), 'meta');
  }
  meta ??= _child(moovKids, 'meta');
  Mp4Atom? ilst;
  if (meta != null) {
    ilst = _child(mp4Children(r, metaChildrenStart(r, meta), meta.end), 'ilst');
  }
  return Mp4MetaPath(moov, udta, meta, ilst);
}

/// `meta` is a full box (4 version/flag bytes) in ISO files but a plain
/// container in some QuickTime files.
int metaChildrenStart(ByteReader r, Mp4Atom meta) {
  final peek = r.read(meta.dataOffset + 4, 4);
  return peek.startsWithAscii('hdlr') ? meta.dataOffset : meta.dataOffset + 4;
}

void parseMp4(ByteReader r, TagBuilder out) {
  final path = mp4MetaPath(r);
  if (path == null) throw const TagFormatException('no moov');
  out.containers.add(TagContainer.mp4);
  final moovKids = mp4Children(r, path.moov.dataOffset, path.moov.end);
  final mvhd = _child(moovKids, 'mvhd');
  if (mvhd != null) _mvhd(readExact(r, mvhd.dataOffset, mvhd.dataSize), out);
  if (path.udta != null) {
    final chpl = _child(
      mp4Children(r, path.udta!.dataOffset, path.udta!.end),
      'chpl',
    );
    if (chpl != null) {
      _chpl(readExact(r, chpl.dataOffset, chpl.dataSize), out);
    }
  }
  final ilst = path.ilst;
  if (ilst == null) return;
  if (ilst.dataSize > TagLimits.maxTagBytes) {
    throw const TagFormatException('ilst too large');
  }
  final bytes = readExact(r, ilst.dataOffset, ilst.dataSize);
  final items = mp4Children(MemoryByteReader(bytes), 0, bytes.length);
  for (final item in items) {
    try {
      _item(bytes, item, out);
    } on TagFormatException {
      continue;
    }
  }
}

void _mvhd(Uint8List d, TagBuilder out) {
  if (d.isEmpty) return;
  final int scale;
  final int duration;
  if (d[0] == 1) {
    if (d.length < 32) return;
    scale = d.u32be(20);
    duration = d.u64be(24);
  } else {
    if (d.length < 20) return;
    scale = d.u32be(12);
    duration = d.u32be(16);
  }
  if (scale > 0 && duration > 0 && duration != 0xFFFFFFFF) {
    out.duration = Duration(microseconds: duration * 1000000 ~/ scale);
  }
}

/// Nero chapters: version, flags, optional u32, count, (u64 start in 100 ns, u8
/// length, UTF-8 title)*.
void _chpl(Uint8List d, TagBuilder out) {
  if (d.length < 5) return;
  var pos = 4;
  if (d[0] != 0) pos += 4;
  if (pos >= d.length) return;
  final count = d[pos++];
  for (var i = 0; i < count; i++) {
    if (pos + 9 > d.length) break;
    final start = d.u64be(pos);
    final len = d[pos + 8];
    pos += 9;
    if (pos + len > d.length) break;
    final title = decodeUtf8(Uint8List.sublistView(d, pos, pos + len));
    pos += len;
    out.addChapter(TagChapter(Duration(microseconds: start ~/ 10), title));
  }
}

void _item(Uint8List bytes, Mp4Atom item, TagBuilder out) {
  final kids = mp4Children(MemoryByteReader(bytes), item.dataOffset, item.end);
  final data = [
    for (final k in kids)
      if (k.type == 'data' && k.dataSize >= 8)
        (
          bytes.u32be(k.dataOffset) & 0xFFFFFF,
          Uint8List.sublistView(bytes, k.dataOffset + 8, k.end),
        ),
  ];
  if (data.isEmpty) return;
  final type = item.type;
  final text = mp4TextAtoms[type];
  if (text != null) {
    out.add(text, [for (final (t, v) in data) _text(t, v)]);
    return;
  }
  switch (type) {
    case 'trkn' || 'disk':
      final v = data.first.$2;
      if (v.length < 6) return;
      final n = v.u16be(2);
      final total = v.u16be(4);
      final isTrack = type == 'trkn';
      if (n > 0) {
        out.addOne(isTrack ? TagField.trackNumber : TagField.discNumber, '$n');
      }
      if (total > 0) {
        out.addOne(
          isTrack ? TagField.trackTotal : TagField.discTotal,
          '$total',
        );
      }
    case 'gnre':
      final v = data.first.$2;
      if (v.length >= 2) {
        final g = v.u16be(0) - 1;
        if (g >= 0 && g < id3v1Genres.length) {
          out.addOne(TagField.genre, id3v1Genres[g]);
        }
      }
    case 'cpil':
      final v = data.first.$2;
      if (v.isNotEmpty) {
        out.addOne(TagField.compilation, v.last != 0 ? '1' : '0');
      }
    case 'tmpo':
      final v = data.first.$2;
      if (v.length >= 2 && v.u16be(0) > 0) {
        out.addOne(TagField.bpm, '${v.u16be(0)}');
      }
    case 'covr':
      for (final (t, v) in data) {
        if (v.length > TagLimits.maxPictureBytes) continue;
        final mime = switch (t) {
          13 => 'image/jpeg',
          14 => 'image/png',
          27 => 'image/bmp',
          _ => '',
        };
        final copy = Uint8List.fromList(v);
        out.addPicture(
          EmbeddedPicture(
            type: PictureType.frontCover,
            mimeType: normaliseMime(mime, copy),
            bytes: copy,
          ),
        );
      }
    case '----':
      String? name;
      for (final k in kids) {
        if (k.type == 'name' && k.dataSize >= 4) {
          name = decodeUtf8(
            Uint8List.sublistView(bytes, k.dataOffset + 4, k.end),
          );
        }
      }
      if (name == null) return;
      out.add(userFieldAliases[name.toLowerCase()] ?? name.toUpperCase(), [
        for (final (t, v) in data) _text(t, v),
      ]);
  }
}

String _text(int type, Uint8List v) => switch (type) {
  2 => decodeUtf16(v, bigEndian: true),
  21 when v.length <= 8 => '${_signed(v)}',
  _ => decodeUtf8(v),
};

int _signed(Uint8List v) {
  var n = 0;
  for (final b in v) {
    n = (n << 8) | b;
  }
  final bits = v.length * 8;
  if (bits > 0 && bits < 64 && n >= 1 << (bits - 1)) n -= 1 << bits;
  return n;
}
