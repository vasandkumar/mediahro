import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:mediahro/features/music/tags/ape.dart';
import 'package:mediahro/features/music/tags/asf.dart';
import 'package:mediahro/features/music/tags/audio_tags.dart';
import 'package:mediahro/features/music/tags/byte_reader.dart';
import 'package:mediahro/features/music/tags/id3.dart';
import 'package:mediahro/features/music/tags/mp4.dart';
import 'package:mediahro/features/music/tags/mpeg_duration.dart';
import 'package:mediahro/features/music/tags/riff.dart';
import 'package:mediahro/features/music/tags/vorbis.dart';
import 'package:mediahro_ffi/mediahro_ffi.dart';

/// Containers the reader recognises by their magic bytes.
enum AudioContainer { mpeg, flac, ogg, mp4, asf, wav, aiff, dsf, apeFamily }

/// Reads tags from every format MUS-002 lists: ID3v1/2.2/2.3/2.4, Vorbis
/// comments (FLAC, Ogg Vorbis/Opus/Speex/FLAC), APEv1/v2 (Monkey's Audio,
/// WavPack, Musepack, MP3), MP4 atoms, ASF, WAV/AIFF chunks and DSF.
///
/// Parsing is synchronous over a [ByteReader] and runs in an isolate
/// ([readFile], [readVirtualFile]); hostile input yields [AudioTags.empty]
/// instead of an exception (CLAUDE.md §1.10).
abstract final class TagReader {
  /// Parses [r]; never throws for malformed bytes. [NeedBytes] escapes so a
  /// [SparseByteReader] driver can fetch more.
  static AudioTags read(ByteReader r) {
    try {
      return _read(r);
    } on NeedBytes {
      rethrow;
    } on TagFormatException {
      return AudioTags.empty;
      // Bounds or arithmetic slips (RangeError, NaN.toInt) in a parser are
      // bugs, but a hostile file must never crash a scan over them.
      // ignore: avoid_catching_errors
    } on ArgumentError {
      return AudioTags.empty;
      // Same for NaN/Infinity conversions from hostile numbers.
      // ignore: avoid_catching_errors
    } on UnsupportedError {
      return AudioTags.empty;
    } on FormatException {
      return AudioTags.empty;
    }
  }

  static AudioContainer detect(ByteReader r) {
    var start = 0;
    final id3 = id3v2Size(r, 0);
    if (id3 != null) start = id3;
    final h = r.read(start, 16);
    if (h.startsWithAscii('fLaC')) return AudioContainer.flac;
    if (start == 0) {
      if (h.startsWithAscii('OggS')) return AudioContainer.ogg;
      if (h.startsWithAscii('ftyp', 4)) return AudioContainer.mp4;
      if (isAsf(r)) return AudioContainer.asf;
      if (h.startsWithAscii('RIFF') && h.startsWithAscii('WAVE', 8)) {
        return AudioContainer.wav;
      }
      if (h.startsWithAscii('FORM') &&
          (h.startsWithAscii('AIFF', 8) || h.startsWithAscii('AIFC', 8))) {
        return AudioContainer.aiff;
      }
      if (h.startsWithAscii('DSD ')) return AudioContainer.dsf;
    }
    for (final m in const ['MAC ', 'wvpk', 'MPCK', 'MP+', 'TTA1']) {
      if (h.startsWithAscii(m)) return AudioContainer.apeFamily;
    }
    return AudioContainer.mpeg;
  }

