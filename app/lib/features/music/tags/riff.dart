import 'dart:math' as math;
import 'dart:typed_data';

import 'package:mediahro/features/music/tags/audio_tags.dart';
import 'package:mediahro/features/music/tags/byte_reader.dart';
import 'package:mediahro/features/music/tags/id3.dart';
import 'package:mediahro/features/music/tags/text_codec.dart';

/// RIFF INFO list ids → canonical fields.
const Map<String, String> _info = {
  'INAM': TagField.title,
  'IART': TagField.artist,
  'IPRD': TagField.album,
  'IGNR': TagField.genre,
  'ICRD': TagField.date,
  'ITRK': TagField.trackNumber,
  'IPRT': TagField.trackNumber,
  'ICMT': TagField.comment,
  'ICOP': TagField.copyright,
  'ISFT': TagField.encoder,
  'IMUS': TagField.composer,
  'ICMS': TagField.composer,
};

/// WAV: LIST/INFO and an embedded `id3 ` chunk; duration from `fmt `/`data`.
void parseWav(ByteReader r, TagBuilder out) {
  final h = readExact(r, 0, 12);
  if (!h.startsWithAscii('RIFF') || !h.startsWithAscii('WAVE', 8)) {
    throw const TagFormatException('not WAV');
  }
  final end = math.min(r.length, 8 + h.u32le(4));
  final info = TagBuilder();
  final id3 = TagBuilder();
  var byteRate = 0;
  var dataSize = 0;
  var pos = 12;
  var chunks = 0;
  while (pos + 8 <= end && chunks++ < TagLimits.maxFields) {
    final c = r.read(pos, 8);
    if (c.length < 8) break;
    final id = c.ascii(0, 4);
    final size = c.u32le(4);
    final data = pos + 8;
    switch (id) {
      case 'fmt ' when size >= 16:
        byteRate = readExact(r, data, 16).u32le(8);
      case 'data':
        dataSize = math.min(size, end - data);
      case 'LIST' when size >= 4 && size <= TagLimits.maxTagBytes:
        final list = readExact(r, data, size);
        if (list.startsWithAscii('INFO')) _infoList(list, info);
      case 'id3 ' || 'ID3 ':
        if (size <= TagLimits.maxTagBytes) {
          parseId3v2(MemoryByteReader(readExact(r, data, size)), 0, id3);
        }
    }
    pos = data + size + (size & 1);
  }
  out.mergeMissing(id3);
  if (info.fields.isNotEmpty) {
    info.containers.add(TagContainer.riffInfo);
    out.mergeMissing(info);
  }
  if (byteRate > 0 && dataSize > 0) {
    out.duration ??= Duration(microseconds: dataSize * 1000000 ~/ byteRate);
  }
}

void _infoList(Uint8List list, TagBuilder out) {
  var pos = 4;
  while (pos + 8 <= list.length) {
    final id = list.ascii(pos, 4);
    final size = list.u32le(pos + 4);
    if (size > list.length - pos - 8) break;
    final raw = Uint8List.sublistView(list, pos + 8, pos + 8 + size);
    final key = _info[id];
    if (key != null) out.addOne(key, _zeroTerminated(raw));
    pos += 8 + size + (size & 1);
  }
}

/// INFO strings are nominally Latin-1; most modern writers emit UTF-8.
String _zeroTerminated(Uint8List b) {
  final nul = b.indexOf(0);
  final s = nul < 0 ? b : Uint8List.sublistView(b, 0, nul);
  final u = decodeUtf8(s);
  return u.contains('�') ? decodeLatin1(s) : u;
}

/// AIFF / AIFF-C: NAME, AUTH, (c), ANNO and an `ID3 ` chunk; duration from
/// COMM.
void parseAiff(ByteReader r, TagBuilder out) {
  final h = readExact(r, 0, 12);
  if (!h.startsWithAscii('FORM') ||
      !(h.startsWithAscii('AIFF', 8) || h.startsWithAscii('AIFC', 8))) {
    throw const TagFormatException('not AIFF');
  }
  final end = math.min(r.length, 8 + h.u32be(4));
  final text = TagBuilder();
  final id3 = TagBuilder();
  var pos = 12;
  var chunks = 0;
  while (pos + 8 <= end && chunks++ < TagLimits.maxFields) {
    final c = r.read(pos, 8);
    if (c.length < 8) break;
    final id = c.ascii(0, 4);
    final size = c.u32be(4);
    final data = pos + 8;
    if (size > TagLimits.maxTagBytes) break;
    switch (id) {
      case 'COMM' when size >= 18:
        final comm = readExact(r, data, 18);
        final frames = comm.u32be(2);
        final rate = _extended80(Uint8List.sublistView(comm, 8, 18));
        // A hostile COMM chunk can claim any rate; keep real ones only.
        if (rate >= 1000 && rate <= 6144000 && frames > 0) {
          out.duration = Duration(microseconds: (frames / rate * 1e6).round());
        }
      case 'NAME':
        text.addOne(TagField.title, _zeroTerminated(readExact(r, data, size)));
      case 'AUTH':
        text.addOne(TagField.artist, _zeroTerminated(readExact(r, data, size)));
      case '(c) ':
        text.addOne(
          TagField.copyright,
          _zeroTerminated(readExact(r, data, size)),
        );
      case 'ANNO':
        text.addOne(
          TagField.comment,
          _zeroTerminated(readExact(r, data, size)),
        );
      case 'ID3 ' || 'id3 ':
        parseId3v2(MemoryByteReader(readExact(r, data, size)), 0, id3);
    }
    pos = data + size + (size & 1);
  }
  out.mergeMissing(id3);
  if (text.fields.isNotEmpty) {
    text.containers.add(TagContainer.aiffText);
    out.mergeMissing(text);
  }
}

/// IEEE 754 80-bit extended (AIFF sample rate).
double _extended80(Uint8List b) {
  final exp = ((b[0] & 0x7F) << 8) | b[1];
  final sign = (b[0] & 0x80) != 0 ? -1 : 1;
  var mantissa = 0.0;
  for (var i = 0; i < 8; i++) {
    mantissa = mantissa * 256 + b[2 + i];
  }
  if (exp == 0 && mantissa == 0) return 0;
  return sign * mantissa * math.pow(2, exp - 16383 - 63).toDouble();
}

/// DSF: ID3v2 at the metadata pointer; duration from the `fmt ` chunk.
void parseDsf(ByteReader r, TagBuilder out) {
  final h = readExact(r, 0, 80);
  if (!h.startsWithAscii('DSD ') || !h.startsWithAscii('fmt ', 28)) {
    throw const TagFormatException('not DSF');
  }
  final freq = h.u32le(56);
  final samples = h.u64le(64);
  if (freq > 0 && samples > 0) {
    out.duration = Duration(microseconds: samples * 1000000 ~/ freq);
  }
  final meta = h.u64le(20);
  if (meta > 0 && meta < r.length) parseId3v2(r, meta, out);
}
