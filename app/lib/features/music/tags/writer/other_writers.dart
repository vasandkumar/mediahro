import 'dart:convert';
import 'dart:typed_data';

import 'package:mediahro/features/music/tags/ape.dart';
import 'package:mediahro/features/music/tags/asf.dart';
import 'package:mediahro/features/music/tags/audio_tags.dart';
import 'package:mediahro/features/music/tags/byte_reader.dart';
import 'package:mediahro/features/music/tags/id3.dart';
import 'package:mediahro/features/music/tags/writer/id3_writer.dart';
import 'package:mediahro/features/music/tags/writer/tag_edit.dart';

// -------------------------------------------------------------------- APE --

const Map<String, String> _apeKey = {
  TagField.title: 'Title',
  TagField.artist: 'Artist',
  TagField.albumArtist: 'Album Artist',
  TagField.album: 'Album',
  TagField.genre: 'Genre',
  TagField.composer: 'Composer',
  TagField.date: 'Year',
  TagField.trackNumber: 'Track',
  TagField.discNumber: 'Disc',
  TagField.comment: 'Comment',
  TagField.lyrics: 'Lyrics',
};

/// APEv2 (Monkey's Audio, WavPack, Musepack, and MP3s that carry one):
/// the old APE tag is replaced, binary items other than covers are kept,
/// and an ID3v1 after it is refreshed.
WritePlan planApe(ByteReader r, AudioTags after, TagEdit edit) {
  final v1 = hasId3v1(r);
  final end = v1 ? r.length - 128 : r.length;
  final loc = findApeTag(r, end);
  final keptBinary = <(String, int, Uint8List)>[];
  if (loc != null) {
    final b = readExact(r, loc.itemsOffset, loc.itemsSize);
    var pos = 0;
    for (var i = 0; i < loc.itemCount && pos + 8 <= b.length; i++) {
      final len = b.u32le(pos);
      final flags = b.u32le(pos + 4);
      final keyEnd = b.indexOf(0, pos + 8);
      if (keyEnd < 0 || keyEnd + 1 + len > b.length) break;
      final key = latin1.decode(Uint8List.sublistView(b, pos + 8, keyEnd));
      final value = Uint8List.sublistView(b, keyEnd + 1, keyEnd + 1 + len);
      pos = keyEnd + 1 + len;
      final binary = (flags >> 1) & 3 == 1;
      if (binary &&
          !(edit.pictures != null &&
              key.toUpperCase().startsWith('COVER ART'))) {
        keptBinary.add((key, flags, Uint8List.fromList(value)));
      }
    }
  }
  final items = BytesBuilder(copy: false);
  var count = 0;
  void item(String key, int flags, List<int> value) {
    // APE keys: 2–255 printable ASCII characters.
    if (key.length < 2 ||
        key.length > 255 ||
        key.codeUnits.any((u) => u < 0x20 || u > 0x7E)) {
      return;
    }
    items
      ..u32le(value.length)
      ..u32le(flags)
      ..add(latin1.encode(key))
      ..u8(0)
      ..add(value);
    count++;
  }

  for (final e in after.fields.entries) {
    final key = _apeKey[e.key] ?? e.key;
    item(key, 0, utf8.encode(e.value.join('\u0000')));
  }
  for (final (k, f, v) in keptBinary) {
    item(k, f, v);
  }
  if (edit.pictures != null) {
    for (final p in after.pictures) {
      final name = p.type == PictureType.backCover
          ? 'Cover Art (Back)'
          : 'Cover Art (Front)';
      item(name, 2, [...utf8.encode('cover.jpg'), 0, ...p.bytes]);
    }
  }
  final body = items.toBytes();
  Uint8List headerFooter(int flags) =>
      (BytesBuilder(copy: false)
            ..ascii('APETAGEX')
            ..u32le(2000)
            ..u32le(body.length + 32)
            ..u32le(count)
            ..u32le(flags)
            ..add(Uint8List(8)))
          .toBytes();
  final tag = BytesBuilder(copy: false)
    ..add(headerFooter(0xA0000000))
    ..add(body)
    ..add(headerFooter(0x80000000));
  final audioEnd = loc?.start ?? end;
  return WritePlan([
    RangePart(0, audioEnd),
    BytesPart(tag.toBytes()),
    if (v1) BytesPart(buildId3v1(after, r.read(r.length - 128, 128))),
  ]);
}

// -------------------------------------------------------------------- ASF --

Uint8List _utf16z(String s) => Uint8List.fromList([
  for (final u in s.codeUnits) ...[u & 0xFF, u >> 8],
  0,
  0,
]);

