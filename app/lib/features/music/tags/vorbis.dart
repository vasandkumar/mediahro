import 'dart:convert';
import 'dart:typed_data';

import 'package:mediahro/features/music/tags/audio_tags.dart';
import 'package:mediahro/features/music/tags/byte_reader.dart';
import 'package:mediahro/features/music/tags/id3.dart';
import 'package:mediahro/features/music/tags/text_codec.dart';

/// Vorbis-comment aliases written by other taggers → canonical names.
const Map<String, String> _aliases = {
  'ALBUM ARTIST': TagField.albumArtist,
  'ALBUM_ARTIST': TagField.albumArtist,
  'TOTALTRACKS': TagField.trackTotal,
  'TOTALDISCS': TagField.discTotal,
  'DESCRIPTION': TagField.comment,
  'UNSYNCEDLYRICS': TagField.lyrics,
  'YEAR': TagField.date,
  'ORGANIZATION': TagField.label,
  'PUBLISHER': TagField.label,
  'MUSICBRAINZ_RELEASEGROUPID': TagField.mbReleaseGroupId,
};

/// A Vorbis comment block (FLAC VORBIS_COMMENT, Ogg Vorbis/Opus/Speex
/// comment header) without the framing bit.
void parseVorbisComment(Uint8List b, TagBuilder out) {
  if (b.length < 8) throw const TagFormatException('short comment');
  final vendorLen = b.u32le(0);
  var pos = 4 + vendorLen;
  if (pos + 4 > b.length) throw const TagFormatException('vendor');
  final count = b.u32le(pos);
  pos += 4;
  out.containers.add(TagContainer.vorbisComment);
  // Ogg chapter extension: CHAPTERxxx=hh:mm:ss.fff, CHAPTERxxxNAME=title.
  final chapterStarts = <String, Duration>{};
  final chapterNames = <String, String>{};
  for (var i = 0; i < count && i < TagLimits.maxFields; i++) {
    if (pos + 4 > b.length) break;
    final len = b.u32le(pos);
    pos += 4;
    if (len > b.length - pos) break;
    final entry = decodeUtf8(Uint8List.sublistView(b, pos, pos + len));
    pos += len;
    final eq = entry.indexOf('=');
    if (eq <= 0) continue;
    final key = entry.substring(0, eq).toUpperCase();
    final value = entry.substring(eq + 1);
    if (key == 'METADATA_BLOCK_PICTURE') {
      try {
        parseFlacPicture(base64.decode(value.trim()), out);
      } on FormatException {
        continue;
      } on TagFormatException {
        continue;
      }
      continue;
    }
    if (key == 'COVERART') continue; // legacy base64 without a header
    if (RegExp(r'^CHAPTER\d+$').hasMatch(key)) {
      if (parseClock(value.trim()) case final Duration t) {
        chapterStarts[key] = t;
      }
      continue;
    }
    if (RegExp(r'^CHAPTER\d+NAME$').hasMatch(key)) {
      chapterNames[key.substring(0, key.length - 4)] = value;
      continue;
    }
    out.addOne(_aliases[key] ?? key, value);
  }
  for (final k in chapterStarts.keys.toList()..sort()) {
    out.addChapter(TagChapter(chapterStarts[k]!, chapterNames[k] ?? ''));
  }
}

/// FLAC PICTURE block (also base64 in METADATA_BLOCK_PICTURE).
void parseFlacPicture(Uint8List b, TagBuilder out) {
  var pos = 0;
  int u32() {
    if (pos + 4 > b.length) throw const TagFormatException('picture');
    final v = b.u32be(pos);
    pos += 4;
    return v;
  }

  String str(String Function(Uint8List) decode) {
    final n = u32();
    if (n > b.length - pos) throw const TagFormatException('picture');
    final s = decode(Uint8List.sublistView(b, pos, pos + n));
    pos += n;
    return s;
  }

  final type = PictureType.fromCode(u32());
  final mime = str(decodeLatin1);
  final desc = str(decodeUtf8);
  pos += 16; // width, height, depth, colours
  final len = u32();
  if (len > b.length - pos || len > TagLimits.maxPictureBytes) {
    throw const TagFormatException('picture data');
  }
  final data = Uint8List.fromList(Uint8List.sublistView(b, pos, pos + len));
  out.addPicture(
    EmbeddedPicture(
      type: type,
      mimeType: normaliseMime(mime, data),
      description: desc,
      bytes: data,
    ),
  );
}

/// One FLAC metadata block header.
final class FlacBlock {
  const FlacBlock(this.type, this.offset, this.length, {required this.last});

