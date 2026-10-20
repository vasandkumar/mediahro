import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:mediahro_subtitles/src/decoding.dart';
import 'package:mediahro_subtitles/src/formats.dart';
import 'package:mediahro_subtitles/src/subtitle_parser.dart';

/// Decodes and parses subtitle bytes in a separate isolate, killed after
/// [ParseLimits.timeout] (PRIV-005): a hostile file can neither block the
/// UI isolate nor run forever. [format] null sniffs the text.
///
/// Throws [SubtitleParseException] for oversized, malformed, unknown or
/// timed-out input.
Future<SubtitleDocument> parseSubtitlesIsolated(
  Uint8List bytes, {
  SubtitleFormat? format,
  String? charset,
  double? fps,
  ParseLimits limits = const ParseLimits(),
}) async {
  if (bytes.length > limits.maxBytes) {
    throw const SubtitleParseException('file too large');
  }
  final port = ReceivePort();
  final isolate = await Isolate.spawn(
    _entry,
    _Job(port.sendPort, bytes, format, charset, fps, limits),
    onExit: port.sendPort,
  );
  try {
    final reply = await port.first.timeout(limits.timeout);
    return switch (reply) {
      final SubtitleDocument d => d,
      final String error => throw SubtitleParseException(error),
      _ => throw const SubtitleParseException('parser stopped'),
    };
  } on TimeoutException {
    throw const SubtitleParseException('parsing took too long');
  } finally {
    isolate.kill(priority: Isolate.immediate);
    port.close();
  }
}

/// The same work on the calling isolate: for the isolate itself and for
/// fuzzing.
SubtitleDocument parseSubtitleBytes(
  Uint8List bytes, {
  SubtitleFormat? format,
  String? charset,
  double? fps,
  ParseLimits limits = const ParseLimits(),
}) {
  final text = decodeSubtitleText(bytes, charset: charset);
  final f = format ?? sniffSubtitleFormat(text);
  if (f == null) throw const SubtitleParseException('unknown format');
  final parser = parserFor(f, fps: fps);
  if (parser == null) {
    throw SubtitleParseException('no text parser for ${f.name}');
  }
  return parser.parse(text, limits: limits);
}

final class _Job {
  const _Job(
    this.reply,
    this.bytes,
    this.format,
    this.charset,
    this.fps,
    this.limits,
  );

  final SendPort reply;
  final Uint8List bytes;
  final SubtitleFormat? format;
  final String? charset;
  final double? fps;
  final ParseLimits limits;
}

void _entry(_Job job) {
  try {
    job.reply.send(
      parseSubtitleBytes(
        job.bytes,
        format: job.format,
        charset: job.charset,
        fps: job.fps,
        limits: job.limits,
      ),
    );
  } on SubtitleParseException catch (e) {
    job.reply.send(e.message);
  } on FormatException catch (e) {
    job.reply.send(e.message);
  }
}