/// WMA: Content Description and Extended Content Description objects are
/// rebuilt; the Metadata Library loses entries for edited keys; header and
/// file sizes are updated.
WritePlan planAsf(ByteReader r, AudioTags after, TagEdit edit) {
  final head = readExact(r, 0, 30);
  final headerSize = head.u64le(16);
  final h = readExact(r, 0, headerSize);
  final kept = <Uint8List>[];
  Uint8List? fileProps;
  var pos = 30;
  final names = {for (final e in asfNames.entries) e.value: e.key};
  while (pos + 24 <= h.length) {
    final size = h.u64le(pos + 16);
    if (size < 24 || pos + size > h.length) break;
    final obj = Uint8List.sublistView(h, pos, pos + size);
    bool isG(Uint8List g) {
      for (var i = 0; i < 16; i++) {
        if (obj[i] != g[i]) return false;
      }
      return true;
    }

    if (isG(AsfGuid.contentDescription) || isG(AsfGuid.extendedContent)) {
      // Rebuilt below.
    } else if (isG(AsfGuid.fileProperties)) {
      fileProps = Uint8List.fromList(obj);
      kept.add(fileProps);
    } else {
      kept.add(Uint8List.fromList(obj));
    }
    pos += size;
  }
  // Content Description: title, author, copyright, description, rating.
  final cdStrings = [
    _utf16z(after.title ?? ''),
    _utf16z(after.artists.isEmpty ? '' : after.artists.first),
    _utf16z(after.first(TagField.copyright) ?? ''),
    _utf16z(after.comment ?? ''),
    _utf16z(''),
  ];
  final cd = BytesBuilder(copy: false)
    ..add(AsfGuid.contentDescription)
    ..u64le(24 + 10 + cdStrings.fold<int>(0, (a, s) => a + s.length));
  for (final s in cdStrings) {
    cd.u16le(s.length);
  }
  cdStrings.forEach(cd.add);
  // Extended content: every other field as a WM/ attribute (string type).
  final attrs = <List<int>>[];
  for (final e in after.fields.entries) {
    if (const {
      TagField.title,
      TagField.copyright,
      TagField.comment,
    }.contains(e.key)) {
      continue;
    }
    final name = names[e.key] ?? e.key;
    for (final v in e.value) {
      if (e.key == TagField.artist && v == e.value.first) continue;
      final n = _utf16z(name);
      final val = _utf16z(v);
      attrs.add(
        (BytesBuilder(copy: false)
              ..u16le(n.length)
              ..add(n)
              ..u16le(0)
              ..u16le(val.length)
              ..add(val))
            .toBytes(),
      );
    }
  }
  for (final p in after.pictures) {
    final mime = _utf16z(p.mimeType);
    final desc = _utf16z(p.description);
    final v =
        (BytesBuilder(copy: false)
              ..u8(p.type.index)
              ..u32le(p.bytes.length)
              ..add(mime)
              ..add(desc)
              ..add(p.bytes))
            .toBytes();
    if (v.length > 0xFFFF) continue; // WORD-sized value field
    final n = _utf16z('WM/Picture');
    attrs.add(
      (BytesBuilder(copy: false)
            ..u16le(n.length)
            ..add(n)
            ..u16le(1)
            ..u16le(v.length)
            ..add(v))
          .toBytes(),
    );
  }
  final ecBody = BytesBuilder(copy: false)..u16le(attrs.length);
  attrs.forEach(ecBody.add);
  final ecb = ecBody.toBytes();
  final ec = BytesBuilder(copy: false)
    ..add(AsfGuid.extendedContent)
    ..u64le(24 + ecb.length)
    ..add(ecb);
  final objects = [cd.toBytes(), ec.toBytes(), ...kept];
  final newHeaderSize = 30 + objects.fold<int>(0, (a, o) => a + o.length);
  final fp = fileProps;
  if (fp != null && fp.length >= 24 + 24) {
    final newFileSize = r.length - headerSize + newHeaderSize;
    fp.setRange(24 + 16, 24 + 24, _le64(newFileSize));
  }
  final header = BytesBuilder(copy: false)
    ..add(AsfGuid.header)
    ..u64le(newHeaderSize)
    ..u32le(objects.length)
    ..add([h[28], h[29]]);
  objects.forEach(header.add);
  return WritePlan([
    BytesPart(header.toBytes()),
    RangePart(headerSize, r.length - headerSize),
  ]);
}

Uint8List _le64(int v) =>
    Uint8List.fromList([for (var i = 0; i < 8; i++) (v >> (8 * i)) & 0xFF]);

