// DVD-Video and Blu-ray folder fixtures for the corpus (VID-007): the IFO,
// MPLS and CLPI structures the engine's disc reader parses. Streams come
// from ffmpeg in generate.dart.
import 'dart:typed_data';

final class _W {
  final b = BytesBuilder();
  void u8(int v) => b.addByte(v & 0xff);
  void u16(int v) => b.add([(v >> 8) & 0xff, v & 0xff]);
  void u32(int v) =>
      b.add([(v >> 24) & 0xff, (v >> 16) & 0xff, (v >> 8) & 0xff, v & 0xff]);
  void ascii(String s) => b.add(s.codeUnits);
  void zeros(int n) => b.add(List.filled(n, 0));
  void bytes(List<int> v) => b.add(v);
  int get length => b.length;
  Uint8List done() => b.toBytes();
}

Uint8List _sectors(Map<int, List<int>> at, int count) {
  final out = Uint8List(count * 2048);
  for (final MapEntry(:key, :value) in at.entries) {
    out.setRange(key, key + value.length, value);
  }
  return out;
}

/// VIDEO_TS.IFO: two titles in title set 1 (title 1 = 2 chapters, title 2
/// = 1 chapter).
List<int> vmgIfo() {
  final srpt = _W()
    ..u16(2)
    ..u16(0)
    ..u32(8 + 2 * 12 - 1);
  for (final (ttn, chapters) in [(1, 2), (2, 1)]) {
    srpt
      ..u8(0x3C)
      ..u8(1)
      ..u16(chapters)
      ..u16(0)
      ..u8(1)
      ..u8(ttn)
      ..u32(0);
  }
  return _sectors({
    0: (_W()..ascii('DVDVIDEO-VMG')).done(),
    0xC4: (_W()..u32(1)).done(),
    2048: srpt.done(),
  }, 2);
}

List<int> _bcd(Duration d) {
  int enc(int v) => (v ~/ 10) << 4 | v % 10;
  final ms = d.inMilliseconds;
  final frames = (ms % 1000) * 25 ~/ 1000;
  return [
    enc(ms ~/ 3600000),
    enc(ms ~/ 60000 % 60),
    enc(ms ~/ 1000 % 60),
    0x40 | enc(frames),
  ];
}

List<int> _pgc(List<(int, int, Duration)> cells, List<int> programMap) {
  final p = _W()
    ..zeros(2)
    ..u8(programMap.length)
    ..u8(cells.length)
    ..bytes(_bcd(cells.fold(Duration.zero, (a, c) => a + c.$3)));
  p
    ..zeros(0xE6 - p.length)
    ..u16(0xEC)
    ..u16(0xF0)
    ..u16(0);
  p.zeros(0xEC - p.length);
  programMap.forEach(p.u8);
  p.zeros(0xF0 - p.length);
  for (final (first, last, time) in cells) {
    p
      ..zeros(4)
      ..bytes(_bcd(time))
      ..u32(first)
      ..u32(first)
      ..u32(last)
      ..u32(last);
  }
  return p.done();
}

/// VTS_01_0.IFO for a VOB of [sectors] sectors: AC-3 English audio, French
/// subpicture; PGC 1 = whole VOB in two cells/chapters, PGC 2 = second half.
List<int> vtsIfo(int sectors, {Duration half = const Duration(seconds: 3)}) {
  final mid = sectors ~/ 2;
  final pgc1 = _pgc([(0, mid - 1, half), (mid, sectors - 1, half)], [1, 2]);
  final pgc2 = _pgc([(mid, sectors - 1, half)], [1]);
  final pgci = _W()
    ..u16(2)
    ..u16(0)
    ..u32(0)
    ..u32(0x81000000)
    ..u32(24)
    ..u32(0x82000000)
    ..u32(24 + pgc1.length)
    ..bytes(pgc1)
    ..bytes(pgc2);
  final ptt = _W()
    ..u16(2)
    ..u16(0)
    ..u32(0)
    ..u32(16)
    ..u32(24)
    ..u16(1)
    ..u16(1)
    ..u16(1)
    ..u16(2)
    ..u16(2)
    ..u16(1);
  final audio = _W()
    ..u16(1)
    ..u8(0x04) // AC-3, language present
    ..u8(0x01) // 2 channels
    ..ascii('en')
    ..zeros(4);
  final subs = _W()
    ..u16(1)
    ..u8(0x01) // 2-bit RLE, language present
    ..u8(0)
    ..ascii('fr')
    ..zeros(2);
  final pgciBytes = pgci.done();
  return _sectors({
    0: (_W()..ascii('DVDVIDEO-VTS')).done(),
    0xC8:
        (_W()
              ..u32(2)
              ..u32(3))
            .done(),
    0x202: audio.done(),
    0x254: subs.done(),
    2 * 2048: ptt.done(),
    3 * 2048: pgciBytes,
  }, 4 + pgciBytes.length ~/ 2048);
}

