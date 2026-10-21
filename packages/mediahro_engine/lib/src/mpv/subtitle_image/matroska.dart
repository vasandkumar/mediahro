import 'dart:typed_data';

/// A track of a Matroska file.
final class MkvTrack {
  const MkvTrack({
    required this.number,
    required this.codecId,
    this.codecPrivate,
    this.pixelWidth,
    this.pixelHeight,
  });

  final int number;
  final String codecId;
  final Uint8List? codecPrivate;
  final int? pixelWidth;
  final int? pixelHeight;
}

/// One packet of a Matroska file.
final class MkvBlock {
  const MkvBlock({
    required this.track,
    required this.pts,
    required this.data,
    this.duration,
  });

  final int track;
  final Duration pts;
  final Duration? duration;
  final Uint8List data;
}

final class MatroskaFormatException implements Exception {
  const MatroskaFormatException(this.message);

  final String message;

  @override
  String toString() => 'MatroskaFormatException($message)';
}

/// The tracks and packets of a Matroska file as mpv's `dump-cache` writes
/// it (ADR-031 part 2). Only what subtitle extraction needs is read:
/// unlaced blocks, in file order.
final class MatroskaFile {
  MatroskaFile._(this.tracks, this.blocks);

  /// Parses [bytes]; stops at [maxBlocks] packets so a hostile file cannot
  /// make the parser build an unbounded list.
  factory MatroskaFile.parse(Uint8List bytes, {int maxBlocks = 200000}) {
    final r = _Reader(bytes, maxBlocks)..walk(0, bytes.length, _Ctx.top);
    return MatroskaFile._(r.tracks, r.blocks);
  }

  final List<MkvTrack> tracks;
  final List<MkvBlock> blocks;
}

// A subtitle block longer than an hour has no duration set.
const int _maxBlockUs = 3600 * 1000000;

enum _Ctx { top, segment, tracks, trackEntry, video, cluster, blockGroup, info }

const _idSegment = 0x18538067;
const _idInfo = 0x1549A966;
const _idTimecodeScale = 0x2AD7B1;
const _idTracks = 0x1654AE6B;
const _idTrackEntry = 0xAE;
const _idTrackNumber = 0xD7;
const _idCodecId = 0x86;
const _idCodecPrivate = 0x63A2;
const _idVideo = 0xE0;
const _idPixelWidth = 0xB0;
const _idPixelHeight = 0xBA;
const _idCluster = 0x1F43B675;
const _idTimecode = 0xE7;
const _idSimpleBlock = 0xA3;
const _idBlockGroup = 0xA0;
const _idBlock = 0xA1;
const _idBlockDuration = 0x9B;

final class _Reader {
  _Reader(this.b, this.maxBlocks);

  final Uint8List b;
  final int maxBlocks;
  final tracks = <MkvTrack>[];
  final blocks = <MkvBlock>[];

  int _scale = 1000000;
  int _clusterTime = 0;

  // The track entry being read.
  int? _number;
  String? _codec;
  Uint8List? _private;
  int? _w;
  int? _h;

  // The block group being read.
  Uint8List? _groupBlock;
  int? _groupDuration;

