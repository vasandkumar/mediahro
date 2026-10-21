import 'dart:math' as math;
import 'dart:typed_data';

import 'package:mediahro_ffi/mediahro_ffi.dart';

/// Native DSD (AUD-043, ADR-023): mpv cannot emit DoP, so a DSD file is
/// presented to it as a 24-bit PCM WAV stream in DoP packing ("DSD over
/// PCM", the open standard from dsd-guide.com), made on the fly from the
/// DSF or DFF file. A DAC that recognises the alternating marker bytes plays
/// the DSD bits natively; the stream must therefore reach the device
/// unchanged (no resampling, gain or filters), which the engine arranges
/// for the item.

/// A DSD file's layout: where its sound data starts, how channels are
/// stored, and the rate.
final class DsdInfo {
  const DsdInfo({
    required this.isDsf,
    required this.channels,
    required this.dsdRate,
    required this.bytesPerChannel,
    required this.dataOffset,
    this.blockSize = 0,
  });

  /// DSF (little-endian, least significant bit first, blocks per channel) or
  /// DFF (big-endian IFF, most significant bit first, bytes interleaved).
  final bool isDsf;
  final int channels;

  /// 1-bit samples per second and channel: 2,822,400 for DSD64.
  final int dsdRate;
  final int bytesPerChannel;

  /// Where the first sound byte is in the file.
  final int dataOffset;

  /// DSF only: bytes per channel in one block.
  final int blockSize;

  /// The PCM rate of the DoP stream: 16 DSD bits per 24-bit sample.
  int get dopRate => dsdRate ~/ 16;

  /// DoP frames (one 24-bit sample per channel each).
  int get frames => bytesPerChannel ~/ 2;
}

/// Highest DSD rate sent as DoP (DSD256: 705.6 kHz PCM); higher ones are
/// converted to PCM, as few DACs take 1.4 MHz.
const int maxDopDsdRate = 2822400 * 4;

/// Reads [file]'s header; null when it is not an uncompressed DSF or DFF
/// that DoP can carry (mono or stereo, DSD64 to DSD256, DFF without DST).
Future<DsdInfo?> inspectDsd(VirtualFile file) async {
  try {
    final head = await file.read(0, 4096);
    if (head.length < 12) return null;
    final tag = String.fromCharCodes(head.sublist(0, 4));
    final info = switch (tag) {
      'DSD ' => await _inspectDsf(file, head),
      'FRM8' => await _inspectDff(file, head),
      _ => null,
    };
    if (info == null ||
        info.channels < 1 ||
        info.channels > 2 ||
        info.dsdRate % 16 != 0 ||
        info.dsdRate < 2822400 ||
        info.dsdRate > maxDopDsdRate ||
        info.frames <= 0) {
      return null;
    }
    return info;
  } on Object {
    return null;
  }
}

int _le32(Uint8List b, int o) =>
    b[o] | (b[o + 1] << 8) | (b[o + 2] << 16) | (b[o + 3] << 24);
int _le64(Uint8List b, int o) => _le32(b, o) | (_le32(b, o + 4) << 32);
int _be16(Uint8List b, int o) => (b[o] << 8) | b[o + 1];
int _be32(Uint8List b, int o) =>
    (b[o] << 24) | (b[o + 1] << 16) | (b[o + 2] << 8) | b[o + 3];
int _be64(Uint8List b, int o) => (_be32(b, o) << 32) | _be32(b, o + 4);

Future<DsdInfo?> _inspectDsf(VirtualFile file, Uint8List h) async {
  // 'DSD ' chunk (28 bytes), then 'fmt ' (52), then 'data'.
  if (h.length < 92 || String.fromCharCodes(h.sublist(28, 32)) != 'fmt ') {
    return null;
  }
  final formatId = _le32(h, 28 + 16);
  final channels = _le32(h, 28 + 24);
  final rate = _le32(h, 28 + 28);
  final bits = _le32(h, 28 + 32);
  final samples = _le64(h, 28 + 36);
  final block = _le32(h, 28 + 44);
  final dataAt = 28 + _le64(h, 28 + 4);
  // Raw DSD, least significant bit first.
  if (formatId != 0 || bits != 1 || block <= 0 || block > 1 << 20) return null;
  final tagAt = await file.read(dataAt, 4);
  if (String.fromCharCodes(tagAt) != 'data') return null;
  return DsdInfo(
    isDsf: true,
    channels: channels,
    dsdRate: rate,
    bytesPerChannel: (samples + 7) ~/ 8,
    dataOffset: dataAt + 12,
    blockSize: block,
  );
}

