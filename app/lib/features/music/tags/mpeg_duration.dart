import 'package:mediahro/features/music/tags/byte_reader.dart';
import 'package:mediahro/features/music/tags/id3.dart';

const _bitrates = {
  'v1l3': [0, 32, 40, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320],
  'v2l3': [0, 8, 16, 24, 32, 40, 48, 56, 64, 80, 96, 112, 128, 144, 160],
  'v1l2': [0, 32, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320, 384],
  'v1l1': [
    0,
    32,
    64,
    96,
    128,
    160,
    192,
    224,
    256,
    288,
    320,
    352,
    384,
    416,
    448,
  ],
  'v2l1': [0, 32, 48, 56, 64, 80, 96, 112, 128, 144, 160, 176, 192, 224, 256],
};

const _rates = [
  [44100, 48000, 32000], // MPEG-1
  [22050, 24000, 16000], // MPEG-2
  [11025, 12000, 8000], // MPEG-2.5
];

/// Duration of an MPEG audio stream (MP3/MP2) from its Xing/Info or VBRI
/// header, else estimated from the first frame's bitrate (CBR). Null when no
/// frame is found near the start.
Duration? mpegDuration(ByteReader r) {
  final start = id3v2Size(r, 0) ?? 0;
  final probe = r.read(start, 64 * 1024);
  for (var i = 0; i + 4 <= probe.length; i++) {
    if (probe[i] != 0xFF || (probe[i + 1] & 0xE0) != 0xE0) continue;
    final h = probe.u32be(i);
    final versionBits = (h >> 19) & 3; // 0: 2.5, 2: 2, 3: 1
    final layerBits = (h >> 17) & 3; // 1: III, 2: II, 3: I
    final brIndex = (h >> 12) & 0xF;
    final srIndex = (h >> 10) & 3;
    if (versionBits == 1 || layerBits == 0 || brIndex == 0 || brIndex == 15) {
      continue;
    }
    if (srIndex == 3) continue;
    final v1 = versionBits == 3;
    final layer = 4 - layerBits;
    final rate =
        _rates[versionBits == 3 ? 0 : (versionBits == 2 ? 1 : 2)][srIndex];
    final table = switch ((v1, layer)) {
      (true, 3) => 'v1l3',
      (true, 2) => 'v1l2',
      (true, _) => 'v1l1',
      (false, 1) => 'v2l1',
      _ => 'v2l3',
    };
    final kbps = _bitrates[table]![brIndex];
    final samplesPerFrame = layer == 1 ? 384 : (layer == 3 && !v1 ? 576 : 1152);
    final mono = ((h >> 6) & 3) == 3;
    final sideInfo = v1 ? (mono ? 17 : 32) : (mono ? 9 : 17);
    // Xing / Info.
    final x = i + 4 + sideInfo;
    if (x + 12 <= probe.length &&
        (probe.startsWithAscii('Xing', x) ||
            probe.startsWithAscii('Info', x))) {
      final flags = probe.u32be(x + 4);
      if (flags & 1 != 0) {
        final frames = probe.u32be(x + 8);
        if (frames > 0) return _dur(frames * samplesPerFrame, rate);
      }
    }
    // VBRI (Fraunhofer): 32 bytes after the header.
    final vb = i + 36;
    if (vb + 18 <= probe.length && probe.startsWithAscii('VBRI', vb)) {
      final frames = probe.u32be(vb + 14);
      if (frames > 0) return _dur(frames * samplesPerFrame, rate);
    }
    final end = hasId3v1(r) ? r.length - 128 : r.length;
    final audioBytes = end - start - i;
    if (kbps <= 0 || audioBytes <= 0) return null;
    return Duration(microseconds: audioBytes * 8 * 1000 ~/ kbps);
  }
  return null;
}

Duration _dur(int samples, int rate) =>
    Duration(microseconds: samples * 1000000 ~/ rate);
