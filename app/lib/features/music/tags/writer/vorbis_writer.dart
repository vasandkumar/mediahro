import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:mediahro/features/music/tags/audio_tags.dart';
import 'package:mediahro/features/music/tags/byte_reader.dart';
import 'package:mediahro/features/music/tags/vorbis.dart';
import 'package:mediahro/features/music/tags/writer/tag_edit.dart';

/// A Vorbis comment block from the tags after an edit. Keys are written in
/// their canonical (upper-case) form, one entry per value; pictures go in
/// METADATA_BLOCK_PICTURE (Ogg) or separate PICTURE blocks (FLAC).
Uint8List buildVorbisComment(
  AudioTags t, {
  required String vendor,
  required bool picturesInline,
}) {
  final entries = <List<int>>[
    for (final e in t.fields.entries)
      for (final v in e.value) utf8.encode('${e.key}=$v'),
    if (picturesInline)
      for (final p in t.pictures)
        utf8.encode(
          'METADATA_BLOCK_PICTURE=${base64.encode(flacPictureBlock(p))}',
        ),
  ];
  final vb = utf8.encode(vendor);
  final b = BytesBuilder(copy: false)
    ..u32le(vb.length)
    ..add(vb)
    ..u32le(entries.length);
  for (final e in entries) {
    b
      ..u32le(e.length)
      ..add(e);
  }
  return b.toBytes();
}

/// FLAC PICTURE block data (also the base64 payload in Ogg).
Uint8List flacPictureBlock(EmbeddedPicture p) {
  final mime = latin1.encode(p.mimeType);
  final desc = utf8.encode(p.description);
  return (BytesBuilder(copy: false)
        ..u32be(p.type.index)
        ..u32be(mime.length)
        ..add(mime)
        ..u32be(desc.length)
        ..add(desc)
        ..u32be(0)
        ..u32be(0)
        ..u32be(0)
        ..u32be(0)
        ..u32be(p.bytes.length)
        ..add(p.bytes))
      .toBytes();
}

String _vendorOf(Uint8List comment) {
  if (comment.length < 4) return 'Mediahro';
  final n = comment.u32le(0);
  if (n > comment.length - 4) return 'Mediahro';
  return utf8.decode(
    Uint8List.sublistView(comment, 4, 4 + n),
    allowMalformed: true,
  );
}

/// FLAC: STREAMINFO and every block we don't manage are kept; the comment
/// (and pictures, when edited) are replaced; padding absorbs the size
/// change so re-edits stay cheap.
WritePlan planFlac(ByteReader r, AudioTags after, TagEdit edit) {
  final start = r.read(0, 4).startsWithAscii('fLaC') ? 0 : _afterId3(r);
  final blocks = flacBlocks(r, start);
  final audio = blocks.last.offset + blocks.last.length;
  var vendor = 'Mediahro';
  var oldPadding = 0;
  final kept = <(int, Uint8List)>[];
  for (final b in blocks) {
    switch (b.type) {
      case 1:
        oldPadding += b.length + 4;
      case 4:
        vendor = _vendorOf(readExact(r, b.offset, b.length));
      case 6 when edit.pictures != null:
        break;
      default:
        kept.add((b.type, readExact(r, b.offset, b.length)));
    }
  }
  final out = <(int, Uint8List)>[
    kept.first, // STREAMINFO
    (4, buildVorbisComment(after, vendor: vendor, picturesInline: false)),
    ...kept.skip(1),
    if (edit.pictures != null)
      for (final p in after.pictures) (6, flacPictureBlock(p)),
  ];
  final metaOld = audio - start - 4;
  final metaNew = out.fold<int>(0, (a, b) => a + 4 + b.$2.length);
  // Reuse the old space when the tag fits, else leave 4 KiB for next time.
  var padding = metaOld - metaNew - 4;
  if (padding < 0) padding = 4096;
  final b = BytesBuilder(copy: false)..ascii('fLaC');
  for (final (type, data) in [...out, (1, Uint8List(padding))]) {
    final last = type == 1;
    b
      ..u8((last ? 0x80 : 0) | type)
      ..u24be(data.length)
      ..add(data);
  }
  if (oldPadding < 0) throw const TagWriteUnsupported('padding');
  return WritePlan([
    if (start > 0) RangePart(0, start),
    BytesPart(b.toBytes()),
    RangePart(audio, r.length - audio),
  ]);
}

int _afterId3(ByteReader r) {
  final h = r.read(0, 10);
  if (!h.startsWithAscii('ID3')) return 0;
  return 10 + h.syncSafe(6) + (h[5] & 0x10 != 0 ? 10 : 0);
}

// ------------------------------------------------------------------- Ogg --

final Uint32List _crcTable = () {
  final t = Uint32List(256);
  for (var i = 0; i < 256; i++) {
    var r = i << 24;
    for (var k = 0; k < 8; k++) {
      r = (r & 0x80000000) != 0 ? ((r << 1) ^ 0x04C11DB7) : (r << 1);
      r &= 0xFFFFFFFF;
    }
    t[i] = r;
  }
  return t;
}();

/// Ogg page CRC (polynomial 0x04C11DB7, no reflection).
int oggCrc(Uint8List page) {
  var crc = 0;
  for (final b in page) {
    crc = ((crc << 8) ^ _crcTable[((crc >> 24) & 0xFF) ^ b]) & 0xFFFFFFFF;
  }
  return crc;
}

final class _Page {
  _Page(this.offset, this.header, this.segments, this.dataLength);
  final int offset;
  final Uint8List header; // 27 bytes
  final Uint8List segments;
  final int dataLength;

