import 'dart:typed_data';

import 'package:mediahro/images/metadata/bytes.dart';
import 'package:mediahro/images/metadata/tiff.dart';
import 'package:meta/meta.dart';

/// A JPEG preview embedded in a RAW file, by position in the file.
@immutable
final class RawPreview {
  const RawPreview(this.offset, this.length);

  final int offset;
  final int length;
}

const int _subIfds = 0x014A;
const int _compression = 0x0103;
const int _stripOffsets = 0x0111;
const int _stripCounts = 0x0117;
const int _jpegOffset = TiffTag.thumbOffset;
const int _jpegLength = TiffTag.thumbLength;
const int _rw2JpgFromRaw = 0x002E;

/// The JPEG previews a RAW file carries, smallest first.
///
/// Camera RAWs embed one or more full-colour JPEGs (thumbnail, preview,
/// sometimes a near-full-size render). Gallery thumbnails and the first
/// frame of the viewer use these instead of developing the sensor data
/// (IMG-001, IMG-003). [head] holds the start of the file (a few MiB is
/// enough for the directories), [fileLength] its size. Supports TIFF-based
/// RAWs (NEF, ARW, DNG, CR2, ORF, RW2, PEF, SRW, ...) and Fujifilm RAF; Canon
/// CR3 is read through LibRaw.
List<RawPreview> findRawPreviews(Uint8List head, int fileLength) {
  final found = <RawPreview>[];
  void add(int offset, int length) {
    if (offset <= 0 || length < 1024) return;
    if (offset + length > fileLength) return;
    found.add(RawPreview(offset, length));
  }

  guardUntrusted<Object>(() {
    if (head.length > 92 &&
        String.fromCharCodes(head.sublist(0, 15)) == 'FUJIFILMCCD-RAW') {
      final v = ByteView(head);
      add(v.u32(84), v.u32(88));
    } else {
      final t = TiffStructure.parse(head);
      final seen = <int>{};
      void scan(TiffIfd? ifd) {
        if (ifd == null || !seen.add(ifd.offset)) return;
        final e = ifd.entries;
        final off = e[_jpegOffset];
        final len = e[_jpegLength];
        if (off != null && len != null) {
          add(t.ints(off).firstOrNull ?? 0, t.ints(len).firstOrNull ?? 0);
        }
        final comp = e[_compression];
        final so = e[_stripOffsets];
        final sc = e[_stripCounts];
        if (comp != null && so != null && sc != null) {
          final c = t.ints(comp).firstOrNull ?? 0;
          final offs = t.ints(so);
          final lens = t.ints(sc);
          // JPEG-compressed single strip: old-style (6) or new-style (7).
          if ((c == 6 || c == 7) && offs.length == 1 && lens.length == 1) {
            add(offs.first, lens.first);
          }
        }
        // Panasonic RW2: the JPEG sits inside the tag value.
        final rw2 = e[_rw2JpgFromRaw];
        if (rw2 != null && rw2.offset != null && rw2.raw.length > 1024) {
          add(rw2.offset!, rw2.raw.length);
        }
        final subs = e[_subIfds];
        if (subs != null) {
          for (final o in t.ints(subs).take(8)) {
            scan(t.ifdAt(o));
          }
        }
      }

      t.chain.forEach(scan);
    }
    return found;
  });
  found.sort((a, b) => a.length.compareTo(b.length));
  return found;
}

/// The preview to use for a [edge]-pixel thumbnail: the smallest one that is
/// big enough to be sharp (about 40 KB and up is ≥ 512 px), else the largest.
RawPreview? previewForThumbnail(List<RawPreview> previews, int edge) {
  if (previews.isEmpty) return null;
  final minBytes = edge <= 256 ? 20000 : 40000;
  for (final p in previews) {
    if (p.length >= minBytes) return p;
  }
  return previews.last;
}
