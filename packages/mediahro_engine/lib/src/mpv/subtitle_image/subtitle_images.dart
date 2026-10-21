import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:mediahro_engine/src/api/models.dart';
import 'package:mediahro_engine/src/api/subtitle_image.dart';
import 'package:mediahro_engine/src/mpv/subtitle_image/dvb.dart';
import 'package:mediahro_engine/src/mpv/subtitle_image/matroska.dart';
import 'package:mediahro_engine/src/mpv/subtitle_image/pgs.dart';
import 'package:mediahro_engine/src/mpv/subtitle_image/vobsub.dart';

/// Bitmap subtitle codecs `extractSubtitleImageTrack` reads, by mpv codec
/// name, with the Matroska codec id the dump writes them under.
const Map<String, String> imageSubtitleCodecs = {
  'hdmv_pgs_subtitle': 'S_HDMV/PGS',
  'dvd_subtitle': 'S_VOBSUB',
  'dvb_subtitle': 'S_DVBSUB',
};

/// The largest dump read into memory.
const int maxSubtitleDumpBytes = 256 << 20;

/// Decodes the bitmaps of the first subtitle track of Matroska [bytes] whose
/// codec is [codecId] (tests: no libmpv). The first packet is placed at
/// [firstAt] on the media's timeline, when given.
Iterable<SubtitleImage> decodeSubtitleImages(
  Uint8List bytes,
  String codecId, {
  Duration? firstAt,
}) sync* {
  final file = MatroskaFile.parse(bytes);
  final track = file.tracks.where((t) => t.codecId == codecId).firstOrNull;
  if (track == null) return;
  final blocks = [
    for (final b in file.blocks)
      if (b.track == track.number) b,
  ];
  if (blocks.isEmpty) return;
  // The recorder starts its output near 0; the first packet was at
  // [firstAt] on the media's timeline.
  final shift = firstAt == null ? Duration.zero : firstAt - blocks.first.pts;
  final images = switch (codecId) {
    'S_HDMV/PGS' => decodePgs(blocks),
    'S_VOBSUB' => decodeVobSub(blocks, track.codecPrivate),
    'S_DVBSUB' => decodeDvb(blocks),
    _ => const <SubtitleImage>[],
  };
  // A bitmap never outlasts the next one.
  SubtitleImage? held;
  for (final raw in images) {
    final image = shift == Duration.zero ? raw : raw.shifted(shift);
    final h = held;
    if (h != null) yield h.end > image.start ? h.withEnd(image.start) : h;
    held = image;
  }
  if (held != null) yield held;
}

/// Reads the Matroska dump [dump] in an isolate and streams its bitmaps in
/// time order (parsers run isolated and bounded, CLAUDE.md §1.10). The
/// isolate stays a few bitmaps ahead of the listener, so a slow consumer
/// (OCR) does not make the whole track pile up in memory.
Stream<SubtitleImage> streamSubtitleImages(
  File dump,
  String codec, {
  Duration? firstAt,
}) {
  final codecId = imageSubtitleCodecs[codec];
  if (codecId == null) {
    return Stream.error(
      EngineException(
        EngineError(
          code: EngineErrorCode.notSupported,
          detail: 'subtitle codec $codec is not a bitmap codec',
        ),
      ),
    );
  }
  const window = 8;
  final port = ReceivePort();
  final controller = StreamController<SubtitleImage>();
  Isolate? isolate;
  SendPort? credits;
  var inflight = 0;

  void pump() {
    final c = credits;
    while (c != null && !controller.isPaused && inflight < window) {
      c.send(null);
      inflight++;
    }
  }

  void finish() {
    port.close();
    unawaited(controller.close());
  }

  port.listen((m) {
    switch (m) {
      case final SendPort p:
        credits = p;
        pump();
      case final List<Object?> v when v.length == 9:
        inflight--;
        controller.add(
          SubtitleImage(
            start: Duration(microseconds: v[0]! as int),
            end: Duration(microseconds: v[1]! as int),
            x: v[2]! as int,
            y: v[3]! as int,
            width: v[4]! as int,
            height: v[5]! as int,
            frameWidth: v[6]! as int,
            frameHeight: v[7]! as int,
            rgba: (v[8]! as TransferableTypedData).materialize().asUint8List(),
          ),
        );
        pump();
      case final String error:
        controller.addError(
          EngineException(
            EngineError(
              code: EngineErrorCode.unsupportedFormat,
              detail: 'bitmap subtitles: $error',
            ),
          ),
        );
        finish();
      case null:
        finish();
      default:
        break;
    }
  });
  controller
    ..onResume = pump
    ..onCancel = () {
      port.close();
      isolate?.kill(priority: Isolate.immediate);
    }
    ..onListen = () async {
      try {
        isolate = await Isolate.spawn(_worker, (
          port.sendPort,
          dump.path,
          codecId,
          firstAt?.inMicroseconds,
        ));
      } on Object catch (e) {
        controller.addError(e);
        finish();
      }
    };
  return controller.stream;
}

Future<void> _worker((SendPort, String, String, int?) args) async {
  final (out, path, codecId, firstUs) = args;
  final commands = ReceivePort();
  var credit = 0;
  Completer<void>? waiting;
  commands.listen((_) {
    credit++;
    final w = waiting;
    waiting = null;
    if (w != null && !w.isCompleted) w.complete();
  });
  out.send(commands.sendPort);
  try {
    final file = File(path);
    if (file.lengthSync() > maxSubtitleDumpBytes) {
      out.send('track too large');
      return;
    }
    for (final image in decodeSubtitleImages(
      file.readAsBytesSync(),
      codecId,
      firstAt: firstUs == null ? null : Duration(microseconds: firstUs),
    )) {
      while (credit == 0) {
        await (waiting = Completer<void>()).future;
      }
      credit--;
      out.send([
        image.start.inMicroseconds,
        image.end.inMicroseconds,
        image.x,
        image.y,
        image.width,
        image.height,
        image.frameWidth,
        image.frameHeight,
        TransferableTypedData.fromList([image.rgba]),
      ]);
    }
    out.send(null);
  } on Object catch (e) {
    out.send('$e');
  } finally {
    commands.close();
  }
}