  void walk(int start, int end, _Ctx ctx) {
    var p = start;
    while (p < end && blocks.length < maxBlocks) {
      final idLen = _vintLength(p);
      if (idLen == 0 || p + idLen > end) return;
      var id = 0;
      for (var i = 0; i < idLen; i++) {
        id = (id << 8) | b[p + i];
      }
      p += idLen;
      if (p >= end) return;
      final sizeLen = _vintLength(p);
      if (sizeLen == 0 || p + sizeLen > end) return;
      var size = b[p] & (0xFF >> sizeLen);
      var unknown = size == (0xFF >> sizeLen);
      for (var i = 1; i < sizeLen; i++) {
        size = (size << 8) | b[p + i];
        if (b[p + i] != 0xFF) unknown = false;
      }
      p += sizeLen;
      // An unknown size runs to the end of the parent.
      final bodyEnd = unknown || p + size > end ? end : p + size;
      switch ((ctx, id)) {
        case (_Ctx.top, _idSegment):
          walk(p, bodyEnd, _Ctx.segment);
        case (_Ctx.segment, _idInfo):
          walk(p, bodyEnd, _Ctx.info);
        case (_Ctx.info, _idTimecodeScale):
          final v = _uint(p, bodyEnd);
          if (v > 0) _scale = v;
        case (_Ctx.segment, _idTracks):
          walk(p, bodyEnd, _Ctx.tracks);
        case (_Ctx.tracks, _idTrackEntry):
          _number = _codec = _private = _w = _h = null;
          walk(p, bodyEnd, _Ctx.trackEntry);
          final n = _number;
          final c = _codec;
          if (n != null && c != null) {
            tracks.add(
              MkvTrack(
                number: n,
                codecId: c,
                codecPrivate: _private,
                pixelWidth: _w,
                pixelHeight: _h,
              ),
            );
          }
        case (_Ctx.trackEntry, _idTrackNumber):
          _number = _uint(p, bodyEnd);
        case (_Ctx.trackEntry, _idCodecId):
          _codec = String.fromCharCodes(b.sublist(p, bodyEnd));
        case (_Ctx.trackEntry, _idCodecPrivate):
          _private = Uint8List.fromList(b.sublist(p, bodyEnd));
        case (_Ctx.trackEntry, _idVideo):
          walk(p, bodyEnd, _Ctx.video);
        case (_Ctx.video, _idPixelWidth):
          _w = _uint(p, bodyEnd);
        case (_Ctx.video, _idPixelHeight):
          _h = _uint(p, bodyEnd);
        case (_Ctx.segment, _idCluster):
          _clusterTime = 0;
          walk(p, bodyEnd, _Ctx.cluster);
        case (_Ctx.cluster, _idTimecode):
          _clusterTime = _uint(p, bodyEnd);
        case (_Ctx.cluster, _idSimpleBlock):
          _block(p, bodyEnd, null);
        case (_Ctx.cluster, _idBlockGroup):
          _groupBlock = null;
          _groupDuration = null;
          walk(p, bodyEnd, _Ctx.blockGroup);
          final s = _groupBlock;
          if (s != null) _block(0, s.length, _groupDuration, source: s);
        case (_Ctx.blockGroup, _idBlock):
          _groupBlock = Uint8List.fromList(b.sublist(p, bodyEnd));
        case (_Ctx.blockGroup, _idBlockDuration):
          _groupDuration = _uint(p, bodyEnd);
        default:
          break;
      }
      if (unknown && id != _idSegment && id != _idCluster) return;
      // An unknown-size element ran to the end of its parent.
      p = bodyEnd;
    }
  }

  // A block: track number (vint), signed 16-bit time, flags, then frames.
  void _block(int start, int end, int? duration, {Uint8List? source}) {
    final d = source ?? b;
    final len = _vintLengthIn(d, start);
    if (len == 0 || start + len + 3 > end) return;
    var track = d[start] & (0xFF >> len);
    for (var i = 1; i < len; i++) {
      track = (track << 8) | d[start + i];
    }
    var rel = (d[start + len] << 8) | d[start + len + 1];
    if (rel >= 0x8000) rel -= 0x10000;
    final flags = d[start + len + 2];
    // Subtitle tracks are not laced.
    if (flags & 0x06 != 0) return;
    final ticks = _clusterTime + rel;
    final ns = ticks * _scale;
    blocks.add(
      MkvBlock(
        track: track,
        pts: Duration(microseconds: ns ~/ 1000),
        // An unset duration (all ones) is not a duration.
        duration: duration == null || duration * _scale ~/ 1000 > _maxBlockUs
            ? null
            : Duration(microseconds: duration * _scale ~/ 1000),
        data: Uint8List.fromList(d.sublist(start + len + 3, end)),
      ),
    );
  }

  int _vintLength(int p) => _vintLengthIn(b, p);

  static int _vintLengthIn(Uint8List d, int p) {
    if (p >= d.length) return 0;
    final first = d[p];
    if (first == 0) return 0;
    var len = 1;
    var mask = 0x80;
    while (first & mask == 0) {
      mask >>= 1;
      len++;
    }
    return len > 8 ? 0 : len;
  }

  int _uint(int p, int end) {
    var v = 0;
    for (var i = p; i < end && i < p + 8; i++) {
      v = (v << 8) | b[i];
    }
    return v;
  }
}
