import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:mediahro_ffi/mediahro_ffi.dart';

/// AUD-002: one trimming source for MP4/M4A gapless metadata.
///
/// FFmpeg's mov demuxer discards the iTunSMPB padding counted back from the
/// container duration (`duration - remainder`). That is right for files
/// written like iTunes, whose last AAC frame and media duration still contain
/// the padding, and wrong for files whose stts/mdhd already end at
/// `priming + samples` (FFmpeg 6.x output tagged afterwards): their padding is
/// trimmed twice and the album loses that many samples at every join.
///
/// FFmpeg releases also differ: some apply only the tag's priming and never
/// trim the padding at all.
///
/// [inspectSmpb] therefore gives two corrections: the exact end of the
/// content ([SmpbFix.end], seconds after priming, for mpv's per-file `end`,
/// which cuts sample-accurately whatever the demuxer does), and, for the
/// double-trimmed framing, the tag's remainder field ([SmpbFix.blankAt]) that
/// [Mp4GaplessFile] reads as zero so the demuxer cannot cut before that end.
final class SmpbFix {
  const SmpbFix({required this.end, this.blankAt});

  /// Content end in seconds on mpv's timeline, as its per-file `end`.
  final String end;

  /// Absolute offset of the remainder field to read as zero, when needed.
  final int? blankAt;
}

Future<SmpbFix?> inspectSmpb(VirtualFile file) async {
  final length = await file.length();
  if (length == null || length < 16) return null;
  final head = await file.read(0, 8);
  if (head.length < 8 || ascii.decode(head.sublist(4, 8)) != 'ftyp') {
    return null;
  }
  // Top-level boxes: find moov.
  var at = 0;
  int? moovAt;
  var moovSize = 0;
  while (at + 8 <= length) {
    final h = await file.read(at, 16);
    if (h.length < 8) break;
    final view = ByteData.sublistView(h);
    var size = view.getUint32(0);
    var header = 8;
    if (size == 1 && h.length >= 16) {
      size = view.getUint64(8);
      header = 16;
    } else if (size == 0) {
      size = length - at;
    }
    if (size < header) return null;
    if (_type(h, 4) == 'moov') {
      moovAt = at;
      moovSize = size;
      break;
    }
    at += size;
  }
  // A moov larger than this is not an audio file worth inspecting.
  if (moovAt == null || moovSize > 16 << 20) return null;
  final moov = await file.read(moovAt, moovSize);
  if (moov.length != moovSize) return null;
  final found = _Scan()..walk(moov, 8, moov.length);
  final smpb = found.smpbText;
  if (smpb == null || found.timescale == null || found.duration == null) {
    return null;
  }
  // " 00000000 PPPPPPPP RRRRRRRR SSSSSSSSSSSSSSSS ...": priming, remainder,
  // sample count (hex).
  final text = ascii.decode(
    moov.sublist(smpb, found.smpbEnd),
    allowInvalid: true,
  );
  final tokens = RegExp('[0-9A-Fa-f]+').allMatches(text).toList();
  if (tokens.length < 4) return null;
  final priming = int.parse(tokens[1].group(0)!, radix: 16);
  final remainder = int.parse(tokens[2].group(0)!, radix: 16);
  final samples = int.parse(tokens[3].group(0)!, radix: 16);
  // FFmpeg reads the tag in media time units; only the common case where
  // they are samples (timescale = sample rate) is corrected.
  final rate = found.sampleRate;
  if (rate == null || rate <= 0 || found.timescale != rate) return null;
  if (samples <= 0) return null;
  // Without an edit list the timeline starts at the first packet, priming
  // included; an edit list shifts it so the content starts at 0.
  final offset = (found.editMediaTime ?? 0) > 0 ? 0 : priming;
  final end = ((offset + samples) / rate).toStringAsFixed(9);
  final duration = found.duration!;
  final doubleTrim =
      remainder > 0 &&
      duration > remainder &&
      duration > samples &&
      duration - remainder < priming + samples;
  return SmpbFix(
    end: end,
    blankAt: doubleTrim ? moovAt + smpb + tokens[2].start : null,
  );
}

String _type(Uint8List b, int at) =>
    String.fromCharCodes(b.sublist(at, at + 4));

/// Walks the boxes FFmpeg reads for gapless playback.
final class _Scan {
  int? timescale;
  int? duration;
  int? sampleRate;
  int? editMediaTime;
  int? smpbText;
  int? smpbEnd;
  bool _soundTrack = false;
  int? _trackTimescale;
  int? _trackDuration;
  int? _trackEditMediaTime;
  bool _freeformIsSmpb = false;