// ------------------------------------------------------ WAV / AIFF / DSF --

const Map<String, String> _infoFor = {
  TagField.title: 'INAM',
  TagField.artist: 'IART',
  TagField.album: 'IPRD',
  TagField.genre: 'IGNR',
  TagField.date: 'ICRD',
  TagField.trackNumber: 'ITRK',
  TagField.comment: 'ICMT',
  TagField.copyright: 'ICOP',
  TagField.composer: 'IMUS',
};

/// WAV: a new `id3 ` chunk (the full tag) and a refreshed LIST/INFO chunk;
/// every other chunk is kept in place.
WritePlan planWav(ByteReader r, AudioTags after, TagEdit edit) =>
    _planChunks(r, after, edit, wav: true);

/// AIFF/AIFF-C: a new `ID3 ` chunk; NAME/AUTH/(c)/ANNO are dropped (the
/// ID3 tag holds them now).
WritePlan planAiff(ByteReader r, AudioTags after, TagEdit edit) =>
    _planChunks(r, after, edit, wav: false);

WritePlan _planChunks(
  ByteReader r,
  AudioTags after,
  TagEdit edit, {
  required bool wav,
}) {
  final h = readExact(r, 0, 12);
  int size(Uint8List b, int o) => wav ? b.u32le(o) : b.u32be(o);
  final end = r.length < 8 + size(h, 4) ? r.length : 8 + size(h, 4);
  final parts = <FilePart>[];
  var pos = 12;
  Uint8List? oldId3;
  while (pos + 8 <= end) {
    final c = readExact(r, pos, 8);
    final id = c.ascii(0, 4);
    final n = size(c, 4);
    final total = 8 + n + (n & 1);
    if (pos + 8 + n > end) {
      parts.add(RangePart(pos, end - pos));
      break;
    }
    final isId3 = id == 'id3 ' || id == 'ID3 ';
    final isInfo =
        wav && id == 'LIST' && r.read(pos + 8, 4).startsWithAscii('INFO');
    final isAiffText =
        !wav && const {'NAME', 'AUTH', '(c) ', 'ANNO'}.contains(id);
    if (isId3) {
      oldId3 = readExact(r, pos + 8, n);
    } else if (!isInfo && !isAiffText) {
      parts.add(RangePart(pos, total.clamp(0, end - pos)));
    }
    pos += total;
  }
  final id3 = buildId3v2(
    oldId3 == null ? null : MemoryByteReader(oldId3),
    0,
    after,
    edit,
  );
  final chunks = BytesBuilder(copy: false);
  void chunk(String id, List<int> data) {
    chunks.ascii(id);
    wav ? chunks.u32le(data.length) : chunks.u32be(data.length);
    chunks.add(data);
    if (data.length.isOdd) chunks.u8(0);
  }

  if (wav) {
    final info = BytesBuilder(copy: false)..ascii('INFO');
    for (final e in _infoFor.entries) {
      final v = after.first(e.key);
      if (v == null) continue;
      final bytes = [...utf8.encode(v), 0];
      info
        ..ascii(e.value)
        ..u32le(bytes.length)
        ..add(bytes);
      if (bytes.length.isOdd) info.u8(0);
    }
    chunk('LIST', info.toBytes());
    chunk('id3 ', id3);
  } else {
    chunk('ID3 ', id3);
  }
  final tail = chunks.toBytes();
  final bodyLength =
      4 + parts.fold<int>(0, (a, p) => a + p.length) + tail.length;
  final head = BytesBuilder(copy: false)..add(Uint8List.sublistView(h, 0, 4));
  wav ? head.u32le(bodyLength) : head.u32be(bodyLength);
  head.add(Uint8List.sublistView(h, 8, 12));
  return WritePlan([BytesPart(head.toBytes()), ...parts, BytesPart(tail)]);
}

/// DSF: the ID3v2 tag at the metadata pointer is replaced; the header's
/// file size and pointer are updated.
WritePlan planDsf(ByteReader r, AudioTags after, TagEdit edit) {
  final h = Uint8List.fromList(readExact(r, 0, 28));
  final meta = h.u64le(20);
  final audioEnd = meta > 0 && meta <= r.length ? meta : r.length;
  final tag = buildId3v2(
    meta > 0 && meta < r.length ? r : null,
    meta > 0 ? meta : 0,
    after,
    edit,
  );
  h
    ..setRange(12, 20, _le64(audioEnd + tag.length))
    ..setRange(20, 28, _le64(audioEnd));
  return WritePlan([
    BytesPart(h),
    RangePart(28, audioEnd - 28),
    BytesPart(tag),
  ]);
}
