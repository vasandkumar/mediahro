import 'dart:typed_data';

import 'package:mediahro/features/music/tags/audio_tags.dart';
import 'package:mediahro/features/music/tags/byte_reader.dart';
import 'package:mediahro/features/music/tags/id3.dart';
import 'package:mediahro/features/music/tags/text_codec.dart';

/// APE item keys that differ from the canonical names.
const Map<String, String> _apeAliases = {
  'YEAR': TagField.date,
  'TRACK': TagField.trackNumber,
  'DISC': TagField.discNumber,
  'ALBUM ARTIST': TagField.albumArtist,
  'UNSYNCEDLYRICS': TagField.lyrics,
  'MUSICBRAINZ_TRACKID': TagField.mbRecordingId,
};

/// Location of an APEv1/v2 tag: `itemsOffset` of the first item, [itemsSize],
/// [itemCount], and the whole tag's range for the writer.
final class ApeTagLocation {
  const ApeTagLocation({
    required this.start,
    required this.end,
    required this.itemsOffset,
    required this.itemsSize,
    required this.itemCount,
    required this.version,
  });

  /// Whole tag including header (when present) and footer.
  final int start;
  final int end;
  final int itemsOffset;
  final int itemsSize;
  final int itemCount;
  final int version;
}

/// Finds an APE tag whose footer ends at [end] (the file end, or just
/// before an ID3v1 tag).
ApeTagLocation? findApeTag(ByteReader r, int end) {
  if (end < 32) return null;
  final f = r.read(end - 32, 32);
  if (f.length < 32 || !f.startsWithAscii('APETAGEX')) return null;
  final version = f.u32le(8);
  final size = f.u32le(12); // items + footer
  final count = f.u32le(16);
  final flags = f.u32le(20);
  if (size < 32 || size > TagLimits.maxTagBytes || size > end) {
    throw const TagFormatException('APE size');
  }
  final hasHeader = version >= 2000 && (flags & 0x80000000) != 0;
  final itemsOffset = end - size;
  return ApeTagLocation(
    start: hasHeader ? itemsOffset - 32 : itemsOffset,
    end: end,
    itemsOffset: itemsOffset,
    itemsSize: size - 32,
    itemCount: count,
    version: version,
  );
}

void parseApe(ByteReader r, ApeTagLocation loc, TagBuilder out) {
  final b = readExact(r, loc.itemsOffset, loc.itemsSize);
  out.containers.add(TagContainer.ape);
  var pos = 0;
  for (var i = 0; i < loc.itemCount && i < TagLimits.maxFields; i++) {
    if (pos + 8 > b.length) break;
    final len = b.u32le(pos);
    final flags = b.u32le(pos + 4);
    pos += 8;
    final keyEnd = b.indexOf(0, pos);
    if (keyEnd < 0 || keyEnd - pos > 255) break;
    final key = decodeLatin1(Uint8List.sublistView(b, pos, keyEnd));
    pos = keyEnd + 1;
    if (len > b.length - pos) break;
    final value = Uint8List.sublistView(b, pos, pos + len);
    pos += len;
    final kind = (flags >> 1) & 3; // 0 text, 1 binary, 2 external link
    final upper = key.toUpperCase();
    if (kind == 1) {
      if (upper.startsWith('COVER ART')) _cover(upper, value, out);
      continue;
    }
    if (kind != 0) continue;
    final values = decodeUtf8(value).split('\u0000');
    out.add(_apeAliases[upper] ?? upper, values);
  }
}

/// `Cover Art (Front)`: file name, NUL, image bytes.
void _cover(String key, Uint8List v, TagBuilder out) {
  final nul = v.indexOf(0);
  if (nul < 0) return;
  final bytes = Uint8List.fromList(Uint8List.sublistView(v, nul + 1));
  if (bytes.length > TagLimits.maxPictureBytes) return;
  out.addPicture(
    EmbeddedPicture(
      type: key.contains('BACK')
          ? PictureType.backCover
          : PictureType.frontCover,
      mimeType: normaliseMime('', bytes),
      bytes: bytes,
    ),
  );
}