  int get serial => header.u32le(14);
  int get seq => header.u32le(18);
  int get length => 27 + segments.length + dataLength;
}

List<_Page> _pages(ByteReader r, {int max = 1 << 30}) {
  final pages = <_Page>[];
  var pos = 0;
  while (pos + 27 <= r.length && pages.length < max) {
    final h = readExact(r, pos, 27);
    if (!h.startsWithAscii('OggS')) {
      throw const TagFormatException('Ogg sync lost');
    }
    final segs = readExact(r, pos + 27, h[26]);
    final len = segs.fold<int>(0, (a, b) => a + b);
    pages.add(_Page(pos, h, segs, len));
    pos += 27 + segs.length + len;
  }
  return pages;
}

/// Ogg Vorbis/Opus: the comment packet is rebuilt; the header packets after
/// the first page are re-paged; when the page count changes, every later
/// page of the stream gets its sequence number shifted and its CRC redone.
WritePlan planOgg(ByteReader r, AudioTags after, TagEdit edit) {
  // Header pages: read until the comment (and Vorbis setup) packets end.
  final allPages = _pages(r);
  if (allPages.isEmpty) throw const TagFormatException('no Ogg pages');
  final serial = allPages.first.serial;
  final first = readExact(r, 0, allPages.first.length);
  final firstData = Uint8List.sublistView(
    first,
    27 + allPages.first.segments.length,
  );
  final opus = firstData.startsWithAscii('OpusHead');
  final vorbis = firstData.length > 7 && firstData.startsWithAscii('vorbis', 1);
  if (!opus && !vorbis) {
    throw const TagWriteUnsupported('Ogg codec without a comment writer');
  }
  // Reassemble packets 2 (comment) and, for Vorbis, 3 (setup).
  final wanted = vorbis ? 2 : 1;
  final packets = <Uint8List>[];
  var current = BytesBuilder(copy: false);
  var pi = 1;
  for (; pi < allPages.length && packets.length < wanted; pi++) {
    final p = allPages[pi];
    if (p.serial != serial) continue;
    var dataPos = p.offset + 27 + p.segments.length;
    for (final seg in p.segments) {
      current.add(readExact(r, dataPos, seg));
      dataPos += seg;
      if (seg < 255) {
        packets.add(current.toBytes());
        current = BytesBuilder(copy: false);
      }
    }
  }
  if (packets.length < wanted) throw const TagFormatException('headers');
  final headerEnd = allPages[pi - 1].offset + allPages[pi - 1].length;
  final oldHeaderPages = pi - 1;
  final oldComment = packets.first;
  final prefixLen = vorbis ? 7 : 8;
  final vendor = _vendorOf(Uint8List.sublistView(oldComment, prefixLen));
  final comment = BytesBuilder(copy: false)
    ..add(Uint8List.sublistView(oldComment, 0, prefixLen))
    ..add(buildVorbisComment(after, vendor: vendor, picturesInline: true));
  if (vorbis) comment.u8(1); // framing bit
  final newPackets = [comment.toBytes(), ...packets.skip(1)];
  final newPages = _paginate(newPackets, serial, firstSeq: 1);
  final delta = newPages.length - oldHeaderPages;
  final parts = <FilePart>[
    RangePart(0, allPages.first.length),
    for (final p in newPages) BytesPart(p),
  ];
  if (delta == 0) {
    parts.add(RangePart(headerEnd, r.length - headerEnd));
  } else {
    // Renumber the rest of this stream; pages of other streams are copied.
    for (final p in allPages.skip(pi)) {
      if (p.serial != serial) {
        parts.add(RangePart(p.offset, p.length));
        continue;
      }
      final page = Uint8List.fromList(readExact(r, p.offset, p.length));
      final seq = p.seq + delta;
      page
        ..setRange(18, 22, _le32(seq))
        ..setRange(22, 26, _le32(0));
      page.setRange(22, 26, _le32(oggCrc(page)));
      parts.add(BytesPart(page));
    }
  }
  return WritePlan(parts);
}

Uint8List _le32(int v) => Uint8List.fromList([
  v & 0xFF,
  (v >> 8) & 0xFF,
  (v >> 16) & 0xFF,
  (v >> 24) & 0xFF,
]);

/// Packs header packets into pages (granule 0), at most 255 segments each.
List<Uint8List> _paginate(
  List<Uint8List> packets,
  int serial, {
  required int firstSeq,
}) {
  final pages = <Uint8List>[];
  var seq = firstSeq;
  var segs = <int>[];
  var data = BytesBuilder(copy: false);
  var continued = false;
  var nextContinued = false;

  void flush() {
    final h = BytesBuilder(copy: false)
      ..ascii('OggS')
      ..u8(0)
      ..u8(continued ? 1 : 0)
      ..add(Uint8List(8)) // granule 0 for headers
      ..u32le(serial)
      ..u32le(seq++)
      ..u32le(0)
      ..u8(segs.length)
      ..add(segs)
      ..add(data.toBytes());
    final page = h.toBytes();
    page.setRange(22, 26, _le32(oggCrc(page)));
    pages.add(page);
    segs = [];
    data = BytesBuilder(copy: false);
    continued = nextContinued;
  }

  for (final packet in packets) {
    var pos = 0;
    while (true) {
      final n = math.min(255, packet.length - pos);
      segs.add(n);
      data.add(Uint8List.sublistView(packet, pos, pos + n));
      pos += n;
      final ended = n < 255;
      if (segs.length == 255) {
        nextContinued = !ended;
        flush();
        nextContinued = false;
      }
      if (ended) break;
    }
  }
  if (segs.isNotEmpty) flush();
  return pages;
}