/// CLPI with one STC sequence starting at presentation time 0.
List<int> clpi({required int endTicks}) {
  final b = _W()
    ..ascii('HDMV0200')
    ..u32(0x20);
  b
    ..zeros(0x20 - b.length)
    ..u32(18)
    ..u8(0)
    ..u8(1)
    ..u32(0)
    ..u8(1)
    ..u8(0)
    ..u16(0x1001)
    ..u32(0)
    ..u32(0)
    ..u32(endTicks);
  return b.done();
}

/// MPLS over clip 00001 with [items] (in, out) in 45 kHz ticks and entry
/// [marks] (item, time). Each item declares an MPEG-2 video and an English
/// AC-3 stream.
List<int> mpls({
  required List<(int, int)> items,
  required List<(int, int)> marks,
}) {
  List<int> playItem(int inTime, int outTime) {
    final stn = _W()
      ..zeros(2)
      ..u8(1) // video
      ..u8(1) // audio
      ..zeros(5)
      ..zeros(5)
      // video: stream entry (len 9) + attributes (len 5)
      ..u8(9)
      ..u8(1)
      ..u16(0x1011)
      ..zeros(6)
      ..u8(5)
      ..u8(0x02)
      ..u8(0x31)
      ..zeros(3)
      // audio
      ..u8(9)
      ..u8(1)
      ..u16(0x1100)
      ..zeros(6)
      ..u8(5)
      ..u8(0x81)
      ..u8(0x31)
      ..ascii('eng');
    final stnBytes = stn.done();
    final body = _W()
      ..ascii('00001M2TS')
      ..u16(0x0001)
      ..u8(0)
      ..u32(inTime)
      ..u32(outTime)
      ..zeros(8)
      ..u8(0)
      ..u8(0)
      ..u16(0)
      ..u16(stnBytes.length)
      ..bytes(stnBytes);
    final bodyBytes = body.done();
    return (_W()
          ..u16(bodyBytes.length)
          ..bytes(bodyBytes))
        .done();
  }

  final list = _W()
    ..zeros(2)
    ..u16(items.length)
    ..u16(0);
  for (final (i, o) in items) {
    list.bytes(playItem(i, o));
  }
  final listBytes = list.done();
  final markBody = _W()..u16(marks.length);
  for (final (item, time) in marks) {
    markBody
      ..u8(0)
      ..u8(1)
      ..u16(item)
      ..u32(time)
      ..u16(0xFFFF)
      ..u32(0);
  }
  final markBytes = markBody.done();
  const appInfo = 0x28;
  const playlistAt = appInfo + 4 + 14;
  final marksAt = playlistAt + 4 + listBytes.length;
  final out = _W()
    ..ascii('MPLS0200')
    ..u32(playlistAt)
    ..u32(marksAt)
    ..u32(0);
  out
    ..zeros(appInfo - out.length)
    ..u32(14)
    ..zeros(14)
    ..u32(listBytes.length)
    ..bytes(listBytes)
    ..u32(markBytes.length)
    ..bytes(markBytes);
  return out.done();
}