  /// 0 STREAMINFO, 1 PADDING, 2 APPLICATION, 3 SEEKTABLE, 4 VORBIS_COMMENT,
  /// 5 CUESHEET, 6 PICTURE.
  final int type;

  /// Offset of the block data (after the 4-byte header).
  final int offset;
  final int length;
  final bool last;
}

/// FLAC metadata blocks starting after `fLaC` at [start] (after any ID3v2).
List<FlacBlock> flacBlocks(ByteReader r, int start) {
  final magic = r.read(start, 4);
  if (!magic.startsWithAscii('fLaC')) {
    throw const TagFormatException('not FLAC');
  }
  final blocks = <FlacBlock>[];
  var pos = start + 4;
  while (blocks.length < TagLimits.maxFields) {
    final h = r.read(pos, 4);
    if (h.length < 4) throw const TagFormatException('truncated FLAC');
    final last = (h[0] & 0x80) != 0;
    final type = h[0] & 0x7F;
    final len = h.u24be(1);
    blocks.add(FlacBlock(type, pos + 4, len, last: last));
    pos += 4 + len;
    if (last) break;
  }
  return blocks;
}

void parseFlac(ByteReader r, int start, TagBuilder out) {
  for (final block in flacBlocks(r, start)) {
    switch (block.type) {
      case 0 when block.length >= 18:
        final si = readExact(r, block.offset, 18);
        final rate = (si[10] << 12) | (si[11] << 4) | (si[12] >> 4);
        final samples = ((si[13] & 0x0F) << 32) | si.u32be(14);
        if (rate > 0 && samples > 0) {
          out.duration = Duration(microseconds: samples * 1000000 ~/ rate);
        }
      case 4:
        parseVorbisComment(readExact(r, block.offset, block.length), out);
      case 6:
        try {
          parseFlacPicture(readExact(r, block.offset, block.length), out);
        } on TagFormatException {
          continue;
        }
    }
  }
}

/// Ogg: reassembles the first packets of the first logical stream and reads
/// the comment header (Vorbis, Opus, Speex, FLAC-in-Ogg).
void parseOgg(ByteReader r, TagBuilder out) {
  final packets = _oggPackets(r, maxPackets: 3);
  if (packets.isEmpty) throw const TagFormatException('no Ogg packets');
  final first = packets.first;
  Uint8List? comment;
  if (first.length >= 7 &&
      first[0] == 1 &&
      first.startsWithAscii('vorbis', 1)) {
    if (packets.length > 1 &&
        packets[1].length > 7 &&
        packets[1][0] == 3 &&
        packets[1].startsWithAscii('vorbis', 1)) {
      comment = Uint8List.sublistView(packets[1], 7);
    }
  } else if (first.startsWithAscii('OpusHead')) {
    if (packets.length > 1 && packets[1].startsWithAscii('OpusTags')) {
      comment = Uint8List.sublistView(packets[1], 8);
    }
  } else if (first.startsWithAscii('Speex   ')) {
    if (packets.length > 1) comment = packets[1];
  } else if (first.length > 13 &&
      first[0] == 0x7F &&
      first.startsWithAscii('FLAC', 1)) {
    // FLAC-in-Ogg: the next packets are metadata blocks; type 4 is the
    // comment.
    for (final p in packets.skip(1)) {
      if (p.isNotEmpty && (p[0] & 0x7F) == 4) {
        comment = Uint8List.sublistView(p, 4);
        break;
      }
    }
  }
  if (comment != null) parseVorbisComment(comment, out);
}

List<Uint8List> _oggPackets(ByteReader r, {required int maxPackets}) {
  final packets = <Uint8List>[];
  var current = BytesBuilder(copy: false);
  var pos = 0;
  int? serial;
  var pages = 0;
  while (packets.length < maxPackets && pages++ < 4096) {
    final h = r.read(pos, 27);
    if (h.length < 27 || !h.startsWithAscii('OggS')) break;
    final pageSerial = h.u32le(14);
    serial ??= pageSerial;
    final segCount = h[26];
    final table = readExact(r, pos + 27, segCount);
    var dataPos = pos + 27 + segCount;
    final pageLen = table.fold<int>(0, (a, b) => a + b);
    if (pageSerial != serial) {
      pos = dataPos + pageLen;
      continue;
    }
    for (final seg in table) {
      current.add(readExact(r, dataPos, seg));
      dataPos += seg;
      if (current.length > TagLimits.maxTagBytes) {
        throw const TagFormatException('Ogg packet too large');
      }
      if (seg < 255) {
        packets.add(current.toBytes());
        current = BytesBuilder(copy: false);
        if (packets.length >= maxPackets) break;
      }
    }
    pos = dataPos;
  }
  return packets;
}
