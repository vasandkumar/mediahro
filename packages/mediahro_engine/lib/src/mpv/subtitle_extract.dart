import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:mediahro_engine/src/api/models.dart';
import 'package:mediahro_engine/src/mpv/mpv_client.dart';
import 'package:mediahro_engine/src/mpv/mpv_node.dart';
import 'package:mediahro_engine/src/mpv/render_mapping.dart';
import 'package:mediahro_engine/src/mpv/stream_protocol.dart';
import 'package:mediahro_engine/src/mpv/subtitle_convert.dart';
import 'package:mediahro_ffi/mediahro_ffi.dart' show VirtualFile;
// The mpv bindings are an engine-private part of mediahro_ffi (lane B1).
// ignore: implementation_imports
import 'package:mediahro_ffi/src/mpv/mpv.dart' show Libmpv;

/// Embedded subtitle codecs [extractSubtitleTrack] reads, by mpv codec name,
/// with the container their packets are dumped to.
const Map<String, String> textSubtitleDump = {
  'subrip': 'srt',
  'srt': 'srt',
  'text': 'srt',
  'ass': 'ass',
  'ssa': 'ass',
  'webvtt': 'vtt',
  'mov_text': 'mp4',
};

/// Writes embedded text subtitle track [trackId] of a source to [out]
/// (ADR-031: SUB-030 editing, SUB-050 auto-sync and SUB-053 translation of
/// embedded tracks). The output format follows [out]'s extension: `.srt`,
/// `.ass`/`.ssa` (ASS sources keep their styles) or `.vtt`.
///
/// A headless libmpv core selects only that subtitle stream of the source,
/// so its demuxer reads the subtitle packets alone into the cache; a second
/// of external silence stands in for the audio mpv needs before it loads a
/// file. The cache is dumped as a stream copy (`dump-cache`) and converted
/// here, which needs no subtitle decoder (MP4 timed text included). The
/// recorder rebases timestamps, so cues are shifted back to the first
/// packet's time.
Future<void> extractSubtitleTrack({
  required String url,
  required int trackId,
  required String codec,
  required int audioTracks,
  required File out,
  VirtualFile? virtualFile,
  Map<String, String> headers = const {},
  String? libmpvPath,
  Duration timeout = const Duration(minutes: 5),
}) async {
  final kind = textSubtitleDump[codec];
  if (kind == null) {
    throw EngineException(
      EngineError(
        code: EngineErrorCode.notSupported,
        detail: 'subtitle track $trackId is $codec, not text',
      ),
    );
  }
  final target = _target(out.path);
  if (target == null) {
    throw const EngineException(
      EngineError(
        code: EngineErrorCode.invalidArgument,
        detail: 'subtitles are written as .srt, .ass, .ssa or .vtt',
      ),
    );
  }
  final dir = await Directory.systemTemp.createTemp('mediahro-subx');
  final silence = File('${dir.path}${Platform.pathSeparator}silence.wav')
    ..writeAsBytesSync(_silentWav());
  final dump = File('${dir.path}${Platform.pathSeparator}track.$kind');
  final client = await MpvClient.create(
    options: {
      'config': 'no',
      'terminal': 'no',
      'load-scripts': 'no',
      'ytdl': 'no',
      'idle': 'yes',
      'vid': 'no',
      'ao': 'null',
      'pause': 'yes',
      'cache': 'yes',
      'demuxer-max-bytes': '${64 << 20}',
      'demuxer-max-back-bytes': '${64 << 20}',
      'demuxer-readahead-secs': '${365 * 24 * 3600}',
    },
    library: Libmpv.open(path: libmpvPath),
  );
  final protocol = MpvStreamProtocol.register(client);
  final loaded = Completer<void>();
  final events = client.events.listen((e) {
    switch (e) {
      case MpvFileLoaded() when !loaded.isCompleted:
        loaded.complete();
      case MpvEndFile(:final reason, :final error) when !loaded.isCompleted:
        loaded.completeError(
          EngineException(
            EngineError(
              code: reason == MpvEndReason.error
                  ? EngineErrorCode.unsupportedFormat
                  : EngineErrorCode.sourceUnavailable,
              detail: 'subtitle extraction: end-file $reason/$error',
            ),
          ),
        );
      default:
        break;
    }
  });
  try {
    final source = virtualFile == null || protocol == null
        ? url
        : protocol.urlFor(virtualFile);
    await client.loadfile(
      source,
      options: _encode({
        'sid': '$trackId',
        // The external silence follows the source's own audio tracks.
        'aid': '${audioTracks + 1}',
        'audio-file': silence.path,
        if (headers.isNotEmpty)
          'http-header-fields': headers.entries
              .map((e) => '${e.key}: ${e.value}')
              .join(','),
      }),
    );
    await loaded.future.timeout(timeout);
    final deadline = DateTime.now().add(timeout);
    Map<String, Object?>? state;
    while (true) {
      final s = await client.getProperty('demuxer-cache-state');
      state = s is Map<String, Object?> ? s : null;
      if (state?['eof-cached'] == true || state?['eof'] == true) break;
      if (DateTime.now().isAfter(deadline)) {
        throw const EngineException(
          EngineError(
            code: EngineErrorCode.networkTimeout,
            detail: 'subtitle extraction: source not read in time',
          ),
        );
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    final ranges = state?['seekable-ranges'];
    final first = ranges is List && ranges.isNotEmpty && ranges.first is Map
        ? (ranges.first as Map)['start']
        : null;
    final last = ranges is List && ranges.isNotEmpty && ranges.last is Map
        ? (ranges.last as Map)['end']
        : null;
    var cues = const <_Event>[];
    String? assHeader;
    if (first is num && last is num) {
      await client.command([
        'dump-cache',
        // A margin either side: a dump starting exactly at the first
        // packet can leave it out.
        _n(first.toDouble() - 1),
        _n(last.toDouble() + 1),
        dump.path,
      ]);
      if (dump.existsSync() && dump.lengthSync() > 0) {
        final (events, header) = _read(kind, dump);
        assHeader = header;
        cues = _rebaseEvents(events, _us(first.toDouble()));
      }
    }
    await out.writeAsString(_write(target, cues, assHeader));
  } on MpvException catch (e) {
    throw EngineException(
      EngineError(code: EngineErrorCode.unsupportedFormat, detail: '$e'),
    );
  } finally {
    await events.cancel();
    protocol?.shutdown();
    await client.destroy();
    await protocol?.dispose();
    await dir.delete(recursive: true).catchError((Object _) => dir);
  }
}

/// One subtitle event: a cue, or for ASS sources the Dialogue fields after
/// Start/End (`Layer` first) so styles survive.
final class _Event {
  const _Event(this.start, this.end, this.text, {this.assLayer, this.assRest});
  final Duration start;
  final Duration end;
  final String text;
  final String? assLayer;
  final String? assRest;

  _Event shift(Duration by) =>
      _Event(start + by, end + by, text, assLayer: assLayer, assRest: assRest);
}

String? _target(String path) {
  final p = path.toLowerCase();
  if (p.endsWith('.srt')) return 'srt';
  if (p.endsWith('.ass') || p.endsWith('.ssa')) return 'ass';
  if (p.endsWith('.vtt')) return 'vtt';
  return null;
}

(List<_Event>, String?) _read(String kind, File dump) => switch (kind) {
  'mp4' => (_readTx3g(dump.readAsBytesSync()), null),
  'ass' => _readAss(_text(dump)),
  'vtt' => (_readVtt(_text(dump)), null),
  _ => (_readSrt(_text(dump)), null),
};

String _text(File f) {
  final bytes = f.readAsBytesSync();
  if (bytes.length > maxInputChars) {
    throw const EngineException(
      EngineError(
        code: EngineErrorCode.unsupportedFormat,
        detail: 'subtitle track too large',
      ),
    );
  }
  return utf8.decode(bytes, allowMalformed: true).replaceFirst('﻿', '');
}

// The recorder starts its output at 0 (SRT somewhere else again); the
// first packet was at [firstUs]. MP4 keeps gaps as empty samples, so its
// first sample is the first packet even when it holds no text.
List<_Event> _rebaseEvents(List<_Event> events, int firstUs) {
  if (events.isEmpty) return events;
  final by = Duration(microseconds: firstUs) - events.first.start;
  return [
    for (final e in events)
      if (e.text.trim().isNotEmpty || e.assRest != null) e.shift(by),
  ];
}

List<_Event> _readSrt(String s) {
  final out = <_Event>[];
  final time = RegExp(
    r'(\d+):(\d\d):(\d\d)[,.](\d{1,3})\s*-->\s*(\d+):(\d\d):(\d\d)[,.](\d{1,3})',
  );
  for (final block in s.replaceAll('\r\n', '\n').split(RegExp(r'\n\s*\n'))) {
    final lines = block.trim().split('\n');
    final i = lines.indexWhere(time.hasMatch);
    if (i < 0) continue;
    final m = time.firstMatch(lines[i])!;
    out.add(_Event(_hms(m, 1), _hms(m, 5), lines.sublist(i + 1).join('\n')));
    if (out.length >= maxCues) break;
  }
  return out;
}

List<_Event> _readVtt(String s) {
  final out = <_Event>[];
  final time = RegExp(
    r'(?:(\d+):)?(\d\d):(\d\d)\.(\d{3})\s*-->\s*(?:(\d+):)?(\d\d):(\d\d)\.(\d{3})',
  );
  for (final block in s.replaceAll('\r\n', '\n').split(RegExp(r'\n\s*\n'))) {
    final lines = block.trim().split('\n');
    final i = lines.indexWhere(time.hasMatch);
    if (i < 0) continue;
    final m = time.firstMatch(lines[i])!;
    Duration t(int g) => Duration(
      hours: int.parse(m.group(g) ?? '0'),
      minutes: int.parse(m.group(g + 1)!),
      seconds: int.parse(m.group(g + 2)!),
      milliseconds: int.parse(m.group(g + 3)!),
    );
    out.add(_Event(t(1), t(5), lines.sublist(i + 1).join('\n')));
    if (out.length >= maxCues) break;
  }
  return out;
}

(List<_Event>, String?) _readAss(String s) {
  final lines = s.replaceAll('\r\n', '\n').split('\n');
  final events = lines.indexWhere((l) => l.trim() == '[Events]');
  final header = (events < 0 ? lines : lines.sublist(0, events))
      .join('\n')
      .trimRight();
  final out = <_Event>[];
  final time = RegExp(r'^(\d+):(\d\d):(\d\d)\.(\d\d)$');
  Duration? t(String v) {
    final m = time.firstMatch(v.trim());
    if (m == null) return null;
    return Duration(
      hours: int.parse(m.group(1)!),
      minutes: int.parse(m.group(2)!),
      seconds: int.parse(m.group(3)!),
      milliseconds: int.parse(m.group(4)!) * 10,
    );
  }

  for (final l in lines) {
    if (!l.startsWith('Dialogue:')) continue;
    // Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text
    final f = l.substring(9).split(',');
    if (f.length < 10) continue;
    final start = t(f[1]);
    final end = t(f[2]);
    if (start == null || end == null) continue;
    final rest = f.sublist(3).join(',');
    out.add(
      _Event(
        start,
        end,
        _plain(f.sublist(9).join(',')),
        assLayer: f[0].trim(),
        assRest: rest,
      ),
    );
    if (out.length >= maxCues) break;
  }
  return (out, header);
}

// ASS override tags out, line breaks in.
String _plain(String ass) => ass
    .replaceAll(RegExp(r'\{[^}]*\}'), '')
    .replaceAll(r'\N', '\n')
    .replaceAll(r'\n', '\n')
    .replaceAll(r'\h', ' ');

/// 3GPP timed text samples (`tx3g`) from an MP4 holding one subtitle track:
/// each sample is a 16-bit length and UTF-8 (or BOM-marked UTF-16) text,
/// style boxes after it are ignored. Empty samples keep the gaps.
List<_Event> _readTx3g(Uint8List b) {
  final d = ByteData.sublistView(b);
  int u32(int o) => d.getUint32(o);
  // Box children of [from, to).
  Iterable<(String, int, int)> boxes(int from, int to) sync* {
    var o = from;
    while (o + 8 <= to) {
      var size = u32(o);
      final type = String.fromCharCodes(b.sublist(o + 4, o + 8));
      var header = 8;
      if (size == 1 && o + 16 <= to) {
        size = d.getUint64(o + 8);
        header = 16;
      } else if (size == 0) {
        size = to - o;
      }
      if (size < header || o + size > to) return;
      yield (type, o + header, o + size);
      o += size;
    }
  }

  (int, int)? child(int from, int to, String type) {
    for (final (t, s, e) in boxes(from, to)) {
      if (t == type) return (s, e);
    }
    return null;
  }

  final moov = child(0, b.length, 'moov');
  if (moov == null) return const [];
  for (final (t, ts, te) in boxes(moov.$1, moov.$2)) {
    if (t != 'trak') continue;
    final mdia = child(ts, te, 'mdia');
    if (mdia == null) continue;
    final mdhd = child(mdia.$1, mdia.$2, 'mdhd');
    final stbl = () {
      final minf = child(mdia.$1, mdia.$2, 'minf');
      return minf == null ? null : child(minf.$1, minf.$2, 'stbl');
    }();
    if (mdhd == null || stbl == null) continue;
    final v1 = b[mdhd.$1] == 1;
    final timescale = u32(mdhd.$1 + (v1 ? 20 : 12));
    final stts = child(stbl.$1, stbl.$2, 'stts');
    final stsz = child(stbl.$1, stbl.$2, 'stsz');
    final stsc = child(stbl.$1, stbl.$2, 'stsc');
    final co =
        child(stbl.$1, stbl.$2, 'stco') ?? child(stbl.$1, stbl.$2, 'co64');
    final co64 = child(stbl.$1, stbl.$2, 'stco') == null;
    if (timescale == 0 ||
        stts == null ||
        stsz == null ||
        stsc == null ||
        co == null) {
      continue;
    }
    // Sample durations.
    final durations = <int>[];
    for (var i = 0, n = u32(stts.$1 + 4); i < n; i++) {
      final count = u32(stts.$1 + 8 + i * 8);
      final delta = u32(stts.$1 + 12 + i * 8);
      for (var k = 0; k < count && durations.length < maxCues * 2; k++) {
        durations.add(delta);
      }
    }
    // Sample sizes.
    final fixed = u32(stsz.$1 + 4);
    final count = u32(stsz.$1 + 8);
    int sizeOf(int i) => fixed != 0 ? fixed : u32(stsz.$1 + 12 + i * 4);
    final sizes = [
      for (var i = 0; i < count && i < durations.length; i++) sizeOf(i),
    ];
    // Chunk offsets and samples per chunk.
    final chunks = u32(co.$1 + 4);
    int offsetOf(int i) =>
        co64 ? d.getUint64(co.$1 + 8 + i * 8) : u32(co.$1 + 8 + i * 4);
    final offsets = [for (var i = 0; i < chunks; i++) offsetOf(i)];
    final runs = [
      for (var i = 0, n = u32(stsc.$1 + 4); i < n; i++)
        (u32(stsc.$1 + 8 + i * 12), u32(stsc.$1 + 12 + i * 12)),
    ];
    final out = <_Event>[];
    var sample = 0;
    var time = 0;
    for (var c = 0; c < offsets.length && sample < sizes.length; c++) {
      var perChunk = 0;
      for (final (firstChunk, n) in runs) {
        if (firstChunk - 1 <= c) perChunk = n;
      }
      var o = offsets[c];
      for (var k = 0; k < perChunk && sample < sizes.length; k++) {
        final size = sizes[sample];
        final start = time;
        time += durations[sample];
        sample++;
        var text = '';
        if (size >= 2 && o + size <= b.length) {
          final len = d.getUint16(o);
          final raw = b.sublist(
            o + 2,
            o + 2 + (len < size - 2 ? len : size - 2),
          );
          text = raw.length >= 2 && raw[0] == 0xFE && raw[1] == 0xFF
              ? String.fromCharCodes([
                  for (var i = 2; i + 1 < raw.length; i += 2)
                    raw[i] << 8 | raw[i + 1],
                ])
              : utf8.decode(raw, allowMalformed: true);
        }
        o += size;
        out.add(
          _Event(
            Duration(microseconds: start * 1000000 ~/ timescale),
            Duration(microseconds: time * 1000000 ~/ timescale),
            text,
          ),
        );
      }
    }
    return out;
  }
  return const [];
}

String _write(String target, List<_Event> events, String? assHeader) {
  switch (target) {
    case 'ass':
      final b = StringBuffer()
        ..writeln(assHeader ?? _defaultAssHeader)
        ..writeln()
        ..writeln('[Events]')
        ..writeln(
          'Format: Layer, Start, End, Style, Name, MarginL, MarginR, '
          'MarginV, Effect, Text',
        );
      for (final e in events) {
        final rest =
            e.assRest ?? 'Default,,0,0,0,,${e.text.replaceAll('\n', r'\N')}';
        b.writeln(
          'Dialogue: ${e.assLayer ?? '0'},${_assTime(e.start)},'
          '${_assTime(e.end)},$rest',
        );
      }
      return b.toString();
    case 'vtt':
      final b = StringBuffer()..writeln('WEBVTT');
      for (final e in events) {
        b
          ..writeln()
          ..writeln('${_vttTime(e.start)} --> ${_vttTime(e.end)}')
          ..writeln(e.text);
      }
      return b.toString();
    default:
      return toSrt([for (final e in events) Cue(e.start, e.end, e.text)]);
  }
}

const _defaultAssHeader = '''
[Script Info]
ScriptType: v4.00+
PlayResX: 384
PlayResY: 288

[V4+ Styles]
Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding
Style: Default,Arial,20,&H00FFFFFF,&H000000FF,&H00000000,&H00000000,0,0,0,0,100,100,0,0,1,2,0,2,10,10,10,1''';

String _assTime(Duration d) {
  final cs = d.inMilliseconds ~/ 10;
  final h = cs ~/ 360000;
  final m = cs ~/ 6000 % 60;
  final s = cs ~/ 100 % 60;
  return '$h:${_two(m)}:${_two(s)}.${_two(cs % 100)}';
}

String _vttTime(Duration d) {
  final ms = d.inMilliseconds;
  return '${_two(ms ~/ 3600000)}:${_two(ms ~/ 60000 % 60)}:'
      '${_two(ms ~/ 1000 % 60)}.${(ms % 1000).toString().padLeft(3, '0')}';
}

String _two(int v) => v.toString().padLeft(2, '0');

Duration _hms(RegExpMatch m, int g) => Duration(
  hours: int.parse(m.group(g)!),
  minutes: int.parse(m.group(g + 1)!),
  seconds: int.parse(m.group(g + 2)!),
  milliseconds: int.parse(m.group(g + 3)!.padRight(3, '0')),
);

int _us(double seconds) => (seconds * 1e6).round();

String _n(double v) => secondsValue(Duration(microseconds: _us(v)));

// One second of 8 kHz mono silence (WAV).
Uint8List _silentWav() {
  const samples = 8000;
  final b = ByteData(44 + samples * 2);
  void tag(int o, String s) {
    for (var i = 0; i < 4; i++) {
      b.setUint8(o + i, s.codeUnitAt(i));
    }
  }

  tag(0, 'RIFF');
  b.setUint32(4, 36 + samples * 2, Endian.little);
  tag(8, 'WAVE');
  tag(12, 'fmt ');
  b
    ..setUint32(16, 16, Endian.little)
    ..setUint16(20, 1, Endian.little)
    ..setUint16(22, 1, Endian.little)
    ..setUint32(24, 8000, Endian.little)
    ..setUint32(28, 16000, Endian.little)
    ..setUint16(32, 2, Endian.little)
    ..setUint16(34, 16, Endian.little);
  tag(36, 'data');
  b.setUint32(40, samples * 2, Endian.little);
  return b.buffer.asUint8List();
}

String _encode(Map<String, String> options) => options.entries
    .map((e) => '${e.key}=%${utf8.encode(e.value).length}%${e.value}')
    .join(',');