  static AudioTags _read(ByteReader r) {
    final container = detect(r);
    final primary = TagBuilder();
    switch (container) {
      case AudioContainer.flac:
        parseFlac(r, id3v2Size(r, 0) ?? 0, primary);
      case AudioContainer.ogg:
        parseOgg(r, primary);
      case AudioContainer.mp4:
        parseMp4(r, primary);
      case AudioContainer.asf:
        parseAsf(r, primary);
      case AudioContainer.wav:
        parseWav(r, primary);
      case AudioContainer.aiff:
        parseAiff(r, primary);
      case AudioContainer.dsf:
        parseDsf(r, primary);
      case AudioContainer.mpeg || AudioContainer.apeFamily:
        if (id3v2Size(r, 0) != null) parseId3v2(r, 0, primary);
    }
    // FLAC files sometimes carry a stray ID3v2 in front.
    if (container == AudioContainer.flac && id3v2Size(r, 0) != null) {
      final id3 = TagBuilder();
      _tolerant(() => parseId3v2(r, 0, id3));
      primary.mergeMissing(id3);
    }
    // Trailing tags: APE (before an ID3v1 when both exist), then ID3v1.
    if (container
        case AudioContainer.mpeg ||
            AudioContainer.apeFamily ||
            AudioContainer.flac) {
      final v1 = hasId3v1(r);
      final ape = TagBuilder();
      _tolerant(() {
        final loc = findApeTag(r, r.length - (v1 ? 128 : 0));
        if (loc != null) parseApe(r, loc, ape);
      });
      primary.mergeMissing(ape);
      if (v1) {
        final t = TagBuilder();
        parseId3v1(r, t);
        primary.mergeMissing(t);
      }
    }
    if (container == AudioContainer.mpeg && primary.duration == null) {
      _tolerant(() => primary.duration = mpegDuration(r));
    }
    return primary.build();
  }

  static void _tolerant(void Function() parse) {
    try {
      parse();
    } on TagFormatException {
      // A broken secondary tag never hides the primary one.
    }
  }

  /// Reads a local file in a background isolate.
  static Future<AudioTags> readFile(String path) => Isolate.run(() {
    final f = File(path).openSync();
    try {
      return read(FileByteReader(f));
    } finally {
      f.closeSync();
    }
  });

  /// Reads a [VirtualFile] (SAF, network shares): fetches the head and tail,
  /// parses in an isolate, and fetches whatever else the parser asks for.
  static Future<AudioTags> readVirtualFile(VirtualFile file) async {
    final length = await file.length();
    if (length == null || length == 0) return AudioTags.empty;
    final sparse = SparseByteReader(length);
    var fetched = 0;
    Future<void> fetch(int offset, int count) async {
      final o = math.max(0, offset);
      final n = math.min(count, length - o);
      if (n <= 0) return;
      sparse.add(o, await file.read(o, n));
      fetched += n;
    }

    await fetch(0, math.min(length, _head));
    if (length > _head) {
      final tail = math.min(_tail, length - _head);
      await fetch(length - tail, tail);
    }
    for (var round = 0; round < 64; round++) {
      final ranges = sparse.ranges;
      final result = await _parseSparse(length, ranges);
      if (result.$1 != null) return result.$1!;
      final (offset, count) = result.$2!;
      if (fetched + count > TagLimits.maxTagBytes * 2) return AudioTags.empty;
      await fetch(offset, math.max(count, _chunk));
    }
    return AudioTags.empty;
  }

  /// Parses fetched ranges in an isolate. A separate function so the
  /// closure captures only sendable values (never the open file).
  static Future<(AudioTags?, (int, int)?)> _parseSparse(
    int length,
    List<(int, Uint8List)> ranges,
  ) => Isolate.run(() {
    final r = SparseByteReader(length);
    for (final (o, b) in ranges) {
      r.add(o, b);
    }
    try {
      return (read(r), null);
    } on NeedBytes catch (e) {
      return (null, (e.offset, e.length));
    }
  });

  static const int _head = 256 * 1024;
  static const int _tail = 128 * 1024;
  static const int _chunk = 64 * 1024;
}

/// Reads tags from any [VirtualFile]: local paths by positional reads in an
/// isolate, everything else (SAF, shares) by ranges.
Future<AudioTags> readTagsOf(VirtualFile file) {
  final uri = file.uri;
  if (uri.scheme == 'file') return TagReader.readFile(uri.toFilePath());
  return TagReader.readVirtualFile(file);
}