  static const _containers = {
    'trak',
    'edts',
    'mdia',
    'minf',
    'stbl',
    'udta',
    'ilst',
    '----',
  };

  void walk(Uint8List b, int start, int end) {
    final view = ByteData.sublistView(b);
    var at = start;
    while (at + 8 <= end) {
      var size = view.getUint32(at);
      var header = 8;
      if (size == 1 && at + 16 <= end) {
        size = view.getUint64(at + 8);
        header = 16;
      } else if (size == 0) {
        size = end - at;
      }
      if (size < header || at + size > end) return;
      final type = _type(b, at + 4);
      final body = at + header;
      switch (type) {
        case 'trak':
          _soundTrack = false;
          _trackTimescale = null;
          _trackDuration = null;
          _trackEditMediaTime = null;
          walk(b, body, at + size);
          if (_soundTrack && timescale == null) {
            timescale = _trackTimescale;
            duration = _trackDuration;
            editMediaTime = _trackEditMediaTime;
          }
        case 'elst':
          // First entry's media time (signed): version 1 has 64-bit fields.
          final v1 = b[body] == 1;
          if (view.getUint32(body + 4) > 0) {
            _trackEditMediaTime = v1
                ? view.getInt64(body + 16)
                : view.getInt32(body + 12);
          }
        case 'mdhd':
          final v1 = b[body] == 1;
          _trackTimescale = view.getUint32(body + (v1 ? 20 : 12));
          _trackDuration = v1
              ? view.getUint64(body + 24)
              : view.getUint32(body + 16);
        case 'hdlr':
          if (_type(b, body + 8) == 'soun') _soundTrack = true;
        case 'stsd':
          // Version/flags, entry count, then the sample entry: an audio
          // entry (mp4a) carries the rate as 16.16 at byte 32 of its body.
          final entry = body + 8;
          if (_soundTrack && entry + 36 <= at + size) {
            sampleRate ??= view.getUint32(entry + 32) >> 16;
          }
        case 'meta':
          // Full box: version and flags precede the children.
          walk(b, body + 4, at + size);
        case 'data':
          if (_freeformIsSmpb) {
            smpbText = body + 8;
            smpbEnd = at + size;
          }
        case 'name':
          _freeformIsSmpb =
              ascii.decode(
                b.sublist(body + 4, at + size),
                allowInvalid: true,
              ) ==
              'iTunSMPB';
        default:
          if (_containers.contains(type)) walk(b, body, at + size);
      }
      at += size;
    }
  }
}

/// A [VirtualFile] that reads [inner] with the 8 bytes at [blankAt] replaced
/// by ASCII zeros (the iTunSMPB remainder field, see [inspectSmpb]).
final class Mp4GaplessFile implements VirtualFile {
  Mp4GaplessFile(this.inner, this.blankAt);

  final VirtualFile inner;
  final int blankAt;

  @override
  Uri get uri => inner.uri;

  @override
  bool get isSeekable => inner.isSeekable;

  @override
  Future<int?> length() => inner.length();

  @override
  Future<Uint8List> read(int offset, int length) async {
    final data = await inner.read(offset, length);
    final from = blankAt - offset;
    if (from + 8 <= 0 || from >= data.length) return data;
    final out = Uint8List.fromList(data);
    for (var i = from < 0 ? 0 : from; i < from + 8 && i < out.length; i++) {
      out[i] = 0x30;
    }
    return out;
  }

  @override
  Future<void> close() => inner.close();
}

/// A local file as a [VirtualFile] (one handle, serialised reads).
final class LocalVirtualFile implements VirtualFile {
  LocalVirtualFile(this.file);

  final File file;
  RandomAccessFile? _raf;
  Future<void> _lock = Future.value();

  @override
  Uri get uri => file.uri;

  @override
  bool get isSeekable => true;

  @override
  Future<int?> length() => file.length();

  @override
  Future<Uint8List> read(int offset, int length) async {
    final previous = _lock;
    final done = Completer<void>();
    _lock = done.future;
    await previous;
    try {
      final raf = _raf ??= await file.open();
      await raf.setPosition(offset);
      return await raf.read(length);
    } finally {
      done.complete();
    }
  }

  @override
  Future<void> close() async {
    await _raf?.close();
    _raf = null;
  }
}