Future<DsdInfo?> _inspectDff(VirtualFile file, Uint8List h) async {
  if (String.fromCharCodes(h.sublist(12, 16)) != 'DSD ') return null;
  var channels = 0;
  var rate = 0;
  var offset = 16;
  Future<Uint8List> chunkHead(int at) => file.read(at, 12);
  for (var n = 0; n < 64; n++) {
    final c = await chunkHead(offset);
    if (c.length < 12) return null;
    final id = String.fromCharCodes(c.sublist(0, 4));
    final size = _be64(c, 4);
    if (id == 'PROP') {
      // 'SND ' then property chunks.
      final body = await file.read(offset + 12, size);
      if (body.length < 4 ||
          String.fromCharCodes(body.sublist(0, 4)) != 'SND ') {
        return null;
      }
      var p = 4;
      while (p + 12 <= body.length) {
        final pid = String.fromCharCodes(body.sublist(p, p + 4));
        final psize = _be64(body, p + 4);
        final at = p + 12;
        if (pid == 'FS  ' && at + 4 <= body.length) rate = _be32(body, at);
        if (pid == 'CHNL' && at + 2 <= body.length) channels = _be16(body, at);
        if (pid == 'CMPR' && at + 4 <= body.length) {
          // Only uncompressed DSD; DST is converted to PCM instead.
          if (String.fromCharCodes(body.sublist(at, at + 4)) != 'DSD ') {
            return null;
          }
        }
        p = at + psize + (psize.isOdd ? 1 : 0);
      }
    } else if (id == 'DSD ') {
      if (channels == 0 || rate == 0) return null;
      return DsdInfo(
        isDsf: false,
        channels: channels,
        dsdRate: rate,
        bytesPerChannel: size ~/ channels,
        dataOffset: offset + 12,
      );
    }
    offset += 12 + size + (size.isOdd ? 1 : 0);
  }
  return null;
}

// Most significant bit first: DSF stores the oldest sample in the least
// significant bit, so its bytes are reversed.
final Uint8List _reversed = Uint8List.fromList([
  for (var i = 0; i < 256; i++)
    (((i & 0x01) << 7) |
        ((i & 0x02) << 5) |
        ((i & 0x04) << 3) |
        ((i & 0x08) << 1) |
        ((i & 0x10) >> 1) |
        ((i & 0x20) >> 3) |
        ((i & 0x40) >> 5) |
        ((i & 0x80) >> 7)),
]);

/// Packs DSD into DoP: per channel, two consecutive DSD bytes (oldest
/// first, most significant bit first) go under an alternating marker byte
/// (0x05, 0xFA) into one 24-bit sample, written little-endian here as WAV
/// stores it. [channelBytes] holds one list per channel with `2 * frames`
/// bytes each, [firstFrame] is the absolute index of the first frame (the
/// marker parity), and [lsbFirst] reverses DSF bytes.
Uint8List dopPack(
  List<Uint8List> channelBytes, {
  required int firstFrame,
  required bool lsbFirst,
}) {
  final channels = channelBytes.length;
  final frames = channelBytes.first.length ~/ 2;
  final out = Uint8List(frames * channels * 3);
  var o = 0;
  for (var f = 0; f < frames; f++) {
    final marker = (firstFrame + f).isEven ? 0x05 : 0xFA;
    for (var c = 0; c < channels; c++) {
      var older = channelBytes[c][2 * f];
      var newer = channelBytes[c][2 * f + 1];
      if (lsbFirst) {
        older = _reversed[older];
        newer = _reversed[newer];
      }
      // Sample = marker << 16 | older << 8 | newer.
      out[o++] = newer;
      out[o++] = older;
      out[o++] = marker;
    }
  }
  return out;
}

/// The DoP stream as a WAV file: a 44-byte header, then 24-bit samples at
/// [DsdInfo.dopRate]. Seekable, with exact sample parity for any offset.
final class DopVirtualFile implements VirtualFile {
  DopVirtualFile(this._source, this.info, {Uri? uri})
    : uri = uri ?? Uri(scheme: 'dop', path: _source.uri.toString());

  final VirtualFile _source;
  final DsdInfo info;

  @override
  final Uri uri;

  static const int _headerBytes = 44;

  int get _frameBytes => info.channels * 3;
  int get _dataBytes => info.frames * _frameBytes;

  late final Uint8List _header = _wavHeader();

  Uint8List _wavHeader() {
    final h = ByteData(_headerBytes);
    void tag(int at, String s) {
      for (var i = 0; i < 4; i++) {
        h.setUint8(at + i, s.codeUnitAt(i));
      }
    }

    tag(0, 'RIFF');
    h.setUint32(4, 36 + _dataBytes, Endian.little);
    tag(8, 'WAVE');
    tag(12, 'fmt ');
    h
      ..setUint32(16, 16, Endian.little)
      ..setUint16(20, 1, Endian.little) // PCM
      ..setUint16(22, info.channels, Endian.little)
      ..setUint32(24, info.dopRate, Endian.little)
      ..setUint32(28, info.dopRate * _frameBytes, Endian.little)
      ..setUint16(32, _frameBytes, Endian.little)
      ..setUint16(34, 24, Endian.little);
    tag(36, 'data');
    h.setUint32(40, _dataBytes, Endian.little);
    return h.buffer.asUint8List();
  }

  @override
  bool get isSeekable => _source.isSeekable;

  @override
  Future<int?> length() async => _headerBytes + _dataBytes;

  @override
  Future<void> close() => _source.close();

  @override
  Future<Uint8List> read(int offset, int length) async {
    final total = _headerBytes + _dataBytes;
    if (offset >= total || length <= 0) return Uint8List(0);
    final end = math.min(offset + length, total);
    final out = BytesBuilder(copy: false);
    var at = offset;
    if (at < _headerBytes) {
      out.add(_header.sublist(at, math.min(end, _headerBytes)));
      at = _headerBytes;
    }
    if (at < end) {
      final from = at - _headerBytes;
      final to = end - _headerBytes;
      final f0 = from ~/ _frameBytes;
      final f1 = (to + _frameBytes - 1) ~/ _frameBytes;
      final packed = dopPack(
        await _channelBytes(f0, f1 - f0),
        firstFrame: f0,
        lsbFirst: info.isDsf,
      );
      final skip = from - f0 * _frameBytes;
      out.add(Uint8List.sublistView(packed, skip, skip + (to - from)));
    }
    return out.takeBytes();
  }

  // The DSD bytes of frames [firstFrame, firstFrame + frames), per channel.
  Future<List<Uint8List>> _channelBytes(int firstFrame, int frames) async {
    final start = 2 * firstFrame;
    final count = 2 * frames;
    final channels = info.channels;
    if (!info.isDsf) {
      // Interleaved bytes: one span, then split.
      final span = await _source.read(
        info.dataOffset + start * channels,
        count * channels,
      );
      final out = [for (var c = 0; c < channels; c++) Uint8List(count)];
      for (var i = 0; i < count; i++) {
        for (var c = 0; c < channels; c++) {
          final k = i * channels + c;
          if (k < span.length) out[c][i] = span[k];
        }
      }
      return out;
    }
    // Blocks of [DsdInfo.blockSize] bytes per channel, channel after channel.
    final out = [for (var c = 0; c < channels; c++) Uint8List(count)];
    final block = info.blockSize;
    var done = 0;
    while (done < count) {
      final n = start + done;
      final inBlock = n % block;
      final take = math.min(count - done, block - inBlock);
      final blockAt = info.dataOffset + (n ~/ block) * block * channels;
      for (var c = 0; c < channels; c++) {
        final bytes = await _source.read(blockAt + c * block + inBlock, take);
        out[c].setRange(done, done + bytes.length, bytes);
      }
      done += take;
    }
    return out;
  }
}
